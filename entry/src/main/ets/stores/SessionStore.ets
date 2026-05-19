/**
 * 会话状态管理
 * 支持状态持久化和 WebSocket 实时更新
 */

import { Session, Message, SessionStatus, TaskItem, PermissionMode, WSMessage, OutgoingMessage, RecentProject, AttachmentRef } from '../models/Models'
import { apiService } from '../services/APIService'
import { wsService } from '../services/WebSocketService'
import { storageService } from '../services/StorageService'
import { notificationHelper } from '../services/NotificationHelper'
import { liveViewService, getAiDisplayName } from '../services/LiveViewService'
import { authStore } from './AuthStore'
import { appState } from './AppState'

export class SessionStore {
  private static instance: SessionStore

  // 会话列表
  sessions: Session[] = []
  currentSessionId: string | null = null

  // 消息存储
  messages: Map<string, Message[]> = new Map()

  // 输入框草稿
  inputDrafts: Map<string, string> = new Map()

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

  // 本地删除的会话ID集合（不从服务器重新加载）
  private locallyDeletedSessionIds: Set<string> = new Set()
  private isLocalDataLoaded: boolean = false

  // 状态变更回调（多监听者列表）
  private sessionsChangedListeners: Array<() => void> = []
  private messagesChangedListeners: Array<(sessionId: string) => void> = []
  private statusChangedListeners: Array<(sessionId: string, status: SessionStatus) => void> = []
  private rawMessageListeners: Array<(sessionId: string, msg: WSMessage) => void> = []

  // completed→idle 定时器追踪
  private completedTimers: Map<string, number> = new Map()

  // MARK: - 监听者注册

  addSessionsChangedListener(listener: () => void): void {
    this.sessionsChangedListeners.push(listener)
  }
  removeSessionsChangedListener(listener: () => void): void {
    this.sessionsChangedListeners = this.sessionsChangedListeners.filter(l => l !== listener)
  }
  addMessagesChangedListener(listener: (sessionId: string) => void): void {
    this.messagesChangedListeners.push(listener)
  }
  removeMessagesChangedListener(listener: (sessionId: string) => void): void {
    this.messagesChangedListeners = this.messagesChangedListeners.filter(l => l !== listener)
  }
  addStatusChangedListener(listener: (sessionId: string, status: SessionStatus) => void): void {
    this.statusChangedListeners.push(listener)
  }
  removeStatusChangedListener(listener: (sessionId: string, status: SessionStatus) => void): void {
    this.statusChangedListeners = this.statusChangedListeners.filter(l => l !== listener)
  }
  addRawMessageListener(listener: (sessionId: string, msg: WSMessage) => void): void {
    this.rawMessageListeners.push(listener)
  }
  removeRawMessageListener(listener: (sessionId: string, msg: WSMessage) => void): void {
    this.rawMessageListeners = this.rawMessageListeners.filter(l => l !== listener)
  }

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

    // 设置全局 WebSocket 消息处理器（桌面→移动端同步）
    wsService.setGlobalMessageHandler((message: WSMessage) => {
      this.handleGlobalWSMessage(message)
    })

    // 加载本地缓存的会话数据
    this.loadLocalData()
  }

  // MARK: - 本地数据加载

  private async loadLocalData(): Promise<void> {
    try {
      // 加载本地已删除的会话ID列表
      const deletedIds = await storageService.loadString('locally_deleted_session_ids')
      if (deletedIds) {
        try {
          const ids: string[] = JSON.parse(deletedIds)
          for (let i = 0; i < ids.length; i++) {
            this.locallyDeletedSessionIds.add(ids[i])
          }
          console.info(`[SessionStore] Loaded ${this.locallyDeletedSessionIds.size} locally deleted session IDs`)
        } catch (e) {
          console.error(`[SessionStore] Parse deleted session IDs error: ${e}`)
        }
      }

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

      this.isLocalDataLoaded = true
    } catch (e) {
      console.error(`[SessionStore] Load local data error: ${e}`)
      this.isLocalDataLoaded = true
    }
  }

  // MARK: - 会话操作

  async fetchSessions(): Promise<void> {
    // 等待本地数据加载完成，最多等待 5 秒
    let waitCount = 0
    const maxWait = 100 // 50ms * 100 = 5s
    while (!this.isLocalDataLoaded && waitCount < maxWait) {
      await new Promise<void>(resolve => setTimeout(resolve, 50))
      waitCount++
    }

    this.isLoading = true
    this.error = null
    this.notifySessionsChanged()

    try {
      const serverSessions = await apiService.getSessions()

      // 过滤掉本地已删除的会话
      const filteredServerSessions = serverSessions.filter(s => !this.locallyDeletedSessionIds.has(s.id))

      // 合并本地修改时间（避免被服务器旧数据覆盖）
      const localModifiedMap: Map<string, string> = new Map()
      for (let i = 0; i < this.sessions.length; i++) {
        localModifiedMap.set(this.sessions[i].id, this.sessions[i].modifiedAt)
      }

      this.sessions = filteredServerSessions.map(serverSession => {
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
              aiTool: serverSession.aiTool
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

  getSessionAiTool(sessionId: string): string {
    const session = this.sessions.find(s => s.id === sessionId)
    return session?.aiTool || ''
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

      // 清除 completed→idle 定时器
      const timer = this.completedTimers.get(sessionId)
      if (timer !== undefined) {
        clearTimeout(timer)
        this.completedTimers.delete(sessionId)
      }

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

    // 清除 completed→idle 定时器
    const timer = this.completedTimers.get(sessionId)
    if (timer !== undefined) {
      clearTimeout(timer)
      this.completedTimers.delete(sessionId)
    }

    // 记录到本地已删除列表，防止从服务器重新加载
    this.locallyDeletedSessionIds.add(sessionId)
    const deletedIdsArray: string[] = []
    this.locallyDeletedSessionIds.forEach(id => deletedIdsArray.push(id))
    await storageService.saveString('locally_deleted_session_ids', JSON.stringify(deletedIdsArray))

    // 删除本地数据
    await storageService.deleteMessages(sessionId)
    await storageService.saveSessions(this.sessions)
    await storageService.saveSessionStatuses(this.sessionStatuses)

    // 断开 WebSocket
    wsService.disconnectSession(sessionId)

    this.notifySessionsChanged()
    console.info(`[SessionStore] Deleted local session: ${sessionId}`)
  }

  // 从已删除列表中移除（用于导入会话时恢复）
  async restoreSessionFromDeleted(sessionId: string): Promise<void> {
    this.locallyDeletedSessionIds.delete(sessionId)
    const deletedIdsArray: string[] = []
    this.locallyDeletedSessionIds.forEach(id => deletedIdsArray.push(id))
    await storageService.saveString('locally_deleted_session_ids', JSON.stringify(deletedIdsArray))
    console.info(`[SessionStore] Restored session from deleted list: ${sessionId}`)
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
          aiTool: old.aiTool
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
    // 检查内存中是否已有消息，避免重复加载覆盖内存数据
    const existing = this.messages.get(sessionId)
    if (existing && existing.length > 0) {
      // 内存中已有消息，跳过本地存储加载（防止覆盖 WebSocket 实时消息）
      console.info(`[SessionStore] loadMessages: ${sessionId} already has ${existing.length} messages in memory, skip local load`)
    } else {
      // 先加载本地缓存（快速展示）
      const localMessages = await storageService.loadMessages(sessionId)
      if (localMessages.length > 0) {
        this.messages.set(sessionId, localMessages)
        this.notifyMessagesChanged(sessionId)
      }
    }

    // 后台静默同步服务器消息（不阻塞页面渲染）
    this.syncMessagesFromServer(sessionId)
  }

  // 后台同步服务器消息
  private async syncMessagesFromServer(sessionId: string): Promise<void> {
    try {
      const serverMessages = await apiService.getMessages(sessionId)

      // 重新获取当前本地消息（可能已被 WebSocket 更新），避免覆盖实时消息
      const currentLocal = this.messages.get(sessionId) || []
      const merged = this.mergeMessages(currentLocal, serverMessages)

      this.messages.set(sessionId, merged)
      this.notifyMessagesChanged(sessionId)

      // 保存到本地
      await storageService.saveMessages(sessionId, merged)
    } catch (e) {
      console.error(`[SessionStore] Sync messages error: ${e}`)
    }
  }

  // 智能合并消息：服务器消息为主，保留本地独有的消息
  // 使用多维度去重（toolUseId / id / 内容摘要）防止重复
  private mergeMessages(localMessages: Message[], serverMessages: Message[]): Message[] {
    // 为服务器消息构建多维去重组
    const serverKeys: Map<string, boolean> = new Map()
    const serverToolUseIds: Set<string> = new Set()
    const serverIds: Set<string> = new Set()

    for (let i = 0; i < serverMessages.length; i++) {
      const msg = serverMessages[i]
      // 主键: type + content 摘要
      const primaryKey = this.messageContentKey(msg)
      serverKeys.set(primaryKey, true)
      if (msg.toolUseId) {
        serverToolUseIds.add(msg.toolUseId)
      }
      if (msg.id) {
        serverIds.add(msg.id)
      }
    }

    // 先添加服务器消息
    const result: Message[] = [...serverMessages]

    // 再检查本地消息中是否有服务器没有的
    for (let i = 0; i < localMessages.length; i++) {
      const msg = localMessages[i]
      const primaryKey = this.messageContentKey(msg)

      // 跳过: 主键匹配
      if (serverKeys.has(primaryKey)) continue
      // 跳过: toolUseId 匹配
      if (msg.toolUseId && serverToolUseIds.has(msg.toolUseId)) continue
      // 跳过: id 匹配
      if (msg.id && serverIds.has(msg.id)) continue

      // 额外检查: 对没有 toolUseId 的本地消息，检查服务器是否有同 type 同内容的
      let foundByContent = false
      if (!msg.toolUseId && msg.type !== 'user') {
        for (let j = 0; j < serverMessages.length; j++) {
          const sm = serverMessages[j]
          if (sm.type === msg.type) {
            const localContent = (msg.content || msg.toolResult || '').substring(0, 200)
            const serverContent = (sm.content || sm.toolResult || '').substring(0, 200)
            if (localContent.length > 10 && localContent === serverContent) {
              foundByContent = true
              break
            }
          }
        }
      }

      if (!foundByContent) {
        result.push(msg)
      }
    }

    // 按时间排序
    result.sort((a, b) => {
      return new Date(a.timestamp).getTime() - new Date(b.timestamp).getTime()
    })

    // 最终去重：同类型同内容只保留一条（不含时间戳比对，避免本地/服务器时间戳差异导致重复）
    const finalResult: Message[] = []
    const seenFinal: Set<string> = new Set()
    for (let i = 0; i < result.length; i++) {
      const m = result[i]
      const finalKey = m.type + '|' + (m.toolUseId || '') + '|' + (m.content || m.toolResult || '').substring(0, 200)
      if (seenFinal.has(finalKey)) continue
      seenFinal.add(finalKey)
      finalResult.push(m)
    }

    return finalResult
  }

  // 生成消息内容去重键
  private messageContentKey(msg: Message): string {
    // 优先使用 toolUseId 或 msg.id（排除本地生成的临时 id）
    if (msg.toolUseId) {
      return 'toolUseId:' + msg.toolUseId
    }
    if (msg.id && !msg.id.startsWith('user-') && !msg.id.startsWith('err-') && !msg.id.startsWith('sys-')) {
      return 'id:' + msg.id
    }
    // fallback：按类型 + 内容去重（不含时间戳，避免本地和服务器时间戳不一致导致重复）
    const content = (msg.content || '') || (msg.toolResult || '')
    return msg.type + ':' + content.substring(0, 300)
  }

  addMessage(sessionId: string, message: Message): void {
    let sessionMessages = this.messages.get(sessionId)
    if (!sessionMessages) {
      sessionMessages = []
    }

    // 去重
    let exists = false
    for (let i = 0; i < sessionMessages.length; i++) {
      if (sessionMessages[i].id === message.id) {
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
    wsService.connectGlobal()
    this.wsSubscribed = true

    console.info(`[SessionStore] Subscribed to ${this.sessions.length} sessions, global WS connected`)
  }

  subscribeToSession(sessionId: string): void {
    const serverUrl = authStore.serverUrl
    if (!serverUrl) return

    wsService.setServerUrl(serverUrl)
    wsService.addSubscription(sessionId)
    wsService.connectGlobal()
    this.wsSubscribed = true
    console.info(`[SessionStore] Subscribed to ${sessionId}, global WS connected`)
  }

  disconnectAllSessions(): void {
    wsService.disconnectAll()
  }

  sendMessage(content: string, attachments?: AttachmentRef[]): void {
    if (!this.currentSessionId) return

    const sessionId = this.currentSessionId

    // 添加用户消息
    const userMessage: Message = {
      id: 'user-' + Date.now(),
      type: 'user',
      content: content,
      timestamp: new Date().toISOString()
    }
    this.addMessage(sessionId, userMessage)

    // 发送到服务器
    wsService.sendUserMessage(sessionId, content, attachments)

    // 更新状态
    this.updateSessionStatus(sessionId, 'thinking')
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

  /**
   * 同步会话状态：清除过期的"工作中"状态
   * 当对话列表出现时调用，修复状态停留在 working 但不继续的问题
   */
  syncSessionStatuses(): void {
    const now = Date.now()
    for (const session of this.sessions) {
      const status = this.sessionStatuses.get(session.id)
      if (!status || status === 'idle') continue

      // 如果 WS 没连接，working 状态肯定是过期的
      const wsConnected = wsService.isConnected(session.id)

      if (status === 'completed') {
        // completed 超过 10 秒无新消息 → idle
        const timer = this.completedTimers.get(session.id)
        if (timer === undefined) {
          // timer 已触发或不存在 → 状态可能已过期
          // 同时 WS 未连接说明不在聊天页面 → 可以直接 idle
          if (!wsConnected) {
            this.updateSessionStatus(session.id, 'idle')
          }
        }
        continue
      }

      // working 状态（thinking、streaming、tool_executing 等）
      if (!wsConnected) {
        console.info(`[SessionStore] Stale status for ${session.id}: ${status}, WS not connected, resetting to idle`)
        this.updateSessionStatus(session.id, 'idle')
      }
    }
  }

  // 更新会话状态
  updateSessionStatus(sessionId: string, status: SessionStatus): void {
    this.sessionStatuses.set(sessionId, status)
    this.notifyStatusChanged(sessionId, status)
    this.notifySessionsChanged()

    // 只持久化保存稳定状态（idle 和 completed），临时状态不保存
    if (status === 'idle' || status === 'completed') {
      storageService.saveSessionStatuses(this.sessionStatuses)
    }

    
    // completed 状态 3 秒后自动恢复为 idle，让吉祥物回到睡眠
    if (status === 'completed') {
      // 清除之前的 timer
      const oldTimer = this.completedTimers.get(sessionId)
      if (oldTimer !== undefined) {
        clearTimeout(oldTimer)
      }
      const timer = setTimeout(() => {
        this.completedTimers.delete(sessionId)
        // 只有当前仍然是 completed 时才恢复（避免覆盖新的工作状态）
        if (this.sessionStatuses.get(sessionId) === 'completed') {
          this.updateSessionStatus(sessionId, 'idle')
        }
      }, 8000)
      this.completedTimers.set(sessionId, timer)
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
    for (const listener of this.rawMessageListeners) {
      listener(sessionId, msg)
    }

    // 忽略 connected 消息
    if (msg.type === 'connected') {
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
        // 解析权限模式/模型/努力度同步
        if (msg.verb) {
          if (msg.verb.startsWith('permission_mode:')) {
            const mode = msg.verb.substring('permission_mode:'.length) as PermissionMode
            this.sessionPermissionModes.set(sessionId, mode)
            this.notifySessionsChanged()
          } else if (msg.verb.startsWith('model_updated:')) {
            const modelId = msg.verb.substring('model_updated:'.length)
            console.info(`[SessionStore] Model synced: ${modelId}`)
            // 触发 AppState 刷新模型列表
            appState.fetchModels()
            appState.getCurrentModel()
          } else if (msg.verb.startsWith('effort_updated:')) {
            const level = msg.verb.substring('effort_updated:'.length)
            appState.setEffortLevel(level)
            // 触发刷新服务端值
            appState.fetchEffortOptions()
          }
        }
        break

      case 'content_start':
        this.updateSessionStatus(sessionId, 'streaming')
        // 启动实况窗
        liveViewService.showThinking(sessionId, this.getSessionAiTool(sessionId))
        // 开始回复文本 → 把最后一个 running 工具标记为 completed
        if (msg.blockType === 'text') {
          const msgs = this.messages.get(sessionId)
          if (msgs) {
            for (let i = msgs.length - 1; i >= 0; i--) {
              if (msgs[i].type === 'tool_use' && msgs[i].toolStatus === 'running') {
                msgs[i].toolStatus = 'completed'
                break
              }
            }
          }
          this.notifyMessagesChanged(sessionId)
        }
        break

      case 'content_delta':
      case 'thinking':
        // 流式消息处理在 ChatDetailPage 中处理
        break

      case 'tool_use_complete':
        this.updateSessionStatus(sessionId, 'tool_executing')

        if (msg.toolName) {
          // 把上一个正在运行的标记为完成
          const msgs = this.messages.get(sessionId)
          if (msgs) {
            for (let i = msgs.length - 1; i >= 0; i--) {
              if (msgs[i].type === 'tool_use' && msgs[i].toolStatus === 'running') {
                msgs[i].toolStatus = 'completed'
                break
              }
            }
          }
          this.notifyMessagesChanged(sessionId)
          const toolId = msg.toolUseId || 'tool-' + Date.now()
          const toolMessage: Message = {
            id: toolId,
            type: 'tool_use',
            content: '',
            timestamp: new Date().toISOString(),
            toolName: msg.toolName,
            toolInput: msg.input,
            toolUseId: toolId,
            toolStatus: 'running',
            parentToolUseId: msg.parentToolUseId as string | undefined
          }
          this.addMessage(sessionId, toolMessage)
        }
        break

      case 'tool_result':
        if (msg.toolUseId && msg.content !== undefined && msg.content !== null) {
          this.updateToolResult(sessionId, msg.toolUseId, msg.content, msg.isError === true)
        }
        break

      case 'message_complete':
        console.info(`[SessionStore] Message complete for ${sessionId}`)
        this.updateSessionStatus(sessionId, 'completed')
        // 结束实况窗
        liveViewService.showComplete(sessionId)
        // 把还在 running 的工具标记为 completed（最后那个没有新工具触发）
        {
          const msgs = this.messages.get(sessionId)
          if (msgs) {
            for (let i = msgs.length - 1; i >= 0; i--) {
              if (msgs[i].type === 'tool_use' && msgs[i].toolStatus === 'running') {
                msgs[i].toolStatus = 'completed'
              }
            }
          }
          this.notifyMessagesChanged(sessionId)
        }
        // 后台通知 - 从最后一条 AI 消息获取内容
        {
          const messages = this.messages.get(sessionId)
          let lastContent = ''
          if (messages && messages.length > 0) {
            // 从后往前找最后一条 assistant 消息
            for (let i = messages.length - 1; i >= 0; i--) {
              if (messages[i].type === 'assistant') {
                lastContent = messages[i].content || ''
                break
              }
            }
          }
          const notifyContent = lastContent || '已完成回复'
          this.notifyIfBackground(sessionId, 'AI 回复完成', notifyContent)
        }
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
        // 后台通知
        this.notifyIfBackground(sessionId, '权限请求', msg.toolName || '', 'permission')
        break

      case 'question':
      case 'questions':
        this.updateSessionStatus(sessionId, 'question_pending')

        let questionId: string
        let questionText: string
        let options: string[]

        if (msg.questions && msg.questions.length > 0) {
          const firstQuestion = msg.questions[0]
          questionId = 'q-' + Date.now() + '-' + Math.random().toString(36).substring(2, 6)
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
          questionId = msg.questionId || 'q-' + Date.now() + '-' + Math.random().toString(36).substring(2, 6)
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

        // 后台通知
        if (questionText) {
          this.notifyIfBackground(sessionId, '问题', questionText, 'question')
        }
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

          // 去重：检查是否已有相同内容的用户消息（sendMessage 已添加本地消息）
          const existingMessages = this.messages.get(sessionId)
          let isDuplicate = false
          if (existingMessages) {
            for (let i = existingMessages.length - 1; i >= 0; i--) {
              const m = existingMessages[i]
              if (m.type === 'user' && m.content === contentString) {
                isDuplicate = true
                break
              }
              // 只检查最近的消息，避免全量扫描
              if (existingMessages.length - i > 10) break
            }
          }

          if (!isDuplicate) {
            const userMsg: Message = {
              id: msg.id || 'user-' + Date.now(),
              type: 'user',
              content: contentString,
              timestamp: msg.timestamp || new Date().toISOString()
            }
            this.addMessage(sessionId, userMsg)
            // 后台通知（桌面端发来的用户消息）
            this.notifyIfBackground(sessionId, '用户消息', contentString)
          }
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

      case 'error': {
        const errText: string = (msg.text as string) || (msg.message as string) || '未知错误'
        this.error = errText
        const errMsg: Message = {
          id: 'err-' + Date.now(),
          type: 'error',
          content: errText,
          timestamp: msg.timestamp || new Date().toISOString()
        }
        this.addMessage(sessionId, errMsg)
        break
      }
      case 'system_notification': {
        // 处理 Agent task_notification
        if (msg.subtype === 'task_notification') {
          const taskData = msg.data as Record<string, Object> | undefined
          if (taskData && taskData['toolUseId']) {
            const targetToolUseId = taskData['toolUseId'] as string
            const taskStatus = taskData['status'] as string || ''
            const msgSummary = taskData['summary'] as string || msg.message as string || ''

            // 映射 task status 到 agentTaskStatus
            let agentStatus: string = 'running'
            if (taskStatus === 'completed') agentStatus = 'done'
            else if (taskStatus === 'failed') agentStatus = 'failed'
            else if (taskStatus === 'stopped') agentStatus = 'stopped'

            // 找到对应的 tool_use 消息并更新其 Agent 状态
            const msgs = this.messages.get(sessionId)
            if (msgs) {
              for (let i = msgs.length - 1; i >= 0; i--) {
                if (msgs[i].type === 'tool_use' && msgs[i].toolUseId === targetToolUseId) {
                  msgs[i].agentTaskStatus = agentStatus as 'starting' | 'running' | 'done' | 'failed' | 'stopped'
                  msgs[i].agentSummary = msgSummary
                  break
                }
              }
              this.notifyMessagesChanged(sessionId)
            }
          }
        } else {
          const sysText: string = (msg.text as string) || (msg.message as string) || ''
          const sysMsg: Message = {
            id: 'sys-' + Date.now(),
            type: 'system',
            content: sysText,
            timestamp: msg.timestamp || new Date().toISOString()
          }
          this.addMessage(sessionId, sysMsg)
        }
        break
      }
    }
  }

  // MARK: - 全局 WebSocket 消息处理（桌面→移动端同步）

  private handleGlobalWSMessage(msg: WSMessage): void {
    console.info(`[SessionStore] Global WS msg: ${msg.type}`)

    switch (msg.type) {
      case 'sessions_updated':
        this.fetchSessions().catch((e: Error) => {
          console.error(`[SessionStore] fetchSessions on global event error: ${e.message}`)
        })
        break

      case 'session_activated':
        if (msg.sessionId) {
          console.info(`[SessionStore] New session activated: ${msg.sessionId}`)
          this.subscribeToSession(msg.sessionId)
        }
        break

      case 'session_status_changed':
        if (msg.sessionId && msg.state) {
          console.info(`[SessionStore] Session status changed: ${msg.sessionId} -> ${msg.state}`)
          this.updateSessionStatusFromState(msg.sessionId, msg.state)
        }
        break

      case 'session_broadcast':
        if (msg.sessionId && msg.message) {
          // 已有直连 WS 的会话不重复处理全局广播，避免消息重复
          if (wsService.isSubscribed(msg.sessionId)) {
            console.info(`[SessionStore] Skip session_broadcast for ${msg.sessionId}: already subscribed`)
            break
          }
          console.info(`[SessionStore] Session broadcast for ${msg.sessionId}`)
          this.handleWSMessage(msg.sessionId, msg.message as WSMessage)
        }
        break
    }
  }

  // MARK: - 私有方法

  /**
   * 后台时发送通知
   */
  private notifyIfBackground(sessionId: string, title: string, content: string, notifyType?: string): void {
    console.info(`[SessionStore] notifyIfBackground: ${sessionId}, type=${notifyType || 'default'}`)
    if (appState.isInForeground && this.currentSessionId === sessionId && notifyType !== 'permission') {
      console.info(`[SessionStore] Skip notification: user is viewing this session`)
      return
    }
    const session = this.sessions.find(s => s.id === sessionId)
    const sessionTitle = session?.title || title
    const aiName = getAiDisplayName(session?.aiTool)

    switch (notifyType) {
      case 'permission':
        notificationHelper.notifyPermissionRequest(aiName, sessionTitle, content, sessionId)
        break
      case 'question':
        notificationHelper.notifyQuestion(aiName, sessionTitle, content, sessionId)
        break
      default:
        notificationHelper.notifyNewMessage(aiName, sessionTitle, content, sessionId)
        break
    }
  }

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
        aiTool: old.aiTool
      }
      this.sessions[index] = updated
      this.notifySessionsChanged()
    }
  }

  private updateToolResult(sessionId: string, toolUseId: string, content: object | string, isError: boolean): void {
    const messages = this.messages.get(sessionId)
    if (!messages) {
      console.warn(`[SessionStore] No messages found for session ${sessionId}`)
      return
    }

    const index = messages.findIndex(m => m.id === toolUseId || m.toolUseId === toolUseId)
    if (index >= 0) {
      const resultString = typeof content === 'string' ? content : JSON.stringify(content)
      messages[index].toolResult = resultString
      messages[index].toolStatus = isError ? 'failed' : 'completed'
      this.notifyMessagesChanged(sessionId)
      console.info(`[SessionStore] Tool ${toolUseId} updated: ${isError ? 'failed' : 'completed'}`)
    } else {
      // 工具消息不存在时（如乱序到达），用 tool_result 创建
      console.warn(`[SessionStore] Tool ${toolUseId} not found, creating from tool_result`)
      const resultString = typeof content === 'string' ? content : JSON.stringify(content)
      const toolMessage: Message = {
        id: toolUseId,
        type: 'tool_use',
        content: '',
        timestamp: new Date().toISOString(),
        toolResult: resultString,
        toolStatus: isError ? 'failed' : 'completed'
      }
      this.addMessage(sessionId, toolMessage)
    }
  }

  // MARK: - 通知

  private notifySessionsChanged(): void {
    for (const listener of this.sessionsChangedListeners) {
      listener()
    }
  }

  private notifyMessagesChanged(sessionId: string): void {
    for (const listener of this.messagesChangedListeners) {
      listener(sessionId)
    }
  }

  private notifyStatusChanged(sessionId: string, status: SessionStatus): void {
    for (const listener of this.statusChangedListeners) {
      listener(sessionId, status)
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

    // 清除所有 completed→idle 定时器
    this.completedTimers.forEach((timer) => clearTimeout(timer))
    this.completedTimers.clear()

    // 清除本地存储
    await storageService.saveSessions([])
    await storageService.saveSessionStatuses(new Map())

    this.notifySessionsChanged()
    console.info('[SessionStore] All sessions cleared')
  }
}

export const sessionStore = SessionStore.getInstance()
