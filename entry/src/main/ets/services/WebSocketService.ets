/**
 * WebSocket 服务
 * 负责与服务器的实时通信
 */

import webSocket from '@ohos.net.webSocket'
import { UrlUtils } from '../common/UrlUtils'
import { WSMessage, OutgoingMessage, QuestionItem, TaskStatus, WSMessageType, AttachmentRef } from '../models/Models'

export class WSSessionConnection {
  ws: webSocket.WebSocket | null = null
  status: string = 'disconnected'
  lastActivity: number = 0
  reconnectAttempts: number = 0
}

type WSMessageHandler = (sessionId: string, message: WSMessage) => void

export class WebSocketService {
  private static instance: WebSocketService
  private connections: Map<string, WSSessionConnection> = new Map()
  private serverUrl: string = ''
  private subscribedSessions: Set<string> = new Set()
  private messageHandler: WSMessageHandler | null = null
  private reconnectTimers: Map<string, number> = new Map()
  private heartbeatTimer: number = -1
  private cleanupTimer: number = -1
  private globalConn: WSSessionConnection | null = null
  private globalMsgHandler: ((msg: WSMessage) => void) | null = null
  private globalReconnectTimer: number = -1

  static getInstance(): WebSocketService {
    if (!WebSocketService.instance) {
      WebSocketService.instance = new WebSocketService()
    }
    return WebSocketService.instance
  }

  setMessageHandler(handler: WSMessageHandler): void {
    this.messageHandler = handler
  }

  setGlobalMessageHandler(handler: (msg: WSMessage) => void): void {
    this.globalMsgHandler = handler
  }

  setServerUrl(url: string): void {
    this.serverUrl = UrlUtils.normalizeUrl(url)
  }

  /** 检查是否已有直接 WebSocket 连接到指定会话（用于避免全局广播重复处理） */
  isSubscribed(sessionId: string): boolean {
    return this.subscribedSessions.has(sessionId)
  }

  // MARK: - 连接管理

  subscribeToSessions(sessionIds: string[]): void {
    console.info(`[WS] Subscribing to ${sessionIds.length} sessions`)

    // 使用传统 for 循环
    for (let i = 0; i < sessionIds.length; i++) {
      const sessionId = sessionIds[i]
      if (!this.subscribedSessions.has(sessionId)) {
        this.subscribedSessions.add(sessionId)
        this.connectSession(sessionId)
      }
    }

    // 清理不再需要的连接 - 先收集 key 再操作，避免遍历 Map 时修改
    const keysToRemove: string[] = []
    this.connections.forEach((_, existingId) => {
      let found = false
      for (let i = 0; i < sessionIds.length; i++) {
        if (sessionIds[i] === existingId) {
          found = true
          break
        }
      }
      if (!found) {
        keysToRemove.push(existingId)
      }
    })
    for (let i = 0; i < keysToRemove.length; i++) {
      this.disconnectSession(keysToRemove[i])
    }

    // 启动心跳和清理定时器
    this.startHeartbeat()
    this.startCleanup()
  }

  /**
   * 追加订阅单个会话，不清理已有连接（用于多会话同时工作）
   */
  addSubscription(sessionId: string): void {
    if (!this.subscribedSessions.has(sessionId)) {
      this.subscribedSessions.add(sessionId)
      this.connectSession(sessionId)
    }
  }

  connectSession(sessionId: string): void {
    if (!this.serverUrl) {
      console.error('[WS] serverUrl is empty')
      // removed
    }

    // 检查是否已连接
    const existing = this.connections.get(sessionId)
    if (existing && existing.status === 'connected' && existing.ws) {
      console.info(`[WS] Already connected to ${sessionId}`)
      // removed
    }

    const wsUrl = this.buildWsUrl('/ws/' + sessionId)

    console.info(`[WS] Connecting to ${wsUrl}`)

    const ws = webSocket.createWebSocket()

    const conn = new WSSessionConnection()
    conn.ws = ws
    conn.status = 'connecting'
    conn.lastActivity = Date.now()
    // 不在此处重置 reconnectAttempts，保持退避计数连续
    // 如果是新连接（之前不存在），则从0开始
    const oldConn = this.connections.get(sessionId)
    if (!oldConn) {
      conn.reconnectAttempts = 0
    } else {
      conn.reconnectAttempts = oldConn.reconnectAttempts
    }

    this.connections.set(sessionId, conn)

    ws.connect(wsUrl, (err, value) => {
      if (err) {
        console.error(`[WS] Connect failed: ${err.message}`)
        this.handleDisconnect(sessionId)
        // removed
      }
      console.info(`[WS] Connected to ${sessionId}`)
      this.updateConnectionStatus(sessionId, 'connected')
      // 连接成功后重置重试计数
      const currentConn = this.connections.get(sessionId)
      if (currentConn) {
        currentConn.reconnectAttempts = 0
      }
      this.startReceiving(sessionId, ws)
    })

    ws.on('close', (err, value) => {
      console.info(`[WS] Connection closed: ${sessionId}`)
      // 只在当前连接未被替换时处理断开（防止旧连接回调影响新连接）
      const currentConn = this.connections.get(sessionId)
      if (currentConn && currentConn.ws === ws) {
        this.handleDisconnect(sessionId)
      }
    })

    ws.on('error', (err) => {
      console.error(`[WS] Error: ${err.message}`)
      // 只在当前连接未被替换时更新状态
      const currentConn = this.connections.get(sessionId)
      if (currentConn && currentConn.ws === ws) {
        this.updateConnectionStatus(sessionId, 'error')
        this.scheduleReconnect(sessionId)
      }
    })
  }

  private buildWsUrl(pathSuffix: string): string {
    if (!this.serverUrl) return ''

    // 使用已规范化的 serverUrl，去掉 http/https 前缀，替换为 ws/wss
    const isSecure = this.serverUrl.startsWith('https://')
    let hostPart = this.serverUrl
    if (hostPart.startsWith('https://')) {
      hostPart = hostPart.substring(8)
    } else if (hostPart.startsWith('http://')) {
      hostPart = hostPart.substring(7)
    }

    return (isSecure ? 'wss://' : 'ws://') + hostPart + pathSuffix
  }

  connectGlobal(): void {
    if (!this.serverUrl) {
      console.error('[WS-Global] serverUrl is empty')
      // removed
    }

    if (this.globalConn && this.globalConn.status === 'connected' && this.globalConn.ws) {
      console.info('[WS-Global] Already connected')
      // removed
    }

    const wsUrl = this.buildWsUrl('/ws/global')
    console.info(`[WS-Global] Connecting to ${wsUrl}`)

    const ws = webSocket.createWebSocket()
    const conn = new WSSessionConnection()
    conn.ws = ws
    conn.status = 'connecting'
    conn.lastActivity = Date.now()

    if (!this.globalConn) {
      conn.reconnectAttempts = 0
    } else {
      conn.reconnectAttempts = this.globalConn.reconnectAttempts
    }

    this.globalConn = conn

    ws.connect(wsUrl, (err, value) => {
      if (err) {
        console.error(`[WS-Global] Connect failed: ${err.message}`)
        this.handleGlobalDisconnect()
        // removed
      }
      console.info('[WS-Global] Connected')
      if (this.globalConn) {
        this.globalConn.status = 'connected'
        this.globalConn.reconnectAttempts = 0
      }
      this.startGlobalReceiving(ws)
    })

    ws.on('close', (err, value) => {
      console.info('[WS-Global] Connection closed')
      if (this.globalConn && this.globalConn.ws === ws) {
        this.handleGlobalDisconnect()
      }
    })

    ws.on('error', (err) => {
      console.error(`[WS-Global] Error: ${err.message}`)
      if (this.globalConn && this.globalConn.ws === ws) {
        this.globalConn.status = 'error'
        this.scheduleGlobalReconnect()
      }
    })
  }

  disconnectGlobal(): void {
    if (this.globalConn && this.globalConn.ws) {
      this.globalConn.ws.close((err) => {
        if (err) {
          console.error(`[WS-Global] Close error: ${err.message}`)
        }
      })
    }
    this.globalConn = null
    if (this.globalReconnectTimer >= 0) {
      clearTimeout(this.globalReconnectTimer)
      this.globalReconnectTimer = -1
    }
  }

  private reconnectGlobal(): void {
    // 先清理旧连接状态（同步）
    if (this.globalConn && this.globalConn.ws) {
      try {
        this.globalConn.ws.close()
      } catch (e) {
        // ignore close errors
      }
    }
    this.globalConn = null
    if (this.globalReconnectTimer >= 0) {
      clearTimeout(this.globalReconnectTimer)
      this.globalReconnectTimer = -1
    }
    // 延迟建立新连接，确保旧连接完全释放
    setTimeout(() => {
      this.connectGlobal()
    }, 150)
  }

  private startGlobalReceiving(ws: webSocket.WebSocket): void {
    ws.on('message', (err, value) => {
      if (err) {
        console.error(`[WS-Global] Receive error: ${err.message}`)
        // removed
      }

      let text = ''
      if (typeof value === 'string') {
        text = value
      } else if (typeof value === 'object' && value !== null) {
        text = String(value)
      }

      if (text) {
        this.handleGlobalMessage(text)
      }
    })
  }

  private handleGlobalMessage(text: string): void {
    console.info(`[WS-Global] Received: ${text.substring(0, 200)}`)

    try {
      const json = JSON.parse(text) as WSMessage

      if (this.globalMsgHandler) {
        this.globalMsgHandler(json)
      }

      // 解析成功后更新连接健康状态
      if (this.globalConn) {
        this.globalConn.lastActivity = Date.now()
        this.globalConn.reconnectAttempts = 0
      }
    } catch (e) {
      console.error(`[WS-Global] Parse error: ${e}`)
    }
  }

  private handleGlobalDisconnect(): void {
    if (this.globalConn) {
      this.globalConn.status = 'disconnected'
      this.globalConn.ws = null
    }
    this.scheduleGlobalReconnect()
  }

  private scheduleGlobalReconnect(): void {
    if (!this.globalConn) {
      return
    }

    this.globalConn.reconnectAttempts++
    // 无限重连，退避上限 30 秒
    const delay = Math.min(1000 * Math.pow(2, this.globalConn.reconnectAttempts), 30000)

    console.info(`[WS-Global] Reconnecting in ${delay}ms`)

    if (this.globalReconnectTimer >= 0) {
      clearTimeout(this.globalReconnectTimer)
    }

    this.globalReconnectTimer = setTimeout(() => {
      this.connectGlobal()
    }, delay)
  }

  disconnectSession(sessionId: string): void {
    const conn = this.connections.get(sessionId)
    if (conn && conn.ws) {
      conn.ws.close((err) => {
        if (err) {
          console.error(`[WS] Close error: ${err.message}`)
        }
      })
    }
    this.connections.delete(sessionId)
    this.subscribedSessions.delete(sessionId)

    const timer = this.reconnectTimers.get(sessionId)
    if (timer) {
      clearTimeout(timer)
      this.reconnectTimers.delete(sessionId)
    }
  }

  disconnectAll(): void {
    this.connections.forEach((_, sessionId) => {
      this.disconnectSession(sessionId)
    })
    this.disconnectGlobal()
    // 停止定时器
    if (this.heartbeatTimer >= 0) {
      clearInterval(this.heartbeatTimer)
      this.heartbeatTimer = -1
    }
    if (this.cleanupTimer >= 0) {
      clearInterval(this.cleanupTimer)
      this.cleanupTimer = -1
    }
  }

  // MARK: - 权限模式

  sendSetPermissionMode(sessionId: string, mode: string): boolean {
    const message: OutgoingMessage = {
      type: 'set_permission_mode',
      mode: mode
    }
    return this.send(sessionId, message)
  }

  // MARK: - 消息发送

  send(sessionId: string, message: OutgoingMessage): boolean {
    // 如果连接不存在，尝试建立连接
    if (!this.connections.has(sessionId)) {
      console.info(`[WS] No connection for ${sessionId}, attempting to connect...`)
      if (!this.subscribedSessions.has(sessionId)) {
        this.subscribedSessions.add(sessionId)
      }
      this.connectSession(sessionId)
    }

    const conn = this.connections.get(sessionId)
    if (!conn || !conn.ws || conn.status !== 'connected') {
      console.error(`[WS] Cannot send: not connected to ${sessionId}`)
      return false
    }

    const jsonStr = JSON.stringify(message)
    console.info(`[WS] Sending to ${sessionId}: ${jsonStr.substring(0, 100)}`)

    conn.ws.send(jsonStr, (err) => {
      if (err) {
        console.error(`[WS] Send error: ${err.message}`)
      } else {
        console.info(`[WS] Sent successfully to ${sessionId}`)
      }
    })

    return true
  }

  sendUserMessage(sessionId: string, content: string, attachments?: AttachmentRef[]): boolean {
    const message: OutgoingMessage = {
      type: 'user_message',
      content: content
    }
    if (attachments && attachments.length > 0) {
      message.attachments = attachments
    }
    return this.send(sessionId, message)
  }

  sendPermissionResponse(sessionId: string, requestId: string, allowed: boolean, always: boolean = false): boolean {
    const message: OutgoingMessage = {
      type: 'permission_response',
      requestId: requestId,
      allowed: allowed
    }
    if (always) {
      message.rule = 'always'
    }
    return this.send(sessionId, message)
  }

  sendQuestionResponse(sessionId: string, questionId: string, answer: string): boolean {
    // 服务端没有 question_response 类型，用 user_message 发送回答
    const message: OutgoingMessage = {
      type: 'user_message',
      content: answer
    }
    return this.send(sessionId, message)
  }

  sendAskUserQuestionResponse(sessionId: string, requestId: string, answers: Record<string, string>): boolean {
    const message: OutgoingMessage = {
      type: 'permission_response',
      requestId: requestId,
      allowed: true,
      answers: answers
    }
    return this.send(sessionId, message)
  }

  sendStop(sessionId: string): boolean {
    const message: OutgoingMessage = { type: 'stop_generation' }
    return this.send(sessionId, message)
  }

  // MARK: - 私有方法

  private startReceiving(sessionId: string, ws: webSocket.WebSocket): void {
    ws.on('message', (err, value) => {
      if (err) {
        console.error(`[WS] Receive error: ${err.message}`)
        // removed
      }

      let text = ''
      if (typeof value === 'string') {
        text = value
      } else if (typeof value === 'object' && value !== null) {
        text = String(value)
      }

      if (text) {
        this.handleMessage(sessionId, text)
      }
    })
  }

  private handleMessage(sessionId: string, text: string): void {
    console.info(`[WS] Received for ${sessionId}: ${text.substring(0, 200)}`)

    try {
      const json = JSON.parse(text) as WSMessage
      json.sessionId = sessionId

      if (json.type === 'connected') {
        console.info(`[WS] WebSocket connected for ${sessionId}`)
        this.updateConnectionStatus(sessionId, 'connected')
        // removed
      }

      if (this.messageHandler) {
        this.messageHandler(sessionId, json)
      }
    } catch (e) {
      // 主解析失败，尝试备用解析
      console.error(`[WS] Primary parse error, trying fallback: ${e}`)
      const fallbackMsg = this.parseFallbackMessage(text, sessionId)
      if (fallbackMsg && this.messageHandler) {
        console.info(`[WS] Fallback parse succeeded for ${sessionId}`)
        this.messageHandler(sessionId, fallbackMsg)
      } else {
        console.error(`[WS] Fallback parse also failed`)
      }
    }

    // 更新活动时间
    const conn = this.connections.get(sessionId)
    if (conn) {
      conn.lastActivity = Date.now()
      // 收到消息说明连接正常，重置重试计数
      conn.reconnectAttempts = 0
    }
  }

  private handleDisconnect(sessionId: string): void {
    this.updateConnectionStatus(sessionId, 'disconnected')

    // 重置 ws 引用
    const conn = this.connections.get(sessionId)
    if (conn) {
      conn.ws = null
    }

    this.scheduleReconnect(sessionId)
  }

  private updateConnectionStatus(sessionId: string, status: string): void {
    const conn = this.connections.get(sessionId)
    if (conn) {
      conn.status = status
    }
  }

  private scheduleReconnect(sessionId: string): void {
    if (!this.subscribedSessions.has(sessionId)) {
      return
    }

    const conn = this.connections.get(sessionId)
    if (!conn) {
      return
    }

    // 检查是否已有待处理的 recconnect 定时器，避免重复计数和多重重连
    const existingTimer = this.reconnectTimers.get(sessionId)
    if (existingTimer !== undefined) {
      console.info(`[WS] Reconnect already scheduled for ${sessionId}, skipping`)
      return
    }

    conn.reconnectAttempts++
    // 无限重连，退避上限 30 秒
    const delay = Math.min(1000 * Math.pow(2, conn.reconnectAttempts), 30000)

    console.info(`[WS] Reconnecting to ${sessionId} in ${delay}ms`)

    this.reconnectTimers.set(sessionId, setTimeout(() => {
      this.reconnectTimers.delete(sessionId)
      this.connectSession(sessionId)
    }, delay))
  }

  // MARK: - 心跳与清理

  private startHeartbeat(): void {
    if (this.heartbeatTimer >= 0) {
      clearInterval(this.heartbeatTimer)
    }
    this.heartbeatTimer = setInterval(() => {
      this.checkAndReconnectBrokenConnections()
    }, 30000) // 每 30 秒检查
  }

  private checkAndReconnectBrokenConnections(): void {
    if (!this.serverUrl) {
      return
    }

    this.subscribedSessions.forEach((sessionId) => {
      const conn = this.connections.get(sessionId)
      if (conn) {
        if (conn.status === 'disconnected' || conn.status === 'error' || !conn.ws) {
          // 无限重连，不做次数限制
          console.info(`[WS] Heartbeat: reconnecting broken connection for ${sessionId}`)
          this.scheduleReconnect(sessionId)
        }
      } else {
        console.info(`[WS] Heartbeat: creating missing connection for ${sessionId}`)
        this.connectSession(sessionId)
      }
    })
  }

  private startCleanup(): void {
    if (this.cleanupTimer >= 0) {
      clearInterval(this.cleanupTimer)
    }
    this.cleanupTimer = setInterval(() => {
      this.cleanupIdleConnections()
    }, 60000) // 每 60 秒清理
  }

  private cleanupIdleConnections(): void {
    const now = Date.now()
    this.connections.forEach((conn, sessionId) => {
      // 不在订阅列表中的连接，超过 5 分钟无活动则清理
      if (!this.subscribedSessions.has(sessionId)) {
        if (now - conn.lastActivity > 300000) {
          console.info(`[WS] Cleaning up idle connection: ${sessionId}`)
          this.disconnectSession(sessionId)
        }
      }
    })
  }

  // MARK: - 备用消息解析

  private parseFallbackMessage(text: string, sessionId: string): WSMessage | null {
    try {
      const json = JSON.parse(text) as Record<string, Object>

      const msg: WSMessage = {
        type: (json['type'] as WSMessageType) || undefined,
        sessionId: sessionId
      }

      // 提取常用字段
      msg.questionId = json['question_id'] as string || json['questionId'] as string
      msg.questionText = json['question_text'] as string || json['questionText'] as string
      msg.requestId = json['request_id'] as string || json['requestId'] as string
      msg.description = json['description'] as string
      msg.toolName = json['tool_name'] as string || json['toolName'] as string
      msg.text = json['text'] as string
      msg.blockType = json['block_type'] as string || json['blockType'] as string
      msg.toolUseId = json['tool_use_id'] as string || json['toolUseId'] as string
      msg.state = json['state'] as string
      msg.id = json['id'] as string
      msg.timestamp = json['timestamp'] as string
      msg.title = json['title'] as string
      msg.isError = json['is_error'] as boolean || json['isError'] as boolean
      msg.used = json['used'] as number
      msg.total = json['total'] as number
      msg.percentage = json['percentage'] as number

      // 处理 options
      if (Array.isArray(json['options'])) {
        const opts = json['options'] as Object[]
        msg.options = opts.map(o => String(o))
      }

      // 处理 questions 数组
      if (Array.isArray(json['questions'])) {
        const questionsArray = json['questions'] as Record<string, Object>[]
        msg.questions = []
        for (let i = 0; i < questionsArray.length; i++) {
          const dict = questionsArray[i]
          const item: QuestionItem = {
            question: dict['question'] as string,
            header: dict['header'] as string,
            multiSelect: dict['multi_select'] as boolean || dict['multiSelect'] as boolean
          }

          // 处理 options：支持字符串数组和对象数组
          if (Array.isArray(dict['options'])) {
            const opts = dict['options'] as (string | Record<string, Object>)[]
            item.options = []
            for (let j = 0; j < opts.length; j++) {
              if (typeof opts[j] === 'string') {
                item.options.push({ label: opts[j] as string })
              } else {
                const optDict = opts[j] as Record<string, Object>
                item.options.push({
                  label: optDict['label'] as string,
                  description: optDict['description'] as string
                })
              }
            }
          }
          msg.questions!.push(item)
        }
        // 有 questions 但没有 type，自动标记
        if (!msg.type) {
          msg.type = 'questions'
        }
      }

      // 处理 tasks 数组
      if (Array.isArray(json['tasks'])) {
        const tasksArray = json['tasks'] as Record<string, Object>[]
        msg.tasks = []
        for (let i = 0; i < tasksArray.length; i++) {
          const t = tasksArray[i]
          const taskStatus = String(t['status'] || '')
          let status: TaskStatus = 'pending'
          if (taskStatus === 'in_progress') {
            status = 'in_progress'
          } else if (taskStatus === 'completed') {
            status = 'completed'
          } else if (taskStatus === 'failed') {
            status = 'failed'
          }
          msg.tasks.push({
            id: String(t['id'] || ''),
            content: String(t['content'] || ''),
            status: status,
            activeForm: t['activeForm'] as string || t['active_form'] as string,
            owner: t['owner'] as string
          })
        }
        // 有 tasks 但没有 type，自动标记
        if (!msg.type) {
          msg.type = 'task_list'
        }
      }

      return msg
    } catch (e) {
      console.error(`[WS] Fallback parse error: ${e}`)
      return null
    }
  }

  // MARK: - 主动重连

  /**
   * 强制重连所有已订阅的会话（用于 onForeground 恢复连接）
   */
  forceReconnectAll(): void {
    if (!this.serverUrl) {
      console.info('[WS] forceReconnectAll: no serverUrl, skipping')
      // removed
    }

    console.info(`[WS] forceReconnectAll: ${this.subscribedSessions.size} sessions`)

    this.subscribedSessions.forEach((sessionId) => {
      // 先断开旧连接并移除引用，防止旧连接的 close/error 回调影响新连接
      const oldConn = this.connections.get(sessionId)
      if (oldConn && oldConn.ws) {
        // 标记为 disconnecting 防止回调中处理
        oldConn.status = 'disconnecting'
        try {
          oldConn.ws.close()
        } catch (e) {
          // ignore close errors
        }
        oldConn.ws = null
      }
      // 移除旧连接记录
      this.connections.delete(sessionId)
      // 清除重连定时器
      const timer = this.reconnectTimers.get(sessionId)
      if (timer) {
        clearTimeout(timer)
        this.reconnectTimers.delete(sessionId)
      }

      // 建立新连接
      this.connectSession(sessionId)
    })

    // 重连全局 WS - 使用原子方法避免竞态
    this.reconnectGlobal()

    // 重启心跳
    this.startHeartbeat()
    this.startCleanup()
  }

  // MARK: - 状态查询

  isConnected(sessionId: string): boolean {
    const conn = this.connections.get(sessionId)
    return conn?.status === 'connected'
  }

  getConnectionStatus(sessionId: string): string {
    const conn = this.connections.get(sessionId)
    return conn?.status || 'disconnected'
  }
}

export const wsService = WebSocketService.getInstance()
