/**
 * 缓存管理器单元测试
 */

import { describe, it, expect, beforeEach } from '@ohos/hypium'
import { CacheManager } from '../main/ets/services/CacheManager'

export default function CacheManagerTest() {
  describe('CacheManager', () => {
    let cache: CacheManager

    beforeEach(() => {
      cache = CacheManager.getInstance()
      cache.clear()
    })

    it('should set and get cache', () => {
      const data = { name: 'test', value: 123 }
      cache.set('key-1', data)

      const cached = cache.get('key-1')
      expect(cached).assertDeepEquals(data)
    })

    it('should return null for non-existent keys', () => {
      const cached = cache.get('non-existent')
      expect(cached).assertNull()
    })

    it('should delete cache', () => {
      cache.set('key-1', { data: 'test' })
      const deleted = cache.delete('key-1')
      
      expect(deleted).assertTrue()
      expect(cache.has('key-1')).assertFalse()
    })

    it('should check cache existence', () => {
      cache.set('key-1', { data: 'test' })
      expect(cache.has('key-1')).assertTrue()
      expect(cache.has('key-2')).assertFalse()
    })

    it('should provide stats', () => {
      cache.set('key-1', { data: 'test1' })
      cache.set('key-2', { data: 'test2' })

      const stats = cache.getStats()
      expect(stats.entryCount).assertEqual(2)
      expect(stats.totalSize).assertLarger(0)
    })

    it('should support cache policy', async () => {
      let fetchCount = 0
      const fetcher = async () => {
        fetchCount++
        return { data: 'fresh' }
      }

      // cache-first 策略
      const result1 = await cache.fetchWithPolicy('key-1', fetcher, 'cache-first')
      expect(result1.data).assertEqual('fresh')
      expect(fetchCount).assertEqual(1)

      // 第二次从缓存获取
      const result2 = await cache.fetchWithPolicy('key-1', fetcher, 'cache-first')
      expect(result2.data).assertEqual('fresh')
      expect(fetchCount).assertEqual(1)  // 未增加
    })
  })
}
