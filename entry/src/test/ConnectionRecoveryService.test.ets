/**
 * 连接恢复服务单元测试
 */

import { describe, it, expect, beforeEach } from '@ohos/hypium'
import { ConnectionRecoveryService, QueuedMessage } from '../main/ets/services/ConnectionRecoveryService'
import { OutgoingMessage } from '../main/ets/models/Models'

export default function ConnectionRecoveryServiceTest() {
  describe('ConnectionRecoveryService', () => {
    let service: ConnectionRecoveryService

    beforeEach(() => {
      service = ConnectionRecoveryService.getInstance()
      service.clearAllQueues()
    })

    it('should calculate exponential backoff correctly', () => {
      const delay0 = service.calculateBackoff(0)
      expect(delay0).assertLarger(0)
      expect(delay0).assertLess(2000)  // ~1000ms ± 30%

      const delay1 = service.calculateBackoff(1)
      expect(delay1).assertLarger(delay0)

      const delay5 = service.calculateBackoff(5)
      expect(delay5).assertLarger(delay1)

      // 最大延迟限制
      const delay10 = service.calculateBackoff(10)
      expect(delay10).assertLess(35000)  // maxDelay + jitter
    })

    it('should enqueue and retrieve messages', () => {
      const msg: OutgoingMessage = {
        type: 'user_message',
        content: 'test message',
        sessionId: 'session-1'
      }

      const msgId = service.enqueueMessage('session-1', msg)
      expect(msgId).assertContain('queue-')

      const queue = service.getQueuedMessages('session-1')
      expect(queue.length).assertEqual(1)
      expect(queue[0].message).assertDeepEquals(msg)
    })

    it('should acknowledge and remove messages', () => {
      const msg: OutgoingMessage = {
        type: 'user_message',
        content: 'test message',
        sessionId: 'session-1'
      }

      const msgId = service.enqueueMessage('session-1', msg)
      service.acknowledgeMessage('session-1', msgId)

      const queue = service.getQueuedMessages('session-1')
      expect(queue.length).assertEqual(0)
    })

    it('should record reconnect stats', () => {
      service.recordReconnectAttempt('session-1', true, 1500)
      
      const stats = service.getStats()
      expect(stats.totalReconnects).assertEqual(1)
      expect(stats.successfulReconnects).assertEqual(1)
      expect(stats.averageReconnectTime).assertEqual(1500)
    })

    it('should limit retry attempts', () => {
      for (let i = 0; i < 15; i++) {
        service.recordReconnectAttempt('session-1', false, 0)
      }

      expect(service.shouldRetry('session-1')).assertFalse()
    })
  })
}
