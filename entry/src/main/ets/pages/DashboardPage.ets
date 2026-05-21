/**
 * 仪表盘页面 - 设备状态、用量统计、实时日志
 * 已接入真实 API：/api/status, /api/status/usage, /api/activity-stats, /api/diagnostics/events
 */

import { Theme } from '../common/Theme'
import { sessionStore } from '../stores/SessionStore'
import { connectionManager } from '../services/ConnectionManager'
import { apiService } from '../services/APIService'
import { HdsNavigation, HdsNavigationTitleMode, ScrollEffectType } from '@hms.hds.hdsBaseComponent'
import { hdsMaterial } from '@hms.hds.hdsMaterial'

interface DashboardStats {
  sessionsCount: number
  messagesCount: number
  connectionType: string
  connectionLatency: number
  version: string
  uptime: string
  totalInputTokens: number
  totalOutputTokens: number
  logCount: number
}

@Entry
@Component
struct DashboardPage {
  @State stats: DashboardStats = {
    sessionsCount: 0,
    messagesCount: 0,
    connectionType: '未连接',
    connectionLatency: -1,
    version: '-',
    uptime: '-',
    totalInputTokens: 0,
    totalOutputTokens: 0,
    logCount: 0
  }
  @State logLines: string[] = []
  @State isLoading: boolean = false
  @State isRefreshing: boolean = false

  private scroller: Scroller = new Scroller()

  aboutToAppear(): void {
    this.loadStats()
  }

  private async loadStats(): Promise<void> {
    this.isRefreshing = true

    // 本地统计
    const sessions = sessionStore.sessions
    let totalMessages = 0
    sessionStore.messages.forEach((msgs) => {
      totalMessages += msgs.length
    })

    // 连接状态
    const status = connectionManager.getStatus()
    let connType = '未连接'
    if (status) {
      switch (status.type) {
        case 'lan': connType = '局域网'; break
        case 'pgy': connType = '蒲公英'; break
        case 'tunnel': connType = '远程隧道'; break
        case 'cloud_relay': connType = '云中继'; break
        default: connType = '未知'
      }
    }

    this.stats.sessionsCount = sessions.length
    this.stats.messagesCount = totalMessages
    this.stats.connectionType = connType
    this.stats.connectionLatency = status?.latency || -1

    // 服务器状态
    try {
      const serverStatus = await apiService.getServerStatus()
      this.stats.version = serverStatus.version
      const uptimeSec = Math.floor(serverStatus.uptime / 1000)
      if (uptimeSec < 60) {
        this.stats.uptime = `${uptimeSec}秒`
      } else if (uptimeSec < 3600) {
        this.stats.uptime = `${Math.floor(uptimeSec / 60)}分钟`
      } else {
        const h = Math.floor(uptimeSec / 3600)
        const m = Math.floor((uptimeSec % 3600) / 60)
        this.stats.uptime = `${h}小时${m}分钟`
      }
    } catch (e) {
      console.error('[Dashboard] Failed to fetch server status:', e)
    }

    // 用量统计
    try {
      const usage = await apiService.getUsage()
      this.stats.totalInputTokens = usage.totalInputTokens
      this.stats.totalOutputTokens = usage.totalOutputTokens
    } catch (e) {
      console.error('[Dashboard] Failed to fetch usage:', e)
    }

    // 日志计数
    try {
      const diagStatus = await apiService.getDiagnosticsStatus()
      if (diagStatus.counters && diagStatus.counters['total']) {
        this.stats.logCount = diagStatus.counters['total']
      }
    } catch (e) {
      console.error('[Dashboard] Failed to fetch diagnostics status:', e)
    }

    this.isRefreshing = false
  }

  private async fetchLogs(): Promise<void> {
    this.isLoading = true
    try {
      const response = await apiService.getDiagnosticsEvents(20)
      if (response.events && response.events.length > 0) {
        this.logLines = response.events.map((event) => {
          const time = event.timestamp ? event.timestamp.split('T')[1]?.split('.')[0] || event.timestamp : ''
          return `[${time}] [${event.severity}] ${event.summary}`
        })
      } else {
        this.logLines = ['暂无诊断事件']
      }
    } catch (e) {
      this.logLines = ['获取日志失败：' + (e as Error).message]
    }
    this.isLoading = false
  }

  private formatTokens(count: number): string {
    if (count < 1000) return count.toString()
    if (count < 1000000) return (count / 1000).toFixed(1) + 'K'
    return (count / 1000000).toFixed(1) + 'M'
  }

  build() {
    Stack() {
      HdsNavigation() {
        List({ space: Theme.SpacingMD, scroller: this.scroller }) {
          ListItem() {
            Row().width('100%').height(100)
          }

          // 设备状态
          ListItem() {
            Column({ space: Theme.SpacingSM }) {
              Row() {
                Text('设备状态')
                  .fontSize(Theme.FontCaption)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(Theme.TextSecondary)

                Blank()

                if (this.isRefreshing) {
                  LoadingProgress()
                    .width(16).height(16).color(Theme.PrimaryColor)
                } else {
                  SymbolGlyph($r('sys.symbol.arrow_clockwise'))
                    .fontSize(14)
                    .fontColor([Theme.PrimaryColor])
                }
              }
              .width('100%')
              .onClick(() => {
                if (!this.isRefreshing) this.loadStats()
              })

              Column({ space: 0 }) {
                Row() {
                  Text('连接类型')
                    .fontSize(Theme.FontBody)
                    .fontColor(Theme.TextPrimary)
                  Blank()
                  Text(this.stats.connectionType)
                    .fontSize(Theme.FontBody)
                    .fontColor(this.stats.connectionType !== '未连接' ? Theme.AccentGreen : Theme.TextSecondary)
                }
                .width('100%')
                .padding(Theme.SpacingMD)

                Divider().color(Theme.GlassBorder)

                Row() {
                  Text('连接延迟')
                    .fontSize(Theme.FontBody)
                    .fontColor(Theme.TextPrimary)
                  Blank()
                  Text(this.stats.connectionLatency > 0 ? `${this.stats.connectionLatency}ms` : '未检测')
                    .fontSize(Theme.FontBody)
                    .fontColor(this.stats.connectionLatency > 0 && this.stats.connectionLatency < 200 ?
                      Theme.AccentGreen : Theme.TextSecondary)
                }
                .width('100%')
                .padding(Theme.SpacingMD)

                Divider().color(Theme.GlassBorder)

                Row() {
                  Text('服务端版本')
                    .fontSize(Theme.FontBody)
                    .fontColor(Theme.TextPrimary)
                  Blank()
                  Text(this.stats.version)
                    .fontSize(Theme.FontBody)
                    .fontColor(Theme.TextSecondary)
                }
                .width('100%')
                .padding(Theme.SpacingMD)

                Divider().color(Theme.GlassBorder)

                Row() {
                  Text('运行时长')
                    .fontSize(Theme.FontBody)
                    .fontColor(Theme.TextPrimary)
                  Blank()
                  Text(this.stats.uptime)
                    .fontSize(Theme.FontBody)
                    .fontColor(Theme.TextSecondary)
                }
                .width('100%')
                .padding(Theme.SpacingMD)
              }
              .backgroundColor(Theme.GlassBackground)
              .borderRadius(Theme.RadiusMedium)
              .border({ width: 0.5, color: Theme.GlassBorder })
              .shadow({ radius: Theme.LiquidGlassShadowRadius, color: Theme.LiquidGlassShadowColor, offsetX: 0, offsetY: 4 })
            }
            .width('100%')
          }

          // 用量统计
          ListItem() {
            Column({ space: Theme.SpacingSM }) {
              Text('用量统计')
                .fontSize(Theme.FontCaption)
                .fontWeight(FontWeight.Medium)
                .fontColor(Theme.TextSecondary)
                .width('100%')

              Column({ space: 0 }) {
                Row() {
                  Text('对话数')
                    .fontSize(Theme.FontBody)
                    .fontColor(Theme.TextPrimary)
                  Blank()
                  Text(this.stats.sessionsCount.toString())
                    .fontSize(Theme.FontBody)
                    .fontColor(Theme.PrimaryColor)
                }
                .width('100%')
                .padding(Theme.SpacingMD)

                Divider().color(Theme.GlassBorder)

                Row() {
                  Text('消息数')
                    .fontSize(Theme.FontBody)
                    .fontColor(Theme.TextPrimary)
                  Blank()
                  Text(this.stats.messagesCount.toString())
                    .fontSize(Theme.FontBody)
                    .fontColor(Theme.PrimaryColor)
                }
                .width('100%')
                .padding(Theme.SpacingMD)

                Divider().color(Theme.GlassBorder)

                Row() {
                  Text('输入 Tokens')
                    .fontSize(Theme.FontBody)
                    .fontColor(Theme.TextPrimary)
                  Blank()
                  Text(this.formatTokens(this.stats.totalInputTokens))
                    .fontSize(Theme.FontBody)
                    .fontColor(Theme.TextSecondary)
                }
                .width('100%')
                .padding(Theme.SpacingMD)

                Divider().color(Theme.GlassBorder)

                Row() {
                  Text('输出 Tokens')
                    .fontSize(Theme.FontBody)
                    .fontColor(Theme.TextPrimary)
                  Blank()
                  Text(this.formatTokens(this.stats.totalOutputTokens))
                    .fontSize(Theme.FontBody)
                    .fontColor(Theme.TextSecondary)
                }
                .width('100%')
                .padding(Theme.SpacingMD)

                Divider().color(Theme.GlassBorder)

                Row() {
                  Text('诊断事件数')
                    .fontSize(Theme.FontBody)
                    .fontColor(Theme.TextPrimary)
                  Blank()
                  Text(this.stats.logCount.toString())
                    .fontSize(Theme.FontBody)
                    .fontColor(Theme.TextSecondary)
                }
                .width('100%')
                .padding(Theme.SpacingMD)
              }
              .backgroundColor(Theme.GlassBackground)
              .borderRadius(Theme.RadiusMedium)
              .border({ width: 0.5, color: Theme.GlassBorder })
              .shadow({ radius: Theme.LiquidGlassShadowRadius, color: Theme.LiquidGlassShadowColor, offsetX: 0, offsetY: 4 })
            }
            .width('100%')
          }

          // 实时日志
          ListItem() {
            Column({ space: Theme.SpacingSM }) {
              Row() {
                Text('实时日志')
                  .fontSize(Theme.FontCaption)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(Theme.TextSecondary)

                Blank()

                if (this.isLoading) {
                  LoadingProgress()
                    .width(16).height(16).color(Theme.PrimaryColor)
                }
              }
              .width('100%')
              .onClick(() => {
                if (!this.isLoading) this.fetchLogs()
              })

              Column() {
                if (this.logLines.length === 0) {
                  Row() {
                    Text('点击加载最新诊断事件')
                      .fontSize(Theme.FontBody)
                      .fontColor(Theme.TextSecondary)
                  }
                  .width('100%')
                  .padding(Theme.SpacingMD)
                } else {
                  ForEach(this.logLines, (line: string) => {
                    Row() {
                      Text(line)
                        .fontSize(Theme.FontTiny)
                        .fontColor(Theme.TextTertiary)
                        .maxLines(2)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                    }
                    .width('100%')
                    .padding({ left: Theme.SpacingMD, right: Theme.SpacingMD, top: 6, bottom: 6 })
                  }, (line: string, index: number) => index.toString())
                }
              }
              .backgroundColor(Theme.GlassBackground)
              .borderRadius(Theme.RadiusMedium)
              .border({ width: 0.5, color: Theme.GlassBorder })
              .shadow({ radius: Theme.LiquidGlassShadowRadius, color: Theme.LiquidGlassShadowColor, offsetX: 0, offsetY: 4 })
              .onClick(() => {
                if (!this.isLoading) this.fetchLogs()
              })
            }
            .width('100%')
          }
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: Theme.SpacingLG, right: Theme.SpacingLG })
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        .clip(false)
      }
      .titleBar({
        content: {
          title: { mainTitle: '仪表盘' },
        },
        style: {
          scrollEffectOpts: {
            enableScrollEffect: true,
            scrollEffectType: ScrollEffectType.GRADIENT_BLUR,
          },
          systemMaterialEffect: {
            materialType: hdsMaterial.MaterialType.ADAPTIVE,
            materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE,
          },
        },
        avoidLayoutSafeArea: true,
        enableComponentSafeArea: false,
      })
      .bindToScrollable([this.scroller])
      .titleMode(HdsNavigationTitleMode.MINI)
      .hideBackButton(false)
      .linearGradient({
        angle: 180,
        colors: [
          [Theme.BackgroundGradientStart, 0.0],
          [Theme.BackgroundGradientMiddle, 0.5],
          [Theme.BackgroundGradientEnd, 1.0]
        ]
      })
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    }
    .width('100%')
    .height('100%')
  }
}