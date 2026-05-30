/**
 * 消息指纹工具
 * 用于生成消息唯一标识，支持跨通道去重
 */

import { Message } from '../models/Models'

export interface MessageFingerprint {
  id: string           // 消息唯一 ID
  contentHash: string  // 内容哈希
  vectorClock: number  // 向量时钟（用于冲突解决）
  source: 'local' | 'websocket' | 'http' | 'sync'
  timestamp: number
}

/**
 * 生成消息指纹
 */
export function generateFingerprint(msg: Message, source: MessageFingerprint['source'] = 'local'): MessageFingerprint {
  const content = msg.content || msg.toolResult || ''
  const toolInfo = msg.toolName ? JSON.stringify(msg.toolInput || {}) : ''
  const raw = `${msg.type}|${content}|${toolInfo}|${msg.toolUseId || ''}`
  
  // 使用 DJB2 哈希算法
  let hash = 5381
  for (let i = 0; i < raw.length; i++) {
    const char = raw.charCodeAt(i)
    hash = ((hash << 5) + hash) + char
    hash = hash & hash // Convert to 32bit integer
  }
  
  const contentHash = Math.abs(hash).toString(36)
  
  return {
    id: msg.id || `gen-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`,
    contentHash,
    vectorClock: Date.now(),
    source,
    timestamp: new Date(msg.timestamp).getTime()
  }
}

/**
 * 计算两个消息的相似度（用于模糊去重）
 */
export function calculateSimilarity(msg1: Message, msg2: Message): number {
  // 类型相同
  if (msg1.type !== msg2.type) return 0
  
  // 内容相似度
  const content1 = msg1.content || msg1.toolResult || ''
  const content2 = msg2.content || msg2.toolResult || ''
  
  if (content1 === content2) return 1.0
  
  // 简单的 Jaccard 相似度
  const words1 = new Set(content1.split(/\s+/))
  const words2 = new Set(content2.split(/\s+/))
  
  const intersection = new Set([...words1].filter(x => words2.has(x)))
  const union = new Set([...words1, ...words2])
  
  return union.size > 0 ? intersection.size / union.size : 0
}

/**
 * 消息排序键（用于确定性排序）
 */
export function getMessageSortKey(msg: Message): number {
  return new Date(msg.timestamp).getTime()
}
