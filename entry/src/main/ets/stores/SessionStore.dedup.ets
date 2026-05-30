/**
 * SessionStore 消息去重集成补丁
 * 将 MessageDeduplicator 集成到 SessionStore
 * 
 * 使用方法：
 * 1. 在 SessionStore.ets 中导入 MessageDeduplicator
 * 2. 替换现有的 recentMessageIds 去重逻辑
 * 3. 在 addMessage 和 handleWSMessage 中调用 checkDuplicate
 */

import { Message } from '../models/Models'
import { messageDeduplicator, DedupResult } from '../utils/MessageDeduplicator'

// 在 SessionStore 类中添加以下代码：

/*
// MARK: - 消息去重器

private deduplicator: MessageDeduplicator = messageDeduplicator

// 替换原有的 recentMessageIds 相关代码
// private recentMessageIds: Set<string> = new Set()
// private static readonly DEDUP_CACHE_TTL_MS = 30000

// MARK: - 使用去重器的添加消息方法

private addMessageWithDedup(sessionId: string, msg: Message): boolean {
  const result = this.deduplicator.checkDuplicate(msg, 'websocket')
  
  if (result.isDuplicate) {
    console.info(`[SessionStore] Duplicate message blocked: ${msg.id}, existing: ${result.existingMessageId}`)
    return false
  }
  
  // 原有的添加逻辑
  if (!this.messages.has(sessionId)) {
    this.messages.set(sessionId, [])
  }
  
  const msgs = this.messages.get(sessionId)!
  msgs.push(msg)
  
  // 通知监听器
  this.notifyMessagesChanged(sessionId)
  return true
}

// MARK: - 批量去重添加

private addMessagesWithDedup(sessionId: string, messages: Message[]): number {
  const uniqueMessages = this.deduplicator.deduplicateBatch(messages, 'sync')
  let addedCount = 0
  
  if (!this.messages.has(sessionId)) {
    this.messages.set(sessionId, [])
  }
  
  const msgs = this.messages.get(sessionId)!
  
  for (const msg of uniqueMessages) {
    const result = this.deduplicator.checkDuplicate(msg, 'sync')
    if (!result.isDuplicate) {
      msgs.push(msg)
      addedCount++
    }
  }
  
  if (addedCount > 0) {
    this.notifyMessagesChanged(sessionId)
  }
  
  return addedCount
}

// MARK: - 获取去重统计

getDedupStats(): { bloomSize: number; cacheSize: number; falsePositiveRate: number } {
  return this.deduplicator.getStats()
}

// MARK: - 清理去重缓存（用于内存优化）

clearDedupCache(): void {
  this.deduplicator.clear()
  console.info('[SessionStore] Dedup cache cleared')
}
*/

export default class SessionStoreDedupPatch {
  // 这是一个补丁说明文件，不包含实际实现
  // 实际修改请参考上面的注释代码
}
