/**
 * 布隆过滤器单元测试
 */

import { describe, it, expect } from '@ohos/hypium'
import { BloomFilter } from '../main/ets/utils/BloomFilter'

export default function BloomFilterTest() {
  describe('BloomFilter', () => {
    it('should return false for non-existent items', () => {
      const filter = new BloomFilter(1000, 3)
      expect(filter.mightContain('item-1')).assertFalse()
    })

    it('should return true for added items', () => {
      const filter = new BloomFilter(1000, 3)
      filter.add('item-1')
      expect(filter.mightContain('item-1')).assertTrue()
    })

    it('should handle multiple items', () => {
      const filter = new BloomFilter(1000, 3)
      const items = ['item-1', 'item-2', 'item-3', 'item-4', 'item-5']

      items.forEach(item => filter.add(item))

      items.forEach(item => {
        expect(filter.mightContain(item)).assertTrue()
      })
    })

    it('should track item count', () => {
      const filter = new BloomFilter(1000, 3)
      expect(filter.size()).assertEqual(0)

      filter.add('item-1')
      expect(filter.size()).assertEqual(1)

      filter.add('item-2')
      expect(filter.size()).assertEqual(2)
    })

    it('should clear correctly', () => {
      const filter = new BloomFilter(1000, 3)
      filter.add('item-1')
      filter.add('item-2')

      filter.clear()

      expect(filter.mightContain('item-1')).assertFalse()
      expect(filter.mightContain('item-2')).assertFalse()
      expect(filter.size()).assertEqual(0)
    })

    it('should have low false positive rate', () => {
      const filter = new BloomFilter(10000, 5)
      
      // 添加 100 个元素
      for (let i = 0; i < 100; i++) {
        filter.add(`item-${i}`)
      }

      // 测试不存在的元素
      let falsePositives = 0
      for (let i = 100; i < 200; i++) {
        if (filter.mightContain(`item-${i}`)) {
          falsePositives++
        }
      }

      // 假阳性率应该低于 10%
      const rate = falsePositives / 100
      expect(rate < 0.1).assertTrue()
    })
  })
}
