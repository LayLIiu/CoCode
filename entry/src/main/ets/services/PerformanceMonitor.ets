/**
 * 性能监控服务
 * 采集性能指标、埋点追踪、异常上报
 */

export interface PerformanceMetric {
  name: string
  value: number
  unit: 'ms' | 'count' | 'percent' | 'bytes'
  timestamp: number
  tags?: Record<string, string>
}

export interface TraceEvent {
  id: string
  name: string
  startTime: number
  endTime?: number
  duration?: number
  type: 'api' | 'ui' | 'network' | 'storage' | 'custom'
  metadata?: Record<string, Object>
}

export interface PerformanceReport {
  appId: string
  version: string
  deviceId: string
  timestamp: number
  metrics: PerformanceMetric[]
  traces: TraceEvent[]
  environment: {
    osVersion: string
    deviceModel: string
    appVersion: string
    memoryUsage: number
    cpuUsage: number
  }
}

export type MetricListener = (metric: PerformanceMetric) => void

export class PerformanceMonitor {
  private static instance: PerformanceMonitor

  // 性能指标存储
  private metrics: Map<string, PerformanceMetric[]> = new Map()
  private maxMetricsPerName: number = 100

  // 追踪事件
  private traces: Map<string, TraceEvent> = new Map()
  private completedTraces: TraceEvent[] = []
  private maxCompletedTraces: number = 50

  // 监听器
  private listeners: MetricListener[] = []

  // 配置
  private enabled: boolean = true
  private sampleRate: number = 1.0  // 采样率 100%

  static getInstance(): PerformanceMonitor {
    if (!PerformanceMonitor.instance) {
      PerformanceMonitor.instance = new PerformanceMonitor()
    }
    return PerformanceMonitor.instance
  }

  /**
   * 记录性能指标
   */
  recordMetric(
    name: string,
    value: number,
    unit: PerformanceMetric['unit'],
    tags?: Record<string, string>
  ): void {
    if (!this.enabled || Math.random() > this.sampleRate) return

    const metric: PerformanceMetric = {
      name,
      value,
      unit,
      timestamp: Date.now(),
      tags
    }

    // 存储
    if (!this.metrics.has(name)) {
      this.metrics.set(name, [])
    }
    const metricList = this.metrics.get(name)!
    metricList.push(metric)

    // LRU 淘汰
    if (metricList.length > this.maxMetricsPerName) {
      metricList.shift()
    }

    // 通知监听器
    this.notifyListeners(metric)

    // 控制台输出
    console.debug(`[PerformanceMonitor] ${name}: ${value}${unit}`, tags || '')
  }

  /**
   * 开始追踪事件
   */
  startTrace(id: string, name: string, type: TraceEvent['type'], metadata?: Record<string, Object>): void {
    if (!this.enabled) return

    const trace: TraceEvent = {
      id,
      name,
      startTime: Date.now(),
      type,
      metadata
    }

    this.traces.set(id, trace)
    console.debug(`[PerformanceMonitor] Trace started: ${name} (${id})`)
  }

  /**
   * 结束追踪事件
   */
  endTrace(id: string): TraceEvent | null {
    const trace = this.traces.get(id)
    if (!trace) {
      console.warn(`[PerformanceMonitor] Trace not found: ${id}`)
      return null
    }

    trace.endTime = Date.now()
    trace.duration = trace.endTime - trace.startTime

    // 移动到完成列表
    this.traces.delete(id)
    this.completedTraces.push(trace)

    // LRU 淘汰
    if (this.completedTraces.length > this.maxCompletedTraces) {
      this.completedTraces.shift()
    }

    // 自动记录指标
    this.recordMetric(`trace.${trace.name}.duration`, trace.duration, 'ms', {
      type: trace.type
    })

    console.debug(`[PerformanceMonitor] Trace ended: ${trace.name} (${trace.duration}ms)`)
    return trace
  }

  /**
   * 便捷方法：API 调用追踪
   */
  trackApiCall(apiName: string, metadata?: Record<string, Object>): string {
    const id = `api-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`
    this.startTrace(id, apiName, 'api', metadata)
    return id
  }

  /**
   * 便捷方法：UI 渲染追踪
   */
  trackUIRender(componentName: string): string {
    const id = `ui-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`
    this.startTrace(id, componentName, 'ui')
    return id
  }

  /**
   * 便捷方法：网络请求追踪
   */
  trackNetworkRequest(url: string, method: string): string {
    const id = `net-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`
    this.startTrace(id, `${method} ${url}`, 'network', { url, method })
    return id
  }

  /**
   * 获取指标统计
   */
  getMetricStats(name: string): { avg: number; min: number; max: number; count: number } | null {
    const metrics = this.metrics.get(name)
    if (!metrics || metrics.length === 0) return null

    const values = metrics.map(m => m.value)
    const sum = values.reduce((a, b) => a + b, 0)

    return {
      avg: sum / values.length,
      min: Math.min(...values),
      max: Math.max(...values),
      count: values.length
    }
  }

  /**
   * 获取所有指标名称
   */
  getMetricNames(): string[] {
    return Array.from(this.metrics.keys())
  }

  /**
   * 获取完成的追踪事件
   */
  getCompletedTraces(count: number = 10): TraceEvent[] {
    return this.completedTraces.slice(-count)
  }

  /**
   * 添加监听器
   */
  addListener(listener: MetricListener): void {
    this.listeners.push(listener)
  }

  /**
   * 移除监听器
   */
  removeListener(listener: MetricListener): void {
    this.listeners = this.listeners.filter(l => l !== listener)
  }

  /**
   * 生成性能报告
   */
  generateReport(): PerformanceReport {
    const allMetrics: PerformanceMetric[] = []
    this.metrics.forEach(metricList => {
      allMetrics.push(...metricList)
    })

    return {
      appId: 'com.example.myapplication',
      version: '1.0.0',
      deviceId: 'device-id-placeholder',
      timestamp: Date.now(),
      metrics: allMetrics.slice(-100),  // 最近 100 条
      traces: this.completedTraces.slice(-20),  // 最近 20 条
      environment: {
        osVersion: 'HarmonyOS 4.0',
        deviceModel: 'Unknown',
        appVersion: '1.0.0',
        memoryUsage: 0,  // 需要实际获取
        cpuUsage: 0      // 需要实际获取
      }
    }
  }

  /**
   * 清空数据
   */
  clear(): void {
    this.metrics.clear()
    this.traces.clear()
    this.completedTraces = []
    console.info('[PerformanceMonitor] All data cleared')
  }

  /**
   * 设置启用状态
   */
  setEnabled(enabled: boolean): void {
    this.enabled = enabled
    console.info(`[PerformanceMonitor] ${enabled ? 'Enabled' : 'Disabled'}`)
  }

  /**
   * 设置采样率
   */
  setSampleRate(rate: number): void {
    this.sampleRate = Math.max(0, Math.min(1, rate))
    console.info(`[PerformanceMonitor] Sample rate set to ${this.sampleRate * 100}%`)
  }

  // MARK: - 私有方法

  private notifyListeners(metric: PerformanceMetric): void {
    this.listeners.forEach(listener => {
      try {
        listener(metric)
      } catch (error) {
        console.error('[PerformanceMonitor] Listener error:', error)
      }
    })
  }
}

// 全局单例
export const performanceMonitor = PerformanceMonitor.getInstance()
