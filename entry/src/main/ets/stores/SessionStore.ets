/**
 * 会话状态管理
 * 支持状态持久化和 WebSocket 实时更新
 */

import { Session, Message, SessionStatus, TaskItem, PermissionMode, WSMessage, OutgoingMessage, RecentProject, AttachmentRef, PendingPermission, MessageImage } from '../models/Models'
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

  // 消息存储 (Tail: 已提交消息)
  messages: Map<string, Message[]> = new Map()

  // 流式消息缓冲 (Head: 活跃流式增量)
  streamHeads: Map<string, Message[]> = new Map()

  // 输入框草稿
  inputDrafts: Map<string, string> = new Map()

  // 会话状态
  sessionStatuses: Map<string, SessionStatus> = new Map()
  sessionPermissionModes: Map<string, PermissionMode> = new Map()

  // 任务列表
  sessionTasks: Map<string, TaskItem[]> = new Map()
  taskBarExpanded: boolean = false
  taskBarDismissed: boolean = false

  // 待审批权限请求
  pendingPermissions: Map<string, PendingPermission> = new Map()

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
  private localDataLoadedResolve: (() => void) | null = null
  private localDataLoadedPromise: Promise<void>

  // 数据最后拉取时间（用于 onForeground 防重复拉取）
  lastFetchedAt: number = 0

  // 状态变更回调（多监听者列表）
  private sessionsChangedListeners: Array<() => void> = []
  private messagesChangedListeners: Array<(sessionId: string) => void> = []
  private statusChangedListeners: Array<(sessionId: string, status: SessionStatus) => void> = []
  private rawMessageListeners: Array<(sessionId: string, msg: WSMessage) => void> = []

  // completed→idle 定时器追踪
  private completedTimers: Map<string, number> = new Map()

  // 消息去重缓存（防止全局 WS + 会话 WS 双通道重复传递）
  private recentMessageIds: Set<string> = new Set()
  private static readonly DEDUP_CACHE_TTL_MS = 30000 // 30 秒去重窗口（云中继延迟较高）

  // 定期状态同步定时器（每 15 秒检查一次过期的工作状态）
  private staleStatusTimer: number = -1

  // 定期重复消息清理定时器（每 60 秒兜底清一次）
  private dedupCleanupTimer: number = -1

  // 串行化保存队列（防止并发写入竞态导致数据丢失）
  private saveQueues: Map<string, Promise<void>> = new Map()

  // syncMessagesFromServer 并发保护 Set（防止重复调用导致竞态）
  private syncingSessions: Set<string> = new Set()

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
    // 初始化本地数据加载 Promise（移除 5s while 循环）
    this.localDataLoadedPromise = new Promise<void>((resolve) => {
      this.localDataLoadedResolve = resolve
    })

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

    // 定期检查过期的工作状态（每 15 秒），防止 WS 断开后状态卡住
    this.staleStatusTimer = setInterval(() => {
      this.syncSessionStatuses()
    }, 15000)

    // 定期清理残留的重复消息（每 60 秒），兜底防线
    this.dedupCleanupTimer = setInterval(() => {
      this.cleanupDuplicateMessages()
    }, 60000)
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

        // 过滤掉本地已删除的会话（防止本地存储写入失败导致旧数据残留）
        this.sessions = this.sessions.filter(s => !this.locallyDeletedSessionIds.has(s.id))

        // 并发加载所有会话的本地消息（每批 5 个，避免一次性过多）
        const batchSize = 5
        for (let i = 0; i < localSessions.length; i += batchSize) {
          const batch = localSessions.slice(i, i + batchSize)
          const results = await Promise.all(
            batch.map(session => storageService.loadMessages(session.id))
          )
          for (let j = 0; j < batch.length; j++) {
            const messages = results[j]
            if (messages && messages.length > 0) {
              this.messages.set(batch[j].id, messages)
            }
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
      // 通知 fetchSessions 可以继续了（替代 5s while 循环）
      if (this.localDataLoadedResolve) {
        this.localDataLoadedResolve()
        this.localDataLoadedResolve = null
      }
    } catch (e) {
      console.error(`[SessionStore] Load local data error: ${e}`)
      this.isLocalDataLoaded = true
      if (this.localDataLoadedResolve) {
        this.localDataLoadedResolve()
        this.localDataLoadedResolve = null
      }
    }
  }

  // MARK: - 会话操作

  async fetchSessions(): Promise<void> {
    // 等待本地数据加载（用 Promise 替代 5s while 循环）
    await this.localDataLoadedPromise

    this.isLoading = true
    this.error = null
    this.notifySessionsChanged()

    try {
      const serverSessions = await apiService.getSessions(undefined, 50)

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
      this.lastFetchedAt = Date.now()
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

      // 记录到本地已删除列表，防止服务器缓存未清除前的 fetchSessions 重新拉回（先保存删除标记）
      this.locallyDeletedSessionIds.add(sessionId)
      const deletedIdsArray: string[] = []
      this.locallyDeletedSessionIds.forEach(id => deletedIdsArray.push(id))
      await storageService.saveString('locally_deleted_session_ids', JSON.stringify(deletedIdsArray))

      // 更新内存数据
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
    // 记录到本地已删除列表，防止从服务器重新加载（先保存删除标记，确保原子性）
    this.locallyDeletedSessionIds.add(sessionId)
    const deletedIdsArray: string[] = []
    this.locallyDeletedSessionIds.forEach(id => deletedIdsArray.push(id))
    await storageService.saveString('locally_deleted_session_ids', JSON.stringify(deletedIdsArray))

    // 更新内存数据
    this.sessions = this.sessions.filter(s => s.id !== sessionId)
    this.messages.delete(sessionId)
    this.sessionStatuses.delete(sessionId)

    // 清除 completed→idle 定时器
    const timer = this.completedTimers.get(sessionId)
    if (timer !== undefined) {
      clearTimeout(timer)
      this.completedTimers.delete(sessionId)
    }

    // 删除本地数据（先删除消息，再保存更新后的会话列表）
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

    // 切换会话时从已有消息中提取任务列表
    if (sessionId) {
      this.refreshTasksFromMessages(sessionId)
      // 延迟重试：等 loadMessages/syncMessagesFromServer 完成后再次提取
      setTimeout(() => {
        this.refreshTasksFromMessages(sessionId)
      }, 3000)
    }
  }

  // MARK: - 工具入参提取（兼容多种格式）
  // tool_use_complete 的 toolInput 可能是：
  //   a) 工具输入: { taskId: "1", status: "completed" }
  //   b) 工具输出: { taskId: "1", statusChange: { to: "completed" } }
  //   c) 带 data 包装: { data: { taskId: "1", statusChange: { to: "completed" } } }
  //   d) 带 task 嵌套: { task: { id: "1", subject: "..." } }
  //   e) data + task 嵌套: { data: { task: { id: "1" } } }

  /**
   * 从 toolInput 中安全提取字符串值，按顺序尝试多个 key 路径
   */
  private getStr(input: Record<string, Object> | undefined, ...paths: string[]): string {
    if (!input) return ''
    for (const p of paths) {
      const parts = p.split('.')
      let cur: Object | undefined = input
      let found = true
      for (const k of parts) {
        if (!cur || typeof cur !== 'object') { found = false; break }
        const obj = cur as Record<string, Object>
        const v = obj[k]
        if (v === undefined || v === null) { found = false; break }
        cur = v
      }
      if (found && cur !== undefined && cur !== null) {
        return String(cur)
      }
    }
    return ''
  }

  /**
   * 从 toolInput 中提取对象（如 statusChange / task）
   */
  private getObj(input: Record<string, Object> | undefined, ...paths: string[]): Record<string, Object> | undefined {
    if (!input) return undefined
    for (const p of paths) {
      const parts = p.split('.')
      let cur: Object | undefined = input
      let found = true
      for (const k of parts) {
        if (!cur || typeof cur !== 'object') { found = false; break }
        const obj = cur as Record<string, Object>
        const v = obj[k]
        if (v === undefined || v === null) { found = false; break }
        cur = v
      }
      if (found && cur !== undefined && cur !== null && typeof cur === 'object') {
        return cur as Record<string, Object>
      }
    }
    return undefined
  }

  // 从会话消息中提取任务列表（TaskCreate / TaskUpdate 工具调用）
  // 兼容 tool_use_complete 的两种路径：
  //   CLI 适配器路径（OpenCode）：input = 工具输出，带 data 包裹
  //     eg. { data: { task: { id: "1", subject: "..." } } }
  //     eg. { data: { taskId: "1", statusChange: { from, to } } }
  //   SDK 流式路径：input = 工具输入，无 data 包裹
  //     eg. { taskId: "1", status: "completed" }
  refreshTasksFromMessages(sessionId: string): void {
    const messages = this.messages.get(sessionId)
    if (!messages || messages.length === 0) {
      console.info(`[SessionStore] refreshTasks: ${sessionId} has 0 messages`)
      return
    }

    // DEBUG: 统计消息中 tool_use 的类型
    let toolUseCount = 0
    const toolNames = new Set<string>()
    for (const msg of messages) {
      if (msg.type === 'tool_use' && msg.toolName) {
        toolUseCount++
        toolNames.add(msg.toolName)
      }
    }
    console.info(`[SessionStore] refreshTasks: ${sessionId} has ${messages.length} msgs, ${toolUseCount} tool_use (${Array.from(toolNames).join(',')})`)

    // 任务 ID 生成器：TaskCreate 用自增序号作为降级 ID
    const taskMap: Map<string, TaskItem> = new Map()
    let taskCounter = 0

    // 第一遍：解析所有 TaskCreate / TaskUpdate 工具调用
    for (const msg of messages) {
      if (msg.type !== 'tool_use' || !msg.toolInput) continue
      const input = msg.toolInput as Record<string, Object>

      if (msg.toolName === 'TaskCreate') {
        taskCounter++
        // 尝试所有可能的 ID 路径
        const id = this.getStr(input,
          'data.task.id', 'task.id',
          'data.taskId', 'taskId',
          'id', 'data.id',
          String(taskCounter))
        const subject = this.getStr(input,
          'data.task.subject', 'task.subject',
          'subject', 'data.subject',
          'description', 'data.description')
        const description = this.getStr(input,
          'description', 'data.description',
          'data.task.description', 'task.description')
        const activeForm = this.getStr(input,
          'activeForm', 'data.activeForm',
          'data.task.activeForm', 'task.activeForm')
        if (id) {
          taskMap.set(id, {
            id: id,
            content: subject || description,
            status: 'pending',
            activeForm: activeForm
          })
        }
      } else if (msg.toolName === 'TaskUpdate') {
        const taskId = this.getStr(input,
          'data.taskId', 'taskId',
          'id', 'data.id')
        const status = this.getStr(input,
          'status', 'data.status',
          'statusChange.to', 'data.statusChange.to')
        if (taskId && taskMap.has(taskId)) {
          const existing = taskMap.get(taskId)!
          if (status === 'in_progress') existing.status = 'in_progress'
          else if (status === 'completed') existing.status = 'completed'
          else if (status === 'failed') existing.status = 'failed'
          // 有时 TaskUpdate 也会带 activeForm
          const activeForm = this.getStr(input,
            'activeForm', 'data.activeForm')
          if (activeForm) {
            existing.activeForm = activeForm
          }
        }
      }
    }

    // 第二遍：根据 toolStatus 更新任务完成状态
    // 当工具标记为 completed 但输入中还没有 status 时，将对应任务标记为已完成
    for (const msg of messages) {
      if (msg.type !== 'tool_use' || !msg.toolInput || msg.toolStatus !== 'completed') continue
      const input = msg.toolInput as Record<string, Object>

      if (msg.toolName === 'TaskUpdate') {
        const taskId = this.getStr(input,
          'data.taskId', 'taskId',
          'id', 'data.id')
        if (taskId && taskMap.has(taskId)) {
          const existing = taskMap.get(taskId)!
          if (existing.status !== 'completed') {
            existing.status = 'completed'
            console.info(`[SessionStore] TaskUpdate tool completed -> set task ${taskId} to completed`)
          }
        }
      } else if (msg.toolName === 'TaskCreate') {
        // 单步 TaskCreate（没有后续 TaskUpdate）也标记为 completed
        const taskId = this.getStr(input,
          'data.task.id', 'task.id',
          'data.taskId', 'taskId',
          'id', 'data.id')
        if (taskId && taskMap.has(taskId)) {
          const existing = taskMap.get(taskId)!
          if (existing.status === 'pending') {
            existing.status = 'completed'
            console.info(`[SessionStore] TaskCreate tool completed -> set task ${taskId} to completed`)
          }
        }
      }
    }

    if (taskMap.size > 0) {
      const tasks = Array.from(taskMap.values())
      this.sessionTasks.set(sessionId, tasks)
      this.taskBarDismissed = false
      this.notifySessionsChanged()
      console.info(`[SessionStore] Extracted ${tasks.length} tasks from messages for ${sessionId}`)
      // DEBUG: 输出任务状态
      for (const t of tasks) {
        console.info(`[SessionStore] Task: id=${t.id} status=${t.status} content=${t.content.substring(0, 30)}`)
      }
    }
  }

  // 更新单个任务的 WS 实时状态（利用已有 sessionTasks 作为基础，避免重建覆盖）
  private updateTaskFromWS(sessionId: string, toolName: string, input: Record<string, Object> | undefined): void {
    if (!input) return
    const currentTasks = this.sessionTasks.get(sessionId) || []
    const taskMap = new Map(currentTasks.map(t => [t.id, t]))

    if (toolName === 'TaskCreate') {
      const id = this.getStr(input,
        'data.task.id', 'task.id',
        'data.taskId', 'taskId',
        'id', 'data.id')
      // 如果已有相同 ID 的任务，不重复添加（保留已有状态）
      if (id && !taskMap.has(id)) {
        const subject = this.getStr(input,
          'data.task.subject', 'task.subject',
          'subject', 'data.subject')
        const description = this.getStr(input,
          'description', 'data.description',
          'data.task.description', 'task.description')
        const activeForm = this.getStr(input,
          'activeForm', 'data.activeForm',
          'data.task.activeForm', 'task.activeForm')
        taskMap.set(id, {
          id: id,
          content: subject || description,
          status: 'pending',
          activeForm: activeForm
        })
      }
    } else if (toolName === 'TaskUpdate') {
      const taskId = this.getStr(input,
        'data.taskId', 'taskId',
        'id', 'data.id')
      const status = this.getStr(input,
        'status', 'data.status',
        'statusChange.to', 'data.statusChange.to')
      if (taskId && taskMap.has(taskId)) {
        const existing = taskMap.get(taskId)!
        if (status === 'in_progress') existing.status = 'in_progress'
        else if (status === 'completed') existing.status = 'completed'
        else if (status === 'failed') existing.status = 'failed'
        const activeForm = this.getStr(input,
          'activeForm', 'data.activeForm')
        if (activeForm) {
          existing.activeForm = activeForm
        }
      }
    }

    if (taskMap.size > 0) {
      this.sessionTasks.set(sessionId, Array.from(taskMap.values()))
      this.taskBarDismissed = false
      this.notifySessionsChanged()
    }
  }

  // 串行化保存队列：确保同一会话的保存操作按顺序执行，防止并发竞态
  private enqueueSave(sessionId: string, saveFn: () => Promise<void>): Promise<void> {
    const prev = this.saveQueues.get(sessionId) || Promise.resolve()
    const next = prev.then(() => saveFn()).catch((e: Error) => {
      console.error(`[SessionStore] Save queue error for ${sessionId}: ${e.message}`)
    })
    this.saveQueues.set(sessionId, next)
    return next
  }

  // 保存会话到本地存储
  async saveSessionsToStorage(): Promise<void> {
    await storageService.saveSessions(this.sessions)
    this.notifySessionsChanged()
  }

  // MARK: - 消息操作

  async loadMessages(sessionId: string): Promise<void> {
    // 重新加载时清理流式缓冲，防止残留 Head 数据被误刷入 Tail
    // （页面重新进入时 streamHeads 可能包含上次未刷完的流式内容）
    this.streamHeads.delete(sessionId)

    try {
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
    } catch (e) {
      console.error(`[SessionStore] loadMessages storage error: ${e}`)
    }

    // 从现有消息中提取任务列表
    this.refreshTasksFromMessages(sessionId)

    // 后台静默同步服务器消息（不阻塞页面渲染）
    console.info(`[SessionStore] syncMessagesFromServer calling for ${sessionId}`)
    this.syncMessagesFromServer(sessionId)
  }

  // 后台同步服务器消息
  private async syncMessagesFromServer(sessionId: string): Promise<void> {
    // 并发保护：已有同步进行中则跳过（防止重复调用导致竞态）
    if (this.syncingSessions.has(sessionId)) {
      console.info(`[SessionStore] syncMessagesFromServer: already syncing ${sessionId}, skip`)
      return
    }
    this.syncingSessions.add(sessionId)
    try {
      const serverMessages = await apiService.getMessages(sessionId, 200)

      // 重新获取当前本地消息（可能已被 WebSocket 更新），避免覆盖实时消息
      const currentLocal = this.messages.get(sessionId) || []
      let merged = this.mergeMessages(currentLocal, serverMessages)

      // 检查 merge 计算期间是否有新的 WS 消息到达（避免覆盖丢失）
      const afterMerge = this.messages.get(sessionId) || []
      if (afterMerge.length > currentLocal.length) {
        for (let i = currentLocal.length; i < afterMerge.length; i++) {
          const newMsg = afterMerge[i]
          // 改用 messageContentKey 比较，避免 type+content 误判（tool_use content 全为空）
          const newKey = this.messageContentKey(newMsg)
          const existsById = merged.some(m => m.id === newMsg.id)
          const existsByKey = merged.some(m => this.messageContentKey(m) === newKey)
          if (!existsById && !existsByKey) {
            merged.push(newMsg)
          }
        }
        merged.sort((a, b) =>
          new Date(a.timestamp).getTime() - new Date(b.timestamp).getTime()
        )
      }

      this.messages.set(sessionId, merged)
      this.notifyMessagesChanged(sessionId)

      // 打印所有 tool_use 消息的工具名
      const toolNamesInMerge = merged.filter(m => m.type === 'tool_use' && m.toolName).map(m => m.toolName)
      console.info(`[SessionStore] syncMessagesFromServer merged ${merged.length} msgs, tool_use names: [${toolNamesInMerge.join(', ')}]`)

      // 去重检测并清理：用 messageContentKey 去重（type:content），防止内容微差导致重复
      {
        const deduped: Message[] = []
        const seenKeys: Map<string, boolean> = new Map()
        let removedDupCount = 0
        for (let i = 0; i < merged.length; i++) {
          const key = this.messageContentKey(merged[i])
          if (seenKeys.has(key)) {
            removedDupCount++
            console.warn(`[SessionStore] Removing dup after sync: #${removedDupCount} key=${key.substring(0, 100)} type=${merged[i].type} id=${merged[i].id}`)
            continue
          }
          seenKeys.set(key, true)
          deduped.push(merged[i])
        }
        if (removedDupCount > 0) {
          console.warn(`[SessionStore] Removed ${removedDupCount} dups from merged result, deduped=${deduped.length}`)
          merged = deduped
        }
      }

      // 同步后重新提取任务列表
      this.refreshTasksFromMessages(sessionId)

      // 尝试从专用 API 获取任务列表
      try {
        const apiTasks = await apiService.getTasks(sessionId)
        if (apiTasks.length > 0) {
          console.info(`[SessionStore] Tasks from API: ${apiTasks.length} tasks`)
          this.sessionTasks.set(sessionId, apiTasks)
          this.taskBarDismissed = false
          this.notifySessionsChanged()
        }
      } catch (e) {
        console.info(`[SessionStore] Tasks API error (non-fatal): ${e}`)
      }

      // 串行化保存到本地（通过队列确保顺序）
      this.enqueueSave(sessionId, () => storageService.saveMessages(sessionId, merged))
    } catch (e) {
      console.error(`[SessionStore] Sync messages error: ${e}`)
    } finally {
      this.syncingSessions.delete(sessionId)
    }
  }

  // 智能合并消息：服务器消息为主，保留本地独有的消息
  // 使用多维度去重（toolUseId / id / 内容摘要）防止重复
  private mergeMessages(localMessages: Message[], serverMessages: Message[]): Message[] {
    // 为服务器消息构建多维去重组
    const serverKeys: Map<string, boolean> = new Map()
    const serverIds: Set<string> = new Set()

    for (let i = 0; i < serverMessages.length; i++) {
      const msg = serverMessages[i]
      // 主键: type + toolUseId / type + id / type + content
      const primaryKey = this.messageContentKey(msg)
      serverKeys.set(primaryKey, true)
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

      // 跳过: 主键匹配（含 type + toolUseId / type + id / type + content）
      if (serverKeys.has(primaryKey)) continue
      // 跳过: id 匹配
      if (msg.id && serverIds.has(msg.id)) continue

      // 额外检查: 对 tool_use 消息，检查服务器是否有同 type + 同 toolName 的消息
      // （WS 流式 toolUseId 与服务端 toolUseId 不同时，主键匹配会失败）
      let foundByContent = false
      if (msg.type === 'tool_use' && msg.toolName) {
        for (let j = 0; j < serverMessages.length; j++) {
          const sm = serverMessages[j]
          if (sm.type === 'tool_use' && sm.toolName === msg.toolName) {
            // tool_use 的 content 通常为空，靠 toolName + 时间排序去重
            // 进一步校验：如果两者 toolUseId 相同说明是同一工具调用
            if (sm.toolUseId && sm.toolUseId === msg.toolUseId) {
              foundByContent = true
              break
            }
            // toolUseId 不同但 toolName 相同 → 按时间附近判定是否同一调用
            const msgTime = new Date(msg.timestamp).getTime()
            const smTime = new Date(sm.timestamp).getTime()
            if (Math.abs(msgTime - smTime) < 5000) {
              foundByContent = true
              break
            }
          }
        }
      }

      // 对没有 toolUseId 的本地消息，检查服务器是否有同 type 同内容的
      if (!msg.toolUseId) {
        for (let j = 0; j < serverMessages.length; j++) {
          const sm = serverMessages[j]
          if (sm.type === msg.type) {
            const localContent = (msg.content || msg.toolResult || '').substring(0, 2000)
            const serverContent = (sm.content || sm.toolResult || '').substring(0, 2000)
            if (localContent.length > 10 && localContent === serverContent) {
              foundByContent = true
              break
            }
            // 本地被切分的段落可能是服务端合并消息的子串（流式输出被 tool 事件打断后）
            if (localContent.length > 10 && localContent.length < serverContent.length &&
                serverContent.includes(localContent)) {
              foundByContent = true
              break
            }
            // 规整化对比：trim + 合并空白，捕获流式 vs 服务端格式差异（尾部换行、前后空格等）
            const normLocal = localContent.trim().replace(/\s+/g, ' ')
            const normServer = serverContent.trim().replace(/\s+/g, ' ')
            if (normLocal.length > 10 && normLocal === normServer) {
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
    // 使用完整内容去重，避免超长消息的截断误判
    const finalResult: Message[] = []
    const seenFinal: Map<string, boolean> = new Map()
    for (let i = 0; i < result.length; i++) {
      const m = result[i]
      const contentFull = m.content || m.toolResult || ''
      const finalKey = m.type + '|' + (m.toolUseId || '') + '|' + contentFull
      const existing = seenFinal.get(finalKey)
      if (existing) continue
      seenFinal.set(finalKey, true)
      finalResult.push(m)
    }

    return finalResult
  }

  // 生成消息内容去重键
  private messageContentKey(msg: Message): string {
    // 优先使用 toolUseId + type 作为去重键（避免 tool_use 和 tool_result 共享 toolUseId 互相去重）
    if (msg.toolUseId) {
      return msg.type + ':toolUseId:' + msg.toolUseId
    }
    // 统一使用内容键，确保服务端 ID 消息和本地流式 ID 消息同内容可去重
    const content = (msg.content || '') || (msg.toolResult || '')
    return msg.type + ':' + content.substring(0, 2000)
  }

  addMessage(sessionId: string, message: Message): void {
    let sessionMessages = this.messages.get(sessionId)
    if (!sessionMessages) {
      sessionMessages = []
    }

    // 去重：先按 ID，再按内容
    let exists = false
    for (let i = 0; i < sessionMessages.length; i++) {
      if (sessionMessages[i].id === message.id) {
        exists = true
        break
      }
    }
    if (!exists) {
      // 内容级去重：防止 ID 不同但内容相同的消息重复
      // （Head/Tail 双路径或 WS 重放可能导致同一内容抵达两次）
      const newKey = this.messageContentKey(message)
      for (let i = 0; i < sessionMessages.length; i++) {
        if (this.messageContentKey(sessionMessages[i]) === newKey) {
          exists = true
          break
        }
      }
    }

    if (!exists) {
      sessionMessages.push(message)
      this.messages.set(sessionId, sessionMessages)
      this.notifyMessagesChanged(sessionId)

      // 串行化保存到本地（通过队列确保顺序，防止并发竞态）
      this.enqueueSave(sessionId, () => storageService.saveMessages(sessionId, this.messages.get(sessionId) || []))
    }
  }

  // MARK: - Head/Tail 流式缓冲

  /** 将流式 Head 缓冲刷新到 Tail (messages) */
  flushHeadToTail(sessionId: string): void {
    const head = this.streamHeads.get(sessionId)
    if (!head || head.length === 0) return

    const tail = this.messages.get(sessionId) || []
    let changed = false

    for (let i = 0; i < head.length; i++) {
      const headMsg = head[i]
      // Head 中的消息已不再流式
      headMsg.isStreaming = false

      // 去重检查：先按 ID 匹配，再按 type+内容匹配（防止 WS 流式消息和服务器消息 ID 不同导致的重复）
      let exists = false
      for (let j = tail.length - 1; j >= 0; j--) {
        if (tail[j].id === headMsg.id) {
          exists = true
          break
        }
        // 同类型 + 同内容也视为重复（WS 流式 ID 和服务器 ID 不同）
        if (tail[j].type === headMsg.type && tail[j].content === headMsg.content) {
          exists = true
          break
        }
      }
      if (!exists) {
        tail.push(headMsg)
        changed = true
      }
    }

    if (changed) {
      this.messages.set(sessionId, tail)
      // 串行化保存到本地（通过队列确保顺序）
      this.enqueueSave(sessionId, () => storageService.saveMessages(sessionId, tail))
      this.notifyMessagesChanged(sessionId)
    }
    this.streamHeads.set(sessionId, [])
  }

  /** 获取展示用消息列表 (Tail + Head 合并) */
  getMessagesForDisplay(sessionId: string): Message[] {
    const tail = this.messages.get(sessionId) || []
    const head = this.streamHeads.get(sessionId) || []
    if (head.length === 0) return tail
    return [...tail, ...head]
  }

  /**
   * 获取去重后的消息列表（展示层安全网）
   * 用 messageContentKey 过滤掉 ID 不同但内容完全相同的重复消息。
   * 额外按 type+content 去重，覆盖服务端 ID 与本地流式 ID 不一致的情况。
   * 对 tool_use 特殊处理：忽略 toolUseId 差异，按 type + toolName 去重，
   * 解决 WS 瞬时 toolUseId 与服务端 toolUseId 不同导致的重复。
   * 不修改原始数组，仅用于 UI 渲染。
   */
  getDedupedMessages(sessionId: string): Message[] {
    const tail = this.messages.get(sessionId) || []
    const result: Message[] = []
    const seen = new Set<string>()
    let dupCount = 0
    for (let i = 0; i < tail.length; i++) {
      const key = this.messageContentKey(tail[i])
      if (seen.has(key)) {
        dupCount++
        const logContent = (tail[i].content || '').substring(0, 60)
        console.info(`[SessionStore] getDedupedMessages #${dupCount}: skip type=${tail[i].type} id=${tail[i].id} key=${key.substring(0, 80)} content="${logContent}"`)
        continue
      }
      seen.add(key)
      result.push(tail[i])
    }
    // 用规整化内容再做一道去重（trim + 合并空白），捕获流式 vs 服务端格式差异
    if (dupCount === 0 && result.length >= 2) {
      const normalizedSeen = new Set<string>()
      const normResult: Message[] = []
      for (let i = 0; i < result.length; i++) {
        const content = (result[i].content || '').trim().replace(/\s+/g, ' ')
        const normKey = result[i].type + ':' + content.substring(0, 2000)
        if (result[i].toolUseId) {
          // 有 toolUseId 的 tool_use 消息：按 type + toolName 去重（忽略 toolUseId 差异）
          // tool_result 有 toolResult 内容，不会走此路径
          if (result[i].type === 'tool_use' && result[i].toolName) {
            const toolKey = result[i].type + ':tool:' + result[i].toolName
            if (normalizedSeen.has(toolKey)) {
              dupCount++
              console.info(`[SessionStore] getDedupedMessages toolDup #${dupCount}: skip type=${result[i].type} toolName=${result[i].toolName} toolUseId=${result[i].toolUseId}`)
              continue
            }
            normalizedSeen.add(toolKey)
          } else {
            // 非 tool 消息但有 toolUseId，用原始 key（同第一道去重）
            if (normalizedSeen.has(normKey)) {
              dupCount++
              console.info(`[SessionStore] getDedupedMessages normDup #${dupCount}: skip type=${result[i].type} id=${result[i].id}`)
              continue
            }
            normalizedSeen.add(normKey)
          }
          normResult.push(result[i])
          continue
        }
        if (normalizedSeen.has(normKey)) {
          dupCount++
          console.info(`[SessionStore] getDedupedMessages normDup #${dupCount}: skip type=${result[i].type} id=${result[i].id} normKey=${normKey.substring(0, 80)}`)
          continue
        }
        normalizedSeen.add(normKey)
        normResult.push(result[i])
      }
      if (dupCount > 0) {
        console.info(`[SessionStore] getDedupedMessages: removed ${dupCount} dups (incl normalized) from ${tail.length} msgs for ${sessionId}`)
        return normResult
      }
    }
    if (dupCount > 0) {
      console.info(`[SessionStore] getDedupedMessages: removed ${dupCount} dups from ${tail.length} msgs for ${sessionId}`)
    }
    return result
  }

  /**
   * 全量扫描并清理所有会话中的残留重复消息
   * 每 60 秒执行一次，作为最后的兜底防线
   */
  private cleanupDuplicateMessages(): void {
    // ArkTS 不支持 for...of 解构，改用 Map.forEach
    const sessionIds: string[] = []
    this.messages.forEach((_msgs: Message[], sid: string) => {
      sessionIds.push(sid)
    })
    for (let si = 0; si < sessionIds.length; si++) {
      const sessionId = sessionIds[si]
      const msgs = this.messages.get(sessionId)
      if (!msgs || msgs.length < 2) continue
      const cleaned: Message[] = []
      const seen = new Set<string>()
      let changed = false
      for (let i = 0; i < msgs.length; i++) {
        const key = this.messageContentKey(msgs[i])
        if (seen.has(key)) {
          changed = true
          continue
        }
        seen.add(key)
        cleaned.push(msgs[i])
      }
      if (changed) {
        console.info(`[SessionStore] Cleaned ${msgs.length - cleaned.length} duplicate(s) for ${sessionId}`)
        this.messages.set(sessionId, cleaned)
        this.enqueueSave(sessionId, () => storageService.saveMessages(sessionId, cleaned))
        this.notifyMessagesChanged(sessionId)
      }
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

  sendAskUserQuestionResponse(requestId: string, answers: Record<string, string>): void {
    if (!this.currentSessionId) return
    wsService.sendAskUserQuestionResponse(this.currentSessionId, requestId, answers)
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


    // completed 状态 2 秒后自动恢复为 idle，让吉祥物回到睡眠
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
      }, 2000)
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

    // ⚠️ 去重检查必须在 rawMessageListener 之前！
    // 防止 WS 消息经会话 WS + 全局广播双通道到达时，ChatDetailPage 被触发两次，
    // 导致 streamingText 重复积累（内容翻倍）或消息重复插入。
    // 优先用 msg.id（最可靠），没有 ID 时降级到 toolUseId/type+content 多维摘要
    let dedupKey: string
    if (msg.id && !msg.id.startsWith('tool-')) {
      dedupKey = sessionId + ':id:' + msg.id + ':' + msg.type
    } else if (msg.toolUseId) {
      // 必须包含 msg.type，防止 tool_use_complete 和 tool_result 共享 toolUseId 互相去重
      dedupKey = sessionId + ':type:' + msg.type + ':toolUseId:' + msg.toolUseId
    } else {
      // 降级：type + text/toolName/content 构建摘要，避免只取前100字符导致的误去重
      const textPart = typeof msg.text === 'string' ? msg.text.substring(0, 200) : ''
      const contentPart = typeof msg.content === 'string' ? (msg.content as string).substring(0, 200) : ''
      const toolPart = msg.toolName || ''
      dedupKey = sessionId + ':no-id:' + msg.type + ':' + toolPart + ':' + textPart + ':' + contentPart
    }
    if (this.recentMessageIds.has(dedupKey)) {
      console.info(`[SessionStore] Dedup: skipping duplicate msg ${msg.id || '(no-id)'} (${msg.type})`)
      return
    }
    this.recentMessageIds.add(dedupKey)
    // 延迟清理去重缓存
    setTimeout(() => {
      this.recentMessageIds.delete(dedupKey)
    }, SessionStore.DEDUP_CACHE_TTL_MS)

    // 转发原始消息给 ChatDetailPage（用于流式缓冲等本地处理）
    for (const listener of this.rawMessageListeners) {
      listener(sessionId, msg)
    }

    // 独立处理 tasks：无论消息类型是什么，只要带有 tasks 数组就更新任务列表
    // （桌面端可能将 tasks 合并在 status 或其他消息中一起发送）
    if (msg.tasks && msg.tasks.length > 0) {
      console.info(`[SessionStore] Tasks found in WS msg type=${msg.type}: ${msg.tasks.length} tasks`)
      this.sessionTasks.set(sessionId, msg.tasks)
      this.taskBarDismissed = false
      this.notifySessionsChanged()
    }
    // 每次收到重要 WS 消息时，尝试从已加载的消息中刷新任务列表
    if (msg.type === 'status' || msg.type === 'tool_use_complete' || msg.type === 'tool_result' || msg.type === 'message_complete' || msg.type === 'task_list' || msg.type === 'task_update') {
      this.refreshTasksFromMessages(sessionId)
    }

    // DEBUG: 记录所有消息的完整结构，用于排查任务列表问题
    try {
      const debugMsg = JSON.stringify(msg)
      if (debugMsg.length > 800) {
        console.info(`[SessionStore] WS msg debug (truncated): ${debugMsg.substring(0, 800)}`)
      } else {
        console.info(`[SessionStore] WS msg debug: ${debugMsg}`)
      }
      // 特别检查是否有 tasks 相关字段
      if ((msg as Record<string, Object>)['tasks'] || (msg as Record<string, Object>)['task_list'] || (msg as Record<string, Object>)['taskData']) {
        console.info(`[SessionStore] *** FOUND TASK DATA in msg type=${messageType} ***`)
      }
    } catch (e) {
      console.info(`[SessionStore] WS msg debug error: ${e}`)
    }

    switch (messageType) {
      case 'session_title_updated':
        if (msg.title) {
          this.updateSessionTitle(sessionId, msg.title)
        }
        break

      case 'status':
        if (msg.state) {
          this.updateSessionStatusFromState(sessionId, msg.state)

          // 有工具执行时刷新任务列表
          if (msg.state === 'tool_executing' || msg.state === 'streaming') {
            this.refreshTasksFromMessages(sessionId)
          }
        }
        // 解析权限模式/模型/努力度同步
        if (msg.verb) {
          if (msg.verb.startsWith('permission_mode:')) {
            const mode = msg.verb.substring('permission_mode:'.length) as PermissionMode
            this.sessionPermissionModes.set(sessionId, mode)
            this.notifySessionsChanged()
            // 同步触发状态变更通知，确保 ChatDetailPage/ConversationListPage 刷新权限显示
            this.notifyStatusChanged(sessionId, this.sessionStatuses.get(sessionId) || 'idle')
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
          // 工具标记 completed 后刷新任务列表，确保任务状态实时同步
          this.refreshTasksFromMessages(sessionId)
        }
        break

      case 'content_delta':
      case 'thinking':
        // 流式增量更新 Head 缓冲
        {
          const deltaText = typeof msg.text === 'string' ? msg.text as string : ''
          if (deltaText) {
            let head = this.streamHeads.get(sessionId)
            if (!head) {
              head = []
            }

            if (messageType === 'content_delta') {
              if (head.length > 0 && head[head.length - 1].type === 'assistant') {
                const last = head[head.length - 1]
                last.content = (last.content || '') + deltaText
              } else {
                head.push({
                  id: 'stream-' + Date.now(),
                  type: 'assistant',
                  content: deltaText,
                  isStreaming: true,
                  timestamp: new Date().toISOString(),
                })
              }
            } else { // thinking
              if (head.length > 0 && head[head.length - 1].type === 'thinking') {
                const last = head[head.length - 1]
                last.content = (last.content || '') + deltaText
              } else {
                head.push({
                  id: 'thinking-' + Date.now(),
                  type: 'thinking',
                  content: deltaText,
                  isStreaming: true,
                  timestamp: new Date().toISOString(),
                })
              }
            }

            this.streamHeads.set(sessionId, head)
          }
        }
        break

      case 'tool_use_complete':
        // 非流式事件：先将 Head 刷新到 Tail
        this.flushHeadToTail(sessionId)
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

          // 跟踪 TaskCreate / TaskUpdate 工具调用（实时更新任务列表）
          if (msg.toolName === 'TaskCreate' || msg.toolName === 'TaskUpdate') {
            // DEBUG: 打印 task tool 的 input 格式
            try {
              if (msg.toolName === 'TaskUpdate') {
                const sc = msg.input ? msg.input['statusChange'] : 'no-input'
                const sTop = msg.input ? msg.input['status'] : 'no-input'
                console.info(`[SessionStore] TaskUpdate input: status=${sTop}, statusChange=${sc}, raw=${JSON.stringify(msg.input)}`)
              } else if (msg.toolName === 'TaskCreate') {
                const t = msg.input ? msg.input['task'] : 'no-input'
                console.info(`[SessionStore] TaskCreate input: hasTask=${t !== undefined}, raw=${JSON.stringify(msg.input)}`)
              }
            } catch (e) {
              console.info(`[SessionStore] TaskUpdate/TaskCreate debug error: ${e}`)
            }
            this.updateTaskFromWS(sessionId, msg.toolName, msg.input)
          }
          // 工具标记 completed 后刷新任务列表（捕获 toolStatus 变化）
          this.refreshTasksFromMessages(sessionId)
        }
        break

      case 'tool_result':
        // 非流式事件：先将 Head 刷新到 Tail
        this.flushHeadToTail(sessionId)
        if (msg.toolUseId && msg.content !== undefined && msg.content !== null) {
          this.updateToolResult(sessionId, msg.toolUseId, msg.content, msg.isError === true)
        }
        // 工具执行完成后重新提取任务列表，更新进度
        this.refreshTasksFromMessages(sessionId)
        break

      case 'message_complete':
        console.info(`[SessionStore] Message complete for ${sessionId}`)
        // 最终化：将 Head 刷新到 Tail 并清空 Head
        this.flushHeadToTail(sessionId)
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
        // 消息完成时重新提取任务列表，刷新完成进度
        this.refreshTasksFromMessages(sessionId)
        // 后台通知 - 检测文件/图片生成，从最后一条 AI 消息获取内容
        {
          const messages = this.messages.get(sessionId)
          let lastContent = ''
          let hasFile = false
          let hasImage = false
          if (messages && messages.length > 0) {
            // 从后往前找最后一条 assistant 或 tool_use 消息
            for (let i = messages.length - 1; i >= 0; i--) {
              const m = messages[i]
              if (m.type === 'assistant') {
                lastContent = m.content || ''
                break
              }
              if (m.type === 'tool_use' && m.toolStatus === 'completed') {
                if (m.images && m.images.length > 0) {
                  hasImage = true
                }
                if (m.toolInput && m.toolInput['file_path']) {
                  hasFile = true
                }
              }
            }
          }
          let notifyTitle = 'AI 回复完成'
          if (hasImage && hasFile) notifyTitle = 'AI 生成了图片和文件'
          else if (hasImage) notifyTitle = 'AI 生成了图片'
          else if (hasFile) notifyTitle = 'AI 生成了文件'
          const notifyContent = lastContent || notifyTitle
          this.notifyIfBackground(sessionId, notifyTitle, notifyContent)
        }
        break

      case 'permission_request':
        // 非流式事件：先将 Head 刷新到 Tail
        this.flushHeadToTail(sessionId)
        this.updateSessionStatus(sessionId, 'permission_pending')

        // 设置 pendingPermission 状态
        if (msg.requestId) {
          const pending: PendingPermission = {
            requestId: msg.requestId,
            toolName: msg.toolName,
            toolUseId: msg.toolUseId,
            input: msg.input as Record<string, Object>,
            description: msg.description
          }
          this.pendingPermissions.set(sessionId, pending)

          // AskUserQuestion 工具特殊处理：添加带 toolName 的消息，由 ChatDetailPage 特殊渲染
          const permMessage: Message = {
            id: 'permission-' + msg.requestId,
            type: 'permission_request',
            content: msg.description || '权限请求: ' + (msg.toolName || ''),
            timestamp: new Date().toISOString(),
            toolName: msg.toolName,
            permissionId: msg.requestId,
            permissionDescription: msg.description,
            toolInput: msg.input as Record<string, Object>
          }
          this.addMessage(sessionId, permMessage)
        }
        // 后台通知
        this.notifyIfBackground(sessionId, '权限请求', msg.toolName || '', 'permission')
        break

      case 'question':
      case 'questions':
        // 非流式事件：先将 Head 刷新到 Tail
        this.flushHeadToTail(sessionId)
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

          // 去重：先按 msg.id 匹配，再按内容匹配（不论 msg.id 是否存在）
          const existingMessages = this.messages.get(sessionId)
          let isDuplicate = false
          if (existingMessages) {
            for (let i = existingMessages.length - 1; i >= 0; i--) {
              const m = existingMessages[i]
              // 按 ID 精确去重（如果 msg.id 存在）
              if (msg.id && m.id === msg.id) {
                isDuplicate = true
                break
              }
              // 按内容去重：同类型 + 同内容（不限 msg.id 是否存在）
              if (m.type === 'user' && m.content === contentString) {
                isDuplicate = true
                break
              }
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
        // 任务已在通用处理器中更新（msg.tasks），此处再处理一次确保不漏
        if (msg.tasks && msg.tasks.length > 0) {
          console.info(`[SessionStore] Task ${messageType} with ${msg.tasks.length} tasks`)
          this.sessionTasks.set(sessionId, msg.tasks)
          this.taskBarDismissed = false
          this.notifySessionsChanged()
        } else {
          // 没有 tasks 字段时也尝试从消息列表刷新
          this.refreshTasksFromMessages(sessionId)
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
          // 已有直连 WS 且真正在线时才跳过全局广播，防止 WS 断开后遗漏 message_complete 等关键消息
          if (wsService.isSubscribed(msg.sessionId) && wsService.isConnected(msg.sessionId)) {
            console.info(`[SessionStore] Skip session_broadcast for ${msg.sessionId}: already connected`)
            break
          }
          console.info(`[SessionStore] Session broadcast for ${msg.sessionId} (direct WS not connected)`)
          this.handleWSMessage(msg.sessionId, msg.message as WSMessage)
        }
        break

      default:
        // DEBUG: 记录未知全局消息类型，排查任务列表问题
        try {
          const debugStr = JSON.stringify(msg)
          console.info(`[SessionStore] Global WS default: ${msg.type}, data: ${debugStr.substring(0, 500)}`)
        } catch (e) {
          console.info(`[SessionStore] Global WS default: ${msg.type}, keys: ${Object.keys(msg).join(',')}`)
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
    // 获取当前状态，避免覆盖已完成状态
    const currentStatus = this.sessionStatuses.get(sessionId) || 'idle'

    // 如果当前是 completed 或 idle，且新状态是 working 状态，忽略
    // 这避免桌面端延迟的状态消息覆盖移动端的完成状态
    if ((currentStatus === 'completed' || currentStatus === 'idle') &&
        (state === 'thinking' || state === 'streaming' || state === 'tool_executing')) {
      console.info(`[SessionStore] Ignoring stale status ${state} for ${sessionId}, current is ${currentStatus}`)
      return
    }

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

    // 解析 content blocks，提取文本和图片
    let resultText = ''
    const extractedImages: MessageImage[] = []

    if (typeof content === 'string') {
      resultText = content
    } else if (Array.isArray(content)) {
      const blocks = content as Array<Record<string, Object>>
      for (let i = 0; i < blocks.length; i++) {
        const block = blocks[i]
        if (block['type'] === 'text' && block['text']) {
          resultText += String(block['text'])
        } else if (block['type'] === 'image') {
          const source = block['source'] as Record<string, Object> | undefined
          if (source && source['data'] && source['media_type']) {
            const mediaType = String(source['media_type'])
            const imageData = String(source['data'])
            const img: MessageImage = { data: imageData, mediaType: mediaType }
            extractedImages.push(img)
          }
        }
      }
    } else {
      // 非数组对象回退到 JSON.stringify
      resultText = JSON.stringify(content)
    }

    const index = messages.findIndex(m => m.id === toolUseId || m.toolUseId === toolUseId)
    if (index >= 0) {
      messages[index].toolResult = resultText
      messages[index].toolStatus = isError ? 'failed' : 'completed'
      if (extractedImages.length > 0) {
        messages[index].images = extractedImages
      }
      this.notifyMessagesChanged(sessionId)
      console.info(`[SessionStore] Tool ${toolUseId} updated: ${isError ? 'failed' : 'completed'}, images: ${extractedImages.length}`)
    } else {
      // 工具消息不存在时（如乱序到达），用 tool_result 创建
      console.warn(`[SessionStore] Tool ${toolUseId} not found, creating from tool_result`)
      const toolMessage: Message = {
        id: toolUseId,
        type: 'tool_use',
        content: '',
        timestamp: new Date().toISOString(),
        toolUseId: toolUseId,
        toolResult: resultText,
        toolStatus: isError ? 'failed' : 'completed',
        images: extractedImages.length > 0 ? extractedImages : undefined
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

  collapseTaskBar(): void {
    if (this.taskBarExpanded) {
      this.taskBarExpanded = false
      this.notifySessionsChanged()
    }
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

    // 清除定期状态同步定时器
    if (this.staleStatusTimer >= 0) {
      clearInterval(this.staleStatusTimer)
      this.staleStatusTimer = -1
    }

    // 清除重复消息清理定时器
    if (this.dedupCleanupTimer >= 0) {
      clearInterval(this.dedupCleanupTimer)
      this.dedupCleanupTimer = -1
    }

    // 清除本地存储
    await storageService.saveSessions([])
    await storageService.saveSessionStatuses(new Map())

    this.notifySessionsChanged()
    console.info('[SessionStore] All sessions cleared')
  }
}

export const sessionStore = SessionStore.getInstance()
