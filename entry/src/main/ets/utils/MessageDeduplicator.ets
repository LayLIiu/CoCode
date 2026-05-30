/**
 * 消息去重器
 * 结合布隆过滤器和精确匹配，实现高效去重
 */

import { Message } from '../models/Models'
import { BloomFilter } from './BloomFilter'
import { generateFingerprint, MessageFingerprint } from './MessageFingerprint'

export interface DedupResult {
  isDuplicate: boolean
  fingerprint: MessageFingerprint
  existingMessageId?: string
}

export class MessageDeduplicator {
  private bloomFilter: BloomFilter
  private exactMatchCache: Map<string, MessageFingerprint>
  private recentFingerprints: Map<string, MessageFingerprint>
  private maxCacheSize: number
  private dedupWindowMs: number

  constructor(maxCacheSize: number = 1000, dedupWindowMs: number = 30000) {
    this.bloomFilter = new BloomFilter(50000, 5) // 50K 位，5 个哈希函数
    this.exactMatchCache = new Map()
    this.recentFingerprints = new Map()
    this.maxCacheSize = maxCacheSize
    this.dedupWindowMs = dedupWindowMs
  }

  /**
   * 检查消息是否重复
   */
  checkDuplicate(msg: Message, source: MessageFingerprint['source'] = 'local'): DedupResult {
    const fingerprint = generateFingerprint(msg, source)
    const key = `${fingerprint.id}:${fingerprint.contentHash}`

    // 第一阶段：布隆过滤器快速检查
    if (!this.bloomFilter.mightContain(key)) {
      // 一定不存在，直接添加
      this.addToFilter(key, fingerprint)
      return { isDuplicate: false, fingerprint }
    }

    // 第二阶段：精确匹配检查
    const existingFp = this.recentFingerprints.get(fingerprint.id)
    if (existingFp) {
      // 找到相同 ID，检查时间窗口
      const timeDiff = Math.abs(fingerprint.timestamp - existingFp.timestamp)
      if (timeDiff < this.dedupWindowMs) {
        // 在去重窗口内，判定为重复
        return { isDuplicate: true, fingerprint, existingMessageId: existingFp.id }
      }
    }

    // 第三阶段：内容哈希精确检查
    const contentKey = fingerprint.contentHash
    if (this.exactMatchCache.has(contentKey)) {
      const existing = this.exactMatchCache.get(contentKey)!
      const timeDiff = Math.abs(fingerprint.timestamp - existing.timestamp)
      if (timeDiff < this.dedupWindowMs) {
        return { isDuplicate: true, fingerprint, existingMessageId: existing.id }
      }
    }

    // 不是重复，添加到过滤器
    this.addToFilter(key, fingerprint)
    return { isDuplicate: false, fingerprint }
  }

  /**
   * 批量去重
   */
  deduplicateBatch(messages: Message[], source: MessageFingerprint['source'] = 'local'): Message[] {
    const uniqueMessages: Message[] = []
    const seenIds = new Set<string>()

    for (const msg of messages) {
      const result = this.checkDuplicate(msg, source)
      if (!result.isDuplicate && !seenIds.has(result.fingerprint.id)) {
        uniqueMessages.push(msg)
        seenIds.add(result.fingerprint.id)
      }
    }

    return uniqueMessages
  }

  /**
   * 添加到过滤器
   */
  private addToFilter(key: string, fingerprint: MessageFingerprint): void {
    this.bloomFilter.add(key)
    this.recentFingerprints.set(fingerprint.id, fingerprint)
    this.exactMatchCache.set(fingerprint.contentHash, fingerprint)

    // LRU 淘汰
    if (this.recentFingerprints.size > this.maxCacheSize) {
      const firstKey = this.recentFingerprints.keys().next().value
      if (firstKey) {
        this.recentFingerprints.delete(firstKey)
      }
    }

    if (this.exactMatchCache.size > this.maxCacheSize) {
      const firstKey = this.exactMatchCache.keys().next().value
      if (firstKey) {
        this.exactMatchCache.delete(firstKey)
      }
    }
  }

  /**
   * 清空去重器
   */
  clear(): void {
    this.bloomFilter.clear()
    this.recentFingerprints.clear()
    this.exactMatchCache.clear()
  }

  /**
   * 获取统计信息
   */
  getStats(): { bloomSize: number; cacheSize: number; falsePositiveRate: number } {
    return {
      bloomSize: this.bloomFilter.size(),
      cacheSize: this.recentFingerprints.size,
      falsePositiveRate: this.bloomFilter.getFalsePositiveRate()
    }
  }
}

// 全局单例
export const messageDeduplicator = new MessageDeduplicator()
