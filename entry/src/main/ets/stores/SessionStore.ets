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
import { toastManager } from '../services/ToastManager'
import { authStore } from './AuthStore'
import { appState } from './AppState'

// 流式消息内部缓冲区类型
class StreamingBuffer {
  assistant: string = ''
  thinking: string = ''
  blockType: string = ''
}

class OfficialCodexThreadRuntimeSnapshot {
  active: boolean = false
  status: string = ''
  updatedAt: Object = ''
}

export class SessionStore {
  private static instance: SessionStore
  private static readonly OFFICIAL_CODEX_RECENT_DAYS = 15
  private static readonly OFFICIAL_CODEX_LIST_LIMIT = 120
  private static readonly OFFICIAL_CODEX_SEND_TIMEOUT_MS = 30000
  private static readonly OFFICIAL_CODEX_SEND_STALE_MS = 45000
  private static readonly OFFICIAL_CODEX_DISCOVERY_INTERVAL_MS = 20000
  private static readonly OFFICIAL_CODEX_STATUS_SYNC_INTERVAL_MS = 10000

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

  // Codex Controller 连接状态
  codexControllerStatus: string = 'unknown' // 'unknown' | 'connected' | 'reconnecting'
  codexControllerReconnectAttempt: number = 0
  private officialCodexThreadIds: Map<string, string> = new Map()
  private officialCodexThreadRuntime: Map<string, OfficialCodexThreadRuntimeSnapshot> = new Map()
  private officialCodexSendQueues: Map<string, Promise<void>> = new Map()
  private officialCodexSendStartedAt: Map<string, number> = new Map()
  private officialCodexSendBusyWarnedAt: Map<string, number> = new Map()
  private officialCodexActiveTurns: Map<string, string> = new Map()
  private officialCodexLocalPollingSessions: Set<string> = new Set()
  private syncingOfficialCodexLatest: Set<string> = new Set()
  private officialCodexRecentActivityAt: Map<string, number> = new Map()
  private officialCodexTerminalAt: Map<string, number> = new Map()
  private officialCodexWarmupInFlight: Promise<void> | null = null
  private lastOfficialCodexWarmupAt: number = 0
  private lastOfficialCodexRuntimeSnapshotAt: number = 0

  // 本地删除的会话ID集合（不从服务器重新加载）
  private locallyDeletedSessionIds: Set<string> = new Set()
  private archivedSessionIds: Set<string> = new Set()
  private archivedOfficialCodexThreadIds: Set<string> = new Set()
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
  private sessionsChangedNotifyTimer: number = -1
  private sessionsChangedPending: boolean = false

  // completed→idle 定时器追踪
  private completedTimers: Map<string, number> = new Map()

  // 消息去重缓存（防止全局 WS + 会话 WS 双通道重复传递）
  private recentMessageIds: Set<string> = new Set()
  private static readonly DEDUP_CACHE_TTL_MS = 30000 // 30 秒去重窗口（云中继延迟较高）
  private static readonly LOCAL_MESSAGE_CACHE_LIMIT = 100

  // 定期状态同步定时器（每 15 秒检查一次过期的工作状态）
  private staleStatusTimer: number = -1

  // 定期重复消息清理定时器（每 60 秒兜底清一次）
  private dedupCleanupTimer: number = -1

  // Official Codex 全局心跳（无论停留在哪个页面，都自动同步运行中的对话）
  private officialCodexHeartbeatTimer: number = -1
  private officialCodexDiscoveryTimer: number = -1

  // 流式消息内部缓冲区（关闭逐字显示后，只在这里累积，等 message_complete 一次性刷入）
  private streamingBuffers: Map<string, StreamingBuffer> = new Map()
  private streamingPreviewTimers: Map<string, number> = new Map()

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
    // 防止重复添加同一监听器
    if (!this.messagesChangedListeners.includes(listener)) {
      this.messagesChangedListeners.push(listener)
    }
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

    // 统一定时器：先清理过期状态，再同步活跃会话（避免两个定时器交替导致状态振荡）
    // 每 10 秒执行一次，合并了原来的 staleStatusTimer + officialCodexHeartbeatTimer
    this.staleStatusTimer = setInterval(() => {
      // 第一步：清理过期的工作状态
      this.syncSessionStatuses()
      // 第二步：前台时同步 Official Codex 活跃会话（在清理之后执行，避免清理后被恢复）
      if (appState.isInForeground) {
        void this.syncTrackedOfficialCodexSessions()
      }
    }, SessionStore.OFFICIAL_CODEX_STATUS_SYNC_INTERVAL_MS)

    // 独立线程发现器：定期把本地新增/更新的 Codex 线程同步进移动端列表
    this.officialCodexDiscoveryTimer = setInterval(() => {
      if (!appState.isInForeground) return
      void this.syncOfficialCodexThreadsToLocal(Math.max(SessionStore.OFFICIAL_CODEX_LIST_LIMIT, 80))
    }, SessionStore.OFFICIAL_CODEX_DISCOVERY_INTERVAL_MS)

    // 应用启动时同步所有 Official Codex 会话状态
    setTimeout(() => {
      this.syncAllOfficialCodexStatuses()
    }, 2000)

    // officialCodexHeartbeatTimer 不再独立运行，已合并到 staleStatusTimer

    // 延迟连接全局 WebSocket（等待 authStore 初始化完成）
    setTimeout(() => {
      const serverUrl = authStore.serverUrl
      if (serverUrl) {
        console.info(`[SessionStore] Auto-connecting global WS to ${serverUrl}`)
        wsService.setServerUrl(serverUrl)
        wsService.connectGlobal()
      }
    }, 3000)

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

      const archivedIds = await storageService.loadString('archived_session_ids')
      if (archivedIds) {
        try {
          const ids: string[] = JSON.parse(archivedIds)
          for (let i = 0; i < ids.length; i++) {
            this.archivedSessionIds.add(ids[i])
          }
          console.info(`[SessionStore] Loaded ${this.archivedSessionIds.size} archived session IDs`)
        } catch (e) {
          console.error(`[SessionStore] Parse archived session IDs error: ${e}`)
        }
      }

      const archivedOfficialThreadIds = await storageService.loadString('archived_official_codex_thread_ids')
      if (archivedOfficialThreadIds) {
        try {
          const ids: string[] = JSON.parse(archivedOfficialThreadIds)
          for (let i = 0; i < ids.length; i++) {
            this.archivedOfficialCodexThreadIds.add(ids[i])
          }
          console.info(`[SessionStore] Loaded ${this.archivedOfficialCodexThreadIds.size} archived Official Codex thread IDs`)
        } catch (e) {
          console.error(`[SessionStore] Parse archived Official Codex thread IDs error: ${e}`)
        }
      }

      const savedOfficialCodexThreadIds = await storageService.loadString('official_codex_thread_ids')
      if (savedOfficialCodexThreadIds) {
        try {
          const parsed = JSON.parse(savedOfficialCodexThreadIds) as Record<string, string>
          Object.keys(parsed).forEach((sessionId: string) => {
            const threadId = parsed[sessionId]
            if (threadId && threadId.length > 0) {
              this.officialCodexThreadIds.set(sessionId, threadId)
            }
          })
          console.info(`[SessionStore] Loaded ${this.officialCodexThreadIds.size} Official Codex thread bindings`)
        } catch (e) {
          console.error(`[SessionStore] Parse Official Codex thread bindings error: ${e}`)
        }
      }

      // 加载本地会话
      const localSessions = await storageService.loadSessions()
      if (localSessions.length > 0) {
        this.sessions = localSessions

        // 过滤掉本地已删除的会话（防止本地存储写入失败导致旧数据残留）
        this.sessions = this.sessions.filter(s => !this.locallyDeletedSessionIds.has(s.id) || !!s.officialCodexThreadId)
        this.sessions = this.sessions.filter(s => !this.isSessionArchivedByIdentity(s.id, s.officialCodexThreadId || ''))
        this.hydrateOfficialCodexThreadIds()

        // 启动时只加载会话元信息，不预加载所有消息。
        // 消息体在进入 ChatDetailPage 时按需读取，避免历史线程多时启动和列表滑动卡顿。

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

      this.warmOfficialCodexControllerIfNeeded()

      // 无论本地是否已有会话，都后台自动同步 Codex 线程列表
      void this.syncOfficialCodexThreadsToLocal(SessionStore.OFFICIAL_CODEX_LIST_LIMIT).then(() => {
        console.info('[SessionStore] Auto-synced Codex threads on startup')
      }).catch((e: Error) => {
        console.error('[SessionStore] Auto-sync Codex threads error:', e.message)
      })

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
      const filteredServerSessions = serverSessions.filter(s =>
        !this.locallyDeletedSessionIds.has(s.id) && !this.isSessionArchivedByIdentity(s.id, s.officialCodexThreadId || ''))

      // 合并本地修改时间（避免被服务器旧数据覆盖）
      const localModifiedMap: Map<string, string> = new Map()
      const localOfficialCodexSessions: Session[] = []
      for (let i = 0; i < this.sessions.length; i++) {
        localModifiedMap.set(this.sessions[i].id, this.sessions[i].modifiedAt)
        if (this.sessions[i].officialCodexThreadId) {
          localOfficialCodexSessions.push(this.sessions[i])
        }
      }

      // 合并服务器会话和本地 Official Codex 会话
      const mergedSessions: Session[] = []
      const mergedIds = new Set<string>()
      const mergedOfficialThreadIds = new Set<string>()
      
      // 先添加服务器会话
      for (let i = 0; i < filteredServerSessions.length; i++) {
        const serverSession = filteredServerSessions[i]
        const localTime = localModifiedMap.get(serverSession.id)
        
        if (localTime) {
          const localDate = new Date(localTime).getTime()
          const serverDate = new Date(serverSession.modifiedAt).getTime()
          if (localDate > serverDate) {
            mergedSessions.push({
              id: serverSession.id,
              title: serverSession.title,
              projectPath: serverSession.projectPath,
              workDir: serverSession.workDir,
              workDirExists: serverSession.workDirExists,
              createdAt: serverSession.createdAt,
              modifiedAt: localTime,
              messageCount: serverSession.messageCount,
              aiTool: serverSession.aiTool,
              officialCodexThreadId: serverSession.officialCodexThreadId
            })
          } else {
            mergedSessions.push(serverSession)
          }
        } else {
          mergedSessions.push(serverSession)
        }
        
        mergedIds.add(serverSession.id)
        if (serverSession.officialCodexThreadId) {
          mergedOfficialThreadIds.add(serverSession.officialCodexThreadId)
        }
      }
      
      // 再添加本地 Official Codex 会话（确保不被覆盖）
      for (let i = 0; i < localOfficialCodexSessions.length; i++) {
        const session = localOfficialCodexSessions[i]
        const threadId = session.officialCodexThreadId || ''
        // 只有当 id 和 threadId 都不存在时才添加
        if (!mergedIds.has(session.id) && (threadId.length === 0 || !mergedOfficialThreadIds.has(threadId))) {
          mergedSessions.push(session)
          mergedIds.add(session.id)
          if (threadId) {
            mergedOfficialThreadIds.add(threadId)
          }
        }
      }
      
      this.sessions = mergedSessions
      
      console.info(`[fetchSessions] Merged ${filteredServerSessions.length} server + ${localOfficialCodexSessions.length} local Official Codex = ${this.sessions.length} total`)

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
      // 先记录到本地已删除列表，防止服务器广播 sessions_updated 时重新拉回
      this.locallyDeletedSessionIds.add(sessionId)
      const deletedIdsArray: string[] = []
      this.locallyDeletedSessionIds.forEach(id => deletedIdsArray.push(id))
      await storageService.saveString('locally_deleted_session_ids', JSON.stringify(deletedIdsArray))

      // 再调用服务器 API 删除
      await apiService.deleteSession(sessionId)

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
    console.info(`[SessionStore] deleteLocalSession called: ${sessionId}`)
    try {
      const session = this.sessions.find(s => s.id === sessionId)

      // Official Codex 本地线程默认不做永久隐藏，避免主列表缺少对话
      if (!session?.officialCodexThreadId) {
        this.locallyDeletedSessionIds.add(sessionId)
        const deletedIdsArray: string[] = []
        this.locallyDeletedSessionIds.forEach(id => deletedIdsArray.push(id))
        await storageService.saveString('locally_deleted_session_ids', JSON.stringify(deletedIdsArray))
        console.info(`[SessionStore] Saved ${deletedIdsArray.length} deleted session IDs`)
      }

      // 更新内存数据
      const oldCount = this.sessions.length
      this.sessions = this.sessions.filter(s => s.id !== sessionId)
      console.info(`[SessionStore] Sessions: ${oldCount} -> ${this.sessions.length}`)
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
      console.info(`[SessionStore] Deleted local session done: ${sessionId}`)
    } catch (e) {
      console.error(`[SessionStore] deleteLocalSession error: ${e}`)
    }
  }

  // 检查会话是否已被本地删除
  isSessionLocallyDeleted(sessionId: string): boolean {
    return this.locallyDeletedSessionIds.has(sessionId)
  }

  isSessionArchived(sessionId: string): boolean {
    return this.archivedSessionIds.has(sessionId)
  }

  isOfficialCodexThreadArchived(threadId: string): boolean {
    return this.archivedOfficialCodexThreadIds.has(threadId)
  }

  private isSessionArchivedByIdentity(sessionId: string, officialCodexThreadId: string): boolean {
    if (this.archivedSessionIds.has(sessionId)) return true
    if (officialCodexThreadId.length > 0 && this.archivedOfficialCodexThreadIds.has(officialCodexThreadId)) return true
    return false
  }

  // 从已删除列表中移除（用于导入会话时恢复）
  async restoreSessionFromDeleted(sessionId: string): Promise<void> {
    this.locallyDeletedSessionIds.delete(sessionId)
    const deletedIdsArray: string[] = []
    this.locallyDeletedSessionIds.forEach(id => deletedIdsArray.push(id))
    await storageService.saveString('locally_deleted_session_ids', JSON.stringify(deletedIdsArray))
    console.info(`[SessionStore] Restored session from deleted list: ${sessionId}`)
  }

  private async saveArchivedSessionIds(): Promise<void> {
    const archivedIdsArray: string[] = []
    this.archivedSessionIds.forEach(id => archivedIdsArray.push(id))
    await storageService.saveString('archived_session_ids', JSON.stringify(archivedIdsArray))
    const archivedThreadIdsArray: string[] = []
    this.archivedOfficialCodexThreadIds.forEach(id => archivedThreadIdsArray.push(id))
    await storageService.saveString('archived_official_codex_thread_ids', JSON.stringify(archivedThreadIdsArray))
  }

  async archiveSession(sessionId: string): Promise<void> {
    const session = this.sessions.find(s => s.id === sessionId)
    this.archivedSessionIds.add(sessionId)
    const threadId = session?.officialCodexThreadId || this.officialCodexThreadIds.get(sessionId) || ''
    if (threadId.length > 0) {
      this.archivedOfficialCodexThreadIds.add(threadId)
    }
    const removedSessionIds: string[] = []
    for (let i = 0; i < this.sessions.length; i++) {
      const candidate = this.sessions[i]
      if (candidate.id === sessionId) {
        removedSessionIds.push(candidate.id)
        continue
      }
      if (threadId.length > 0 && (candidate.officialCodexThreadId || '') === threadId) {
        removedSessionIds.push(candidate.id)
        this.archivedSessionIds.add(candidate.id)
      }
    }
    await this.saveArchivedSessionIds()
    if (removedSessionIds.length > 0) {
      this.sessions = this.sessions.filter(s => !removedSessionIds.includes(s.id))
    } else {
      this.sessions = this.sessions.filter(s => s.id !== sessionId)
    }
    for (let i = 0; i < removedSessionIds.length; i++) {
      const removedId = removedSessionIds[i]
      this.sessionStatuses.delete(removedId)
      this.pendingPermissions.delete(removedId)
      this.streamHeads.delete(removedId)
      this.sessionTasks.delete(removedId)
      this.officialCodexRecentActivityAt.delete(removedId)
      this.officialCodexActiveTurns.delete(removedId)
      this.officialCodexTerminalAt.delete(removedId)
      const timer = this.completedTimers.get(removedId)
      if (timer !== undefined) {
        clearTimeout(timer)
        this.completedTimers.delete(removedId)
      }
      if (this.currentSessionId === removedId) {
        this.currentSessionId = null
      }
    }
    if (threadId.length > 0) {
      this.officialCodexThreadRuntime.delete(threadId)
    }
    await this.saveSessionsToStorage()
    this.notifySessionsChanged()
    console.info(`[SessionStore] Archived session: ${sessionId}, removed ${removedSessionIds.length} session(s), threadId=${threadId}`)
  }

  async unarchiveSession(sessionId: string, officialCodexThreadId: string = ''): Promise<void> {
    if (!this.archivedSessionIds.has(sessionId) && !(officialCodexThreadId.length > 0 && this.archivedOfficialCodexThreadIds.has(officialCodexThreadId))) return
    this.archivedSessionIds.delete(sessionId)
    if (officialCodexThreadId.length > 0) {
      this.archivedOfficialCodexThreadIds.delete(officialCodexThreadId)
    }
    await this.saveArchivedSessionIds()
    this.notifySessionsChanged()
    console.info(`[SessionStore] Unarchived session: ${sessionId}`)
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
          aiTool: old.aiTool,
          officialCodexThreadId: old.officialCodexThreadId
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
  private enqueueSave(sessionId: string, saveFn: () => Promise<void | boolean>): Promise<void> {
    const prev = this.saveQueues.get(sessionId) || Promise.resolve()
    const next = prev.then(async () => {
      await saveFn()  // 显式 await，忽略返回值
    }).catch((e: Error) => {
      console.error(`[SessionStore] Save queue error for ${sessionId}: ${e.message}`)
    })
    this.saveQueues.set(sessionId, next)
    return next
  }

  private persistMessages(sessionId: string, messages?: Message[]): Promise<void> {
    const source = messages || this.messages.get(sessionId) || []
    const deduped = this.deduplicateMessages(source)
    const start = Math.max(0, deduped.length - SessionStore.LOCAL_MESSAGE_CACHE_LIMIT)
    const cached = deduped.slice(start)
    return this.enqueueSave(sessionId, () => storageService.saveMessages(sessionId, cached))
  }

  // 保存会话到本地存储
  async saveSessionsToStorage(): Promise<void> {
    this.pruneArchivedSessions()
    await storageService.saveSessions(this.sessions)
    this.notifySessionsChanged()
  }

  private pruneArchivedSessions(): void {
    if (this.sessions.length <= 0) return
    const kept: Session[] = []
    let removed = 0
    for (let i = 0; i < this.sessions.length; i++) {
      const session = this.sessions[i]
      const threadId = session.officialCodexThreadId || this.officialCodexThreadIds.get(session.id) || ''
      if (this.isSessionArchivedByIdentity(session.id, threadId)) {
        removed++
        this.sessionStatuses.delete(session.id)
        this.pendingPermissions.delete(session.id)
        this.streamHeads.delete(session.id)
        this.sessionTasks.delete(session.id)
        this.officialCodexRecentActivityAt.delete(session.id)
        this.officialCodexActiveTurns.delete(session.id)
        this.officialCodexTerminalAt.delete(session.id)
        this.officialCodexLocalPollingSessions.delete(session.id)
        this.clearOfficialCodexSendLock(session.id)
        continue
      }
      kept.push(session)
    }
    if (removed > 0) {
      this.sessions = kept
      console.info(`[SessionStore] Pruned ${removed} archived session(s)`)
    }
  }

  async importOfficialCodexThreads(sessions: Session[]): Promise<void> {
    const imported: Session[] = []
    for (let i = 0; i < sessions.length; i++) {
      const session = sessions[i]
      const threadId = session.officialCodexThreadId || ''
      if (!threadId) continue

      let exists = false
      for (let j = 0; j < this.sessions.length; j++) {
        if (this.sessions[j].id === session.id || this.sessions[j].officialCodexThreadId === threadId) {
          exists = true
          break
        }
      }

      if (!exists) {
        this.sessions.push(session)
        imported.push(session)
      }
      this.officialCodexThreadIds.set(session.id, threadId)
      await this.restoreSessionFromDeleted(session.id)
    }

    // 立即保存和通知刷新
    await this.saveOfficialCodexThreadIds()
    await this.saveSessionsToStorage()
    
    // 强制触发响应式更新
    this.sessions = [...this.sessions]
    this.notifySessionsChanged()
    
    console.info(`[SessionStore] Imported ${imported.length} Official Codex threads, total sessions: ${this.sessions.length}`)

    // 不在导入时后台拉取每个 Codex 线程的完整消息。
    // 列表只需要轻量 metadata；进入某个对话时再按需同步该线程内容。
  }

  async importOfficialCodexThread(session: Session): Promise<void> {
    await this.importOfficialCodexThreads([session])
  }

  private async fetchOfficialCodexThreads(limit: number = SessionStore.OFFICIAL_CODEX_LIST_LIMIT): Promise<Array<Record<string, Object>>> {
    try {
      const localResponse = await apiService.getLocalCodexThreads(limit, SessionStore.OFFICIAL_CODEX_RECENT_DAYS)
      const localThreads = (localResponse['threads'] as Array<Record<string, Object>>) || []
      if (localThreads.length > 0) {
        console.info(`[SessionStore] Loaded ${localThreads.length} local Codex threads`)
        return localThreads
      }
    } catch (e) {
      console.error(`[SessionStore] Load local Codex threads error: ${e}`)
    }

    this.warmOfficialCodexControllerIfNeeded()

    const response = await apiService.listCodexRemoteThreads(limit)
    const result = response['result'] as Record<string, Object>
    const remoteThreads = (result && result['data']) as Array<Record<string, Object>>
    return remoteThreads || []
  }

  private async refreshOfficialCodexThreadRuntimeOnly(limit: number = 80): Promise<void> {
    try {
      const data = await this.fetchOfficialCodexThreads(limit)
      for (let i = 0; i < data.length; i++) {
        this.updateOfficialCodexThreadRuntimeSnapshot(data[i])
      }
      this.lastOfficialCodexRuntimeSnapshotAt = Date.now()
    } catch (e) {
      console.info(`[SessionStore] refreshOfficialCodexThreadRuntimeOnly skipped: ${e}`)
    }
  }

  async syncOfficialCodexThreadsToLocal(limit: number = SessionStore.OFFICIAL_CODEX_LIST_LIMIT): Promise<void> {
    try {
      const data = await this.fetchOfficialCodexThreads(limit)
      if (!data || data.length === 0) return

      let changed = false
      for (let i = 0; i < data.length; i++) {
        this.updateOfficialCodexThreadRuntimeSnapshot(data[i])
        const session = this.buildOfficialCodexSessionFromThread(data[i])
        if (!session) continue
        if (this.isSessionArchivedByIdentity(session.id, session.officialCodexThreadId || '')) continue

        let existingIndex = -1
        for (let j = 0; j < this.sessions.length; j++) {
          if (this.sessions[j].id === session.id || this.sessions[j].officialCodexThreadId === session.officialCodexThreadId) {
            existingIndex = j
            break
          }
        }

        if (existingIndex >= 0) {
          const old = this.sessions[existingIndex]
          const oldModifiedAt = new Date(old.modifiedAt).getTime()
          const nextModifiedAt = new Date(session.modifiedAt).getTime()
          const resolvedModifiedAt = !Number.isNaN(oldModifiedAt) && !Number.isNaN(nextModifiedAt) && oldModifiedAt > nextModifiedAt
            ? old.modifiedAt
            : session.modifiedAt
          this.sessions[existingIndex] = {
            id: old.id,
            title: session.title,
            projectPath: session.projectPath,
            workDir: session.workDir,
            workDirExists: session.workDirExists,
            createdAt: old.createdAt || session.createdAt,
            modifiedAt: resolvedModifiedAt,
            messageCount: old.messageCount,
            aiTool: 'codex',
            officialCodexThreadId: session.officialCodexThreadId
          }
        } else {
          this.sessions.push(session)
        }
        this.officialCodexThreadIds.set(session.id, session.officialCodexThreadId || '')
        changed = true
      }

      // 总是保存和通知，确保界面刷新
      await this.saveOfficialCodexThreadIds()
      await this.saveSessionsToStorage()
      this.notifySessionsChanged()
      console.info(`[syncOfficialCodexThreadsToLocal] Synced ${data.length} threads, changed=${changed}`)
    } catch (e) {
      console.error(`[SessionStore] Sync Official Codex threads error: ${e}`)
      this.notifySessionsChanged()
    }
  }

  async syncCurrentOfficialCodexSession(): Promise<void> {
    if (!this.currentSessionId) return
    const session = this.sessions.find(s => s.id === this.currentSessionId)
    const threadId = session?.officialCodexThreadId || this.officialCodexThreadIds.get(this.currentSessionId) || ''
    if (threadId.length <= 0) return
    await this.ensureOfficialCodexControllerConnected()
    await this.syncOfficialCodexPendingPermissions(this.currentSessionId, threadId)
    await this.syncOfficialCodexThreadMessages(this.currentSessionId, threadId)
  }

  async refreshCurrentOfficialCodexSessionState(): Promise<void> {
    if (!this.currentSessionId) return
    const session = this.sessions.find(s => s.id === this.currentSessionId)
    const threadId = session?.officialCodexThreadId || this.officialCodexThreadIds.get(this.currentSessionId) || ''
    if (threadId.length <= 0) return
    await this.ensureOfficialCodexControllerConnected()
    await this.syncOfficialCodexPendingPermissions(this.currentSessionId, threadId)
    await this.refreshOfficialCodexActiveSession(this.currentSessionId, threadId)
  }

  isOfficialCodexSessionPublic(sessionId: string): boolean {
    return this.isOfficialCodexSession(sessionId)
  }

  getOfficialCodexThreadId(sessionId: string): string {
    const session = this.sessions.find((s: Session) => s.id === sessionId)
    return session?.officialCodexThreadId || this.officialCodexThreadIds.get(sessionId) || ''
  }

  private buildOfficialCodexSessionFromThread(thread: Record<string, Object>): Session | null {
    const threadId = (thread['id'] as string) || ''
    if (threadId.length === 0) return null

    // 兼容本地 API 和远程 API 的字段
    const name = ((thread['name'] as string) || '').trim()
    const preview = ((thread['preview'] as string) || '').trim()
    const title = name.length > 0 ? name : preview
    const cwd = ((thread['cwd'] as string) || '').trim()

    // 优先使用 effectiveUpdatedAt（Codex Mini 计算的有效更新时间）
    // 然后是 updatedAt，最后是 mtimeMs
    const effectiveUpdatedAt = thread['effectiveUpdatedAt']
    const updatedAt = thread['updatedAt']
    const mtimeMs = thread['mtimeMs']
    const effectiveUpdatedMs = thread['effectiveUpdatedMs']

    const createdAt = this.formatOfficialCodexTime(thread['createdAt'])
    let modifiedAt: string
    if (effectiveUpdatedAt && typeof effectiveUpdatedAt === 'string') {
      modifiedAt = effectiveUpdatedAt
    } else if (updatedAt && typeof updatedAt === 'string') {
      modifiedAt = updatedAt
    } else if (effectiveUpdatedMs && typeof effectiveUpdatedMs === 'number') {
      modifiedAt = new Date(effectiveUpdatedMs).toISOString()
    } else if (mtimeMs && typeof mtimeMs === 'number') {
      modifiedAt = new Date(mtimeMs).toISOString()
    } else {
      modifiedAt = this.formatOfficialCodexTime(updatedAt)
    }

    return {
      id: 'official-codex-' + threadId,
      title: title.length > 0 ? title : 'Codex Desktop 对话',
      projectPath: cwd.length > 0 ? cwd : 'Codex Desktop',
      workDir: cwd,
      workDirExists: true,
      createdAt,
      modifiedAt,
      messageCount: 0,
      aiTool: 'codex',
      officialCodexThreadId: threadId
    }
  }

  private normalizeSessionTimestamp(timestamp: string | undefined, fallback: string): string {
    if (typeof timestamp === 'string' && timestamp.trim().length > 0) {
      const parsed = new Date(timestamp).getTime()
      if (!Number.isNaN(parsed) && parsed > 0) {
        return new Date(parsed).toISOString()
      }
    }
    return fallback
  }

  private getLatestMessageTimestamp(messages: Message[], fallback: string): string {
    let latestTime = new Date(fallback).getTime()
    if (Number.isNaN(latestTime) || latestTime <= 0) {
      latestTime = Date.now()
    }

    for (let i = 0; i < messages.length; i++) {
      const nextTime = new Date(messages[i].timestamp).getTime()
      if (!Number.isNaN(nextTime) && nextTime > latestTime) {
        latestTime = nextTime
      }
    }

    return new Date(latestTime).toISOString()
  }

  private findExistingSessionIdByOfficialCodexThreadId(threadId: string): string | null {
    if (!threadId || threadId.length <= 0) return null
    for (let i = 0; i < this.sessions.length; i++) {
      const session = this.sessions[i]
      if (session.officialCodexThreadId === threadId || this.officialCodexThreadIds.get(session.id) === threadId) {
        return session.id
      }
    }
    return null
  }

  private async ensureOfficialCodexSessionForThreadId(threadId: string): Promise<string | null> {
    if (!threadId || threadId.length <= 0) return null

    const existing = this.findExistingSessionIdByOfficialCodexThreadId(threadId)
    if (existing) return existing

    try {
      const threads = await this.fetchOfficialCodexThreads(Math.max(SessionStore.OFFICIAL_CODEX_LIST_LIMIT, 80))
      for (let i = 0; i < threads.length; i++) {
        const item = threads[i]
        if (((item['id'] as string) || '') !== threadId) continue
        const session = this.buildOfficialCodexSessionFromThread(item)
        if (!session) return null
        if (this.isSessionArchivedByIdentity(session.id, threadId)) return null

        this.sessions.push(session)
        this.officialCodexThreadIds.set(session.id, threadId)
        await this.restoreSessionFromDeleted(session.id)
        await this.saveOfficialCodexThreadIds()
        await this.saveSessionsToStorage()
        this.notifySessionsChanged()
        console.info(`[SessionStore] Auto-created Official Codex session for thread ${threadId}`)
        return session.id
      }
    } catch (e) {
      console.error(`[SessionStore] ensureOfficialCodexSessionForThreadId error: ${e}`)
    }

    return null
  }

  private updateSessionActivity(
    sessionId: string,
    timestamp: string | undefined,
    messageCount?: number,
    persist: boolean = false
  ): void {
    const index = this.sessions.findIndex((session: Session) => session.id === sessionId)
    if (index < 0) return

    const old = this.sessions[index]
    const nextModifiedAt = this.normalizeSessionTimestamp(timestamp, old.modifiedAt || old.createdAt || new Date().toISOString())
    const nextMessageCount = messageCount !== undefined ? messageCount : old.messageCount

    if (old.modifiedAt === nextModifiedAt && old.messageCount === nextMessageCount) {
      return
    }

    this.sessions[index] = {
      id: old.id,
      title: old.title,
      projectPath: old.projectPath,
      workDir: old.workDir,
      workDirExists: old.workDirExists,
      createdAt: old.createdAt,
      modifiedAt: nextModifiedAt,
      messageCount: nextMessageCount,
      aiTool: old.aiTool,
      officialCodexThreadId: old.officialCodexThreadId
    }

    this.notifySessionsChanged()
    if (persist) {
      void storageService.saveSessions(this.sessions)
    }
  }

  private updateOfficialCodexThreadRuntimeSnapshot(thread: Record<string, Object>): void {
    const threadId = ((thread['id'] as string) || '').trim()
    if (threadId.length <= 0) return

    const snapshot = new OfficialCodexThreadRuntimeSnapshot()
    snapshot.active = thread['active'] === true
    snapshot.status = ((thread['status'] as string) || '').trim()
    snapshot.updatedAt = thread['updatedAt']
    this.officialCodexThreadRuntime.set(threadId, snapshot)
  }

  private getOfficialCodexThreadRuntime(threadId: string): OfficialCodexThreadRuntimeSnapshot | null {
    return this.officialCodexThreadRuntime.get(threadId) || null
  }

  private markOfficialCodexActivity(sessionId: string): void {
    this.officialCodexRecentActivityAt.set(sessionId, Date.now())
  }

  private hasRecentOfficialCodexActivity(sessionId: string, windowMs: number = 20000): boolean {
    const lastAt = this.officialCodexRecentActivityAt.get(sessionId) || 0
    return lastAt > 0 && (Date.now() - lastAt) < windowMs
  }

  private hasPendingOfficialCodexWork(sessionId: string, windowMs: number = 20000): boolean {
    if (this.officialCodexSendQueues.has(sessionId)) {
      return true
    }
    const startedAt = this.officialCodexSendStartedAt.get(sessionId) || 0
    return startedAt > 0 && (Date.now() - startedAt) < windowMs
  }

  private hasOfficialCodexActiveTurn(sessionId: string): boolean {
    return this.officialCodexActiveTurns.has(sessionId)
  }

  private hasOfficialCodexStreamingPreview(sessionId: string): boolean {
    const buffer = this.streamingBuffers.get(sessionId)
    if (buffer) {
      if (buffer.assistant.trim().length > 0) return true
      if (buffer.blockType === 'text' && buffer.thinking.trim().length > 0) return true
    }

    const head = this.streamHeads.get(sessionId) || []
    for (let i = head.length - 1; i >= 0; i--) {
      const message = head[i]
      if (message.type === 'assistant' && (message.content || '').trim().length > 0) {
        return true
      }
    }

    return false
  }

  private hasOfficialCodexThinkingPreview(sessionId: string): boolean {
    const buffer = this.streamingBuffers.get(sessionId)
    if (buffer && buffer.thinking.trim().length > 0 && buffer.assistant.trim().length <= 0) {
      return true
    }

    const head = this.streamHeads.get(sessionId) || []
    for (let i = head.length - 1; i >= 0; i--) {
      const message = head[i]
      if (message.type === 'thinking' && (message.content || '').trim().length > 0) {
        return true
      }
    }

    return false
  }

  private hasOfficialCodexTerminalCooldown(sessionId: string, windowMs: number = 60000): boolean {
    const lastAt = this.officialCodexTerminalAt.get(sessionId) || 0
    return lastAt > 0 && (Date.now() - lastAt) < windowMs
  }

  private isOfficialCodexThreadRuntimeActive(threadId: string): boolean {
    const runtime = this.getOfficialCodexThreadRuntime(threadId)
    if (!runtime) return false
    if (runtime.active === true) return true

    const status = (runtime.status || '').replace(/[-_]/g, '').toLowerCase()
    return status === 'running' || status === 'inprogress' || status === 'pending'
  }

  private formatOfficialCodexTime(value: Object): string {
    // 处理 undefined、null、空字符串等情况
    if (value === undefined || value === null || value === '') {
      return new Date().toISOString()
    }

    // 如果是字符串，尝试解析 ISO 格式或数字
    if (typeof value === 'string') {
      const trimmed = (value as string).trim()
      if (trimmed.length === 0) {
        return new Date().toISOString()
      }
      // 尝试解析 ISO 格式（如 "2026-05-28T15:29:34.007Z"）
      const parsed = Date.parse(trimmed)
      if (!isNaN(parsed) && parsed > 0) {
        return new Date(parsed).toISOString()
      }
      // 尝试当作数字解析
      const raw = Number(trimmed)
      if (!isNaN(raw) && raw > 0) {
        const ms = raw > 1000000000000 ? raw : raw * 1000
        return new Date(ms).toISOString()
      }
      return new Date().toISOString()
    }

    // 如果是数字时间戳
    const raw = Number(value)
    if (isNaN(raw) || raw <= 0) {
      return new Date().toISOString()
    }
    const ms = raw > 1000000000000 ? raw : raw * 1000
    return new Date(ms).toISOString()
  }

  private async recoverOfficialCodexController(): Promise<void> {
    try {
      await apiService.restoreCodexControllerSession(true)
    } catch (e) {}
    try {
      await apiService.connectCodexController()
    } catch (e) {}
  }

  warmOfficialCodexControllerIfNeeded(force: boolean = false): void {
    const hasOfficialCodexState = this.officialCodexThreadIds.size > 0 ||
      this.sessions.some((session: Session) =>
        !!session.officialCodexThreadId || (session.aiTool || '').toLowerCase().indexOf('codex') >= 0)
    if (!hasOfficialCodexState) return

    const now = Date.now()
    if (!force && now - this.lastOfficialCodexWarmupAt < 30 * 1000) return
    if (this.officialCodexWarmupInFlight) return

    this.lastOfficialCodexWarmupAt = now
    this.officialCodexWarmupInFlight = this.recoverOfficialCodexController()
      .catch((e: Error) => console.info(`[SessionStore] Official Codex warmup skipped: ${e.message}`))
      .then(() => {
        this.officialCodexWarmupInFlight = null
      })
  }

  private async ensureOfficialCodexControllerConnected(): Promise<void> {
    try {
      const status = await apiService.getCodexControllerWsStatus()
      const connected = status['connected'] as boolean
      if (connected) return
    } catch (e) {}
    await this.recoverOfficialCodexController()
  }

  private async syncOfficialCodexPendingPermissions(sessionId: string, threadId: string): Promise<void> {
    try {
      const response = await apiService.getCodexRemotePendingPermissions(sessionId, threadId)
      const permissions = response['permissions'] as Array<Record<string, Object>>
      if (!permissions || permissions.length === 0) {
        this.reconcileOfficialCodexPermissions(sessionId, new Set<string>())
        return
      }

      const activeIds: Set<string> = new Set()
      for (let i = 0; i < permissions.length; i++) {
        const permission = permissions[i]
        const requestId = (permission['requestId'] as string) || ''
        if (requestId.length === 0) continue
        activeIds.add(requestId)
        this.addOfficialCodexPermissionMessage(sessionId, {
          requestId,
          toolName: (permission['toolName'] as string) || 'unknown',
          input: (permission['input'] as Record<string, Object>) || {},
          description: (permission['description'] as string) || ''
        })
      }
      this.reconcileOfficialCodexPermissions(sessionId, activeIds)
    } catch (e) {
      console.error(`[SessionStore] Sync Official Codex pending permissions error: ${e}`)
    }
  }

  private reconcileOfficialCodexPermissions(sessionId: string, activeIds: Set<string>): void {
    const currentPending = this.pendingPermissions.get(sessionId)
    if (currentPending && !activeIds.has(currentPending.requestId)) {
      this.pendingPermissions.delete(sessionId)
    }

    const sessionMessages = this.messages.get(sessionId) || []
    let changed = false
    for (let i = 0; i < sessionMessages.length; i++) {
      const message = sessionMessages[i]
      if (message.type === 'permission_request' &&
        message.permissionId &&
        !message.isPermissionHandled &&
        !activeIds.has(message.permissionId)) {
        sessionMessages[i] = {
          id: message.id,
          type: message.type,
          content: message.content,
          timestamp: message.timestamp,
          toolName: message.toolName,
          toolInput: message.toolInput,
          permissionId: message.permissionId,
          permissionDescription: message.permissionDescription,
          isPermissionHandled: true
        }
        changed = true
      }
    }

    if (changed) {
      this.messages.set(sessionId, sessionMessages)
      this.persistMessages(sessionId, sessionMessages)
      this.notifyMessagesChanged(sessionId)
    }

    if (activeIds.size === 0 && this.sessionStatuses.get(sessionId) === 'permission_pending') {
      this.updateSessionStatus(sessionId, 'thinking')
      this.upsertOfficialCodexStatusMessage(sessionId, '权限已处理，Codex Desktop 继续工作')
    }
  }

  private addOfficialCodexPermissionMessage(sessionId: string, pending: PendingPermission): void {
    // 先检查是否已存在
    const existing = this.messages.get(sessionId) || []
    for (let i = 0; i < existing.length; i++) {
      if (existing[i].type === 'permission_request' && existing[i].permissionId === pending.requestId) {
        return
      }
    }

    this.flushStreamingBuffer(sessionId)
    this.flushHeadToTail(sessionId)
    this.updateSessionStatus(sessionId, 'permission_pending')
    this.pendingPermissions.set(sessionId, pending)

    const permissionMessage: Message = {
      id: 'permission-' + Date.now(),
      type: 'permission_request',
      content: '',
      timestamp: new Date().toISOString(),
      toolName: pending.toolName,
      toolInput: pending.input,
      permissionId: pending.requestId,
      permissionDescription: pending.description
    }
    this.addMessage(sessionId, permissionMessage)
  }

  private upsertOfficialCodexStatusMessage(sessionId: string, content: string): void {
    const id = 'official-codex-status-current'
    const now = new Date().toISOString()
    const sessionMessages = this.messages.get(sessionId) || []
    for (let i = sessionMessages.length - 1; i >= 0; i--) {
      if (sessionMessages[i].id === id) {
        if (sessionMessages[i].content !== content) {
          sessionMessages[i] = {
            id,
            type: 'system_notification',
            content,
            timestamp: now
          }
          this.messages.set(sessionId, sessionMessages)
          this.persistMessages(sessionId, sessionMessages)
          this.notifyMessagesChanged(sessionId)
        }
        return
      }
    }

    sessionMessages.push({
      id,
      type: 'system_notification',
      content,
      timestamp: now
    })
    this.messages.set(sessionId, sessionMessages)
    this.persistMessages(sessionId, sessionMessages)
    this.notifyMessagesChanged(sessionId)
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
        // 始终进行去重清理（即使数量相同也可能有内容重复）
        const deduped = this.deduplicateMessages(existing)
        if (deduped.length !== existing.length) {
          console.warn(`[SessionStore] loadMessages: cleaned ${existing.length - deduped.length} duplicates from memory for ${sessionId}`)
          this.messages.set(sessionId, deduped)
          // 立即保存去重后的消息到本地存储
          this.persistMessages(sessionId, deduped)
          this.notifyMessagesChanged(sessionId)
        }
      } else {
        // 先加载本地缓存（快速展示）
        const localMessages = await storageService.loadMessages(sessionId)
        if (localMessages.length > 0) {
          // 关键修复：加载后立即去重，防止本地存储中的重复消息污染内存
          const deduped = this.deduplicateMessages(localMessages)
          if (deduped.length !== localMessages.length) {
            console.warn(`[SessionStore] loadMessages: cleaned ${localMessages.length - deduped.length} duplicates from local storage for ${sessionId}`)
            // 更新本地存储
            this.persistMessages(sessionId, deduped)
          }
          this.messages.set(sessionId, deduped)
          this.notifyMessagesChanged(sessionId)
        }
      }
    } catch (e) {
      console.error(`[SessionStore] loadMessages storage error: ${e}`)
    }

    // 从现有消息中提取任务列表
    this.refreshTasksFromMessages(sessionId)


    // Official Codex 会话：主动同步最新状态和消息
    if (this.isOfficialCodexSession(sessionId)) {
      void this.syncOfficialCodexSessionOnLoad(sessionId)
      return
    }

    // 后台静默同步服务器消息（不阻塞页面渲染）
    // 检查是否已经在同步中，避免重复调用
    if (!this.syncingSessions.has(sessionId)) {
      console.info(`[SessionStore] syncMessagesFromServer calling for ${sessionId}`)
      this.syncMessagesFromServer(sessionId)
    } else {
      console.info(`[SessionStore] syncMessagesFromServer: already syncing ${sessionId}, skip`)
    }
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
          const newKey = this.messageSemanticKey(newMsg)
          const existsById = merged.some(m => m.id === newMsg.id)
          const existsByKey = merged.some(m => this.messageSemanticKey(m) === newKey)
          if (!existsById && !existsByKey) {
            merged.push(newMsg)
          }
        }
        merged.sort((a, b) =>
          new Date(a.timestamp).getTime() - new Date(b.timestamp).getTime()
        )
      }

      // 去重检测并清理：用语义键去重，防止重新进入聊天页后
      // 服务端正式消息和本地流式临时消息 ID/toolUseId 不一致导致重复。
      // 始终执行去重，而不是只在检测到重复时
      {
        const deduped: Message[] = []
        const seenKeys: Set<string> = new Set()
        const seenIds: Set<string> = new Set()
        let removedDupCount = 0
        for (let i = 0; i < merged.length; i++) {
          const m = merged[i]
          const hasStableId = this.isStableMessageId(m.id)
          // 优先按 ID 去重
          if (m.id && hasStableId) {
            if (seenIds.has(m.id)) {
              removedDupCount++
              console.warn(`[SessionStore] Removing dup after sync (by ID): #${removedDupCount} id=${m.id} type=${m.type}`)
              continue
            }
            seenIds.add(m.id)
          }
          // 语义内容去重：即使有稳定 ID 的消息也要参与，
          // 以捕获"本地临时 ID + 服务器稳定 ID"表示同一条消息的情况。
          // 当两条消息语义键相同但 ID 不同时，优先保留稳定 ID 的那条。
          const key = this.messageSemanticKey(m)
          if (seenKeys.has(key)) {
            removedDupCount++
            // 如果当前消息有稳定 ID 而已有消息没有，用稳定 ID 版本替换
            if (hasStableId) {
              let replaced = false
              for (let j = 0; j < deduped.length; j++) {
                if (this.messageSemanticKey(deduped[j]) === key && !this.isStableMessageId(deduped[j].id)) {
                  console.info(`[SessionStore] Replacing transient ${deduped[j].id} with stable ${m.id} (same semantic key)`)
                  deduped[j] = m
                  replaced = true
                  removedDupCount-- // 替换不算额外删除
                  break
                }
              }
              if (replaced) {
                continue
              }
            }
            console.warn(`[SessionStore] Removing dup after sync (by content): #${removedDupCount} key=${key.substring(0, 100)} type=${m.type} id=${m.id}`)
            continue
          }
          seenKeys.add(key)
          deduped.push(m)
        }
        if (removedDupCount > 0) {
          console.warn(`[SessionStore] Removed ${removedDupCount} dups from merged result, deduped=${deduped.length}`)
        }
        merged = deduped  // 始终使用去重后的结果
      }

      this.messages.set(sessionId, merged)
      this.notifyMessagesChanged(sessionId)

      // 打印所有 tool_use 消息的工具名
      const toolNamesInMerge = merged.filter(m => m.type === 'tool_use' && m.toolName).map(m => m.toolName)
      console.info(`[SessionStore] syncMessagesFromServer merged ${merged.length} msgs, tool_use names: [${toolNamesInMerge.join(', ')}]`)

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
      this.persistMessages(sessionId, merged)
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

    // 先对服务器消息本身去重（防止服务器返回重复消息）
    const dedupedServerMessages: Message[] = []
    for (let i = 0; i < serverMessages.length; i++) {
      const msg = serverMessages[i]
      const primaryKey = this.messageContentKey(msg)
      const semanticKey = this.messageSemanticKey(msg)

      // 检查是否已在去重后的列表中
      let isDup = false
      const hasStableId = this.isStableMessageId(msg.id)
      if (hasStableId) {
        if (serverIds.has(msg.id)) {
          isDup = true
        } else {
          serverIds.add(msg.id)
        }
      }
      // 服务端历史内部不要按 semanticKey 去重，否则两条相同内容的真实历史消息会被误删。
      // semanticKey 只登记给后续“本地临时消息 vs 服务端正式消息”匹配使用。
      if (!isDup && serverKeys.has(primaryKey)) {
        isDup = true
      }

      if (!isDup) {
        serverKeys.set(primaryKey, true)
        serverKeys.set(semanticKey, true)
        dedupedServerMessages.push(msg)
      } else {
        console.info(`[SessionStore] mergeMessages: skip dup server msg id=${msg.id} type=${msg.type}`)
      }
    }

    // 先添加去重后的服务器消息
    const result: Message[] = [...dedupedServerMessages]

    // 再检查本地消息中是否有服务器没有的
    for (let i = 0; i < localMessages.length; i++) {
      const msg = localMessages[i]
      const primaryKey = this.messageContentKey(msg)
      const semanticKey = this.messageSemanticKey(msg)

      // 跳过: 主键匹配（含 type + toolUseId / type + id / type + content）
      if (serverKeys.has(primaryKey)) continue
      // 跳过: 语义匹配（服务端有正式 ID，本地是 stream-/user-/toolUseId 临时形态时尤其重要）
      if (serverKeys.has(semanticKey)) continue
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
            // toolUseId 不同但 toolName 相同 → 检查 toolInput 是否相同：
            // 不同 toolInput 说明是不同调用（如 Read 不同文件），不应合并
            const localInput = msg.toolInput ? this.stableStringify(msg.toolInput) : ''
            const serverInput = sm.toolInput ? this.stableStringify(sm.toolInput) : ''
            if (localInput && serverInput && localInput !== serverInput) {
              continue
            }
            // toolInput 相同时，按时间附近判定是否同一调用
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
            // 内容完全匹配（降低长度阈值，确保短消息也能去重）
            if (localContent.length > 0 && localContent === serverContent) {
              foundByContent = true
              break
            }
            // 本地和服务端可能一个是整段、一个是拆分段（页面重进后历史同步常见）
            if (this.isOverlappingText(localContent, serverContent)) {
              foundByContent = true
              break
            }
            // 规整化对比：trim + 合并空白，捕获流式 vs 服务端格式差异（尾部换行、前后空格等）
            const normLocal = localContent.trim().replace(/\s+/g, ' ')
            const normServer = serverContent.trim().replace(/\s+/g, ' ')
            if (normLocal.length > 0 && normLocal === normServer) {
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
    // 增加 ID 维度：优先用 ID 去重，无 ID 时用内容去重，防止不同消息内容相同被误合并
    const finalResult: Message[] = []
    const seenFinal: Map<string, boolean> = new Map()
    const seenFinalIds: Set<string> = new Set()
    for (let i = 0; i < result.length; i++) {
      const m = result[i]
      // 优先按 ID 去重（如果有有效 ID）
      const hasStableId = this.isStableMessageId(m.id)
      if (hasStableId) {
        if (seenFinalIds.has(m.id)) {
          continue
        }
        seenFinalIds.add(m.id)
      }
      // 稳定 ID 的服务端历史消息只按 ID 去重，避免两次相同内容的真实消息被误删。
      if (hasStableId) {
        seenFinal.set(this.messageSemanticKey(m), true)
        finalResult.push(m)
        continue
      }
      // 临时消息使用语义键去重，捕获流式 vs 服务端格式差异，也避免 toolUseId 变化造成重复
      const finalKey = this.messageSemanticKey(m)
      const existing = seenFinal.get(finalKey)
      if (existing) continue
      seenFinal.set(finalKey, true)
      finalResult.push(m)
    }

    return finalResult
  }


  // 稳定化 JSON.stringify：递归对 key 排序，消除嵌套对象属性顺序不确定性
  private stableStringify(value: Object | undefined | null): string {
    if (value === undefined || value === null) return ''
    if (Array.isArray(value)) {
      const items: string[] = []
      for (let i = 0; i < value.length; i++) {
        items.push(this.stableStringify(value[i] as Object))
      }
      return '[' + items.join(',') + ']'
    }
    if (typeof value === 'object') {
      const obj = value as Record<string, Object>
      const keys = Object.keys(obj).sort()
      const pairs: string[] = []
      for (const key of keys) {
        pairs.push(JSON.stringify(key) + ':' + this.stableStringify(obj[key]))
      }
      return '{' + pairs.join(',') + '}'
    }
    return JSON.stringify(value)
  }

  private isStableMessageId(id: string | undefined | null): boolean {
    if (!id) return false
    return !id.startsWith('stream-') &&
      !id.startsWith('thinking-') &&
      !id.startsWith('user-') &&
      !id.startsWith('permission-') &&
      !id.startsWith('question-') &&
      !id.startsWith('err-') &&
      !id.startsWith('sys-')
  }

  // 生成消息内容去重键
  private messageContentKey(msg: Message): string {
    // 1. 有有效 ID 的消息直接用 ID（排除临时 ID）
    if (msg.id &&
        !msg.id.startsWith('stream-') &&
        !msg.id.startsWith('thinking-') &&
        !msg.id.startsWith('user-') &&
        !msg.id.startsWith('permission-') &&
        !msg.id.startsWith('question-') &&
        !msg.id.startsWith('err-') &&
        !msg.id.startsWith('sys-')) {
      return msg.type + ':id:' + msg.id
    }

    // 2. tool_use 消息：用 toolName + 稳定化的 toolInput 作为键
    // 关键修复：tool_use 的 content 为空，不能靠内容去重
    // 注意：截取长度必须与 messageSemanticKey 保持一致（1000字符），否则会导致去重失败
    if (msg.type === 'tool_use' && msg.toolName) {
      const inputStr = msg.toolInput ? this.stableStringify(msg.toolInput) : ''
      const parentId = msg.parentToolUseId ? ':parent:' + msg.parentToolUseId : ''
      return msg.type + ':tool:' + msg.toolName + ':' + inputStr.substring(0, 1000) + parentId
    }

    // 3. tool_result 消息：关联到对应的 tool_use
    if (msg.type === 'tool_result' && msg.toolUseId) {
      return msg.type + ':result:' + msg.toolUseId
    }

    // 4. permission_request 用 permissionId
    if (msg.type === 'permission_request' && msg.permissionId) {
      return msg.type + ':perm:' + msg.permissionId
    }

    // 5. question 用 questionId
    if (msg.type === 'question' && msg.questionId) {
      return msg.type + ':q:' + msg.questionId
    }

    // 6. 普通消息：用规整化内容
    // 注意：截取长度必须与 messageSemanticKey 保持一致（4000字符），且使用相同的规整化方法
    const content = this.normalizeMessageText(msg.content || msg.toolResult || '')
    return msg.type + ':content:' + content.substring(0, 4000)
  }

  // 生成跨来源的语义去重键：忽略服务端 ID / 临时 ID / 变化的 toolUseId。
  // 用于历史同步和页面重新进入时清理”同一内容不同 ID”的重复消息。
  private messageSemanticKey(msg: Message): string {
    if (this.isOfficialCodexMessageId(msg.id)) {
      return msg.type + ':official:' + msg.id
    }

    if (msg.type === 'tool_use' && msg.toolName) {
      const inputStr = msg.toolInput ? this.stableStringify(msg.toolInput) : ''
      const parentId = msg.parentToolUseId ? ':parent:' + msg.parentToolUseId : ''
      return msg.type + ':tool:' + msg.toolName + ':' + inputStr.substring(0, 1000) + parentId
    }

    if (msg.type === 'permission_request' && msg.permissionId) {
      return msg.type + ':perm:' + msg.permissionId
    }

    if (msg.type === 'question' && msg.questionId) {
      return msg.type + ':q:' + msg.questionId
    }

    const content = this.normalizeMessageText(msg.content || msg.toolResult || '')
    if (content.length > 0) {
      return msg.type + ':content:' + content.substring(0, 4000)
    }

    return this.messageContentKey(msg)
  }

  private normalizeMessageText(text: string): string {
    return text
      .replace(/\r\n/g, '\n')
      .trim()
      .replace(/\s+/g, ' ')
  }

  private isOverlappingText(a: string, b: string): boolean {
    const left = this.normalizeMessageText(a)
    const right = this.normalizeMessageText(b)
    if (!left || !right) return false
    if (left === right) return true

    const shorter = left.length < right.length ? left : right
    const longer = left.length < right.length ? right : left
    // 短文本容易误伤，例如“好的”和“好的，已完成”，只对较长内容做包含式去重
    return shorter.length >= 80 && longer.includes(shorter)
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
      const newKey = this.messageSemanticKey(message)
      for (let i = 0; i < sessionMessages.length; i++) {
        if (this.messageSemanticKey(sessionMessages[i]) === newKey) {
          exists = true
          break
        }
      }
    }

    if (!exists) {
      sessionMessages.push(message)
      this.messages.set(sessionId, sessionMessages)
      this.updateSessionActivity(sessionId, message.timestamp, sessionMessages.length)
      this.notifyMessagesChanged(sessionId)

      // 串行化保存到本地（通过队列确保顺序，防止并发竞态）
      this.persistMessages(sessionId)
    }
  }

  // MARK: - Head/Tail 流式缓冲

  /** 将流式缓冲区内容一次性刷入 streamHeads（整条消息显示，不逐字追加） */
  private flushStreamingBuffer(sessionId: string): void {
    const buffer = this.streamingBuffers.get(sessionId)
    if (!buffer) return
    this.streamingBuffers.delete(sessionId)
    this.cancelStreamingPreviewTimer(sessionId)
    this.updateStreamingHeadFromBuffer(sessionId, buffer, false, false)
  }

  private scheduleStreamingPreviewFlush(sessionId: string): void {
    if (this.streamingPreviewTimers.has(sessionId)) {
      return
    }
    const timer = setTimeout(() => {
      this.streamingPreviewTimers.delete(sessionId)
      const buffer = this.streamingBuffers.get(sessionId)
      if (!buffer) return
      this.updateStreamingHeadFromBuffer(sessionId, buffer, true, true)
    }, 120)
    this.streamingPreviewTimers.set(sessionId, timer)
  }

  private cancelStreamingPreviewTimer(sessionId: string): void {
    const timer = this.streamingPreviewTimers.get(sessionId)
    if (timer !== undefined) {
      clearTimeout(timer)
      this.streamingPreviewTimers.delete(sessionId)
    }
  }

  private updateStreamingHeadFromBuffer(
    sessionId: string,
    buffer: StreamingBuffer,
    isStreaming: boolean,
    usePreviewIds: boolean
  ): void {
    const nextHead: Message[] = []
    const suffix = usePreviewIds ? sessionId : String(Date.now())
    if (buffer.thinking.trim().length > 0) {
      nextHead.push({
        id: usePreviewIds ? `thinking-preview-${suffix}` : `thinking-${suffix}`,
        type: 'thinking',
        content: buffer.thinking,
        isStreaming,
        timestamp: new Date().toISOString(),
      })
    }
    if (buffer.assistant.trim().length > 0) {
      nextHead.push({
        id: usePreviewIds ? `stream-preview-${suffix}` : `stream-${suffix}`,
        type: 'assistant',
        content: buffer.assistant,
        isStreaming,
        timestamp: new Date().toISOString(),
      })
    }

    this.streamHeads.set(sessionId, nextHead)
    this.notifyMessagesChanged(sessionId)
  }

  /** 将流式 Head 缓冲刷新到 Tail (messages) */
  flushHeadToTail(sessionId: string): void {
    const head = this.streamHeads.get(sessionId)
    if (!head || head.length === 0) return

    let tail = this.messages.get(sessionId) || []
    let changed = false

    for (let i = 0; i < head.length; i++) {
      const headMsg = head[i]
      // Head 中的消息已不再流式
      headMsg.isStreaming = false

      // 使用 messageContentKey 进行统一的去重检查
      const headKey = this.messageSemanticKey(headMsg)
      let exists = false

      // 先按 ID 检查
      if (headMsg.id) {
        for (let j = tail.length - 1; j >= 0; j--) {
          if (tail[j].id === headMsg.id) {
            exists = true
            break
          }
        }
      }

      // 再按内容键检查
      if (!exists) {
        for (let j = tail.length - 1; j >= 0; j--) {
          if (this.messageSemanticKey(tail[j]) === headKey) {
            exists = true
            break
          }
        }
      }

      if (!exists) {
        tail.push(headMsg)
        changed = true
      }
    }

    if (changed) {
      // 最终彻底去重，确保没有遗漏
      const deduped = this.deduplicateMessages(tail)
      if (deduped.length !== tail.length) {
        console.warn(`[SessionStore] flushHeadToTail: removed ${tail.length - deduped.length} duplicates`)
        tail = deduped
      }
      this.messages.set(sessionId, tail)
      const latestTimestamp = this.getLatestMessageTimestamp(tail, new Date().toISOString())
      this.updateSessionActivity(sessionId, latestTimestamp, tail.length)
      // 串行化保存到本地（通过队列确保顺序）
      this.persistMessages(sessionId, tail)
      this.notifyMessagesChanged(sessionId)
    }
    this.streamHeads.set(sessionId, [])
  }

  /**
   * 彻底去重消息数组（修改原始数据）
   * 使用多维度去重策略，比 getDedupedMessages 更严格
   * 返回去重后的新数组
   */
  private deduplicateMessages(messages: Message[]): Message[] {
    if (messages.length < 2) return messages

    const result: Message[] = []
    const seenById: Set<string> = new Set()
    const seenByContent: Set<string> = new Set()
    const seenByTool: Set<string> = new Set()

    for (let i = 0; i < messages.length; i++) {
      const msg = messages[i]
      const collapsibleIndex = this.findCollapsibleTextMessageIndex(result, msg)
      if (collapsibleIndex >= 0) {
        const existing = result[collapsibleIndex]
        if (this.isStableMessageId(msg.id) && !this.isStableMessageId(existing.id)) {
          result[collapsibleIndex] = msg
          console.info(`[SessionStore] deduplicateMessages: replace transient with stable ${existing.id} -> ${msg.id}`)
        } else {
          console.info(`[SessionStore] deduplicateMessages: collapse transient duplicate ${msg.id}`)
        }
        continue
      }

      // 1. 按 ID 去重（排除临时 ID）
      const hasStableId = this.isStableMessageId(msg.id)
      if (hasStableId) {
        if (seenById.has(msg.id)) {
          console.info(`[SessionStore] deduplicateMessages: skip by ID ${msg.id}`)
          continue
        }
        seenById.add(msg.id)
      }

      // 有稳定 ID 的历史消息用 ID 保真，但仍需做语义交叉去重：
      // 当内存中同时存在"临时 ID 版本"和"稳定 ID 版本"的同一消息时，
      // 优先保留稳定 ID 版本。两条都有稳定 ID 且内容相同的真实对话不会被误删。
      if (hasStableId) {
        const semanticKey = this.messageSemanticKey(msg)
        if (seenByContent.has(semanticKey) || seenByTool.has(semanticKey)) {
          // 语义键已存在，检查是否可以替换已有的临时 ID 版本
          let replaced = false
          for (let j = 0; j < result.length; j++) {
            const existingKey = this.messageSemanticKey(result[j])
            if (existingKey === semanticKey && !this.isStableMessageId(result[j].id)) {
              console.info(`[SessionStore] deduplicateMessages: replace transient ${result[j].id} with stable ${msg.id}`)
              result[j] = msg
              replaced = true
              break
            }
          }
          if (replaced) {
            seenById.add(msg.id)
            continue
          }
          // 两条都有稳定 ID 但语义相同，保留先出现的（ID 保真）
          console.info(`[SessionStore] deduplicateMessages: skip stable ID dup ${msg.id} (semantic match)`)
          continue
        }
        // 登记语义键，供后续临时 ID 消息匹配
        if (msg.type === 'tool_use' && msg.toolName) {
          seenByTool.add(semanticKey)
        } else {
          seenByContent.add(semanticKey)
        }
        result.push(msg)
        continue
      }

      // 2. tool_use 消息：按 toolName + toolInput 去重
      if (msg.type === 'tool_use' && msg.toolName) {
        const toolKey = this.messageSemanticKey(msg)
        if (seenByTool.has(toolKey)) {
          console.info(`[SessionStore] deduplicateMessages: skip tool_use ${msg.toolName}`)
          continue
        }
        seenByTool.add(toolKey)
      }

      // 3. 其他消息：按规整化内容去重
      if (msg.type !== 'tool_use') {
        const content = this.normalizeMessageText(msg.content || msg.toolResult || '')
        const contentKey = this.messageSemanticKey(msg)
        if (content.length > 0 && seenByContent.has(contentKey)) {
          console.info(`[SessionStore] deduplicateMessages: skip ${msg.type} by content`)
          continue
        }
        seenByContent.add(contentKey)
      }

      result.push(msg)
    }

    return this.removeOverlappingTextMessages(result)
  }

  private findCollapsibleTextMessageIndex(messages: Message[], next: Message): number {
    if (!this.isCollapsibleTextMessage(next)) return -1

    const start = Math.max(0, messages.length - 6)
    for (let i = messages.length - 1; i >= start; i--) {
      const current = messages[i]
      if (!this.isCollapsibleTextMessage(current)) continue
      if (this.shouldCollapseTransientTextMessage(current, next)) {
        return i
      }
    }
    return -1
  }

  private isCollapsibleTextMessage(message: Message): boolean {
    return message.type === 'assistant' || message.type === 'user' || message.type === 'error'
  }

  private shouldCollapseTransientTextMessage(left: Message, right: Message): boolean {
    if (left.type !== right.type) return false
    if (this.isStableMessageId(left.id) && this.isStableMessageId(right.id)) return false
    if (!this.isMessageTimeClose(left.timestamp, right.timestamp, 15 * 60 * 1000)) return false

    if (this.isSameOfficialCodexTurnMessage(left, right)) {
      return true
    }

    const leftText = this.normalizeMessageText(left.content || left.toolResult || '')
    const rightText = this.normalizeMessageText(right.content || right.toolResult || '')
    if (leftText.length <= 0 || rightText.length <= 0) return false
    return this.isLikelyTransientOfficialCodexDuplicate(leftText, rightText)
  }

  private isLikelyTransientOfficialCodexDuplicate(leftText: string, rightText: string): boolean {
    if (leftText === rightText) return true

    const shorter = leftText.length <= rightText.length ? leftText : rightText
    const longer = leftText.length <= rightText.length ? rightText : leftText
    if (shorter.length < 24) return false

    if (longer.includes(shorter)) return true
    return this.isOverlappingText(leftText, rightText)
  }

  private removeOverlappingTextMessages(messages: Message[]): Message[] {
    if (messages.length < 2) return messages

    const removedIndexes: Set<number> = new Set()
    for (let i = 0; i < messages.length; i++) {
      if (removedIndexes.has(i)) continue
      const a = messages[i]
      const aText = this.normalizeMessageText(a.content || a.toolResult || '')
      if (aText.length < 80 || a.type === 'tool_use') continue

      for (let j = i + 1; j < messages.length; j++) {
        if (removedIndexes.has(j)) continue
        const b = messages[j]
        if (a.type !== b.type) continue
        if (this.isStableMessageId(a.id) && this.isStableMessageId(b.id)) continue

        const aTurn = this.extractOfficialCodexTurnIdFromMessage(a.id)
        const bTurn = this.extractOfficialCodexTurnIdFromMessage(b.id)
        if (aTurn.length > 0 && bTurn.length > 0 && aTurn !== bTurn) {
          continue
        }

        const bText = this.normalizeMessageText(b.content || b.toolResult || '')
        if (bText.length < 80) continue
        if (!this.isOverlappingText(aText, bText)) continue

        if (aText.length >= bText.length) {
          removedIndexes.add(j)
          console.info(`[SessionStore] removeOverlappingTextMessages: skip contained ${b.type} id=${b.id}`)
        } else {
          removedIndexes.add(i)
          console.info(`[SessionStore] removeOverlappingTextMessages: skip contained ${a.type} id=${a.id}`)
          break
        }
      }
    }

    if (removedIndexes.size === 0) return messages

    const result: Message[] = []
    for (let i = 0; i < messages.length; i++) {
      if (!removedIndexes.has(i)) {
        result.push(messages[i])
      }
    }
    return result
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
    const head = this.streamHeads.get(sessionId) || []
    const source = head.length > 0 ? [...tail, ...head] : tail
    if (source.length < 2) return source

    const result: Message[] = []
    const seen = new Set<string>()
    const seenById = new Set<string>()
    let dupCount = 0

    for (let i = 0; i < source.length; i++) {
      const msg = source[i]
      const hasStableId = this.isStableMessageId(msg.id)
      // 第一道：按稳定 ID 去重
      if (hasStableId) {
        if (seenById.has(msg.id)) {
          dupCount++
          console.info(`[SessionStore] getDedupedMessages #${dupCount}: skip by ID type=${msg.type} id=${msg.id}`)
          continue
        }
        seenById.add(msg.id)
      }
      // 第二道：按语义键去重（所有消息都参与，包括稳定 ID 的）
      const semanticKey = this.messageSemanticKey(msg)
      if (seen.has(semanticKey)) {
        dupCount++
        // 如果当前消息有稳定 ID 而已有消息没有，用稳定 ID 版本替换
        if (hasStableId) {
          let replaced = false
          for (let j = 0; j < result.length; j++) {
            if (this.messageSemanticKey(result[j]) === semanticKey && !this.isStableMessageId(result[j].id)) {
              console.info(`[SessionStore] getDedupedMessages: replace transient ${result[j].id} with stable ${msg.id}`)
              result[j] = msg
              replaced = true
              dupCount-- // 替换不算额外删除
              break
            }
          }
          if (replaced) {
            seen.add(semanticKey)
            continue
          }
        }
        console.info(`[SessionStore] getDedupedMessages #${dupCount}: skip by semantic type=${msg.type} id=${msg.id} key=${semanticKey.substring(0, 80)}`)
        continue
      }
      seen.add(semanticKey)
      result.push(msg)
    }

    // 第二道去重：用规整化内容去重（包括稳定 ID 消息也参与内容交叉去重）
    const normalizedSeen = new Set<string>()
    const finalResult: Message[] = []
    let normDupCount = 0

    for (let i = 0; i < result.length; i++) {
      const msg = result[i]
      const hasStableId = this.isStableMessageId(msg.id)
      let normKey: string

      if (hasStableId) {
        // 稳定 ID 消息：同时按 ID 和内容去重
        // 先按 ID 去重（同一 ID 不应出现两次）
        normKey = msg.type + ':id:' + msg.id
        if (normalizedSeen.has(normKey)) {
          normDupCount++
          console.info(`[SessionStore] getDedupedMessages normDup #${normDupCount}: skip by stable ID type=${msg.type} id=${msg.id}`)
          continue
        }
        normalizedSeen.add(normKey)
        // 再按语义内容去重：如果内容与临时 ID 消息重复，替换临时 ID 版本
        const contentKey = this.messageSemanticKey(msg)
        if (normalizedSeen.has(contentKey)) {
          normDupCount++
          // 检查是否可以替换已有的临时 ID 版本
          let replaced = false
          for (let j = 0; j < finalResult.length; j++) {
            if (this.messageSemanticKey(finalResult[j]) === contentKey && !this.isStableMessageId(finalResult[j].id)) {
              console.info(`[SessionStore] getDedupedMessages normDup: replace transient ${finalResult[j].id} with stable ${msg.id}`)
              finalResult[j] = msg
              replaced = true
              normDupCount-- // 替换不算额外删除
              break
            }
          }
          if (replaced) {
            continue
          }
          console.info(`[SessionStore] getDedupedMessages normDup #${normDupCount}: skip by content type=${msg.type} id=${msg.id}`)
          continue
        }
        normalizedSeen.add(contentKey)
      } else if (msg.type === 'tool_use' && msg.toolName) {
        normKey = this.messageSemanticKey(msg)
        if (normalizedSeen.has(normKey)) {
          normDupCount++
          console.info(`[SessionStore] getDedupedMessages normDup #${normDupCount}: skip tool_use type=${msg.type} id=${msg.id}`)
          continue
        }
        normalizedSeen.add(normKey)
      } else {
        const normContent = this.normalizeMessageText((msg.content || '') || (msg.toolResult || ''))
        // 注意：截取长度必须与 messageSemanticKey 保持一致（4000字符）
        normKey = msg.type + ':content:' + normContent.substring(0, 4000)
        if (normalizedSeen.has(normKey)) {
          normDupCount++
          console.info(`[SessionStore] getDedupedMessages normDup #${normDupCount}: skip by content type=${msg.type} id=${msg.id}`)
          continue
        }
        normalizedSeen.add(normKey)
      }

      finalResult.push(msg)
    }

    const totalRemoved = dupCount + normDupCount
    if (totalRemoved > 0) {
      console.info(`[SessionStore] getDedupedMessages: removed ${totalRemoved} dups from ${source.length} msgs for ${sessionId}`)
    }

    return this.removeOverlappingTextMessages(finalResult)
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

      // 使用更彻底的去重方法
      const cleaned = this.deduplicateMessages(msgs)
      if (cleaned.length !== msgs.length) {
        console.info(`[SessionStore] Cleaned ${msgs.length - cleaned.length} duplicate(s) for ${sessionId}`)
        this.messages.set(sessionId, cleaned)
        this.persistMessages(sessionId, cleaned)
        this.notifyMessagesChanged(sessionId)
      }
    }
  }

  // MARK: - WebSocket

  subscribeToAllSessions(): void {
    const serverUrl = authStore.serverUrl
    if (!serverUrl) return

    wsService.setServerUrl(serverUrl)
    wsService.connectGlobal()
    this.wsSubscribed = true

    console.info('[SessionStore] Global WS connected; per-session WS is only opened for the active chat')
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

  sendMessage(content: string, attachments?: AttachmentRef[]): boolean {
    if (!this.currentSessionId) return false

    const sessionId = this.currentSessionId
    const session = this.sessions.find(s => s.id === sessionId)

    if (this.shouldUseOfficialCodexRemote(session, attachments) && this.hasActiveOfficialCodexSend(sessionId)) {
      const lastWarnedAt = this.officialCodexSendBusyWarnedAt.get(sessionId) || 0
      if (Date.now() - lastWarnedAt > 10000) {
        this.officialCodexSendBusyWarnedAt.set(sessionId, Date.now())
        const notice: Message = {
          id: 'official-codex-send-busy-' + Date.now(),
          type: 'system_notification',
          content: '上一条消息还在提交到 Codex Desktop，我会自动恢复连接。',
          timestamp: new Date().toISOString()
        }
        this.addMessage(sessionId, notice)
      }
      return false
    }

    // 添加用户消息
    const userMessage: Message = {
      id: 'user-' + Date.now(),
      type: 'user',
      content: content,
      timestamp: new Date().toISOString()
    }
    this.addMessage(sessionId, userMessage)

    if (this.shouldUseOfficialCodexRemote(session, attachments)) {
      this.sendOfficialCodexRemoteMessage(sessionId, content, session)
      this.updateSessionStatus(sessionId, 'thinking')
      return true
    }

    // 发送到服务器
    wsService.sendUserMessage(sessionId, content, attachments)

    // 更新状态
    this.updateSessionStatus(sessionId, 'thinking')
    return true
  }

  private shouldUseOfficialCodexRemote(session: Session | undefined, attachments?: AttachmentRef[]): boolean {
    const aiTool = (session?.aiTool || '').toLowerCase()
    return aiTool.includes('codex') && (!attachments || attachments.length === 0)
  }

  private hasActiveOfficialCodexSend(sessionId: string): boolean {
    if (!this.officialCodexSendQueues.has(sessionId)) return false

    const startedAt = this.officialCodexSendStartedAt.get(sessionId) || 0
    if (startedAt > 0 && Date.now() - startedAt > SessionStore.OFFICIAL_CODEX_SEND_STALE_MS) {
      console.warn(`[SessionStore] Official Codex send lock stale, clearing: ${sessionId}`)
      this.clearOfficialCodexSendLock(sessionId)
      return false
    }

    return true
  }

  private clearOfficialCodexSendLock(sessionId: string): void {
    this.officialCodexSendQueues.delete(sessionId)
    this.officialCodexSendStartedAt.delete(sessionId)
    this.officialCodexSendBusyWarnedAt.delete(sessionId)
  }

  private timeoutAfter(ms: number, message: string): Promise<Record<string, Object>> {
    return new Promise<Record<string, Object>>((_resolve, reject) => {
      setTimeout(() => {
        reject(new Error(message))
      }, ms)
    })
  }

  private isOfficialCodexSession(sessionId: string): boolean {
    const session = this.sessions.find((s: Session) => s.id === sessionId)
    return !!session?.officialCodexThreadId || (session?.aiTool || '').toLowerCase().indexOf('codex') >= 0
  }

  private sendOfficialCodexRemoteMessage(sessionId: string, content: string, session: Session | undefined): void {
    this.officialCodexSendStartedAt.set(sessionId, Date.now())
    let observedThreadId = this.officialCodexThreadIds.get(sessionId) || session?.officialCodexThreadId || ''
    const next = Promise.resolve()
      .then(async () => {
        this.markOfficialCodexActivity(sessionId)
        const cwd = session?.workDir || session?.projectPath || ''
        const threadId = observedThreadId
        const transportMode = authStore.officialCodexSendMode || 'auto'
        if (transportMode === 'remote_control') {
          await this.ensureOfficialCodexControllerConnected()
        }
        const result = await Promise.race([
          apiService.sendCodexRemotePrompt(content, cwd, threadId, sessionId, '', '', '', transportMode),
          this.timeoutAfter(SessionStore.OFFICIAL_CODEX_SEND_TIMEOUT_MS, '发送超时，已自动重置发送状态。请确认 Codex Desktop 在线后重试。')
        ])
        const actualTransportMode = (result['actualTransportMode'] as string) || ''
        const requestedTransportMode = (result['requestedTransportMode'] as string) || transportMode
        const nextThreadId = (result['threadId'] as string) || ''
        const turnId = (result['turnId'] as string) || ''
        if (actualTransportMode !== 'script_fallback' && nextThreadId.length <= 0) {
          throw new Error('发送失败：没有拿到 Codex Desktop 会话 ID')
        }

        console.info(`[SessionStore] Official Codex send requested=${requestedTransportMode} actual=${actualTransportMode || 'unknown'} threadId=${nextThreadId || observedThreadId || 'pending'}`)
        if (actualTransportMode === 'script_fallback') {
          toastManager.info('Codex 已通过脚本发送')
        } else if (actualTransportMode === 'remote_control') {
          toastManager.info('Codex 已通过官方通道发送')
        }

        if (nextThreadId.length > 0) {
          observedThreadId = nextThreadId
          await this.saveOfficialCodexThreadId(sessionId, nextThreadId)
        }
        if (turnId.length > 0) {
          this.officialCodexActiveTurns.set(sessionId, turnId)
        }
        this.markOfficialCodexActivity(sessionId)
        if (observedThreadId.length > 0) {
          void this.pollOfficialCodexLocalThread(sessionId, observedThreadId, 0, 0, '')
        } else if (actualTransportMode === 'script_fallback') {
          this.updateSessionStatus(sessionId, this.getLocalOfficialCodexPollingStatus(sessionId))
        }
      })
      .catch((e: Error) => {
        this.officialCodexActiveTurns.delete(sessionId)
        this.warmOfficialCodexControllerIfNeeded(true)
        if (observedThreadId.length > 0 && this.isOfficialCodexTransientPollingError(e)) {
          this.markOfficialCodexActivity(sessionId)
          this.updateSessionStatus(sessionId, this.getLocalOfficialCodexPollingStatus(sessionId))
          void this.pollOfficialCodexLocalThread(
            sessionId,
            observedThreadId,
            0,
            0,
            this.buildMessagesSignatureForPolling(sessionId)
          )
          console.info(`[SessionStore] Official Codex send transient error; observing local thread ${observedThreadId}: ${e.message}`)
          return
        }
        const errMsg: Message = {
          id: 'official-codex-error-' + Date.now(),
          type: 'error',
          content: e.message || String(e),
          timestamp: new Date().toISOString()
        }
        this.addMessage(sessionId, errMsg)
        this.updateSessionStatus(sessionId, 'idle')
      })
      .then(() => {
        if (this.officialCodexSendQueues.get(sessionId) === next) {
          this.clearOfficialCodexSendLock(sessionId)
        }
      })

    this.officialCodexSendQueues.set(sessionId, next)
  }

  private pollOfficialCodexLocalThread(
    sessionId: string,
    threadId: string,
    attempt: number = 0,
    stableTicks: number = 0,
    lastSignature: string = ''
  ): Promise<void> {
    if (attempt === 0) {
      if (this.officialCodexLocalPollingSessions.has(sessionId)) {
        return Promise.resolve()
      }
      this.officialCodexLocalPollingSessions.add(sessionId)
    }

    if (attempt > 3600) {
      this.officialCodexActiveTurns.delete(sessionId)
      this.officialCodexLocalPollingSessions.delete(sessionId)
      this.updateSessionStatus(sessionId, 'idle')
      return Promise.resolve()
    }

    return new Promise((resolve) => {
      setTimeout(() => {
        // 关键修复：如果已经有 terminal cooldown 且没有活跃 turn，立即停止轮询
        // 防止已完成的会话被 polling 循环反复恢复为 thinking
        if (this.hasOfficialCodexTerminalCooldown(sessionId) && !this.hasOfficialCodexActiveTurn(sessionId)) {
          this.officialCodexLocalPollingSessions.delete(sessionId)
          this.updateSessionStatus(sessionId, 'completed')
          resolve()
          return
        }

        const beforeSignature = this.buildMessagesSignatureForPolling(sessionId)
        this.syncOfficialCodexThreadMessagesFromLocal(sessionId, threadId)
          .then((changed: boolean) => {
            const afterSignature = this.buildMessagesSignatureForPolling(sessionId)
            const hasChanged = changed || afterSignature !== beforeSignature || afterSignature !== lastSignature
            const nextStableTicks = hasChanged ? 0 : stableTicks + 1

            if (hasChanged) {
              this.markOfficialCodexActivity(sessionId)
              this.updateSessionStatus(sessionId, this.getLocalOfficialCodexPollingStatus(sessionId))
            } else if (nextStableTicks >= 45 &&
              this.isLocalOfficialCodexTurnLikelyComplete(sessionId) &&
              (!this.hasOfficialCodexActiveTurn(sessionId) ||
                (!this.isOfficialCodexThreadRuntimeActive(threadId) && nextStableTicks >= 120))) {
              this.officialCodexActiveTurns.delete(sessionId)
              this.officialCodexLocalPollingSessions.delete(sessionId)
              this.updateSessionStatus(sessionId, 'completed')
              resolve()
              return
            } else if (nextStableTicks >= 90 &&
              !this.hasOfficialCodexActiveTurn(sessionId) &&
              !this.hasRecentOfficialCodexActivity(sessionId, 120000) &&
              !this.isOfficialCodexThreadRuntimeActive(threadId)) {
              this.officialCodexLocalPollingSessions.delete(sessionId)
              this.updateSessionStatus(sessionId, 'idle')
              resolve()
              return
            } else {
              this.updateSessionStatus(sessionId, this.getLocalOfficialCodexPollingStatus(sessionId))
            }

            this.pollOfficialCodexLocalThread(
              sessionId,
              threadId,
              attempt + 1,
              nextStableTicks,
              afterSignature
            ).then(() => resolve())
          })
          .catch(() => {
            // 如果已经有 terminal cooldown，不再恢复 thinking
            if (this.hasOfficialCodexTerminalCooldown(sessionId) && !this.hasOfficialCodexActiveTurn(sessionId)) {
              this.officialCodexLocalPollingSessions.delete(sessionId)
              this.updateSessionStatus(sessionId, 'idle')
              resolve()
              return
            }
            this.updateSessionStatus(sessionId, this.getLocalOfficialCodexPollingStatus(sessionId))
            this.pollOfficialCodexLocalThread(
              sessionId,
              threadId,
              attempt + 1,
              stableTicks + 1,
              lastSignature
            ).then(() => resolve())
          })
      }, this.getOfficialCodexLocalPollDelayMs(attempt, stableTicks))
    })
  }

  private getOfficialCodexLocalPollDelayMs(attempt: number, stableTicks: number): number {
    if (attempt < 20) return 700
    if (stableTicks < 20) return 1200
    return 2500
  }

  private buildMessagesSignatureForPolling(sessionId: string): string {
    const messages = this.messages.get(sessionId) || []
    if (messages.length <= 0) return '0'
    const last = messages[messages.length - 1]
    return String(messages.length) + ':' + last.id + ':' + last.type + ':' +
      (last.content || '').length + ':' + (last.toolResult || '').length + ':' +
      (last.toolStatus || '')
  }

  private getLocalOfficialCodexPollingStatus(sessionId: string): SessionStatus {
    if (this.hasOfficialCodexStreamingPreview(sessionId)) {
      return 'streaming'
    }
    if (this.hasOfficialCodexThinkingPreview(sessionId)) {
      return 'thinking'
    }

    const messages = this.messages.get(sessionId) || []
    for (let i = messages.length - 1; i >= 0; i--) {
      const message = messages[i]
      if (message.type === 'tool_use' && message.toolStatus !== 'completed' && message.toolStatus !== 'failed') {
        return 'tool_executing'
      }
      if (message.type === 'assistant') return 'streaming'
      if (message.type === 'error') return 'idle'
      if (message.type === 'user') return 'thinking'
    }
    return 'thinking'
  }

  private isLocalOfficialCodexTurnLikelyComplete(sessionId: string): boolean {
    const messages = this.messages.get(sessionId) || []
    if (messages.length <= 0) return false
    const last = messages[messages.length - 1]
    if (last.type === 'assistant' || last.type === 'error') return true
    if (last.type === 'tool_use' && (last.toolStatus === 'completed' || last.toolStatus === 'failed')) return true
    return false
  }

  private getOfficialCodexPollDelayMs(attempt: number): number {
    if (attempt < 20) return 500
    if (attempt < 60) return 1000
    return 2000
  }

  private getNextOfficialCodexPollAttempt(attempt: number): number {
    if (attempt < 20) return attempt + 1
    return 20
  }

  private getNextOfficialCodexPollAttemptAfterSuccess(attempt: number, hasData: boolean): number {
    if (hasData) {
      return Math.min(attempt + 1, 20)
    }
    return attempt + 1
  }

  private isOfficialCodexTransientPollingError(error: Error): boolean {
    const message = (error.message || String(error)).toLowerCase()
    return message.indexOf('timeout') >= 0 ||
      message.indexOf('超时') >= 0 ||
      message.indexOf('network') >= 0 ||
      message.indexOf('网络') >= 0 ||
      message.indexOf('controller websocket closed') >= 0 ||
      message.indexOf('connection ended') >= 0 ||
      message.indexOf('temporarily') >= 0
  }

  private normalizeOfficialCodexTurnStatus(status: string): string {
    return (status || '').replace(/[-_]/g, '').toLowerCase()
  }

  private getOfficialCodexPollingStatus(turn: Record<string, Object> | null, status: string): SessionStatus {
    if (status !== 'inprogress' && status !== 'pending' && status !== 'running') return 'thinking'
    const items = turn && turn['items'] as Array<Record<string, Object>>
    if (items) {
      for (let i = 0; i < items.length; i++) {
        const type = ((items[i]['type'] as string) || '').toLowerCase()
        if (type.includes('tool') || type.includes('command') || type.includes('exec')) {
          return 'tool_executing'
        }
      }
    }
    return status === 'inprogress' || status === 'running' ? 'streaming' : 'thinking'
  }

  private handleOfficialCodexUpdate(sessionId: string, threadId: string, data: Record<string, Object>): void {
    const status = data['status'] as string
    const content = data['content'] as Record<string, Object>
    const turnId = data['turnId'] as string
    const role = data['role'] as string

    console.info(`[SessionStore] handleOfficialCodexUpdate: sessionId=${sessionId}, status=${status}, role=${role}, turnId=${turnId}`)

    if (status === 'completed' || status === 'idle') {
      // turn 完成：标记流式消息为非流式，更新状态，然后从 API 拉取完整消息
      this.flushStreamingBuffer(sessionId)
      this.flushHeadToTail(sessionId)
      this.updateSessionStatusFromState(sessionId, status)
      setTimeout(() => {
        void this.syncOfficialCodexThreadMessages(sessionId, threadId)
      }, 2000)
      return
    }

    // 非 completed 状态：不通过此路径创建 assistant 消息。
    // AI 回复文本统一由标准 WS 流式路径（content_start → content_delta → message_complete）处理，
    // 避免同一条回复被两条路径各创建一遍导致重复。
    // 仅在此更新工作状态，让 UI 显示"思考中"等
    if (status === 'active' || status === 'in_progress' || status === 'running') {
      if (this.hasOfficialCodexTerminalCooldown(sessionId) && !this.hasOfficialCodexActiveTurn(sessionId)) {
        console.info(`[SessionStore] Ignoring late active update for ${sessionId} after terminal status`)
        return
      }
      this.updateSessionStatus(sessionId, this.getLocalOfficialCodexPollingStatus(sessionId))
    }
  }

  private shouldUseLocalOfficialCodexReceive(sessionId: string, messageType: string): boolean {
    if (!this.isOfficialCodexSession(sessionId)) return false
    return messageType === 'content_start' ||
      messageType === 'content_delta' ||
      messageType === 'thinking' ||
      messageType === 'tool_use_complete' ||
      messageType === 'tool_result' ||
      messageType === 'message_complete' ||
      messageType === 'official_codex_update'
  }

  private handleOfficialCodexLocalDrivenMessage(sessionId: string, messageType: string): void {
    const threadId: string = this.getOfficialCodexThreadId(sessionId)
    if (threadId.length <= 0) return

    // 如果已经有 terminal cooldown 且没有活跃 turn，忽略迟到的消息
    if (this.hasOfficialCodexTerminalCooldown(sessionId) && !this.hasOfficialCodexActiveTurn(sessionId)) {
      console.info(`[SessionStore] Ignoring late local-driven message ${messageType} for ${sessionId} after terminal status`)
      return
    }

    this.markOfficialCodexActivity(sessionId)

    if (messageType === 'tool_use_complete' || messageType === 'tool_result') {
      this.updateSessionStatus(sessionId, 'tool_executing')
    } else if (messageType === 'message_complete') {
      this.streamHeads.delete(sessionId)
      this.officialCodexActiveTurns.delete(sessionId)
      this.officialCodexLocalPollingSessions.delete(sessionId)
      void this.syncOfficialCodexThreadMessagesFromLocal(sessionId, threadId).then(() => {
        this.updateSessionStatus(sessionId, 'completed')
      })
      return
    } else {
      this.updateSessionStatus(sessionId, this.getLocalOfficialCodexPollingStatus(sessionId))
    }

    void this.pollOfficialCodexLocalThread(
      sessionId,
      threadId,
      0,
      0,
      this.buildMessagesSignatureForPolling(sessionId)
    )
  }

  private upsertOfficialCodexAssistantMessage(
    sessionId: string,
    turnId: string,
    content: string,
    isError: boolean,
    isStreaming: boolean
  ): void {
    const id = 'official-codex-assistant-' + (turnId || 'latest')
    let sessionMessages = this.messages.get(sessionId) || []
    for (let i = sessionMessages.length - 1; i >= 0; i--) {
      if (sessionMessages[i].id === id) {
        if (sessionMessages[i].content !== content || sessionMessages[i].isStreaming !== isStreaming) {
          const old = sessionMessages[i]
          sessionMessages[i] = {
            id: old.id,
            type: isError ? 'error' : 'assistant',
            content,
            timestamp: old.timestamp,
            toolUseId: old.toolUseId,
            toolName: old.toolName,
            toolInput: old.toolInput,
            toolResult: old.toolResult,
            toolStatus: old.toolStatus,
            isStreaming,
            permissionId: old.permissionId,
            permissionDescription: old.permissionDescription,
            isPermissionHandled: old.isPermissionHandled,
            permissionResult: old.permissionResult,
            questionId: old.questionId,
            options: old.options,
            selectedAnswer: old.selectedAnswer,
            isQuestionAnswered: old.isQuestionAnswered,
            questions: old.questions,
            parentToolUseId: old.parentToolUseId,
            agentTaskStatus: old.agentTaskStatus,
            agentSummary: old.agentSummary,
            tasks: old.tasks,
            images: old.images,
            isError: isError || old.isError
          }
          sessionMessages = sessionMessages.slice()
          this.messages.set(sessionId, sessionMessages)
          this.persistMessages(sessionId, sessionMessages)
          this.notifyMessagesChanged(sessionId)
        }
        return
      }
    }

    const assistantMessage: Message = {
      id,
      type: isError ? 'error' : 'assistant',
      content,
      timestamp: new Date().toISOString(),
      isStreaming
    }
    this.addMessage(sessionId, assistantMessage)
  }

  private async saveOfficialCodexThreadId(sessionId: string, threadId: string): Promise<void> {
    this.officialCodexThreadIds.set(sessionId, threadId)
    const index = this.sessions.findIndex((s: Session) => s.id === sessionId)
    if (index >= 0 && this.sessions[index].officialCodexThreadId !== threadId) {
      const old = this.sessions[index]
      this.sessions[index] = {
        id: old.id,
        title: old.title,
        projectPath: old.projectPath,
        workDir: old.workDir,
        workDirExists: old.workDirExists,
        createdAt: old.createdAt,
        modifiedAt: old.modifiedAt,
        messageCount: old.messageCount,
        aiTool: old.aiTool || 'codex',
        officialCodexThreadId: threadId
      }
      await this.saveSessionsToStorage()
      this.notifySessionsChanged()
    }
    await this.saveOfficialCodexThreadIds()
  }

  private async saveOfficialCodexThreadIds(): Promise<void> {
    const raw: Record<string, string> = {}
    this.officialCodexThreadIds.forEach((value: string, key: string) => {
      raw[key] = value
    })
    await storageService.saveString('official_codex_thread_ids', JSON.stringify(raw))
  }

  private hydrateOfficialCodexThreadIds(): void {
    if (this.officialCodexThreadIds.size === 0) return
    for (let i = 0; i < this.sessions.length; i++) {
      const session = this.sessions[i]
      if (!session.officialCodexThreadId) {
        const threadId = this.officialCodexThreadIds.get(session.id)
        if (threadId) {
          this.sessions[i] = {
            id: session.id,
            title: session.title,
            projectPath: session.projectPath,
            workDir: session.workDir,
            workDirExists: session.workDirExists,
            createdAt: session.createdAt,
            modifiedAt: session.modifiedAt,
            messageCount: session.messageCount,
            aiTool: session.aiTool || 'codex',
            officialCodexThreadId: threadId
          }
        }
      }
    }
  }


  /**
   * 打开 Official Codex 会话时，同步最新状态和消息
   * 解决：移动端打开对话时不知道桌面端工作到哪一步的问题
   */
  private async syncOfficialCodexSessionOnLoad(sessionId: string): Promise<void> {
    const session = this.sessions.find((s: Session) => s.id === sessionId)
    const threadId = session?.officialCodexThreadId || this.officialCodexThreadIds.get(sessionId)
    if (!threadId) return

    console.info(`[SessionStore] syncOfficialCodexSessionOnLoad: syncing thread ${threadId} for ${sessionId}`)

    try {
      const changed = await this.syncOfficialCodexThreadMessagesFromLocal(sessionId, threadId)
      const runtimeActive = this.isOfficialCodexThreadRuntimeActive(threadId)
      // 修复：只有真正有活跃 turn 时才恢复 thinking，hasRecentOfficialCodexActivity 不再单独恢复
      if (this.hasOfficialCodexActiveTurn(sessionId) || runtimeActive) {
        this.updateSessionStatus(sessionId, this.getLocalOfficialCodexPollingStatus(sessionId))
        void this.pollOfficialCodexLocalThread(sessionId, threadId, 0, changed ? 0 : 1, this.buildMessagesSignatureForPolling(sessionId))
        return
      }
      this.updateSessionStatus(sessionId, changed ? 'completed' : 'idle')
    } catch (e) {
      console.error(`[SessionStore] syncOfficialCodexSessionOnLoad error: ${e}`)
      const supplemented = await this.supplementOfficialCodexMessagesFromLocal(sessionId, threadId, false)
      const runtimeActive = this.isOfficialCodexThreadRuntimeActive(threadId)
      this.updateSessionStatus(sessionId, runtimeActive ? 'thinking' : (supplemented ? 'completed' : 'idle'))
    }
  }
  private async syncOfficialCodexThreadMessages(sessionId: string, threadId: string): Promise<void> {
    try {
      const loadedFromLocal = await this.syncOfficialCodexThreadMessagesFromLocal(sessionId, threadId)
      if (!loadedFromLocal && (this.messages.get(sessionId) || []).length <= 0) {
        console.info(`[SessionStore] Local Codex thread has no messages yet: ${threadId}`)
      }
    } catch (e) {
      console.error(`[SessionStore] Sync Official Codex thread messages error: ${e}`)
    }
  }

  private async syncOfficialCodexThreadMessagesFromLocal(sessionId: string, threadId: string): Promise<boolean> {
    try {
      const beforeSignature = this.buildMessagesSignatureForPolling(sessionId)
      const response = await apiService.getLocalCodexThreadMessages(threadId, 400)
      const data = (response['messages'] as Array<Record<string, Object>>) || []
      const importedMessages = this.buildOfficialCodexMessagesFromLocal(data)
      if (importedMessages.length === 0) return false

      const mergedMessages = this.mergeOfficialCodexThreadMessages(this.messages.get(sessionId) || [], importedMessages)
      this.messages.set(sessionId, mergedMessages)
      await this.persistMessages(sessionId, mergedMessages)
      const latestTimestamp = this.getLatestMessageTimestamp(mergedMessages, new Date().toISOString())
      this.updateSessionActivity(sessionId, latestTimestamp, mergedMessages.length, true)
      this.notifyMessagesChanged(sessionId)
      console.info(`[SessionStore] Loaded ${importedMessages.length} local Codex messages for ${threadId}`)
      return this.buildMessagesSignatureForPolling(sessionId) !== beforeSignature
    } catch (e) {
      console.error(`[SessionStore] Sync local Official Codex thread messages error: ${e}`)
      return false
    }
  }

  private async supplementOfficialCodexMessagesFromLocal(
    sessionId: string,
    threadId: string,
    onlyWhenAssistantMissing: boolean
  ): Promise<boolean> {
    const currentMessages = this.messages.get(sessionId) || []
    if (onlyWhenAssistantMissing && this.hasAssistantMessage(currentMessages)) {
      return false
    }

    const beforeCount = currentMessages.length
    await this.syncOfficialCodexThreadMessagesFromLocal(sessionId, threadId)
    const nextMessages = this.messages.get(sessionId) || []
    if (onlyWhenAssistantMissing) {
      return this.hasAssistantMessage(nextMessages)
    }
    return nextMessages.length > beforeCount
  }

  private mergeOfficialCodexThreadMessages(current: Message[], imported: Message[]): Message[] {
    // 清理：imported 中包含某个 turn 的正式 assistant 消息时，
    // 从 current 中删除对应的流式临时消息（stream- 前缀），
    // 防止标准 WS 流式路径创建的临时消息和 API 正式消息同时存在导致重复。

    // 收集 imported 中所有 assistant 消息的归一化内容
    const importedAssistantContents: string[] = []
    for (let i = 0; i < imported.length; i++) {
      if (imported[i].type === 'assistant' && imported[i].content) {
        importedAssistantContents.push(this.normalizeMessageText(imported[i].content))
      }
    }

    let cleanedCurrent = current
    if (importedAssistantContents.length > 0) {
      cleanedCurrent = []
      let removedCount = 0
      for (let i = 0; i < current.length; i++) {
        const msg = current[i]
        // 清理实时流式 assistant：如果内容与 imported 中的正式 assistant 高度匹配，
        // 删除非官方消息，避免聊天中同时出现“流式临时气泡 + 正式历史气泡”。
        if (msg.type === 'assistant' && !this.isOfficialCodexMessageId(msg.id) && msg.content) {
          const normContent = this.normalizeMessageText(msg.content)
          let matched = false
          for (let j = 0; j < importedAssistantContents.length; j++) {
            const importedNorm = importedAssistantContents[j]
            if (normContent === importedNorm ||
                this.isLikelyTransientOfficialCodexDuplicate(normContent, importedNorm)) {
              matched = true
              break
            }
          }
          if (matched) {
            removedCount++
            console.info(`[SessionStore] mergeCodex: removed streaming msg id=${msg.id}, matched imported content`)
            continue
          }
        }
        cleanedCurrent.push(msg)
      }
      if (removedCount > 0) {
        console.info(`[SessionStore] mergeCodex: removed ${removedCount} streaming messages`)
      }
    }

    const merged = cleanedCurrent.slice()
    for (let i = 0; i < imported.length; i++) {
      const next = imported[i]
      let index = -1
      for (let j = 0; j < merged.length; j++) {
        if (this.shouldMergeOfficialCodexMessage(merged[j], next)) {
          index = j
          break
        }
      }

      if (index >= 0) {
        merged[index] = this.mergeOfficialCodexMessage(merged[index], next)
      } else {
        merged.push(next)
      }
    }

    merged.sort((a, b) => this.compareMessagesForDisplay(a, b))
    return this.deduplicateMessages(merged)
  }

  private buildOfficialCodexMessagesFromLocal(data: Array<Record<string, Object>> | undefined): Message[] {
    if (!data || data.length === 0) return []

    const messages: Message[] = []
    for (let i = 0; i < data.length; i++) {
      const item = data[i]
      const id = ((item['id'] as string) || `local-codex-${i}`).trim()
      const type = ((item['type'] as string) || '').trim()
      const timestamp = ((item['timestamp'] as string) || new Date().toISOString()).trim()
      const content = ((item['content'] as string) || '').trim()

      if (type === 'user' || type === 'assistant' || type === 'thinking' || type === 'error') {
        if (content.length === 0 && type !== 'thinking') continue
        messages.push({
          id,
          type: type as 'user' | 'assistant' | 'thinking' | 'error',
          content,
          timestamp,
          isError: item['isError'] === true
        })
        continue
      }

      if (type === 'tool_use') {
        messages.push({
          id,
          type: 'tool_use',
          content,
          timestamp,
          toolName: ((item['toolName'] as string) || 'unknown').trim(),
          toolUseId: ((item['toolUseId'] as string) || id).trim(),
          toolInput: (item['toolInput'] as Record<string, Object>) || {},
          toolStatus: ((item['toolStatus'] as string) || 'completed') as 'pending' | 'running' | 'completed' | 'failed'
        })
        continue
      }

      if (type === 'tool_result') {
        messages.push({
          id,
          type: 'tool_result',
          content,
          timestamp,
          toolUseId: ((item['toolUseId'] as string) || '').trim(),
          toolResult: ((item['toolResult'] as string) || content).trim(),
          toolStatus: ((item['toolStatus'] as string) || 'completed') as 'pending' | 'running' | 'completed' | 'failed',
          isError: item['isError'] === true
        })
      }
    }

    return messages
  }

  private shouldMergeOfficialCodexMessage(left: Message, right: Message): boolean {
    if (left.id === right.id) return true

    // 本地刚发送的 user 气泡与官方 thread 回传的 userMessage 合并，避免自己消息重复。
    if (left.type === 'user' && right.type === 'user' &&
      left.id.startsWith('user-') &&
      this.isOfficialCodexMessageId(right.id) &&
      this.normalizeMessageText(left.content) === this.normalizeMessageText(right.content) &&
      this.isMessageTimeClose(left.timestamp, right.timestamp, 10 * 60 * 1000)) {
      return true
    }

    return this.isSameOfficialCodexTurnMessage(left, right)
  }

  private isSameOfficialCodexTurnMessage(left: Message, right: Message): boolean {
    if (left.type !== right.type) return false
    if (left.type !== 'assistant' && left.type !== 'error') return false
    const leftTurn = this.extractOfficialCodexTurnIdFromMessage(left.id)
    const rightTurn = this.extractOfficialCodexTurnIdFromMessage(right.id)
    if (leftTurn.length <= 0 || leftTurn !== rightTurn) return false

    // 只允许“流式临时气泡”（没有 item index）和最终 item 合并。
    // 两个最终 agentMessage item 即使同属一个 turn，也应该是两个阶段性 AI 气泡。
    const leftItemIndex = this.extractOfficialCodexItemIndexFromMessage(left.id)
    const rightItemIndex = this.extractOfficialCodexItemIndexFromMessage(right.id)
    return leftItemIndex < 0 || rightItemIndex < 0
  }

  private compareMessagesForDisplay(a: Message, b: Message): number {
    // Official Codex 消息：同 turn 内按 item index 排序
    const aIsCodex = this.isOfficialCodexMessageId(a.id)
    const bIsCodex = this.isOfficialCodexMessageId(b.id)
    if (aIsCodex && bIsCodex) {
      const aTurn = this.extractOfficialCodexTurnIdFromMessage(a.id)
      const bTurn = this.extractOfficialCodexTurnIdFromMessage(b.id)
      if (aTurn.length > 0 && aTurn === bTurn) {
        const aIdx = this.extractOfficialCodexItemIndexFromMessage(a.id)
        const bIdx = this.extractOfficialCodexItemIndexFromMessage(b.id)
        if (aIdx >= 0 && bIdx >= 0) return aIdx - bIdx
        if (aIdx >= 0) return -1
        if (bIdx >= 0) return 1
        return this.getMessageRoleRank(a) - this.getMessageRoleRank(b)
      }
    }
    const timeDiff = new Date(a.timestamp).getTime() - new Date(b.timestamp).getTime()
    if (timeDiff !== 0) return timeDiff
    return this.getMessageRoleRank(a) - this.getMessageRoleRank(b)
  }

  private extractOfficialCodexTurnIdFromMessage(id: string): string {
    const prefix = this.getOfficialCodexMessagePrefix(id)
    if (prefix.length <= 0) return ''
    const rest = id.substring(prefix.length)
    const lastDash = rest.lastIndexOf('-')
    if (lastDash <= 0) return rest

    const suffix = rest.substring(lastDash + 1)
    if (this.isNumericString(suffix)) {
      return rest.substring(0, lastDash)
    }
    return rest
  }

  private extractOfficialCodexItemIndexFromMessage(id: string): number {
    const prefix = this.getOfficialCodexMessagePrefix(id)
    if (prefix.length <= 0) return -1
    const rest = id.substring(prefix.length)
    const lastDash = rest.lastIndexOf('-')
    if (lastDash <= 0) return -1

    const suffix = rest.substring(lastDash + 1)
    if (!this.isNumericString(suffix)) return -1
    const parsed = Number(suffix)
    return Number.isNaN(parsed) ? -1 : parsed
  }

  private getOfficialCodexMessagePrefix(id: string): string {
    const prefixes = [
      'official-codex-user-',
      'official-codex-assistant-',
      'official-codex-thinking-',
      'official-codex-tool-result-',
      'official-codex-tool-',
      'official-codex-error-'
    ]
    for (let i = 0; i < prefixes.length; i++) {
      const prefix = prefixes[i]
      if (id.startsWith(prefix)) {
        return prefix
      }
    }
    return ''
  }

  private isOfficialCodexMessageId(id: string): boolean {
    return this.getOfficialCodexMessagePrefix(id).length > 0
  }

  private isNumericString(value: string): boolean {
    if (value.length <= 0) return false
    for (let i = 0; i < value.length; i++) {
      const code = value.charCodeAt(i)
      if (code < 48 || code > 57) return false
    }
    return true
  }

  private isMessageTimeClose(left: string, right: string, windowMs: number): boolean {
    const leftTime = new Date(left).getTime()
    const rightTime = new Date(right).getTime()
    if (Number.isNaN(leftTime) || Number.isNaN(rightTime)) return false
    return Math.abs(leftTime - rightTime) <= windowMs
  }

  private getMessageRoleRank(message: Message): number {
    if (message.type === 'user') return 10
    if (message.type === 'thinking') return 20
    if (message.type === 'tool_use') return 30
    if (message.type === 'tool_result') return 40
    if (message.type === 'assistant') return 50
    if (message.type === 'error') return 60
    return 70
  }

  private mergeOfficialCodexMessage(old: Message, next: Message): Message {
    return {
      id: this.getOfficialCodexMergedMessageId(old, next),
      type: next.type || old.type,
      content: next.content || old.content,
      timestamp: this.getOfficialCodexMergedTimestamp(old, next),
      toolUseId: next.toolUseId || old.toolUseId,
      toolName: next.toolName || old.toolName,
      toolInput: next.toolInput || old.toolInput,
      toolResult: next.toolResult || old.toolResult,
      toolStatus: next.toolStatus || old.toolStatus,
      isStreaming: next.isStreaming,
      permissionId: old.permissionId,
      permissionDescription: old.permissionDescription,
      isPermissionHandled: old.isPermissionHandled,
      permissionResult: old.permissionResult,
      questionId: old.questionId,
      options: old.options,
      selectedAnswer: old.selectedAnswer,
      isQuestionAnswered: old.isQuestionAnswered,
      questions: old.questions,
      parentToolUseId: next.parentToolUseId || old.parentToolUseId,
      agentTaskStatus: old.agentTaskStatus,
      agentSummary: old.agentSummary,
      tasks: next.tasks || old.tasks,
      images: next.images || old.images,
      isError: next.isError,
    }
  }

  private getOfficialCodexMergedMessageId(old: Message, next: Message): string {
    const oldItemIndex = this.extractOfficialCodexItemIndexFromMessage(old.id)
    const nextItemIndex = this.extractOfficialCodexItemIndexFromMessage(next.id)
    if (oldItemIndex < 0 && nextItemIndex >= 0) return next.id
    return old.id
  }

  private getOfficialCodexMergedTimestamp(old: Message, next: Message): string {
    if (old.type === 'user' &&
      old.id.startsWith('user-') &&
      this.isOfficialCodexMessageId(next.id)) {
      return next.timestamp || old.timestamp
    }
    return old.timestamp
  }

  private buildOfficialCodexMessagesFromTurns(data: Array<Record<string, Object>> | undefined): Message[] {
    if (!data || data.length === 0) return []

    const messages: Message[] = []
    for (let i = 0; i < data.length; i++) {
      const turn = data[i]
      const turnId = (turn['id'] as string) || i.toString()
      const items = turn['items'] as Array<Record<string, Object>>
      if (!items || items.length === 0) continue
      const turnBaseTime = this.getOfficialCodexTurnBaseTime(turn, i)

      // 重排 items：确保后续 assistant（总结）排在工具后面
      const reorderedItems = this.reorderCodexTurnItems(items)

      for (let j = 0; j < reorderedItems.length; j++) {
        const item = reorderedItems[j]
        // j 用于时间戳（决定顺序），originalIdx 用于 ID（保持稳定）
        const originalIdx = items.indexOf(item) >= 0 ? items.indexOf(item) : j
        const type = this.normalizeOfficialCodexItemType((item['type'] as string) || '')
        const timestamp = this.getOfficialCodexMessageTimestamp(turnBaseTime, j, type)
        if (type === 'userMessage') {
          const text = this.extractOfficialCodexUserText(item)
          if (text.length > 0) {
            messages.push({
              id: 'official-codex-user-' + turnId + '-' + originalIdx,
              type: 'user',
              content: text,
              timestamp
            })
          }
        } else if (type === 'agentMessage' || type === 'assistantMessage') {
          const text = this.extractOfficialCodexItemText(item)
          if (text.length > 0) {
            messages.push({
              id: 'official-codex-assistant-' + turnId + '-' + originalIdx,
              type: 'assistant',
              content: text,
              timestamp
            })
          }
        } else if (type === 'thinking') {
          const thinking = this.extractOfficialCodexThinkingText(item)
          if (thinking.length > 0) {
            messages.push({
              id: 'official-codex-thinking-' + turnId + '-' + originalIdx,
              type: 'thinking',
              content: thinking,
              timestamp
            })
          }
        } else if (type === 'tool_use') {
          const toolUseId = ((item['id'] as string) ||
            (item['toolUseId'] as string) ||
            (item['tool_use_id'] as string) ||
            (item['call_id'] as string) ||
            '').trim()
          const toolInput = this.extractOfficialCodexToolInput(item)
          messages.push({
            id: 'official-codex-tool-' + turnId + '-' + originalIdx,
            type: 'tool_use',
            content: '',
            toolName: this.resolveOfficialCodexToolName(item, toolInput),
            toolUseId: toolUseId || 'official-codex-tool-' + turnId + '-' + originalIdx,
            toolInput,
            toolStatus: this.getOfficialCodexToolStatus(item),
            timestamp
          } as Message)
        } else if (type === 'tool_result') {
          const toolUseId = ((item['tool_use_id'] as string) ||
            (item['toolUseId'] as string) ||
            (item['call_id'] as string) ||
            (item['id'] as string) ||
            '').trim()
          const content = this.extractOfficialCodexItemText(item)
          const isError = item['is_error'] === true || item['isError'] === true
          messages.push({
            id: 'official-codex-tool-result-' + turnId + '-' + originalIdx,
            type: 'tool_result',
            content,
            toolUseId,
            toolResult: content,
            toolStatus: isError ? 'failed' : 'completed',
            isError,
            timestamp
          } as Message)
        } else if (type === 'file_change') {
          const changes = item['changes'] as Array<Record<string, Object>>
          if (changes && changes.length > 0) {
            for (let k = 0; k < changes.length; k++) {
              const change = changes[k]
              const path = ((change['path'] as string) || '文件变更').trim()
              const kind = change['kind'] as Record<string, Object>
              const kindType = kind ? ((kind['type'] as string) || '').trim() : ''
              const diff = ((change['diff'] as string) || '').trim()
              const toolInput: Record<string, Object> = {}
              toolInput['file_path'] = path
              if (kindType.length > 0) {
                toolInput['operation'] = kindType
              }
              messages.push({
                id: 'official-codex-tool-' + turnId + '-' + originalIdx + '-' + k,
                type: 'tool_use',
                content: '',
                toolName: 'Edit',
                toolUseId: 'official-codex-file-change-' + turnId + '-' + originalIdx + '-' + k,
                toolInput,
                toolResult: this.formatOfficialCodexFileChangeDiff(path, kindType, diff),
                toolStatus: this.getOfficialCodexToolStatus(item),
                timestamp: new Date(new Date(timestamp).getTime() + k).toISOString()
              } as Message)
            }
          } else {
            const toolInput: Record<string, Object> = {}
            toolInput['file_path'] = '文件变更'
            messages.push({
              id: 'official-codex-tool-' + turnId + '-' + originalIdx,
              type: 'tool_use',
              content: '',
              toolName: 'Edit',
              toolUseId: 'official-codex-file-change-' + turnId + '-' + originalIdx,
              toolInput,
              toolResult: '',
              toolStatus: this.getOfficialCodexToolStatus(item),
              timestamp
            } as Message)
          }
        } else if (type === 'mcp_tool_call') {
          const toolUseId = ((item['id'] as string) || 'official-codex-mcp-tool-' + turnId + '-' + originalIdx).trim()
          const args = this.extractOfficialCodexToolInput(item)
          const result = this.extractOfficialCodexMcpToolResult(item)
          messages.push({
            id: 'official-codex-tool-' + turnId + '-' + originalIdx,
            type: 'tool_use',
            content: '',
            toolName: this.resolveOfficialCodexToolName(item, args),
            toolUseId,
            toolInput: args,
            toolResult: result,
            toolStatus: this.getOfficialCodexToolStatus(item),
            isError: this.getOfficialCodexToolStatus(item) === 'failed',
            timestamp
          } as Message)
        } else if (type === 'error') {
          const message = ((item['message'] as string) || '').trim()
          if (message.length > 0) {
            messages.push({
              id: 'official-codex-error-' + turnId + '-' + originalIdx,
              type: 'error',
              content: message,
              timestamp
            })
          }
        }
      }
    }
    return messages
  }

  /**
   * 重排 Codex turn 的 items：确保后续 agentMessage（总结）排在工具之后
   */
  private reorderCodexTurnItems(items: Array<Record<string, Object>>): Array<Record<string, Object>> {
    if (!items || items.length <= 1) return items

    let firstToolIdx = -1
    let assistantCount = 0
    for (let i = 0; i < items.length; i++) {
      const type = this.normalizeOfficialCodexItemType((items[i]['type'] as string) || '')
      if (type === 'tool_use' || type === 'tool_result' || type === 'file_change' || type === 'mcp_tool_call') {
        if (firstToolIdx < 0) firstToolIdx = i
      }
      if (type === 'agentMessage' || type === 'assistantMessage') {
        assistantCount++
      }
    }

    if (firstToolIdx < 0 || assistantCount <= 1) return items

    // 第一个 assistant 保持原位（前言），其余移到末尾（总结）
    let seenAssistant = 0
    const deferred: Array<Record<string, Object>> = []
    const before: Array<Record<string, Object>> = []
    for (let i = 0; i < items.length; i++) {
      const type = this.normalizeOfficialCodexItemType((items[i]['type'] as string) || '')
      if (type === 'agentMessage' || type === 'assistantMessage') {
        seenAssistant++
        if (seenAssistant === 1) {
          before.push(items[i])
        } else {
          deferred.push(items[i])
        }
      } else {
        before.push(items[i])
      }
    }

    for (let i = 0; i < deferred.length; i++) {
      before.push(deferred[i])
    }

    console.info(`[SessionStore] reorderCodexTurnItems: moved ${deferred.length} assistant(s) to end`)
    return before
  }

  private hasOfficialCodexAssistantForTurn(messages: Message[], turnId: string): boolean {
    if (turnId.length <= 0) return false
    for (let i = 0; i < messages.length; i++) {
      const message = messages[i]
      if (message.type === 'assistant' &&
        this.extractOfficialCodexTurnIdFromMessage(message.id) === turnId) {
        return true
      }
    }
    return false
  }

  private hasAssistantMessage(messages: Message[]): boolean {
    for (let i = 0; i < messages.length; i++) {
      const type = messages[i].type
      if (type === 'assistant' || type === 'error') {
        return true
      }
    }
    return false
  }

  private getOfficialCodexTurnBaseTime(turn: Record<string, Object>, fallbackIndex: number): number {
    const candidates: string[] = ['createdAt', 'created_at', 'startedAt', 'started_at', 'updatedAt', 'updated_at']
    for (let i = 0; i < candidates.length; i++) {
      const raw = turn[candidates[i]]
      const parsed = this.parseOfficialCodexTime(raw)
      if (parsed > 0) return parsed
    }
    return Date.now() + fallbackIndex * 1000
  }

  private getOfficialCodexMessageTimestamp(turnBaseTime: number, itemIndex: number, itemType: string): string {
    return new Date(turnBaseTime + itemIndex * 10 + this.getOfficialCodexItemRoleOffset(itemType)).toISOString()
  }

  private getOfficialCodexItemRoleOffset(itemType: string): number {
    if (itemType === 'userMessage') return 1
    if (itemType === 'thinking') return 2
    if (itemType === 'tool_use') return 3
    if (itemType === 'tool_result') return 4
    if (itemType === 'agentMessage' || itemType === 'assistantMessage') return 8
    if (itemType === 'error') return 9
    return 5
  }

  private parseOfficialCodexTime(value: Object): number {
    if (value === undefined || value === null) return 0
    if (typeof value === 'number') {
      return value > 1000000000000 ? value : value * 1000
    }
    if (typeof value === 'string') {
      const numeric = Number(value)
      if (!Number.isNaN(numeric) && numeric > 0) {
        return numeric > 1000000000000 ? numeric : numeric * 1000
      }
      const parsed = Date.parse(value)
      return Number.isNaN(parsed) ? 0 : parsed
    }
    return 0
  }

  private normalizeOfficialCodexItemType(type: string): string {
    const normalized = type.replace(/[-_]/g, '').toLowerCase()
    if (normalized === 'agentmessage' || normalized === 'assistantmessage' || normalized === 'assistant') return 'assistantMessage'
    if (normalized === 'usermessage' || normalized === 'user') return 'userMessage'
    if (normalized === 'tooluse' || normalized === 'functioncall') return 'tool_use'
    if (normalized === 'toolresult' || normalized === 'functionresult') return 'tool_result'
    if (normalized === 'thinking' || normalized === 'reasoning') return 'thinking'
    if (normalized === 'localcommand' || normalized === 'commandexecution' || normalized === 'command') return 'tool_use'
    if (normalized === 'filechange' || normalized === 'filechanges' || normalized === 'fileedit') return 'file_change'
    if (normalized === 'mcptoolcall' || normalized === 'mcpcall') return 'mcp_tool_call'
    if (normalized === 'error') return 'error'
    return type
  }

  private normalizeOfficialCodexToolName(name: string): string {
    const normalized = name.trim()
    if (normalized.length === 0) return 'tool'
    const lower = normalized.toLowerCase()
    if (lower === 'shell' || lower === 'bash' || lower === 'command' || lower === 'localcommand' ||
      lower.includes('exec') || lower.includes('terminal') || lower.includes('shell')) return 'Bash'
    if (lower === 'edit' || lower === 'fileedit' || lower === 'applypatch' ||
      lower.includes('apply_patch') || lower.includes('patch') || lower.includes('edit')) return 'Edit'
    if (lower === 'write' || lower === 'filewrite' || lower.includes('write')) return 'Write'
    if (lower === 'read' || lower === 'fileread' || lower.includes('read')) return 'Read'
    if (lower === 'rg' || lower === 'grep' || lower === 'search' ||
      lower.includes('grep') || lower.includes('search')) return 'Grep'
    if (lower === 'glob' || lower === 'find' || lower.includes('glob') || lower.includes('find')) return 'Glob'
    return normalized
  }

  private resolveOfficialCodexToolName(item: Record<string, Object>, input: Record<string, Object>): string {
    const rawTool = item['tool']
    let rawToolName = ''
    if (typeof rawTool === 'string') {
      rawToolName = rawTool
    } else if (rawTool && typeof rawTool === 'object') {
      const toolRecord = rawTool as Record<string, Object>
      rawToolName = ((toolRecord['name'] as string) ||
        (toolRecord['tool'] as string) ||
        (toolRecord['type'] as string) ||
        '').trim()
    }

    const rawName = (rawToolName ||
      (item['name'] as string) ||
      (item['toolName'] as string) ||
      (item['tool_name'] as string) ||
      (item['kind'] as string) ||
      '').trim()
    const normalized = this.normalizeOfficialCodexToolName(rawName)
    if (normalized !== 'tool' && normalized !== 'Tool') return normalized

    if (this.hasStringInput(input, ['command', 'cmd', 'shellCommand'])) return 'Bash'
    if (this.hasStringInput(input, ['pattern', 'query', 'regex'])) return 'Grep'
    if (this.hasStringInput(input, ['glob'])) return 'Glob'
    if (this.hasStringInput(input, ['file_path', 'filePath', 'path', 'uri'])) return 'Read'
    return 'Tool'
  }

  private extractOfficialCodexToolInput(item: Record<string, Object>): Record<string, Object> {
    const input = (item['input'] as Record<string, Object>) ||
      (item['arguments'] as Record<string, Object>) ||
      (item['args'] as Record<string, Object>) ||
      (item['params'] as Record<string, Object>) ||
      {}
    const normalized: Record<string, Object> = {}
    const keys = Object.keys(input)
    for (let i = 0; i < keys.length; i++) {
      normalized[keys[i]] = input[keys[i]]
    }

    this.copyStringField(item, normalized, ['command', 'cmd', 'shellCommand'], 'command')
    this.copyStringField(item, normalized, ['path', 'filePath', 'file_path', 'uri'], 'file_path')
    this.copyStringField(item, normalized, ['pattern', 'query', 'regex'], 'pattern')
    this.copyStringField(item, normalized, ['glob'], 'glob')

    this.copyStringField(normalized, normalized, ['cmd', 'shellCommand'], 'command')
    this.copyStringField(normalized, normalized, ['path', 'filePath', 'uri'], 'file_path')
    this.copyStringField(normalized, normalized, ['query', 'regex'], 'pattern')
    return normalized
  }

  private copyStringField(source: Record<string, Object>, target: Record<string, Object>, keys: string[], targetKey: string): void {
    if (typeof target[targetKey] === 'string' && (target[targetKey] as string).length > 0) return
    for (let i = 0; i < keys.length; i++) {
      const value = source[keys[i]]
      if (typeof value === 'string' && value.trim().length > 0) {
        target[targetKey] = value.trim()
        return
      }
    }
  }

  private hasStringInput(input: Record<string, Object>, keys: string[]): boolean {
    for (let i = 0; i < keys.length; i++) {
      const value = input[keys[i]]
      if (typeof value === 'string' && value.trim().length > 0) return true
    }
    return false
  }

  private getOfficialCodexToolStatus(item: Record<string, Object>): 'pending' | 'running' | 'completed' | 'failed' {
    const raw = (((item['status'] as string) || (item['state'] as string) || '') as string)
      .replace(/[-_]/g, '')
      .toLowerCase()
    if (raw === 'failed' || raw === 'error' || raw === 'cancelled' || raw === 'canceled') return 'failed'
    if (raw === 'pending' || raw === 'queued') return 'pending'
    if (raw === 'running' || raw === 'inprogress' || raw === 'started') return 'running'
    return 'completed'
  }

  private extractOfficialCodexThinkingText(item: Record<string, Object>): string {
    const direct = this.extractOfficialCodexItemText(item) ||
      ((item['thinking'] as string) || '').trim()
    if (direct.length > 0) return direct

    const summary = item['summary']
    if (typeof summary === 'string') return summary.trim()
    if (Array.isArray(summary)) {
      const parts: string[] = []
      for (let i = 0; i < summary.length; i++) {
        const value = summary[i] as string
        if (typeof value === 'string' && value.trim().length > 0) {
          parts.push(value.trim())
        }
      }
      if (parts.length > 0) return parts.join('\n\n').trim()
    }

    return ''
  }

  private getOfficialCodexFileChangeSummary(item: Record<string, Object>): string {
    const changes = item['changes'] as Array<Record<string, Object>>
    if (!changes || changes.length === 0) return '文件变更'

    const firstPath = ((changes[0]['path'] as string) || '').trim()
    if (changes.length === 1) return firstPath || '文件变更'
    return (firstPath || '文件变更') + ' +' + (changes.length - 1)
  }

  private getOfficialCodexFileChangeDiff(item: Record<string, Object>): string {
    const changes = item['changes'] as Array<Record<string, Object>>
    if (!changes || changes.length === 0) return ''

    const parts: string[] = []
    for (let i = 0; i < changes.length; i++) {
      const change = changes[i]
      const path = ((change['path'] as string) || '文件').trim()
      const kind = change['kind'] as Record<string, Object>
      const kindType = kind ? ((kind['type'] as string) || '').trim() : ''
      const diff = ((change['diff'] as string) || '').trim()
      const header = kindType.length > 0 ? path + ' · ' + kindType : path
      parts.push('### ' + header + (diff.length > 0 ? '\n\n```diff\n' + diff + '\n```' : ''))
    }
    return parts.join('\n\n').trim()
  }

  private formatOfficialCodexFileChangeDiff(path: string, kindType: string, diff: string): string {
    const header = kindType.length > 0 ? path + ' · ' + kindType : path
    if (diff.length <= 0) return '### ' + header
    return '### ' + header + '\n\n```diff\n' + diff + '\n```'
  }

  private extractOfficialCodexMcpToolResult(item: Record<string, Object>): string {
    const error = item['error'] as Record<string, Object>
    if (error) {
      const message = ((error['message'] as string) || '').trim()
      if (message.length > 0) return message
    }

    const result = item['result']
    if (typeof result === 'string') return result.trim()
    if (result !== undefined && result !== null) {
      try {
        return JSON.stringify(result, null, 2)
      } catch (_) {
        return String(result)
      }
    }

    return ''
  }

  private extractOfficialCodexItemText(item: Record<string, Object>): string {
    const direct = ((item['text'] as string) ||
      (item['message'] as string) ||
      (item['output_text'] as string) ||
      (item['outputText'] as string) ||
      (item['output'] as string) ||
      (item['value'] as string) ||
      '').trim()
    if (direct.length > 0) return direct

    const content = item['content']
    if (typeof content === 'string') return content.trim()
    if (!Array.isArray(content)) return ''

    const parts: string[] = []
    for (let i = 0; i < content.length; i++) {
      const part = content[i] as Record<string, Object>
      const text = ((part['text'] as string) ||
        (part['content'] as string) ||
        (part['input_text'] as string) ||
        (part['output_text'] as string) ||
        (part['outputText'] as string) ||
        (part['output'] as string) ||
        (part['value'] as string) ||
        '').trim()
      if (text.length > 0) parts.push(text)
    }
    return parts.join('\n\n').trim()
  }

  private extractOfficialCodexUserText(item: Record<string, Object>): string {
    const content = item['content'] as Array<Record<string, Object>>
    if (!content || content.length === 0) {
      return ((item['text'] as string) || (item['message'] as string) || '').trim()
    }

    const parts: string[] = []
    for (let i = 0; i < content.length; i++) {
      const text = ((content[i]['text'] as string) || '').trim()
      if (text.length > 0) parts.push(text)
    }
    return parts.join('\n\n').trim()
  }

  private updateOfficialCodexImportedMessageCount(sessionId: string, count: number): void {
    this.updateSessionActivity(sessionId, undefined, count)
  }

  private findOfficialCodexTurn(data: Array<Record<string, Object>> | undefined, turnId: string): Record<string, Object> | null {
    if (!data || data.length === 0) return null
    for (let i = 0; i < data.length; i++) {
      const item = data[i]
      if (!turnId || item['id'] === turnId) return item
    }
    return data[data.length - 1]
  }

  private extractOfficialCodexAssistantText(turn: Record<string, Object> | null): string {
    if (!turn) return ''
    const items = turn['items'] as Array<Record<string, Object>>
    if (!items || items.length === 0) return ''

    let latest = ''
    for (let i = items.length - 1; i >= 0; i--) {
      const item = items[i]
      const type = this.normalizeOfficialCodexItemType((item['type'] as string) || '')

      if (type === 'agentMessage' || type === 'assistantMessage') {
        const text = this.extractOfficialCodexItemText(item)
        if (text.length > 0) return text
      } else if (type === 'error') {
        const message = (item['message'] as string) || ''
        if (message.length > 0) latest = message
      }
    }
    return latest.trim()
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
    console.info(`[SessionStore] sendAskUserQuestionResponse: currentSessionId=${this.currentSessionId}, requestId=${requestId}, answers=${JSON.stringify(answers)}`)
    if (!this.currentSessionId) {
      console.error('[SessionStore] sendAskUserQuestionResponse: no currentSessionId')
      return
    }
    wsService.sendAskUserQuestionResponse(this.currentSessionId, requestId, answers)
  }

  stopGeneration(): void {
    if (!this.currentSessionId) return

    const sessionId = this.currentSessionId
    const session = this.sessions.find((s: Session) => s.id === sessionId)
    const threadId = session?.officialCodexThreadId || this.officialCodexThreadIds.get(sessionId) || ''

    if (this.isOfficialCodexSession(sessionId)) {
      const transportMode = authStore.officialCodexSendMode || 'auto'
      this.updateSessionStatus(sessionId, 'idle')
      apiService.stopCodexRemotePrompt(threadId, sessionId, transportMode).then(() => {
        toastManager.info('已请求停止 Codex Desktop 当前任务')
      }).catch((e: Error) => {
        const errMsg: Message = {
          id: 'official-codex-stop-error-' + Date.now(),
          type: 'error',
          content: e.message || String(e),
          timestamp: new Date().toISOString()
        }
        this.addMessage(sessionId, errMsg)
        toastManager.error(e.message || '停止 Codex Desktop 任务失败')
      })
      return
    }

    wsService.sendStop(sessionId)
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


  /**
   * 启动时同步所有 Official Codex 会话的状态
   * 确保移动端能正确显示桌面端正在进行的工作
   */
  async syncAllOfficialCodexStatuses(): Promise<void> {
    console.info('[SessionStore] syncAllOfficialCodexStatuses: checking all Official Codex sessions')
    await this.syncOfficialCodexThreadsToLocal(Math.max(SessionStore.OFFICIAL_CODEX_LIST_LIMIT, 80))
    await this.syncTrackedOfficialCodexSessions()
  }

  private async syncTrackedOfficialCodexSessions(): Promise<void> {
    const now = Date.now()
    if (now - this.lastOfficialCodexRuntimeSnapshotAt > 60000) {
      await this.refreshOfficialCodexThreadRuntimeOnly(50)
    }

    const candidates: Session[] = []

    for (let i = 0; i < this.sessions.length; i++) {
      const session = this.sessions[i]
      const threadId = this.officialCodexThreadIds.get(session.id) || session.officialCodexThreadId || ''
      if (this.isSessionArchivedByIdentity(session.id, threadId)) continue
      if (threadId.length <= 0) continue

      const status = this.sessionStatuses.get(session.id) || 'idle'
      const isActiveStatus = status === 'thinking' || status === 'streaming' || status === 'tool_executing' ||
        status === 'permission_pending' || status === 'question_pending'
      const isCurrent = this.currentSessionId === session.id
      const isRuntimeActive = this.isOfficialCodexThreadRuntimeActive(threadId)
      const hasActiveTurn = this.hasOfficialCodexActiveTurn(session.id)
      const hasPendingWork = this.hasPendingOfficialCodexWork(session.id)
      const hasTerminalCooldown = this.hasOfficialCodexTerminalCooldown(session.id)

      if (hasTerminalCooldown && !isCurrent && !hasActiveTurn && !isRuntimeActive && !hasPendingWork) {
        continue
      }

      // 只有真正活跃的会话才进入候选列表：活跃 turn / 活跃状态 / 运行时活跃 / 当前会话
      // 移除 isRecentlyActive 条件，避免对已完成会话反复检查导致状态振荡
      if (isCurrent || isActiveStatus || isRuntimeActive || hasActiveTurn || hasPendingWork) {
        candidates.push(session)
      }
    }

    candidates.sort((a: Session, b: Session) => {
      return new Date(b.modifiedAt).getTime() - new Date(a.modifiedAt).getTime()
    })

    const maxSessions = 2
    for (let i = 0; i < candidates.length && i < maxSessions; i++) {
      const session = candidates[i]
      const threadId = this.officialCodexThreadIds.get(session.id) || session.officialCodexThreadId || ''
      if (threadId.length <= 0) continue
      console.info(`[SessionStore] syncTrackedOfficialCodexSessions: checking session ${session.id}, threadId=${threadId}`)
      await this.refreshOfficialCodexActiveSession(session.id, threadId)
    }
  }
  // MARK: - 状态管理

  /**
   * 同步会话状态：清除过期的"工作中"状态
   * 当对话列表出现时调用，修复状态停留在 working 但不继续的问题
   */
  syncSessionStatuses(): void {
    const now = Date.now()
    for (const session of this.sessions) {
      const archivedThreadId = this.officialCodexThreadIds.get(session.id) || session.officialCodexThreadId || ''
      if (this.isSessionArchivedByIdentity(session.id, archivedThreadId)) continue
      const status = this.sessionStatuses.get(session.id)
      if (!status || status === 'idle') continue

      // 如果 WS 没连接，working 状态肯定是过期的
      const wsConnected = wsService.isConnected(session.id)

      if (status === 'completed') {
        const isOfficialCodexSession = !!(session.officialCodexThreadId ||
          this.officialCodexThreadIds.get(session.id) ||
          ((session.aiTool || '').toLowerCase().indexOf('codex') >= 0))
        if (isOfficialCodexSession) {
          continue
        }
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
      if (session.officialCodexThreadId || (session.aiTool || '').toLowerCase().indexOf('codex') >= 0) {
        const threadId = this.officialCodexThreadIds.get(session.id) || session.officialCodexThreadId || ''
        if (threadId.length > 0) {
          // 修复：只有真正有活跃 turn 或 terminal cooldown 才跳过清理
          // hasRecentOfficialCodexActivity 不再单独作为跳过条件，避免已完成会话状态无法回落
          if (this.hasOfficialCodexActiveTurn(session.id) ||
            this.hasOfficialCodexTerminalCooldown(session.id) ||
            this.hasPendingOfficialCodexWork(session.id)) {
            continue
          }
          void this.refreshOfficialCodexActiveSession(session.id, threadId)
        }
        continue
      }
      if (!wsConnected) {
        console.info(`[SessionStore] Stale status for ${session.id}: ${status}, WS not connected, resetting to idle`)
        this.updateSessionStatus(session.id, 'idle')
      }
    }
  }

  private async refreshOfficialCodexActiveSession(sessionId: string, threadId: string): Promise<void> {
    if (this.syncingOfficialCodexLatest.has(sessionId)) return
    this.syncingOfficialCodexLatest.add(sessionId)
    try {
      const changed = await this.syncOfficialCodexThreadMessagesFromLocal(sessionId, threadId)
      const runtimeActive = this.isOfficialCodexThreadRuntimeActive(threadId)
      if (changed) {
        this.markOfficialCodexActivity(sessionId)
        this.updateSessionStatus(sessionId, this.getLocalOfficialCodexPollingStatus(sessionId))
      }

      // 关键修复：只有真正有活跃 turn 时才设为 thinking 并启动轮询
      // hasRecentOfficialCodexActivity 不再单独作为恢复 thinking 的条件，避免状态振荡
      const hasActiveTurn = this.hasOfficialCodexActiveTurn(sessionId)
      const hasPendingWork = this.hasPendingOfficialCodexWork(sessionId)
      if (hasActiveTurn || runtimeActive || hasPendingWork) {
        this.updateSessionStatus(sessionId, this.getLocalOfficialCodexPollingStatus(sessionId))
        void this.pollOfficialCodexLocalThread(sessionId, threadId, 0, changed ? 0 : 1, this.buildMessagesSignatureForPolling(sessionId))
      } else if (this.hasOfficialCodexTerminalCooldown(sessionId)) {
        this.updateSessionStatus(sessionId, changed ? 'completed' : 'idle')
      } else if (changed) {
        this.updateSessionStatus(sessionId, 'completed')
      } else {
        this.updateSessionStatus(sessionId, 'idle')
      }
    } catch (e) {
      console.info(`[SessionStore] refreshOfficialCodexActiveSession skipped: ${e}`)
      const supplemented = await this.supplementOfficialCodexMessagesFromLocal(sessionId, threadId, true)
      if (this.hasPendingOfficialCodexWork(sessionId)) {
        this.updateSessionStatus(sessionId, this.getLocalOfficialCodexPollingStatus(sessionId))
      } else if (this.hasOfficialCodexTerminalCooldown(sessionId) && !this.hasOfficialCodexActiveTurn(sessionId)) {
        this.updateSessionStatus(sessionId, supplemented ? 'completed' : 'idle')
      } else if (this.hasOfficialCodexActiveTurn(sessionId)) {
        this.updateSessionStatus(sessionId, this.getLocalOfficialCodexPollingStatus(sessionId))
      } else if (supplemented) {
        this.updateSessionStatus(sessionId, 'completed')
      } else {
        this.updateSessionStatus(sessionId, 'idle')
      }
    } finally {
      this.syncingOfficialCodexLatest.delete(sessionId)
    }
  }

  private getLatestOfficialCodexTurn(data: Array<Record<string, Object>> | undefined): Record<string, Object> | null {
    if (!data || data.length <= 0) return null
    let latest: Record<string, Object> | null = null
    let latestTime = -1
    for (let i = 0; i < data.length; i++) {
      const turn = data[i]
      const time = this.getOfficialCodexTurnBaseTime(turn, i)
      if (!latest || time > latestTime) {
        latest = turn
        latestTime = time
      }
    }
    return latest
  }

  // 更新会话状态
  updateSessionStatus(sessionId: string, status: SessionStatus): void {
    const session = this.sessions.find((s: Session) => s.id === sessionId)
    if (this.isSessionArchivedByIdentity(sessionId, session?.officialCodexThreadId || '')) {
      this.sessionStatuses.delete(sessionId)
      return
    }
    const previous = this.sessionStatuses.get(sessionId) || 'idle'
    if (previous === status) {
      return
    }

    const isOfficialCodexStatusSession = !!(session?.officialCodexThreadId ||
      this.officialCodexThreadIds.get(sessionId) ||
      ((session?.aiTool || '').toLowerCase().indexOf('codex') >= 0))

    if (isOfficialCodexStatusSession &&
      (status === 'completed' || status === 'idle') &&
      (previous === 'thinking' || previous === 'streaming' || previous === 'tool_executing') &&
      this.hasPendingOfficialCodexWork(sessionId) &&
      this.hasRecentOfficialCodexActivity(sessionId, 30000)) {
      console.info(`[SessionStore] Blocking premature terminal status: ${sessionId} ${previous}->${status}`)
      return
    }

    // 关键防振荡：如果之前是 completed/idle 且在 terminal cooldown 期间，
    // 不允许通过 polling 或本地推断把它改回活跃状态，除非有真正的活跃 turn
    const shouldBlockOscillation = isOfficialCodexStatusSession
    if (shouldBlockOscillation &&
      (previous === 'completed' || previous === 'idle') &&
      (status === 'thinking' || status === 'streaming' || status === 'tool_executing') &&
      this.hasOfficialCodexTerminalCooldown(sessionId, 120000) &&
      !this.hasOfficialCodexActiveTurn(sessionId) &&
      !this.hasPendingOfficialCodexWork(sessionId)) {
      console.info(`[SessionStore] Blocking status oscillation: ${sessionId} ${previous}->${status} blocked by terminal cooldown`)
      return
    }

    if (this.isWorkingSessionStatus(status) || this.isWaitingSessionStatus(status)) {
      this.officialCodexTerminalAt.delete(sessionId)
    } else if (status === 'completed' || status === 'idle') {
      this.officialCodexTerminalAt.set(sessionId, Date.now())
      this.officialCodexActiveTurns.delete(sessionId)
    }
    this.sessionStatuses.set(sessionId, status)
    this.notifyStatusChanged(sessionId, status)
    if (this.currentSessionId !== sessionId || status === 'idle' || status === 'completed' || previous === 'idle') {
      this.notifySessionsChanged()
    }

    // 只持久化保存稳定状态（idle 和 completed），临时状态不保存
    if (status === 'idle' || status === 'completed') {
      storageService.saveSessionStatuses(this.sessionStatuses)
    }

    // Claude / Codex / OpenCode 统一：completed 短暂停留后回到 idle，
    // 但 Codex 要额外确认没有活跃工作，避免结束态覆盖真实运行态。
    if (status === 'completed') {
      this.scheduleCompletedToIdle(sessionId, isOfficialCodexStatusSession)
    } else if (status === 'idle') {
      const oldTimer = this.completedTimers.get(sessionId)
      if (oldTimer !== undefined) {
        clearTimeout(oldTimer)
        this.completedTimers.delete(sessionId)
      }
    }

    console.info(`[SessionStore] Status updated: ${sessionId} -> ${status}`)
  }

  // 获取会话状态
  getSessionStatus(sessionId: string): SessionStatus {
    return this.sessionStatuses.get(sessionId) || 'idle'
  }

  // 获取所有活跃会话（状态为 thinking/streaming/tool_executing）
  getActiveSessions(): Session[] {
    const activeStatuses: SessionStatus[] = ['thinking', 'streaming', 'tool_executing']
    const result: Session[] = []
    for (let i = 0; i < this.sessions.length; i++) {
      const session = this.sessions[i]
      const status = this.sessionStatuses.get(session.id) || 'idle'
      if (activeStatuses.includes(status)) {
        result.push(session)
      }
    }
    return result
  }

  // 获取活跃会话数量
  getActiveSessionCount(): number {
    return this.getActiveSessions().length
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
    if (messageType === 'official_codex_update') {
      // Codex 消息用 threadId+turnId+status 去重（避免所有流式 delta 共用同一个 key）
      const codexData = (msg as Record<string, Object>)['data'] as Record<string, Object> | undefined
      dedupKey = sessionId + ':codex:' + ((msg as Record<string, Object>)['threadId'] || '') + ':' + (codexData?.['turnId'] || '') + ':' + (codexData?.['status'] || '')
    } else if (msg.id && !msg.id.startsWith('tool-')) {
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

    if (this.shouldUseLocalOfficialCodexReceive(sessionId, messageType)) {
      this.handleOfficialCodexLocalDrivenMessage(sessionId, messageType)
      return
    }

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

      case 'session_status_changed':
        if (msg.state) {
          this.updateSessionStatusFromState(sessionId, msg.state)
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
        // Official Codex 也走标准流式路径，不再 break
        // AI 回复统一通过 content_start → content_delta → message_complete 处理
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
        if (this.isOfficialCodexSession(sessionId) && messageType === 'thinking') {
          break
        }
        // 关闭逐字流式显示：只在内部缓冲区累积，不往 streamHeads 追加
        // 最终在 message_complete / flushHeadToTail 时一次性显示完整消息
        {
          const deltaText = typeof msg.text === 'string' ? msg.text as string : ''
          if (deltaText) {
            let buffer = this.streamingBuffers.get(sessionId)
            if (!buffer) {
              buffer = new StreamingBuffer()
            }

            if (messageType === 'content_delta') {
              buffer.assistant += deltaText
              buffer.blockType = 'text'
            } else { // thinking
              buffer.thinking += deltaText
              buffer.blockType = 'thinking'
            }

            this.streamingBuffers.set(sessionId, buffer)
            this.scheduleStreamingPreviewFlush(sessionId)
          }
        }
        break

      case 'tool_use_complete':
        // 非流式事件：先将缓冲区刷入，再将 Head 刷新到 Tail
        this.flushStreamingBuffer(sessionId)
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
        // 非流式事件：先将缓冲区刷入，再将 Head 刷新到 Tail
        this.flushStreamingBuffer(sessionId)
        this.flushHeadToTail(sessionId)
        if (msg.toolUseId && msg.content !== undefined && msg.content !== null) {
          this.updateToolResult(sessionId, msg.toolUseId, msg.content, msg.isError === true)
        }
        // 工具执行完成后重新提取任务列表，更新进度
        this.refreshTasksFromMessages(sessionId)
        break

      case 'message_complete':
        console.info(`[SessionStore] Message complete for ${sessionId}`)
        // 将流式缓冲区内容一次性刷入 messages（整条消息显示）
        this.flushStreamingBuffer(sessionId)
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
        // 非流式事件：先将缓冲区刷入，再将 Head 刷新到 Tail
        this.flushStreamingBuffer(sessionId)
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
        // 非流式事件：先将缓冲区刷入，再将 Head 刷新到 Tail
        this.flushStreamingBuffer(sessionId)
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
      case 'official_codex_update': {
        const codexData = (msg as Record<string, Object>)['data'] as Record<string, Object> | undefined
        const codexThreadId = (msg as Record<string, Object>)['threadId'] as string || ''
        if (codexThreadId && codexData) {
          this.handleOfficialCodexUpdate(sessionId, codexThreadId, codexData)
        }
        break
      }
    }
  }

  // MARK: - 全局 WebSocket 消息处理（桌面→移动端同步）

  private handleGlobalWSMessage(msg: WSMessage): void {
    console.info(`[SessionStore] Global WS msg: ${msg.type}`)

    switch (msg.type) {
      case 'codex_controller_status':
        // Codex Controller 连接状态变化（重连中/已连接）
        console.info(`[SessionStore] Codex controller status: ${msg.status}`)
        this.codexControllerStatus = msg.status || "unknown"
        this.codexControllerReconnectAttempt = msg.attempt || 0
        this.notifySessionsChanged()
        break

      case 'sessions_updated':
        this.fetchSessions().catch((e: Error) => {
          console.error(`[SessionStore] fetchSessions on global event error: ${e.message}`)
        })
        void this.syncOfficialCodexThreadsToLocal(Math.max(SessionStore.OFFICIAL_CODEX_LIST_LIMIT, 80)).catch((e: Error) => {
          console.error(`[SessionStore] syncOfficialCodexThreadsToLocal on global event error: ${e.message}`)
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
          let targetSessionId = msg.sessionId
          // 检查是否是 Official Codex 格式的 sessionId (official-codex-{threadId})
          if (msg.sessionId.startsWith('official-codex-')) {
            const threadId = msg.sessionId.replace('official-codex-', '')
            const mappedSessionId = this.findExistingSessionIdByOfficialCodexThreadId(threadId)
            if (mappedSessionId) {
              targetSessionId = mappedSessionId
              console.info(`[SessionStore] Mapped threadId ${threadId} to sessionId ${targetSessionId} for status update`)
            } else {
              void this.ensureOfficialCodexSessionForThreadId(threadId).then((createdSessionId: string | null) => {
                if (!createdSessionId) return
                console.info(`[SessionStore] Late-created session ${createdSessionId} for status update of thread ${threadId}`)
                this.updateSessionStatusFromState(createdSessionId, msg.state || 'idle')
              })
              break
            }
          }
          console.info(`[SessionStore] Session status changed: ${targetSessionId} -> ${msg.state}`)
          this.updateSessionStatusFromState(targetSessionId, msg.state)
        }
        break

      case 'session_broadcast':
        if (msg.sessionId && msg.message) {
          // 检查是否是 Official Codex 格式的 sessionId (official-codex-{threadId})
          let targetSessionId = msg.sessionId
          let isOfficialCodexBroadcast = false
          if (msg.sessionId.startsWith('official-codex-')) {
            isOfficialCodexBroadcast = true
            // 从 threadId 找到对应的真实 sessionId
            const threadId = msg.sessionId.replace('official-codex-', '')
            const mappedSessionId = this.findExistingSessionIdByOfficialCodexThreadId(threadId)
            if (mappedSessionId) {
              targetSessionId = mappedSessionId
              console.info(`[SessionStore] Mapped threadId ${threadId} to sessionId ${targetSessionId}`)
            } else {
              void this.ensureOfficialCodexSessionForThreadId(threadId).then((createdSessionId: string | null) => {
                if (!createdSessionId) return
                console.info(`[SessionStore] Late-created session ${createdSessionId} for broadcast of thread ${threadId}`)
                this.handleWSMessage(createdSessionId, msg.message as WSMessage)
              })
              break
            }
          }

          // 已有直连 WS 且真正在线时才跳过全局广播，防止 WS 断开后遗漏 message_complete 等关键消息
          if (!isOfficialCodexBroadcast && wsService.isSubscribed(targetSessionId) && wsService.isConnected(targetSessionId)) {
            console.info(`[SessionStore] Skip session_broadcast for ${targetSessionId}: already connected`)
            break
          }
          console.info(`[SessionStore] Session broadcast for ${targetSessionId} (direct WS not connected)`)
          this.handleWSMessage(targetSessionId, msg.message as WSMessage)
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
    const session = this.sessions.find((s: Session) => s.id === sessionId)
    const threadId = session?.officialCodexThreadId || this.officialCodexThreadIds.get(sessionId) || ''
    const shouldAllowWorkingRecovery =
      this.hasPendingOfficialCodexWork(sessionId) ||
      this.hasOfficialCodexActiveTurn(sessionId) ||
      (threadId.length > 0 && this.isOfficialCodexThreadRuntimeActive(threadId)) ||
      this.hasRecentOfficialCodexActivity(sessionId, 30000) ||
      this.hasOfficialCodexStreamingPreview(sessionId) ||
      this.hasOfficialCodexThinkingPreview(sessionId)

    if ((state === 'completed' || state === 'idle') &&
        (currentStatus === 'thinking' || currentStatus === 'streaming' || currentStatus === 'tool_executing') &&
        this.hasPendingOfficialCodexWork(sessionId) &&
        this.hasRecentOfficialCodexActivity(sessionId, 30000)) {
      console.info(`[SessionStore] Ignoring stale terminal state ${state} for ${sessionId}, current is ${currentStatus}`)
      return
    }

    // 如果当前是 completed 或 idle，且新状态是 working 状态，忽略
    // 这避免桌面端延迟的状态消息覆盖移动端的完成状态
    if ((currentStatus === 'completed' || currentStatus === 'idle') &&
        (state === 'thinking' || state === 'streaming' || state === 'tool_executing') &&
        !shouldAllowWorkingRecovery) {
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

  private isWorkingSessionStatus(status: SessionStatus): boolean {
    return status === 'thinking' || status === 'streaming' || status === 'tool_executing'
  }

  private isWaitingSessionStatus(status: SessionStatus): boolean {
    return status === 'permission_pending' || status === 'question_pending'
  }

  private scheduleCompletedToIdle(sessionId: string, isOfficialCodexStatusSession: boolean): void {
    const oldTimer = this.completedTimers.get(sessionId)
    if (oldTimer !== undefined) {
      clearTimeout(oldTimer)
      this.completedTimers.delete(sessionId)
    }

    const delayMs = isOfficialCodexStatusSession ? 2800 : 2000
    const timer = setTimeout(() => {
      this.completedTimers.delete(sessionId)
      if (this.sessionStatuses.get(sessionId) !== 'completed') {
        return
      }
      if (isOfficialCodexStatusSession &&
        (this.hasPendingOfficialCodexWork(sessionId) ||
          this.hasOfficialCodexActiveTurn(sessionId) ||
          this.hasOfficialCodexStreamingPreview(sessionId) ||
          this.hasOfficialCodexThinkingPreview(sessionId) ||
          this.hasRecentOfficialCodexActivity(sessionId, 12000))) {
        console.info(`[SessionStore] Skip completed->idle cooldown for active Codex session: ${sessionId}`)
        return
      }
      this.updateSessionStatus(sessionId, 'idle')
    }, delayMs)
    this.completedTimers.set(sessionId, timer)
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
        aiTool: old.aiTool,
        officialCodexThreadId: old.officialCodexThreadId
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
      this.updateSessionActivity(sessionId, new Date().toISOString(), messages.length)
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
    this.sessionsChangedPending = true
    if (this.sessionsChangedNotifyTimer >= 0) {
      return
    }

    this.sessionsChangedNotifyTimer = setTimeout(() => {
      this.sessionsChangedNotifyTimer = -1
      if (!this.sessionsChangedPending) {
        return
      }
      this.sessionsChangedPending = false
      for (const listener of this.sessionsChangedListeners) {
        listener()
      }
    }, 16)
  }

  private flushSessionsChanged(): void {
    if (this.sessionsChangedNotifyTimer >= 0) {
      clearTimeout(this.sessionsChangedNotifyTimer)
      this.sessionsChangedNotifyTimer = -1
    }
    if (!this.sessionsChangedPending) {
      return
    }
    this.sessionsChangedPending = false
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

    // officialCodexHeartbeatTimer 已合并到 staleStatusTimer，无需单独清理

    if (this.sessionsChangedNotifyTimer >= 0) {
      clearTimeout(this.sessionsChangedNotifyTimer)
      this.sessionsChangedNotifyTimer = -1
    }
    this.sessionsChangedPending = false

    // 清除本地存储
    await storageService.saveSessions([])
    await storageService.saveSessionStatuses(new Map())

    this.notifySessionsChanged()
    console.info('[SessionStore] All sessions cleared')
  }
}

export const sessionStore = SessionStore.getInstance()
