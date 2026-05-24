/**
 * WebSocket 服务
 * 负责与服务器的实时通信
 * 集成 Paseo 连接可靠性模式：
 * - 连接状态机 (disconnected/connecting/connected/reconnecting/offline)
 * - 真实 Ping/Pong 心跳 + 超时检测
 * - 离线消息队列
 */

import webSocket from '@ohos.net.webSocket'
import { UrlUtils } from '../common/UrlUtils'
import { WSMessage, OutgoingMessage, QuestionItem, TaskStatus, WSMessageType, AttachmentRef } from '../models/Models'

// 连接状态枚举（对应 Paseo HostRuntime 状态机）
export enum ConnectionState {
  DISCONNECTED = 'disconnected',
  CONNECTING = 'connecting',
  CONNECTED = 'connected',
  RECONNECTING = 'reconnecting',
  OFFLINE = 'offline',
  ERROR = 'error'
}

// Pong 超时检测常量
const PING_INTERVAL_MS = 25000    // 每 25s 发一次 ping
const PONG_TIMEOUT_MS = 15000     // 发 ping 后 15s 无 pong 视为断连
const MAX_PONG_MISSED = 4         // 连续 4 次超时才触发重连（云中继容忍丢包 + 抖动）
const MAX_PENDING_MESSAGES = 100  // 离线消息队列最大长度
const MAX_SEND_RETRIES = 3        // 单条消息最大重试次数

export class WSSessionConnection {
  ws: webSocket.WebSocket | null = null
  status: string = 'disconnected'
  lastActivity: number = 0
  reconnectAttempts: number = 0
  // Paseo 集成：消息队列 + 心跳
  pendingMessages: string[] = []
  messageRetryCount: Map<string, number> = new Map()  // 消息重试次数追踪
  lastPongTime: number = 0
  missedPongs: number = 0
  // RTT 追踪
  pingTimestamp: number = 0
  rttSamples: number[] = []
  private static readonly MAX_RTT_SAMPLES = 10

  /** 记录一次 ping 发送时间戳 */
  markPingSent(): void {
    this.pingTimestamp = Date.now()
  }

  /** 记录 pong 并计算 RTT，返回本次 RTT (ms) */
  recordPong(): number {
    this.lastPongTime = Date.now()
    this.missedPongs = 0
    if (this.pingTimestamp > 0) {
      const rtt = Date.now() - this.pingTimestamp
      this.rttSamples.push(rtt)
      if (this.rttSamples.length > WSSessionConnection.MAX_RTT_SAMPLES) {
        this.rttSamples.shift()
      }
      this.pingTimestamp = 0
      return rtt
    }
    return 0
  }

  /** 获取平均 RTT (ms)，无样本返回 0 */
  getAverageRtt(): number {
    if (this.rttSamples.length === 0) return 0
    const sum = this.rttSamples.reduce((a, b) => a + b, 0)
    return sum / this.rttSamples.length
  }

  /** 获取连接质量等级 */
  getConnectionQuality(): 'good' | 'fair' | 'poor' | 'unknown' {
    const avg = this.getAverageRtt()
    if (avg <= 0) return 'unknown'
    if (avg < 150) return 'good'
    if (avg < 500) return 'fair'
    return 'poor'
  }
}

type WSMessageHandler = (sessionId: string, message: WSMessage) => void

export class WebSocketService {
  private static instance: WebSocketService
  private connections: Map<string, WSSessionConnection> = new Map()
  private serverUrl: string = ''
  private subscribedSessions: Set<string> = new Set()
  private messageHandler: WSMessageHandler | null = null
  private reconnectTimers: Map<string, number> = new Map()
  private pingTimer: number = -1       // 统一 ping 定时器（替代旧的 heartbeatTimer）
  private pongCheckTimer: number = -1  // pong 超时检测定时器
  private cleanupTimer: number = -1
  private globalConn: WSSessionConnection | null = null
  private globalMsgHandler: ((msg: WSMessage) => void) | null = null
  private globalReconnectTimer: number = -1
  private reconnectAllTimers: number[] = []
  // 连接状态变化回调（供 SessionStore/UI 层监听）
  private connectionStateListeners: Map<string, Array<(state: ConnectionState) => void>> = new Map()
  // 防抖：记录上次 forceReconnectAll 时间，避免短时间内多次重连
  private lastReconnectAllTime: number = 0
  private static readonly RECONNECT_ALL_DEBOUNCE_MS = 2000  // 2秒内不重复重连

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

  /** 检查连接是否健康（至少有一个会话 WS 在连接中，用于 onForeground 避免全量重连） */
  isHealthy(): boolean {
    // 检查会话级连接
    let anyConnected = false
    this.connections.forEach((conn) => {
      if (conn.status === 'connected') {
        anyConnected = true
      }
    })
    if (anyConnected) return true
    // 检查全局连接
    return this.globalConn !== null && this.globalConn.status === 'connected'
  }

  // MARK: - 连接状态监听

  /**
   * 注册连接状态变化监听（Paseo 模式：UI 层感知连接状态）
   */
  addConnectionStateListener(sessionId: string, listener: (state: ConnectionState) => void): void {
    let listeners = this.connectionStateListeners.get(sessionId)
    if (!listeners) {
      listeners = []
      this.connectionStateListeners.set(sessionId, listeners)
    }
    listeners.push(listener)
  }

  removeConnectionStateListener(sessionId: string, listener: (state: ConnectionState) => void): void {
    const listeners = this.connectionStateListeners.get(sessionId)
    if (!listeners) return
    const idx = listeners.indexOf(listener)
    if (idx >= 0) listeners.splice(idx, 1)
  }

  /**
   * 通知连接状态变化（内部方法）
   */
  private notifyConnectionState(sessionId: string, state: ConnectionState): void {
    const listeners = this.connectionStateListeners.get(sessionId)
    if (!listeners) return
    for (const l of listeners) {
      l(state)
    }
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

    // 启动 ping/pong 心跳和清理定时器
    this.startPingLoop()
    this.startPongCheck()
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
      return
    }

    // 检查是否已连接
    const existing = this.connections.get(sessionId)
    if (existing && existing.ws && (existing.status === 'connected' || existing.status === 'connecting')) {
      console.info(`[WS] Already ${existing.status} to ${sessionId}`)
      return
    }

    const wsUrl = this.buildWsUrl('/ws/' + sessionId)
    console.info(`[WS] Connecting to ${wsUrl}`)

    const ws = webSocket.createWebSocket()
    const conn = new WSSessionConnection()
    conn.ws = ws
    conn.status = 'connecting'
    conn.lastActivity = Date.now()
    conn.missedPongs = 0
    conn.lastPongTime = Date.now()

    // 继承旧连接的重试计数
    const oldConn = this.connections.get(sessionId)
    if (!oldConn) {
      conn.reconnectAttempts = 0
      // 继承离线消息队列（Paseo 模式）
      conn.pendingMessages = []
    } else {
      conn.reconnectAttempts = oldConn.reconnectAttempts
      conn.pendingMessages = oldConn.pendingMessages || []
    }

    this.connections.set(sessionId, conn)
    this.notifyConnectionState(sessionId, ConnectionState.CONNECTING)

    ws.connect(wsUrl, (err, value) => {
      const currentConn = this.connections.get(sessionId)
      if (!currentConn || currentConn.ws !== ws) {
        try {
          ws.close()
        } catch (e) {
          // ignore stale connection close errors
        }
        return
      }

      if (err) {
        console.error(`[WS] Connect failed: ${err.message}`)
        this.notifyConnectionState(sessionId, ConnectionState.ERROR)
        this.handleDisconnect(sessionId)
        return
      }
      console.info(`[WS] Connected to ${sessionId}`)
      this.updateConnectionStatus(sessionId, 'connected')
      conn.lastPongTime = Date.now()
      conn.missedPongs = 0
      this.notifyConnectionState(sessionId, ConnectionState.CONNECTED)

      // 连接成功后重置重试计数
      if (currentConn) {
        currentConn.reconnectAttempts = 0
      }

      // Paseo 模式：连接成功后 flush 离线消息队列
      this.flushPendingMessages(sessionId)

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
        this.notifyConnectionState(sessionId, ConnectionState.ERROR)
        this.scheduleReconnect(sessionId)
      }
    })
  }

  /**
   * 连接成功后 flush 所有 pending 消息（Paseo 模式）
   */
  private flushPendingMessages(sessionId: string): void {
    const conn = this.connections.get(sessionId)
    if (!conn || !conn.ws || conn.status !== 'connected') return

    while (conn.pendingMessages.length > 0) {
      const msg = conn.pendingMessages.shift()
      if (msg) {
        const msgHash = this.hashMessage(msg)
        const retries = conn.messageRetryCount.get(msgHash) || 0

        if (retries >= MAX_SEND_RETRIES) {
          console.warn(`[WS] Flush: skipping message exceeded max retries: ${msg.substring(0, 50)}`)
          conn.messageRetryCount.delete(msgHash)
          continue
        }

        try {
          conn.messageRetryCount.set(msgHash, retries + 1)
          conn.ws.send(msg, (err) => {
            if (err) {
              console.error(`[WS] Flush send error: ${err.message}`)
              // 发送失败重新入队（如果未超过重试上限）
              const currentRetries = conn.messageRetryCount.get(msgHash) || 0
              if (currentRetries < MAX_SEND_RETRIES) {
                conn.pendingMessages.unshift(msg)
              } else {
                console.error(`[WS] Flush: message exceeded max retries, dropping: ${msg.substring(0, 50)}`)
                conn.messageRetryCount.delete(msgHash)
              }
            } else {
              conn.messageRetryCount.delete(msgHash)
            }
          })
        } catch (e) {
          console.error(`[WS] Flush send exception: ${e}`)
          // 异常时不重新入队，避免无限循环
          conn.messageRetryCount.delete(msgHash)
          break
        }
      }
    }
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

  private globalConnecting: boolean = false

  connectGlobal(): void {
    if (!this.serverUrl) {
      console.error('[WS-Global] serverUrl is empty')
      return
    }

    if (this.globalConn && (this.globalConn.status === 'connected' || this.globalConn.status === 'connecting') && this.globalConn.ws) {
      console.info('[WS-Global] Already connected or connecting, skipping')
      return
    }

    if (this.globalConnecting) {
      console.info('[WS-Global] Connection already in progress, skipping')
      return
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
    this.globalConnecting = true

    ws.connect(wsUrl, (err, value) => {
      this.globalConnecting = false
      if (!this.globalConn || this.globalConn.ws !== ws) {
        try {
          ws.close()
        } catch (e) {
          // ignore stale connection close errors
        }
        return
      }

      if (err) {
        console.error(`[WS-Global] Connect failed: ${err.message}`)
        this.handleGlobalDisconnect()
        return
      }
      console.info('[WS-Global] Connected')
      if (this.globalConn) {
        this.globalConn.status = 'connected'
        this.globalConn.reconnectAttempts = 0
        this.globalConn.lastPongTime = Date.now()
      }
      this.startGlobalReceiving(ws)
    })

    ws.on('close', (err, value) => {
      console.info('[WS-Global] Connection closed')
      this.globalConnecting = false
      if (this.globalConn && this.globalConn.ws === ws) {
        this.handleGlobalDisconnect()
      }
    })

    ws.on('error', (err) => {
      console.error(`[WS-Global] Error: ${err.message}`)
      this.globalConnecting = false
      if (this.globalConn && this.globalConn.ws === ws) {
        this.globalConn.status = 'error'
        this.scheduleGlobalReconnect()
      }
    })
  }

  disconnectGlobal(): void {
    this.globalConnecting = false
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
      if (!this.globalConn || this.globalConn.ws !== ws) {
        return
      }

      if (err) {
        console.error(`[WS-Global] Receive error: ${err.message}`)
        return
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
    console.info(`[WS-Global] Received: ${text.substring(0, 1000)}`)

    try {
      const json = JSON.parse(text) as WSMessage

      // 检测 pong 响应（Paseo 模式）
      if (json.type === 'pong') {
        if (this.globalConn) {
          this.globalConn.recordPong()
        }
        return // pong 不往下分发
      }

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
    this.notifyConnectionState(sessionId, ConnectionState.DISCONNECTED)

    const timer = this.reconnectTimers.get(sessionId)
    if (timer !== undefined) {
      clearTimeout(timer)
      this.reconnectTimers.delete(sessionId)
    }
  }

  disconnectAll(): void {
    this.clearReconnectAllTimers()
    this.connections.forEach((_, sessionId) => {
      this.disconnectSession(sessionId)
    })
    this.disconnectGlobal()
    // 停止定时器
    this.stopPingLoop()
    this.stopPongCheck()
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
    const jsonStr = JSON.stringify(message)
    const msgHash = this.hashMessage(jsonStr)

    if (!conn || !conn.ws || conn.status !== 'connected') {
      console.info(`[WS] Cannot send: not connected to ${sessionId}, queuing message`)
      // Paseo 模式：离线时入队，重连后 flush
      if (conn) {
        // 限制队列大小，超过上限时丢弃最旧的消息
        if (conn.pendingMessages.length >= MAX_PENDING_MESSAGES) {
          const dropped = conn.pendingMessages.shift()
          console.warn(`[WS] Pending queue full, dropped oldest message: ${dropped?.substring(0, 50)}`)
        }
        conn.pendingMessages.push(jsonStr)
      }
      // 触发重连（如果正在重连则忽略）
      if (conn && conn.status !== 'reconnecting') {
        this.scheduleReconnect(sessionId)
      }
      return true // 返回 true 表示已入队
    }

    console.info(`[WS] Sending to ${sessionId}: ${jsonStr.substring(0, 100)}`)

    conn.ws.send(jsonStr, (err) => {
      if (err) {
        console.error(`[WS] Send error: ${err.message}`)
        // 发送失败入队备重试，但限制重试次数
        const retries = conn.messageRetryCount.get(msgHash) || 0
        if (retries < MAX_SEND_RETRIES) {
          conn.messageRetryCount.set(msgHash, retries + 1)
          conn.pendingMessages.push(jsonStr)
          console.warn(`[WS] Message queued for retry (${retries + 1}/${MAX_SEND_RETRIES})`)
        } else {
          console.error(`[WS] Message exceeded max retries, dropping: ${jsonStr.substring(0, 50)}`)
          conn.messageRetryCount.delete(msgHash)
        }
      } else {
        console.info(`[WS] Sent successfully to ${sessionId}`)
        conn.messageRetryCount.delete(msgHash)  // 成功后清理重试计数
      }
    })

    return true
  }

  /** 生成消息哈希用于重试计数 */
  private hashMessage(msg: string): string {
    // 简单哈希：取前100字符 + 长度
    return msg.substring(0, 100) + ':' + msg.length
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
    console.info(`[WS] sendAskUserQuestionResponse: sessionId=${sessionId}, requestId=${requestId}, answers=${JSON.stringify(answers)}`)

    // 格式化答案为字符串
    const answerText = Object.entries(answers)
      .map((entry) => `${entry[0]}: ${entry[1]}`)
      .join('\n')

    // 尝试多种格式以确保兼容性
    const message: OutgoingMessage = {
      type: 'permission_response',
      requestId: requestId,
      allowed: true,
      answers: answers,
      input: answers,
      response: answers,  // 备用字段名
      content: answerText
    }

    console.info(`[WS] Sending AskUserQuestion response: ${JSON.stringify(message)}`)
    const result = this.send(sessionId, message)
    console.info(`[WS] sendAskUserQuestionResponse result: ${result}`)
    return result
  }

  sendStop(sessionId: string): boolean {
    const message: OutgoingMessage = { type: 'stop_generation' }
    return this.send(sessionId, message)
  }

  // MARK: - 私有方法

  private startReceiving(sessionId: string, ws: webSocket.WebSocket): void {
    ws.on('message', (err, value) => {
      const currentConn = this.connections.get(sessionId)
      if (!currentConn || currentConn.ws !== ws) {
        return
      }

      if (err) {
        console.error(`[WS] Receive error: ${err.message}`)
        return
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
    console.info(`[WS] Received for ${sessionId}: ${text.substring(0, 1000)}`)

    try {
      const json = JSON.parse(text) as WSMessage
      json.sessionId = sessionId

      // Paseo 模式：检测 pong 响应，更新心跳状态
      if (json.type === 'pong') {
        const conn = this.connections.get(sessionId)
        if (conn) {
          conn.recordPong()
        }
        return // pong 不往下分发
      }

      if (json.type === 'connected') {
        console.info(`[WS] WebSocket connected for ${sessionId}`)
        this.updateConnectionStatus(sessionId, 'connected')
        // 连接确认后重置心跳
        const conn = this.connections.get(sessionId)
        if (conn) {
          conn.lastPongTime = Date.now()
          conn.missedPongs = 0
        }
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
    const oldStatus = this.connections.get(sessionId)?.status
    this.updateConnectionStatus(sessionId, 'disconnected')
    this.notifyConnectionState(sessionId, oldStatus === 'connecting' ? ConnectionState.OFFLINE : ConnectionState.RECONNECTING)

    // 重置 ws 引用（保留 pendingMessages）
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
    this.notifyConnectionState(sessionId, ConnectionState.RECONNECTING)
    // 无限重连，退避上限 30 秒，附加 ±20% 随机抖动防雷雨
    const baseDelay = Math.min(1000 * Math.pow(2, conn.reconnectAttempts), 30000)
    const jitter = baseDelay * (0.8 + Math.random() * 0.4) // 0.8x ~ 1.2x
    const delay = Math.round(jitter)

    console.info(`[WS] Reconnecting to ${sessionId} in ${delay}ms (attempt ${conn.reconnectAttempts})`)

    this.reconnectTimers.set(sessionId, setTimeout(() => {
      this.reconnectTimers.delete(sessionId)
      this.connectSession(sessionId)
    }, delay))
  }

  // MARK: - Ping/Pong 心跳（Paseo 模式）

  /**
   * 对所有已订阅会话发送 ping（替代旧的 timer-based health check）
   */
  private startPingLoop(): void {
    this.stopPingLoop()
    this.pingTimer = setInterval(() => {
      this.sendPingToAll()
    }, PING_INTERVAL_MS)
  }

  private stopPingLoop(): void {
    if (this.pingTimer >= 0) {
      clearInterval(this.pingTimer)
      this.pingTimer = -1
    }
  }

  /**
   * 检测 pong 超时：连续 MAX_PONG_MISSED 次未收到 pong 则强制重连
   */
  private startPongCheck(): void {
    this.stopPongCheck()
    this.pongCheckTimer = setInterval(() => {
      this.checkPongTimeouts()
    }, PONG_TIMEOUT_MS)
  }

  private stopPongCheck(): void {
    if (this.pongCheckTimer >= 0) {
      clearInterval(this.pongCheckTimer)
      this.pongCheckTimer = -1
    }
  }

  private sendPingToAll(): void {
    const now = Date.now()
    this.subscribedSessions.forEach((sessionId) => {
      const conn = this.connections.get(sessionId)
      if (!conn || !conn.ws || conn.status !== 'connected') return

      // 检查会话级 pong
      if (now - conn.lastPongTime > PONG_TIMEOUT_MS) {
        conn.missedPongs++
        if (conn.missedPongs >= MAX_PONG_MISSED) {
          console.warn(`[WS] Session ${sessionId} missed ${conn.missedPongs} pongs, force reconnecting`)
          this.forceReconnect(sessionId)
          return
        }
      }

      // 发送 ping 消息
      conn.markPingSent()
      try {
        conn.ws.send(JSON.stringify({ type: 'ping' }), (err) => {
          if (err) {
            console.error(`[WS] Ping send error: ${err.message}`)
          }
        })
      } catch (e) {
        // ignore
      }
    })

    // 全局 WS ping
    if (this.globalConn && this.globalConn.ws && this.globalConn.status === 'connected') {
      const gNow = Date.now()
      if (gNow - this.globalConn.lastPongTime > PONG_TIMEOUT_MS) {
        this.globalConn.missedPongs++
        if (this.globalConn.missedPongs >= MAX_PONG_MISSED) {
          console.warn('[WS] Global WS missed pongs, reconnecting')
          this.reconnectGlobal()
          return
        }
      }
      try {
        this.globalConn.ws.send(JSON.stringify({ type: 'ping' }), (err) => {
          if (err) {
            console.error(`[WS-Global] Ping send error: ${err.message}`)
          }
        })
      } catch (e) {
        // ignore
      }
    }
  }

  private checkPongTimeouts(): void {
    const now = Date.now()
    this.subscribedSessions.forEach((sessionId) => {
      const conn = this.connections.get(sessionId)
      if (!conn || conn.status !== 'connected') return
      if (now - conn.lastPongTime > PONG_TIMEOUT_MS * (MAX_PONG_MISSED + 1)) {
        console.warn(`[WS] Session ${sessionId} pong timeout, forcing reconnect`)
        this.forceReconnect(sessionId)
      }
    })
  }

  private forceReconnect(sessionId: string): void {
    const conn = this.connections.get(sessionId)
    if (conn && conn.ws) {
      try {
        conn.ws.close()
      } catch (e) {
        // ignore
      }
      conn.ws = null
      conn.status = 'disconnected'
    }
    this.notifyConnectionState(sessionId, ConnectionState.RECONNECTING)
    this.scheduleReconnect(sessionId)
  }

  // MARK: - 空闲连接清理

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
   * 添加防抖机制，避免短时间内多次重连导致卡顿
   */
  forceReconnectAll(): void {
    if (!this.serverUrl) {
      console.info('[WS] forceReconnectAll: no serverUrl, skipping')
      return
    }

    // 防抖：2秒内不重复重连
    const now = Date.now()
    if (now - this.lastReconnectAllTime < WebSocketService.RECONNECT_ALL_DEBOUNCE_MS) {
      console.info(`[WS] forceReconnectAll: debounced (last was ${now - this.lastReconnectAllTime}ms ago)`)
      return
    }
    this.lastReconnectAllTime = now

    console.info(`[WS] forceReconnectAll: ${this.subscribedSessions.size} sessions`)
    this.clearReconnectAllTimers()

    // 分批重连，避免同时创建大量连接导致卡顿
    const sessionIds: string[] = []
    this.subscribedSessions.forEach((id) => sessionIds.push(id))

    // 每批最多 3 个会话，间隔 100ms
    const BATCH_SIZE = 3
    const BATCH_DELAY = 100

    for (let i = 0; i < sessionIds.length; i += BATCH_SIZE) {
      const batch = sessionIds.slice(i, i + BATCH_SIZE)
      const timer = setTimeout(() => {
        this.removeReconnectAllTimer(timer)
        batch.forEach((sessionId) => {
          this.forceReconnectSession(sessionId)
        })
      }, (i / BATCH_SIZE) * BATCH_DELAY)
      this.reconnectAllTimers.push(timer)
    }

    // 延后重连全局 WS
    const globalTimer = setTimeout(() => {
      this.removeReconnectAllTimer(globalTimer)
      this.reconnectGlobal()
    }, sessionIds.length > BATCH_SIZE ? BATCH_DELAY * 2 : 50)
    this.reconnectAllTimers.push(globalTimer)

    // 重启 ping/pong
    this.startPingLoop()
    this.startPongCheck()
    this.startCleanup()
  }

  private clearReconnectAllTimers(): void {
    for (let i = 0; i < this.reconnectAllTimers.length; i++) {
      clearTimeout(this.reconnectAllTimers[i])
    }
    this.reconnectAllTimers = []
  }

  private removeReconnectAllTimer(timer: number): void {
    const index = this.reconnectAllTimers.indexOf(timer)
    if (index >= 0) {
      this.reconnectAllTimers.splice(index, 1)
    }
  }

  /**
   * 强制重连单个会话（Paseo 模式：保留 pendingMessages）
   */
  private forceReconnectSession(sessionId: string): void {
    // 先断开旧连接并移除引用，防止旧连接的 close/error 回调影响新连接
    const oldConn = this.connections.get(sessionId)
    if (oldConn && oldConn.ws) {
      oldConn.status = 'disconnecting'
      try {
        oldConn.ws.close()
      } catch (e) {
        // ignore close errors
      }
      oldConn.ws = null
    }
    // 保留 pendingMessages 但移除旧连接记录
    const pendingMsgs = oldConn ? oldConn.pendingMessages : []
    this.connections.delete(sessionId)

    // 清除重连定时器
    const timer = this.reconnectTimers.get(sessionId)
    if (timer !== undefined) {
      clearTimeout(timer)
      this.reconnectTimers.delete(sessionId)
    }

    // 建立新连接并继承消息队列
    this.connectSession(sessionId)
    const newConn = this.connections.get(sessionId)
    if (newConn && pendingMsgs.length > 0) {
      newConn.pendingMessages = pendingMsgs
    }
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

  /**
   * 获取连接状态枚举（Paseo 模式）
   */
  getConnectionState(sessionId: string): ConnectionState {
    const conn = this.connections.get(sessionId)
    if (!conn) return ConnectionState.DISCONNECTED
    const s = conn.status
    if (s === 'connected') return ConnectionState.CONNECTED
    if (s === 'connecting' || s === 'disconnecting') return ConnectionState.CONNECTING
    if (s === 'reconnecting') return ConnectionState.RECONNECTING
    if (s === 'error') return ConnectionState.ERROR
    return ConnectionState.DISCONNECTED
  }
}

export const wsService = WebSocketService.getInstance()
