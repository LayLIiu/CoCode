/**
 * 缓存管理器
 * 支持内存缓存、磁盘缓存、缓存策略配置
 */

export interface CacheEntry<T> {
  data: T
  timestamp: number
  ttl: number  // Time to live (ms)
  size: number // 字节数
  hits: number
}

export type CachePolicy = 'network-only' | 'cache-first' | 'network-first' | 'stale-while-revalidate'

export class CacheManager {
  private static instance: CacheManager

  // 内存缓存
  private memoryCache: Map<string, CacheEntry<Object>> = new Map()
  private maxMemorySize: number = 50 * 1024 * 1024  // 50MB
  private currentMemorySize: number = 0

  // 默认 TTL
  private defaultTTL: number = 30 * 60 * 1000  // 30分钟

  static getInstance(): CacheManager {
    if (!CacheManager.instance) {
      CacheManager.instance = new CacheManager()
    }
    return CacheManager.instance
  }

  /**
   * 设置缓存
   */
  set<T>(key: string, data: T, ttl?: number): void {
    const entry: CacheEntry<T> = {
      data,
      timestamp: Date.now(),
      ttl: ttl || this.defaultTTL,
      size: this.estimateSize(data),
      hits: 0
    }

    // 检查是否需要淘汰
    this.evictIfNeeded(entry.size)

    this.memoryCache.set(key, entry as CacheEntry<Object>)
    this.currentMemorySize += entry.size

    console.debug(`[CacheManager] Set cache: ${key}, size: ${entry.size} bytes`)
  }

  /**
   * 获取缓存
   */
  get<T>(key: string): T | null {
    const entry = this.memoryCache.get(key) as CacheEntry<T> | undefined

    if (!entry) {
      return null
    }

    // 检查是否过期
    if (this.isExpired(entry)) {
      this.delete(key)
      return null
    }

    // 增加命中计数
    entry.hits++

    console.debug(`[CacheManager] Cache hit: ${key}, hits: ${entry.hits}`)
    return entry.data
  }

  /**
   * 删除缓存
   */
  delete(key: string): boolean {
    const entry = this.memoryCache.get(key)
    if (entry) {
      this.currentMemorySize -= entry.size
      this.memoryCache.delete(key)
      console.debug(`[CacheManager] Cache deleted: ${key}`)
      return true
    }
    return false
  }

  /**
   * 清空所有缓存
   */
  clear(): void {
    this.memoryCache.clear()
    this.currentMemorySize = 0
    console.info('[CacheManager] All cache cleared')
  }

  /**
   * 检查缓存是否存在
   */
  has(key: string): boolean {
    const entry = this.memoryCache.get(key)
    if (!entry) return false
    return !this.isExpired(entry)
  }

  /**
   * 获取缓存统计信息
   */
  getStats(): {
    entryCount: number
    totalSize: number
    maxSize: number
    hitRate: number
    averageHits: number
  } {
    let totalHits = 0
    let entryCount = 0

    this.memoryCache.forEach(entry => {
      totalHits += entry.hits
      entryCount++
    })

    return {
      entryCount,
      totalSize: this.currentMemorySize,
      maxSize: this.maxMemorySize,
      hitRate: entryCount > 0 ? totalHits / entryCount : 0,
      averageHits: entryCount > 0 ? totalHits / entryCount : 0
    }
  }

  /**
   * 清理过期缓存
   */
  cleanupExpired(): number {
    let cleaned = 0
    const now = Date.now()

    this.memoryCache.forEach((entry, key) => {
      if (this.isExpired(entry)) {
        this.delete(key)
        cleaned++
      }
    })

    if (cleaned > 0) {
      console.info(`[CacheManager] Cleaned ${cleaned} expired entries`)
    }

    return cleaned
  }

  /**
   * 设置最大内存大小
   */
  setMaxMemorySize(size: number): void {
    this.maxMemorySize = size
    this.evictIfNeeded(0)
    console.info(`[CacheManager] Max memory size set to ${size} bytes`)
  }

  /**
   * 使用缓存策略获取数据
   */
  async fetchWithPolicy<T>(
    key: string,
    fetcher: () => Promise<T>,
    policy: CachePolicy = 'cache-first',
    ttl?: number
  ): Promise<T> {
    switch (policy) {
      case 'network-only':
        // 仅网络
        return await fetcher()

      case 'cache-first':
        // 优先缓存
        const cached = this.get<T>(key)
        if (cached !== null) {
          return cached
        }
        const fresh = await fetcher()
        this.set(key, fresh, ttl)
        return fresh

      case 'network-first':
        // 优先网络
        try {
          const data = await fetcher()
          this.set(key, data, ttl)
          return data
        } catch (error) {
          const fallback = this.get<T>(key)
          if (fallback !== null) {
            console.warn(`[CacheManager] Network failed, using cache: ${key}`)
            return fallback
          }
          throw error
        }

      case 'stale-while-revalidate':
        // 返回过期缓存，同时后台更新
        const stale = this.get<T>(key)
        if (stale !== null) {
          // 后台更新
          fetcher().then(data => {
            this.set(key, data, ttl)
          }).catch(err => {
            console.error(`[CacheManager] Background revalidation failed: ${key}`, err)
          })
          return stale
        }
        // 无缓存，直接网络请求
        const initial = await fetcher()
        this.set(key, initial, ttl)
        return initial

      default:
        return await fetcher()
    }
  }

  // MARK: - 私有方法

  /**
   * 检查缓存是否过期
   */
  private isExpired(entry: CacheEntry<Object>): boolean {
    return Date.now() - entry.timestamp > entry.ttl
  }

  /**
   * 估算对象大小（字节）
   */
  private estimateSize(data: Object): number {
    try {
      const json = JSON.stringify(data)
      return json.length * 2  // UTF-16 编码
    } catch {
      return 1024  // 默认 1KB
    }
  }

  /**
   * 淘汰缓存以腾出空间
   */
  private evictIfNeeded(newSize: number): void {
    while (this.currentMemorySize + newSize > this.maxMemorySize && this.memoryCache.size > 0) {
      // LRU 淘汰：移除最少使用的
      let minKey = ''
      let minHits = Infinity

      this.memoryCache.forEach((entry, key) => {
        if (entry.hits < minHits) {
          minHits = entry.hits
          minKey = key
        }
      })

      if (minKey) {
        this.delete(minKey)
      } else {
        break
      }
    }
  }
}

// 全局单例
export const cacheManager = CacheManager.getInstance()
