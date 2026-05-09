/**
 * WebSocket 服务
 * 负责与服务器的实时通信
 */

import webSocket from '@ohos.net.webSocket'
import { WSMessage, OutgoingMessage, QuestionItem, TaskStatus, WSMessageType } from '../models/Models'

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

  static getInstance(): WebSocketService {
    if (!WebSocketService.instance) {
      WebSocketService.instance = new WebSocketService()
    }
    return WebSocketService.instance
  }

  setMessageHandler(handler: WSMessageHandler): void {
    this.messageHandler = handler
  }

  setServerUrl(url: string): void {
    this.serverUrl = url
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

    // 清理不再需要的连接
    this.connections.forEach((_, existingId) => {
      let found = false
      for (let i = 0; i < sessionIds.length; i++) {
        if (sessionIds[i] === existingId) {
          found = true
          break
        }
      }
      if (!found) {
        this.disconnectSession(existingId)
      }
    })

    // 启动心跳和清理定时器
    this.startHeartbeat()
    this.startCleanup()
  }

  connectSession(sessionId: string): void {
    if (!this.serverUrl) {
      console.error('[WS] serverUrl is empty')
      return
    }

    // 检查是否已连接
    const existing = this.connections.get(sessionId)
    if (existing && existing.status === 'connected' && existing.ws) {
      console.info(`[WS] Already connected to ${sessionId}`)
      return
    }

    let wsUrl = this.serverUrl

    // 移除协议前缀
    if (wsUrl.startsWith('https://')) {
      wsUrl = wsUrl.substring(8)
    } else if (wsUrl.startsWith('http://')) {
      wsUrl = wsUrl.substring(7)
    }

    // 处理 host:port:token 格式
    const colonCount = this.countChar(wsUrl, ':')
    if (colonCount >= 2) {
      const parts = wsUrl.split(':')
      if (parts.length >= 2) {
        wsUrl = parts[0] + ':' + parts[1]
      }
    }

    // 判断使用 ws:// 还是 wss://
    const isSecure = this.serverUrl.startsWith('https://') ||
      wsUrl.includes('.tunnel.') ||
      wsUrl.includes('trycloudflare') ||
      wsUrl.includes('loca.lt')

    wsUrl = (isSecure ? 'wss://' : 'ws://') + wsUrl + '/ws/' + sessionId

    console.info(`[WS] Connecting to ${wsUrl}`)

    const ws = webSocket.createWebSocket()

    const conn = new WSSessionConnection()
    conn.ws = ws
    conn.status = 'connecting'
    conn.lastActivity = Date.now()
    conn.reconnectAttempts = 0

    this.connections.set(sessionId, conn)

    ws.connect(wsUrl, (err, value) => {
      if (err) {
        console.error(`[WS] Connect failed: ${err.message}`)
        this.handleDisconnect(sessionId)
        return
      }
      console.info(`[WS] Connected to ${sessionId}`)
      this.updateConnectionStatus(sessionId, 'connected')
      this.startReceiving(sessionId, ws)
    })

    ws.on('close', (err, value) => {
      console.info(`[WS] Connection closed: ${sessionId}`)
      this.handleDisconnect(sessionId)
    })

    ws.on('error', (err) => {
      console.error(`[WS] Error: ${err.message}`)
      this.updateConnectionStatus(sessionId, 'error')
      this.scheduleReconnect(sessionId)
    })
  }

  private countChar(str: string, char: string): number {
    let count = 0
    for (let i = 0; i < str.length; i++) {
      if (str[i] === char) {
        count++
      }
    }
    return count
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

  sendUserMessage(sessionId: string, content: string): boolean {
    const message: OutgoingMessage = {
      type: 'user_message',
      content: content
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
    const message: OutgoingMessage = {
      type: 'question_response',
      questionId: questionId,
      answer: answer
    }
    return this.send(sessionId, message)
  }

  sendStop(sessionId: string): boolean {
    const message: OutgoingMessage = { type: 'stop' }
    return this.send(sessionId, message)
  }

  // MARK: - 私有方法

  private startReceiving(sessionId: string, ws: webSocket.WebSocket): void {
    ws.on('message', (err, value) => {
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
    console.info(`[WS] Received for ${sessionId}: ${text.substring(0, 200)}`)

    try {
      const json = JSON.parse(text) as WSMessage
      json.sessionId = sessionId

      if (json.type === 'connected') {
        console.info(`[WS] WebSocket connected for ${sessionId}`)
        this.updateConnectionStatus(sessionId, 'connected')
        return
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

    if (conn.reconnectAttempts >= 5) {
      console.info(`[WS] Max reconnect attempts for ${sessionId}`)
      return
    }

    conn.reconnectAttempts++
    const delay = Math.min(1000 * Math.pow(2, conn.reconnectAttempts), 10000)

    console.info(`[WS] Reconnecting to ${sessionId} in ${delay}ms`)

    const timer = this.reconnectTimers.get(sessionId)
    if (timer) {
      clearTimeout(timer)
    }

    this.reconnectTimers.set(sessionId, setTimeout(() => {
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
          console.info(`[WS] Heartbeat: reconnecting broken connection for ${sessionId}`)
          this.connectSession(sessionId)
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
