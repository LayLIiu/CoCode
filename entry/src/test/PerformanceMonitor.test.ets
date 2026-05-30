/**
 * 性能监控服务单元测试
 */

import { describe, it, expect, beforeEach } from '@ohos/hypium'
import { PerformanceMonitor, PerformanceMetric } from '../main/ets/services/PerformanceMonitor'

export default function PerformanceMonitorTest() {
  describe('PerformanceMonitor', () => {
    let monitor: PerformanceMonitor

    beforeEach(() => {
      monitor = PerformanceMonitor.getInstance()
      monitor.clear()
    })

    it('should record metrics', () => {
      monitor.recordMetric('api_latency', 150, 'ms', { endpoint: '/messages' })
      
      const stats = monitor.getMetricStats('api_latency')
      expect(stats).assertNotNull()
      expect(stats!.avg).assertEqual(150)
      expect(stats!.count).assertEqual(1)
    })

    it('should track trace events', () => {
      const traceId = monitor.startTrace('trace-1', 'api_call', 'api')
      
      // 模拟耗时操作
      setTimeout(() => {
        const trace = monitor.endTrace(traceId)
        expect(trace).assertNotNull()
        expect(trace!.duration).assertLarger(0)
        expect(trace!.name).assertEqual('api_call')
      }, 100)
    })

    it('should collect metric stats', () => {
      for (let i = 0; i < 10; i++) {
        monitor.recordMetric('render_time', i * 10, 'ms')
      }

      const stats = monitor.getMetricStats('render_time')
      expect(stats!.count).assertEqual(10)
      expect(stats!.min).assertEqual(0)
      expect(stats!.max).assertEqual(90)
      expect(stats!.avg).assertEqual(45)
    })

    it('should generate performance report', () => {
      monitor.recordMetric('memory_usage', 1024, 'bytes')
      
      const report = monitor.generateReport()
      expect(report.metrics.length).assertLarger(0)
      expect(report.appId).assertEqual('com.example.myapplication')
    })

    it('should support listeners', () => {
      let receivedMetric: PerformanceMetric | null = null
      
      monitor.addListener((metric) => {
        receivedMetric = metric
      })

      monitor.recordMetric('test_metric', 42, 'ms')
      
      expect(receivedMetric).assertNotNull()
      expect(receivedMetric!.name).assertEqual('test_metric')
      expect(receivedMetric!.value).assertEqual(42)
    })
  })
}
