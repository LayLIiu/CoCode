/**
 * 连接恢复服务
 * 实现指数退避重连策略、离线消息队列持久化
 */

import { storageService } from './StorageService'
import { WSMessage, OutgoingMessage } from '../models/Models'

export interface QueuedMessage {
  id: string
  message: OutgoingMessage
  timestamp: number
  retryCount: number
  sessionId: string
}

export interface ConnectionStats {
  totalReconnects: number
  successfulReconnects: number
  averageReconnectTime: number
  lastConnectedTime: number
  totalDowntime: number
}

export class ConnectionRecoveryService {
  private static instance: ConnectionRecoveryService

  // 离线消息队列
  private offlineQueue: Map<string, QueuedMessage[]> = new Map()
  private maxQueueSize: number = 100

  // 重连策略
  private baseDelay: number = 1000      // 初始延迟 1s
  private maxDelay: number = 30000      // 最大延迟 30s
  private multiplier: number = 2        // 指数倍数
  private jitter: number = 0.3          // 抖动因子（防止惊群效应）
  private maxRetries: number = 10       // 最大重试次数

  // 连接统计
  private stats: ConnectionStats = {
    totalReconnects: 0,
    successfulReconnects: 0,
    averageReconnectTime: 0,
    lastConnectedTime: 0,
    totalDowntime: 0
  }

  // 重连定时器
  private reconnectTimers: Map<string, number> = new Map()
  private reconnectAttempts: Map<string, number> = new Map()

  static getInstance(): ConnectionRecoveryService {
    if (!ConnectionRecoveryService.instance) {
      ConnectionRecoveryService.instance = new ConnectionRecoveryService()
    }
    return ConnectionRecoveryService.instance
  }

  /**
   * 计算指数退避延迟
   */
  calculateBackoff(attempt: number): number {
    const delay = Math.min(
      this.baseDelay * Math.pow(this.multiplier, attempt),
      this.maxDelay
    )

    // 添加随机抖动（±30%）
    const jitterRange = delay * this.jitter
    const actualDelay = delay + (Math.random() * 2 - 1) * jitterRange

    return Math.floor(Math.max(0, actualDelay))
  }

  /**
   * 添加消息到离线队列
   */
  enqueueMessage(sessionId: string, message: OutgoingMessage): string {
    const queueItem: QueuedMessage = {
      id: `queue-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`,
      message,
      timestamp: Date.now(),
      retryCount: 0,
      sessionId
    }

    if (!this.offlineQueue.has(sessionId)) {
      this.offlineQueue.set(sessionId, [])
    }

    const queue = this.offlineQueue.get(sessionId)!
    
    // 队列满时移除最旧的消息
    if (queue.length >= this.maxQueueSize) {
      queue.shift()
      console.warn(`[ConnectionRecovery] Queue full for session ${sessionId}, dropped oldest message`)
    }

    queue.push(queueItem)
    this.persistQueue(sessionId)

    console.info(`[ConnectionRecovery] Message queued: ${queueItem.id}`)
    return queueItem.id
  }

  /**
   * 获取会话的离线消息队列
   */
  getQueuedMessages(sessionId: string): QueuedMessage[] {
    return this.offlineQueue.get(sessionId) || []
  }

  /**
   * 移除已成功发送的消息
   */
  acknowledgeMessage(sessionId: string, messageId: string): void {
    const queue = this.offlineQueue.get(sessionId)
    if (queue) {
      const index = queue.findIndex(m => m.id === messageId)
      if (index >= 0) {
        queue.splice(index, 1)
        this.persistQueue(sessionId)
        console.info(`[ConnectionRecovery] Message acknowledged: ${messageId}`)
      }
    }
  }

  /**
   * 重试失败的消息
   */
  retryFailedMessages(sessionId: string, sendFunc: (msg: OutgoingMessage) => Promise<boolean>): void {
    const queue = this.offlineQueue.get(sessionId)
    if (!queue || queue.length === 0) return

    console.info(`[ConnectionRecovery] Retrying ${queue.length} queued messages for session ${sessionId}`)

    // 按时间戳排序
    queue.sort((a, b) => a.timestamp - b.timestamp)

    // 重试发送
    queue.forEach(item => {
      item.retryCount++
      sendFunc(item.message)
        .then(success => {
          if (success) {
            this.acknowledgeMessage(sessionId, item.id)
          } else if (item.retryCount >= this.maxRetries) {
            console.error(`[ConnectionRecovery] Max retries reached for message ${item.id}`)
            this.acknowledgeMessage(sessionId, item.id) // 移除失败消息
          }
        })
        .catch(err => {
          console.error(`[ConnectionRecovery] Retry failed for message ${item.id}:`, err)
        })
    })
  }

  /**
   * 持久化队列到本地存储
   */
  private async persistQueue(sessionId: string): Promise<void> {
    try {
      const queue = this.offlineQueue.get(sessionId)
      if (queue && queue.length > 0) {
        const key = `offline_queue_${sessionId}`
        await storageService.saveString(key, JSON.stringify(queue))
      }
    } catch (error) {
      console.error('[ConnectionRecovery] Failed to persist queue:', error)
    }
  }

  /**
   * 从本地存储恢复队列
   */
  async restoreQueue(sessionId: string): Promise<void> {
    try {
      const key = `offline_queue_${sessionId}`
      const data = await storageService.loadString(key)
      
      if (data) {
        const queue: QueuedMessage[] = JSON.parse(data)
        this.offlineQueue.set(sessionId, queue)
        console.info(`[ConnectionRecovery] Restored ${queue.length} queued messages for session ${sessionId}`)
      }
    } catch (error) {
      console.error('[ConnectionRecovery] Failed to restore queue:', error)
    }
  }

  /**
   * 记录重连尝试
   */
  recordReconnectAttempt(sessionId: string, success: boolean, duration: number): void {
    this.stats.totalReconnects++
    
    if (success) {
      this.stats.successfulReconnects++
      this.stats.lastConnectedTime = Date.now()
      
      // 更新平均重连时间
      const total = this.stats.averageReconnectTime * (this.stats.successfulReconnects - 1)
      this.stats.averageReconnectTime = (total + duration) / this.stats.successfulReconnects

      // 重置重连计数
      this.reconnectAttempts.set(sessionId, 0)
    } else {
      // 增加重连计数
      const attempts = (this.reconnectAttempts.get(sessionId) || 0) + 1
      this.reconnectAttempts.set(sessionId, attempts)
    }
  }

  /**
   * 获取当前重连尝试次数
   */
  getReconnectAttempts(sessionId: string): number {
    return this.reconnectAttempts.get(sessionId) || 0
  }

  /**
   * 检查是否应该继续重连
   */
  shouldRetry(sessionId: string): boolean {
    const attempts = this.getReconnectAttempts(sessionId)
    return attempts < this.maxRetries
  }

  /**
   * 获取连接统计信息
   */
  getStats(): ConnectionStats {
    return { ...this.stats }
  }

  /**
   * 清空指定会话的离线队列
   */
  clearQueue(sessionId: string): void {
    this.offlineQueue.delete(sessionId)
    this.reconnectAttempts.delete(sessionId)
    storageService.remove(`offline_queue_${sessionId}`)
  }

  /**
   * 清空所有离线队列
   */
  clearAllQueues(): void {
    this.offlineQueue.clear()
    this.reconnectAttempts.clear()
    console.info('[ConnectionRecovery] All queues cleared')
  }
}

// 全局单例
export const connectionRecoveryService = ConnectionRecoveryService.getInstance()
