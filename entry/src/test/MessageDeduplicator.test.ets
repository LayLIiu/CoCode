/**
 * 消息去重器单元测试
 */

import { describe, it, expect } from '@ohos/hypium'
import { MessageDeduplicator, DedupResult } from '../main/ets/utils/MessageDeduplicator'
import { Message } from '../main/ets/models/Models'

export default function MessageDeduplicatorTest() {
  describe('MessageDeduplicator', () => {
    let deduplicator: MessageDeduplicator

    beforeEach(() => {
      deduplicator = new MessageDeduplicator(100, 30000)
    })

    it('should identify duplicate messages with same ID', () => {
      const msg: Message = {
        id: 'msg-1',
        type: 'user',
        content: 'Hello',
        timestamp: new Date().toISOString()
      }

      const result1 = deduplicator.checkDuplicate(msg, 'local')
      expect(result1.isDuplicate).assertFalse()

      const result2 = deduplicator.checkDuplicate(msg, 'websocket')
      expect(result2.isDuplicate).assertTrue()
      expect(result2.existingMessageId).assertEqual('msg-1')
    })

    it('should allow different messages', () => {
      const msg1: Message = {
        id: 'msg-1',
        type: 'user',
        content: 'Hello',
        timestamp: new Date().toISOString()
      }

      const msg2: Message = {
        id: 'msg-2',
        type: 'user',
        content: 'World',
        timestamp: new Date().toISOString()
      }

      const result1 = deduplicator.checkDuplicate(msg1, 'local')
      expect(result1.isDuplicate).assertFalse()

      const result2 = deduplicator.checkDuplicate(msg2, 'local')
      expect(result2.isDuplicate).assertFalse()
    })

    it('should deduplicate batch correctly', () => {
      const messages: Message[] = [
        { id: 'msg-1', type: 'user', content: 'Hello', timestamp: new Date().toISOString() },
        { id: 'msg-1', type: 'user', content: 'Hello', timestamp: new Date().toISOString() },
        { id: 'msg-2', type: 'user', content: 'World', timestamp: new Date().toISOString() },
        { id: 'msg-3', type: 'user', content: 'Test', timestamp: new Date().toISOString() }
      ]

      const unique = deduplicator.deduplicateBatch(messages, 'sync')
      expect(unique.length).assertEqual(3)
    })

    it('should clear cache correctly', () => {
      const msg: Message = {
        id: 'msg-1',
        type: 'user',
        content: 'Hello',
        timestamp: new Date().toISOString()
      }

      deduplicator.checkDuplicate(msg, 'local')
      const stats1 = deduplicator.getStats()
      expect(stats1.cacheSize).assertEqual(1)

      deduplicator.clear()
      const stats2 = deduplicator.getStats()
      expect(stats2.cacheSize).assertEqual(0)
    })
  })
}
