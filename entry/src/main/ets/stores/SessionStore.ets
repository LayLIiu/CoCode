/**
 * 会话状态管理
 * 支持状态持久化和 WebSocket 实时更新
 */

import { Session, Message, SessionStatus, TaskItem, PermissionMode, WSMessage, OutgoingMessage, RecentProject } from '../models/Models'
import { apiService } from '../services/APIService'
import { wsService } from '../services/WebSocketService'
import { storageService } from '../services/StorageService'
import { authStore } from './AuthStore'

export class SessionStore {
  private static instance: SessionStore

  // 会话列表
  sessions: Session[] = []
  currentSessionId: string | null = null

  // 消息存储
  messages: Map<string, Message[]> = new Map()

  // 会话状态
  sessionStatuses: Map<string, SessionStatus> = new Map()
  sessionPermissionModes: Map<string, PermissionMode> = new Map()

  // 任务列表
  sessionTasks: Map<string, TaskItem[]> = new Map()
  taskBarExpanded: boolean = false
  taskBarDismissed: boolean = false

  // 最近项目
  recentProjects: RecentProject[] = []
  isLoadingRecentProjects: boolean = false

  // 加载状态
  isLoading: boolean = false
  isCreating: boolean = false
  error: string | null = null

  // WebSocket 状态
  private wsSubscribed: boolean = false

  // 状态变更回调
  onSessionsChanged?: () => void
  onMessagesChanged?: (sessionId: string) => void
  onStatusChanged?: (sessionId: string, status: SessionStatus) => void
  onRawMessage?: (sessionId: string, msg: WSMessage) => void

  static getInstance(): SessionStore {
    if (!SessionStore.instance) {
      SessionStore.instance = new SessionStore()
    }
    return SessionStore.instance
  }

  constructor() {
    // 设置 WebSocket 消息处理器
    wsService.setMessageHandler((sessionId, message) => {
      this.handleWSMessage(sessionId, message)
    })

    // 加载本地缓存的会话数据
    this.loadLocalData()
  }

  // MARK: - 本地数据加载

  private async loadLocalData(): Promise<void> {
    try {
      // 加载本地会话
      const localSessions = await storageService.loadSessions()
      if (localSessions.length > 0) {
        this.sessions = localSessions

        // 预加载所有会话的本地消息
        for (let i = 0; i < localSessions.length; i++) {
          const session = localSessions[i]
          const localMessages = await storageService.loadMessages(session.id)
          if (localMessages.length > 0) {
            this.messages.set(session.id, localMessages)
          }
        }

        // 加载本地保存的状态
        const savedStatuses = await storageService.loadSessionStatuses()
        savedStatuses.forEach((value: string, key: string) => {
          // 只恢复稳定状态，临时状态重置为 idle
          if (value === 'idle' || value === 'completed') {
            this.sessionStatuses.set(key, value as SessionStatus)
          } else {
            this.sessionStatuses.set(key, 'idle')
          }
        })

        this.notifySessionsChanged()
        console.info(`[SessionStore] Loaded ${localSessions.length} sessions from local, ${savedStatuses.size} statuses`)
      }
    } catch (e) {
      console.error(`[SessionStore] Load local data error: ${e}`)
    }
  }

  // MARK: - 会话操作

  async fetchSessions(): Promise<void> {
    this.isLoading = true
    this.error = null
    this.notifySessionsChanged()

    try {
      const serverSessions = await apiService.getSessions()

      // 合并本地修改时间（避免被服务器旧数据覆盖）
      const localModifiedMap: Map<string, string> = new Map()
      for (let i = 0; i < this.sessions.length; i++) {
        localModifiedMap.set(this.sessions[i].id, this.sessions[i].modifiedAt)
      }

      this.sessions = serverSessions.map(serverSession => {
        const localTime = localModifiedMap.get(serverSession.id)
        if (localTime) {
          const localDate = new Date(localTime).getTime()
          const serverDate = new Date(serverSession.modifiedAt).getTime()
          if (localDate > serverDate) {
            const updatedSession: Session = {
              id: serverSession.id,
              title: serverSession.title,
              projectPath: serverSession.projectPath,
              workDir: serverSession.workDir,
              workDirExists: serverSession.workDirExists,
              createdAt: serverSession.createdAt,
              modifiedAt: localTime,
              messageCount: serverSession.messageCount,
              providerId: serverSession.providerId
            }
            return updatedSession
          }
        }
        return serverSession
      })

      // 保存到本地
      await storageService.saveSessions(this.sessions)

      this.isLoading = false
      this.notifySessionsChanged()

      // 更新 WebSocket 订阅
      if (this.wsSubscribed) {
        this.subscribeToAllSessions()
      }
    } catch (e) {
      this.error = String(e)
      this.isLoading = false
      this.notifySessionsChanged()
    }
  }

  async createSession(workDir?: string): Promise<string | null> {
    this.isCreating = true
    this.notifySessionsChanged()

    try {
      const response = await apiService.createSession(workDir)
      await this.fetchSessions()
      this.isCreating = false
      return response.sessionId
    } catch (e) {
      this.error = String(e)
      this.isCreating = false
      return null
    }
  }

  // 根据提供商类型创建会话
  async createSessionWithProvider(workDir: string, providerId: string): Promise<string | null> {
    this.isCreating = true
    this.notifySessionsChanged()

    try {
      const response = await apiService.createSessionWithProvider(workDir, providerId)
      await this.fetchSessions()
      this.isCreating = false

      // 保存到最近使用
      await storageService.addRecentWorkDir(workDir)

      return response.sessionId
    } catch (e) {
      this.error = String(e)
      this.isCreating = false
      return null
    }
  }

  // 获取提供商 ID 根据 Tab 类型
  getProviderIdForTabType(tabType: string): string {
    if (tabType === 'Claude') {
      return 'claude'
    } else if (tabType === 'Codex') {
      return 'codex'
    } else if (tabType === 'OpenCode') {
      return 'opencode'
    }
    return ''
  }

  async deleteSession(sessionId: string): Promise<void> {
    try {
      await apiService.deleteSession(sessionId)
      this.sessions = this.sessions.filter(s => s.id !== sessionId)
      this.messages.delete(sessionId)
      this.sessionStatuses.delete(sessionId)
      wsService.disconnectSession(sessionId)

      // 删除本地数据
      await storageService.deleteMessages(sessionId)
      await storageService.saveSessions(this.sessions)
      await storageService.saveSessionStatuses(this.sessionStatuses)

      this.notifySessionsChanged()
    } catch (e) {
      this.error = String(e)
    }
  }

  async deleteLocalSession(sessionId: string): Promise<void> {
    // 只删除本地数据，不删除服务器数据
    this.sessions = this.sessions.filter(s => s.id !== sessionId)
    this.messages.delete(sessionId)
    this.sessionStatuses.delete(sessionId)

    // 删除本地数据
    await storageService.deleteMessages(sessionId)
    await storageService.saveSessions(this.sessions)
    await storageService.saveSessionStatuses(this.sessionStatuses)

    // 断开 WebSocket
    wsService.disconnectSession(sessionId)

    this.notifySessionsChanged()
    console.info(`[SessionStore] Deleted local session: ${sessionId}`)
  }

  async renameSession(sessionId: string, title: string): Promise<void> {
    try {
      await apiService.renameSession(sessionId, title)
      const index = this.sessions.findIndex(s => s.id === sessionId)
      if (index >= 0) {
        const old = this.sessions[index]
        const updated: Session = {
          id: old.id,
          title: title,
          projectPath: old.projectPath,
          workDir: old.workDir,
          workDirExists: old.workDirExists,
          createdAt: old.createdAt,
          modifiedAt: new Date().toISOString(),
          messageCount: old.messageCount,
          providerId: old.providerId
        }
        this.sessions[index] = updated

        // 保存到本地
        await storageService.saveSessions(this.sessions)

        this.notifySessionsChanged()
      }
    } catch (e) {
      this.error = String(e)
    }
  }

  setCurrentSession(sessionId: string | null): void {
    this.currentSessionId = sessionId
    this.taskBarExpanded = false
    this.taskBarDismissed = false
  }

  // 保存会话到本地存储
  async saveSessionsToStorage(): Promise<void> {
    await storageService.saveSessions(this.sessions)
    this.notifySessionsChanged()
  }

  // MARK: - 消息操作

  async loadMessages(sessionId: string): Promise<void> {
    // 先加载本地缓存
    const localMessages = await storageService.loadMessages(sessionId)
    if (localMessages.length > 0) {
      this.messages.set(sessionId, localMessages)
      this.notifyMessagesChanged(sessionId)
    }

    // 后台同步服务器消息
    try {
      const serverMessages = await apiService.getMessages(sessionId)

      // 合并消息
      let existingIds: Set<string> = new Set()
      let existingContents: Set<string> = new Set()
      let mergedMessages = this.messages.get(sessionId) || []

      for (let i = 0; i < mergedMessages.length; i++) {
        existingIds.add(mergedMessages[i].id)
        existingContents.add(`${mergedMessages[i].type}-${mergedMessages[i].content}`)
      }

      for (let i = 0; i < serverMessages.length; i++) {
        const msg = serverMessages[i]
        const contentKey = `${msg.type}-${msg.content}`
        if (!existingIds.has(msg.id) && !existingContents.has(contentKey)) {
          mergedMessages.push(msg)
          existingIds.add(msg.id)
          existingContents.add(contentKey)
        }
      }

      // 按时间排序
      mergedMessages.sort((a, b) => {
        return new Date(a.timestamp).getTime() - new Date(b.timestamp).getTime()
      })

      this.messages.set(sessionId, mergedMessages)
      this.notifyMessagesChanged(sessionId)

      // 保存到本地
      await storageService.saveMessages(sessionId, mergedMessages)
    } catch (e) {
      console.error(`[SessionStore] Load messages error: ${e}`)
    }
  }

  addMessage(sessionId: string, message: Message): void {
    let sessionMessages = this.messages.get(sessionId)
    if (!sessionMessages) {
      sessionMessages = []
    }

    // 去重
    let exists = false
    for (let i = 0; i < sessionMessages.length; i++) {
      const m = sessionMessages[i]
      if (m.id === message.id ||
        (m.type === message.type && m.content === message.content && message.content)) {
        exists = true
        break
      }
    }

    if (!exists) {
      sessionMessages.push(message)
      this.messages.set(sessionId, sessionMessages)
      this.notifyMessagesChanged(sessionId)

      // 异步保存到本地
      storageService.saveMessages(sessionId, sessionMessages)
    }
  }

  // MARK: - WebSocket

  subscribeToAllSessions(): void {
    const serverUrl = authStore.serverUrl
    if (!serverUrl) return

    wsService.setServerUrl(serverUrl)
    wsService.subscribeToSessions(this.sessions.map(s => s.id))
    this.wsSubscribed = true

    console.info(`[SessionStore] Subscribed to ${this.sessions.length} sessions`)

    // 请求所有会话的当前状态
    this.requestAllSessionStatuses()
  }

  subscribeToSession(sessionId: string): void {
    const serverUrl = authStore.serverUrl
    if (!serverUrl) return

    wsService.setServerUrl(serverUrl)
    wsService.subscribeToSessions([sessionId])
    this.wsSubscribed = true

    // 请求当前会话状态
    const message: OutgoingMessage = {
      type: 'get_status'
    }
    wsService.send(sessionId, message)
    console.info(`[SessionStore] Subscribed and requested status for ${sessionId}`)
  }

  // 请求所有会话的状态
  private requestAllSessionStatuses(): void {
    for (let i = 0; i < this.sessions.length; i++) {
      const sessionId = this.sessions[i].id
      const message: OutgoingMessage = {
        type: 'get_status'
      }
      wsService.send(sessionId, message)
    }
  }

  disconnectAllSessions(): void {
    wsService.disconnectAll()
  }

  sendMessage(content: string): void {
    if (!this.currentSessionId) return

    // 添加用户消息
    const userMessage: Message = {
      id: 'user-' + Date.now(),
      type: 'user',
      content: content,
      timestamp: new Date().toISOString()
    }
    this.addMessage(this.currentSessionId, userMessage)

    // 发送到服务器
    wsService.sendUserMessage(this.currentSessionId, content)

    // 更新状态
    this.updateSessionStatus(this.currentSessionId, 'thinking')
  }

  sendPermissionResponse(requestId: string, allowed: boolean, always: boolean = false): void {
    if (!this.currentSessionId) return
    wsService.sendPermissionResponse(this.currentSessionId, requestId, allowed, always)
  }

  sendQuestionResponse(questionId: string, answer: string): void {
    if (!this.currentSessionId) return
    wsService.sendQuestionResponse(this.currentSessionId, questionId, answer)
  }

  stopGeneration(): void {
    if (!this.currentSessionId) return
    wsService.sendStop(this.currentSessionId)
  }

  changePermissionMode(mode: PermissionMode): void {
    if (!this.currentSessionId) return

    this.sessionPermissionModes.set(this.currentSessionId, mode)

    const message: OutgoingMessage = {
      type: 'set_permission_mode',
      mode: mode
    }
    wsService.send(this.currentSessionId, message)
  }

  getCurrentPermissionMode(): PermissionMode {
    if (!this.currentSessionId) return PermissionMode.DEFAULT
    return this.sessionPermissionModes.get(this.currentSessionId) || PermissionMode.DEFAULT
  }

  // MARK: - 状态管理

  // 更新会话状态
  updateSessionStatus(sessionId: string, status: SessionStatus): void {
    this.sessionStatuses.set(sessionId, status)
    this.notifyStatusChanged(sessionId, status)
    this.notifySessionsChanged()

    // 只持久化保存稳定状态（idle 和 completed），临时状态不保存
    if (status === 'idle' || status === 'completed') {
      storageService.saveSessionStatuses(this.sessionStatuses)
    }
    console.info(`[SessionStore] Status updated: ${sessionId} -> ${status}`)
  }

  // 获取会话状态
  getSessionStatus(sessionId: string): SessionStatus {
    return this.sessionStatuses.get(sessionId) || 'idle'
  }

  // MARK: - WebSocket 消息处理

  private handleWSMessage(sessionId: string, msg: WSMessage): void {
    console.info(`[SessionStore] WS msg: ${msg.type} for ${sessionId}`)

    // 转发原始消息给 ChatDetailPage（用于流式缓冲等本地处理）
    if (this.onRawMessage) {
      this.onRawMessage(sessionId, msg)
    }

    // 忽略 connected 消息
    if (msg.type === 'connected') {
      // 连接成功后请求状态
      const statusMsg: OutgoingMessage = {
        type: 'get_status'
      }
      wsService.send(sessionId, statusMsg)
      return
    }

    // 处理 type 为 nil 的情况
    let messageType = msg.type
    if (!messageType && msg.questions) {
      messageType = 'questions'
    }

    if (!messageType) return

    switch (messageType) {
      case 'session_title_updated':
        if (msg.title) {
          this.updateSessionTitle(sessionId, msg.title)
        }
        break

      case 'status':
        if (msg.state) {
          this.updateSessionStatusFromState(sessionId, msg.state)
        }
        break

      case 'content_start':
        this.updateSessionStatus(sessionId, 'streaming')
        break

      case 'content_delta':
      case 'thinking':
        // 流式消息处理在 ChatDetailPage 中处理
        break

      case 'tool_use_complete':
        this.updateSessionStatus(sessionId, 'tool_executing')

        if (msg.toolName) {
          const toolMessage: Message = {
            id: msg.toolUseId || 'tool-' + Date.now(),
            type: 'tool_use',
            content: '',
            timestamp: new Date().toISOString(),
            toolName: msg.toolName,
            toolInput: msg.input,
            toolStatus: 'running'
          }
          this.addMessage(sessionId, toolMessage)
        }
        break

      case 'tool_result':
        if (msg.toolUseId && msg.content) {
          this.updateToolResult(sessionId, msg.toolUseId, msg.content)
        }
        break

      case 'message_complete':
        console.info(`[SessionStore] Message complete for ${sessionId}`)
        this.updateSessionStatus(sessionId, 'completed')
        break

      case 'permission_request':
        this.updateSessionStatus(sessionId, 'permission_pending')

        if (msg.requestId) {
          const permMessage: Message = {
            id: 'permission-' + msg.requestId,
            type: 'permission_request',
            content: msg.description || '权限请求: ' + (msg.toolName || ''),
            timestamp: new Date().toISOString(),
            toolName: msg.toolName,
            permissionId: msg.requestId,
            permissionDescription: msg.description
          }
          this.addMessage(sessionId, permMessage)
        }
        break

      case 'question':
      case 'questions':
        this.updateSessionStatus(sessionId, 'question_pending')

        let questionId: string
        let questionText: string
        let options: string[]

        if (msg.questions && msg.questions.length > 0) {
          const firstQuestion = msg.questions[0]
          questionId = 'q-' + Date.now()
          questionText = firstQuestion.question || ''
          const optList: string[] = []
          if (firstQuestion.options) {
            for (let i = 0; i < firstQuestion.options.length; i++) {
              const opt = firstQuestion.options[i]
              if (opt.label) {
                optList.push(opt.label)
              }
            }
          }
          options = optList
        } else {
          questionId = msg.questionId || 'q-' + Date.now()
          questionText = msg.questionText || ''
          options = msg.options || []
        }

        const qMessage: Message = {
          id: 'question-' + questionId,
          type: 'question',
          content: questionText,
          timestamp: new Date().toISOString(),
          questionId: questionId,
          options: options
        }
        this.addMessage(sessionId, qMessage)
        break

      case 'user_message_echo':
        console.info(`[SessionStore] User message echo for ${sessionId}`)
        if (msg.content) {
          let contentString = ''
          if (typeof msg.content === 'string') {
            contentString = msg.content
          } else {
            contentString = JSON.stringify(msg.content)
          }

          // 解析桌面端格式
          if (contentString.startsWith('[') && contentString.includes('"text"')) {
            try {
              const jsonArray = JSON.parse(contentString) as Array<Record<string, string>>
              const texts: string[] = []
              for (let i = 0; i < jsonArray.length; i++) {
                if (jsonArray[i]['text']) {
                  texts.push(jsonArray[i]['text'])
                }
              }
              if (texts.length > 0) {
                contentString = texts.join('\n')
              }
            } catch (e) {
              // 解析失败，使用原内容
            }
          }

          const userMsg: Message = {
            id: msg.id || 'user-' + Date.now(),
            type: 'user',
            content: contentString,
            timestamp: msg.timestamp || new Date().toISOString()
          }
          this.addMessage(sessionId, userMsg)
        }
        break

      case 'token_usage':
        // Token 使用量处理
        break

      case 'task_list':
      case 'task_update':
        if (msg.tasks) {
          this.sessionTasks.set(sessionId, msg.tasks)
          this.taskBarDismissed = false
          this.notifySessionsChanged()
        }
        break

      case 'error':
        if (msg.text) {
          this.error = msg.text
        }
        break
    }
  }

  // MARK: - 私有方法

  private updateSessionStatusFromState(sessionId: string, state: string): void {
    let status: SessionStatus = 'idle'
    switch (state) {
      case 'idle':
        status = 'idle'
        break
      case 'thinking':
        status = 'thinking'
        break
      case 'streaming':
        status = 'streaming'
        break
      case 'tool_executing':
        status = 'tool_executing'
        break
      case 'permission_pending':
        status = 'permission_pending'
        break
      case 'question_pending':
        status = 'question_pending'
        break
      case 'completed':
        status = 'completed'
        break
    }
    this.updateSessionStatus(sessionId, status)
  }

  private updateSessionTitle(sessionId: string, title: string): void {
    const index = this.sessions.findIndex(s => s.id === sessionId)
    if (index >= 0) {
      const old = this.sessions[index]
      const updated: Session = {
        id: old.id,
        title: title,
        projectPath: old.projectPath,
        workDir: old.workDir,
        workDirExists: old.workDirExists,
        createdAt: old.createdAt,
        modifiedAt: old.modifiedAt,
        messageCount: old.messageCount,
        providerId: old.providerId
      }
      this.sessions[index] = updated
      this.notifySessionsChanged()
    }
  }

  private updateToolResult(sessionId: string, toolUseId: string, content: object | string): void {
    const messages = this.messages.get(sessionId)
    if (!messages) return

    const index = messages.findIndex(m => m.id === toolUseId)
    if (index >= 0) {
      const resultString = typeof content === 'string' ? content : JSON.stringify(content)
      messages[index].toolResult = resultString
      messages[index].toolStatus = 'completed'
      this.notifyMessagesChanged(sessionId)
    }
  }

  // MARK: - 通知

  private notifySessionsChanged(): void {
    if (this.onSessionsChanged) {
      this.onSessionsChanged()
    }
  }

  private notifyMessagesChanged(sessionId: string): void {
    if (this.onMessagesChanged) {
      this.onMessagesChanged(sessionId)
    }
  }

  private notifyStatusChanged(sessionId: string, status: SessionStatus): void {
    if (this.onStatusChanged) {
      this.onStatusChanged(sessionId, status)
    }
  }

  // MARK: - 任务面板

  getCurrentTasks(): TaskItem[] {
    if (!this.currentSessionId) return []
    return this.sessionTasks.get(this.currentSessionId) || []
  }

  toggleTaskBarExpanded(): void {
    this.taskBarExpanded = !this.taskBarExpanded
    this.notifySessionsChanged()
  }

  dismissTaskBar(): void {
    this.taskBarDismissed = true
    this.taskBarExpanded = false
    this.notifySessionsChanged()
  }

  // MARK: - 最近项目

  async fetchRecentProjects(): Promise<void> {
    this.isLoadingRecentProjects = true
    try {
      this.recentProjects = await apiService.getRecentProjects()
    } catch (e) {
      console.error(`[SessionStore] Fetch recent projects error: ${e}`)
    }
    this.isLoadingRecentProjects = false
    this.notifySessionsChanged()
  }

  // MARK: - 清除所有数据

  async clearAllSessions(): Promise<void> {
    // 断开所有 WebSocket 连接
    this.disconnectAllSessions()

    // 清除所有本地存储的数据
    for (const session of this.sessions) {
      await storageService.deleteMessages(session.id)
    }

    // 清空内存数据
    this.sessions = []
    this.messages.clear()
    this.sessionStatuses.clear()
    this.sessionTasks.clear()
    this.currentSessionId = null

    // 清除本地存储
    await storageService.saveSessions([])
    await storageService.saveSessionStatuses(new Map())

    this.notifySessionsChanged()
    console.info('[SessionStore] All sessions cleared')
  }
}

export const sessionStore = SessionStore.getInstance()
