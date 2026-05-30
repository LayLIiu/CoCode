/**
 * 布隆过滤器
 * 用于快速判断消息是否可能已存在
 * 空间效率高，支持概率性成员检测
 */

export class BloomFilter {
  private bits: boolean[]
  private size: number
  private hashCount: number
  private itemCount: number = 0

  constructor(size: number = 10000, hashCount: number = 3) {
    this.size = size
    this.hashCount = hashCount
    this.bits = new Array(size).fill(false)
  }

  /**
   * 添加元素
   */
  add(item: string): void {
    for (let i = 0; i < this.hashCount; i++) {
      const index = this.hash(item, i) % this.size
      this.bits[index] = true
    }
    this.itemCount++
  }

  /**
   * 检查元素是否可能存在
   * 返回 true 表示可能存在（有假阳性）
   * 返回 false 表示一定不存在
   */
  mightContain(item: string): boolean {
    for (let i = 0; i < this.hashCount; i++) {
      const index = this.hash(item, i) % this.size
      if (!this.bits[index]) return false
    }
    return true
  }

  /**
   * 清空过滤器
   */
  clear(): void {
    this.bits.fill(false)
    this.itemCount = 0
  }

  /**
   * 获取当前元素数量
   */
  size(): number {
    return this.itemCount
  }

  /**
   * 获取假阳性概率估算
   */
  getFalsePositiveRate(): number {
    if (this.itemCount === 0) return 0
    // P(false positive) ≈ (1 - e^(-kn/m))^k
    const ratio = (this.hashCount * this.itemCount) / this.size
    const prob = Math.pow(1 - Math.exp(-ratio), this.hashCount)
    return prob
  }

  /**
   * 哈希函数（使用双重哈希）
   */
  private hash(item: string, seed: number): number {
    // 使用 DJB2 和 SDBM 组合
    let hash1 = 5381
    let hash2 = 0

    for (let i = 0; i < item.length; i++) {
      const char = item.charCodeAt(i)
      hash1 = ((hash1 << 5) + hash1) + char
      hash2 = char + (hash2 << 6) + (hash2 << 16) - hash2
    }

    // 双重哈希：h(i) = h1 + i * h2
    return Math.abs((hash1 + seed * hash2) % this.size)
  }
}
