/**
 * 存储管理页面
 * 管理对话缓存、存储使用情况
 */

import { Theme } from '../common/Theme'
import { sessionStore } from '../stores/SessionStore'
import { storageService } from '../services/StorageService'
import { HdsNavigation, HdsNavigationTitleMode, ScrollEffectType } from '@hms.hds.hdsBaseComponent'
import { hdsMaterial } from '@hms.hds.hdsMaterial'
import { LengthMetrics } from '@kit.ArkUI'
import router from '@ohos.router'
import preferences from '@ohos.data.preferences'

interface StorageInfo {
  sessionsCount: number
  messagesCount: number
  cacheSize: number
  recentDirsCount: number
}

@Entry
@Component
struct StorageManagementPage {
  @State storageInfo: StorageInfo = {
    sessionsCount: 0,
    messagesCount: 0,
    cacheSize: 0,
    recentDirsCount: 0
  }
  @State showClearCacheConfirm: boolean = false
  @State showDeleteSessionsConfirm: boolean = false
  @State isClearing: boolean = false

  private scroller: Scroller = new Scroller()

  async aboutToAppear(): Promise<void> {
    await this.loadStorageInfo()
  }

  private async loadStorageInfo(): Promise<void> {
    const sessions = sessionStore.sessions
    let totalMessages = 0

    // 从 sessionStore 的 messages Map 中获取消息数量
    sessionStore.messages.forEach((msgs) => {
      totalMessages += msgs.length
    })

    // 获取最近使用目录数量
    let recentDirs: string[] = []
    try {
      const prefs = await preferences.getPreferences(getContext(this), 'claude_prefs')
      const dirsStr = await prefs.get('recent_directories', '[]') as string
      recentDirs = JSON.parse(dirsStr)
    } catch (e) {
      // 忽略错误
    }

    this.storageInfo = {
      sessionsCount: sessions.length,
      messagesCount: totalMessages,
      cacheSize: this.calculateCacheSize(sessions.length, totalMessages),
      recentDirsCount: recentDirs.length
    }
  }

  private calculateCacheSize(sessions: number, messages: number): number {
    // 估算缓存大小（KB）
    // 每个会话约 2KB，每条消息约 0.5KB
    return Math.round(sessions * 2 + messages * 0.5)
  }

  private formatSize(kb: number): string {
    if (kb < 1024) {
      return `${kb} KB`
    } else if (kb < 1024 * 1024) {
      return `${(kb / 1024).toFixed(2)} MB`
    } else {
      return `${(kb / 1024 / 1024).toFixed(2)} GB`
    }
  }

  build() {
    Stack() {
      HdsNavigation() {
        List({ space: Theme.SpacingMD, scroller: this.scroller }) {
          // 顶部留白
          ListItem() {
            Row().width('100%').height(100)
          }

          // 存储概览
          ListItem() {
            this.StorageOverviewSection()
          }

          // 对话数据
          ListItem() {
            this.ConversationDataSection()
          }

          // 缓存数据
          ListItem() {
            this.CacheDataSection()
          }

          // 最近使用目录
          ListItem() {
            this.RecentDirsSection()
          }

          // 危险操作区域
          ListItem() {
            this.DangerZoneSection()
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
          title: { mainTitle: '存储管理' },
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
      .backgroundColor('#000000')
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    }
    .width('100%')
    .height('100%')
    .bindSheet($$this.showClearCacheConfirm, this.ClearCacheConfirmSheet(), {
      height: 200,
      backgroundColor: Theme.GlassBackground,
      dragBar: true
    })
    .bindSheet($$this.showDeleteSessionsConfirm, this.DeleteSessionsConfirmSheet(), {
      height: 220,
      backgroundColor: Theme.GlassBackground,
      dragBar: true
    })
  }

  @Builder
  StorageOverviewSection() {
    Column({ space: Theme.SpacingMD }) {
      Text('存储概览')
        .fontSize(Theme.FontCaption)
        .fontWeight(FontWeight.Medium)
        .fontColor(Theme.TextSecondary)
        .width('100%')

      // 存储使用圆环图
      Column() {
        Stack() {
          // 背景圆环
          Progress({ value: 0, total: 100, type: ProgressType.Ring })
            .width(120)
            .height(120)
            .color(Theme.GlassBorder)

          // 已使用
          Progress({ value: this.storageInfo.cacheSize / 1024, total: 100, type: ProgressType.Ring })
            .width(120)
            .height(120)
            .color(Theme.PrimaryColor)

          // 中心文字
          Column() {
            Text(this.formatSize(this.storageInfo.cacheSize))
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontColor(Theme.TextPrimary)

            Text('已使用')
              .fontSize(Theme.FontCaption)
              .fontColor(Theme.TextSecondary)
          }
        }

        // 详细数据
        Row({ space: Theme.SpacingXL }) {
          Column() {
            Text(this.storageInfo.sessionsCount.toString())
              .fontSize(24)
              .fontWeight(FontWeight.Bold)
              .fontColor(Theme.PrimaryColor)

            Text('对话数')
              .fontSize(Theme.FontCaption)
              .fontColor(Theme.TextSecondary)
          }

          Column() {
            Text(this.storageInfo.messagesCount.toString())
              .fontSize(24)
              .fontWeight(FontWeight.Bold)
              .fontColor(Theme.PrimaryColor)

            Text('消息数')
              .fontSize(Theme.FontCaption)
              .fontColor(Theme.TextSecondary)
          }
        }
        .margin({ top: Theme.SpacingLG })
      }
      .width('100%')
      .padding(Theme.SpacingLG)
      .backgroundColor(Theme.GlassBackground)
      .borderRadius(Theme.RadiusMedium)
      .border({ width: 0.5, color: Theme.GlassBorder })
      .shadow({ radius: Theme.LiquidGlassShadowRadius, color: Theme.LiquidGlassShadowColor, offsetX: 0, offsetY: 4 })
    }
    .width('100%')
  }

  @Builder
  ConversationDataSection() {
    Column({ space: Theme.SpacingSM }) {
      Text('对话数据')
        .fontSize(Theme.FontCaption)
        .fontWeight(FontWeight.Medium)
        .fontColor(Theme.TextSecondary)
        .width('100%')

      Column({ space: 0 }) {
        // 本地对话
        Row() {
          Column({ space: 2 }) {
            Text('本地对话')
              .fontSize(Theme.FontBody)
              .fontColor(Theme.TextPrimary)

            Text(`${this.storageInfo.sessionsCount} 个对话已保存`)
              .fontSize(Theme.FontCaption)
              .fontColor(Theme.TextSecondary)
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)

          SymbolGlyph($r('sys.symbol.chevron_right'))
            .fontSize(14)
            .fontColor([Theme.TextSecondary])
        }
        .width('100%')
        .padding(Theme.SpacingMD)
        .onClick(() => {
          // 跳转到对话列表
          router.back()
        })

        Divider().color(Theme.GlassBorder)

        // 消息记录
        Row() {
          Column({ space: 2 }) {
            Text('消息记录')
              .fontSize(Theme.FontBody)
              .fontColor(Theme.TextPrimary)

            Text(`${this.storageInfo.messagesCount} 条消息`)
              .fontSize(Theme.FontCaption)
              .fontColor(Theme.TextSecondary)
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)

          SymbolGlyph($r('sys.symbol.chevron_right'))
            .fontSize(14)
            .fontColor([Theme.TextSecondary])
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

  @Builder
  CacheDataSection() {
    Column({ space: Theme.SpacingSM }) {
      Text('缓存数据')
        .fontSize(Theme.FontCaption)
        .fontWeight(FontWeight.Medium)
        .fontColor(Theme.TextSecondary)
        .width('100%')

      Column({ space: 0 }) {
        // 应用缓存
        Row() {
          Column({ space: 2 }) {
            Text('应用缓存')
              .fontSize(Theme.FontBody)
              .fontColor(Theme.TextPrimary)

            Text('图片、文件等临时数据')
              .fontSize(Theme.FontCaption)
              .fontColor(Theme.TextSecondary)
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)

          Text(this.formatSize(Math.round(this.storageInfo.cacheSize * 0.3)))
            .fontSize(Theme.FontBody)
            .fontColor(Theme.TextSecondary)
        }
        .width('100%')
        .padding(Theme.SpacingMD)

        Divider().color(Theme.GlassBorder)

        // 网络缓存
        Row() {
          Column({ space: 2 }) {
            Text('网络缓存')
              .fontSize(Theme.FontBody)
              .fontColor(Theme.TextPrimary)

            Text('API 响应、资源文件')
              .fontSize(Theme.FontCaption)
              .fontColor(Theme.TextSecondary)
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)

          Text(this.formatSize(Math.round(this.storageInfo.cacheSize * 0.2)))
            .fontSize(Theme.FontBody)
            .fontColor(Theme.TextSecondary)
        }
        .width('100%')
        .padding(Theme.SpacingMD)

        Divider().color(Theme.GlassBorder)

        // 清除缓存按钮
        Row() {
          Text('清除缓存')
            .fontSize(Theme.FontBody)
            .fontColor(Theme.WarningColor)

          Blank()

          if (this.isClearing) {
            LoadingProgress()
              .width(20)
              .height(20)
              .color(Theme.WarningColor)
          } else {
            SymbolGlyph($r('sys.symbol.trash'))
              .fontSize(18)
              .fontColor([Theme.WarningColor])
          }
        }
        .width('100%')
        .padding(Theme.SpacingMD)
        .onClick(() => {
          if (!this.isClearing) {
            this.showClearCacheConfirm = true
          }
        })
      }
      .backgroundColor(Theme.GlassBackground)
      .borderRadius(Theme.RadiusMedium)
      .border({ width: 0.5, color: Theme.GlassBorder })
      .shadow({ radius: Theme.LiquidGlassShadowRadius, color: Theme.LiquidGlassShadowColor, offsetX: 0, offsetY: 4 })
    }
    .width('100%')
  }

  @Builder
  RecentDirsSection() {
    Column({ space: Theme.SpacingSM }) {
      Text('最近使用的工作目录')
        .fontSize(Theme.FontCaption)
        .fontWeight(FontWeight.Medium)
        .fontColor(Theme.TextSecondary)
        .width('100%')

      Row() {
        Column({ space: 2 }) {
          Text('已保存的目录')
            .fontSize(Theme.FontBody)
            .fontColor(Theme.TextPrimary)

          Text(`${this.storageInfo.recentDirsCount} 个目录`)
            .fontSize(Theme.FontCaption)
            .fontColor(Theme.TextSecondary)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(14)
          .fontColor([Theme.TextSecondary])
      }
      .width('100%')
      .padding(Theme.SpacingMD)
      .backgroundColor(Theme.GlassBackground)
      .borderRadius(Theme.RadiusMedium)
      .border({ width: 0.5, color: Theme.GlassBorder })
      .shadow({ radius: Theme.LiquidGlassShadowRadius, color: Theme.LiquidGlassShadowColor, offsetX: 0, offsetY: 4 })
      .onClick(() => {
        // 可以展示最近目录列表
      })
    }
    .width('100%')
  }

  @Builder
  DangerZoneSection() {
    Column({ space: Theme.SpacingSM }) {
      Text('危险操作')
        .fontSize(Theme.FontCaption)
        .fontWeight(FontWeight.Medium)
        .fontColor(Theme.ErrorColor)
        .width('100%')

      Column({ space: 0 }) {
        // 删除所有对话
        Row() {
          Column({ space: 2 }) {
            Text('删除所有本地对话')
              .fontSize(Theme.FontBody)
              .fontColor(Theme.ErrorColor)

            Text('此操作不可撤销')
              .fontSize(Theme.FontCaption)
              .fontColor(Theme.TextSecondary)
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)

          SymbolGlyph($r('sys.symbol.trash'))
            .fontSize(18)
            .fontColor([Theme.ErrorColor])
        }
        .width('100%')
        .padding(Theme.SpacingMD)
        .onClick(() => {
          this.showDeleteSessionsConfirm = true
        })
      }
      .backgroundColor(Theme.GlassBackground)
      .borderRadius(Theme.RadiusMedium)
      .border({ width: 0.5, color: Theme.GlassBorder })
      .shadow({ radius: Theme.LiquidGlassShadowRadius, color: Theme.LiquidGlassShadowColor, offsetX: 0, offsetY: 4 })
    }
    .width('100%')
  }

  @Builder
  ClearCacheConfirmSheet() {
    Column() {
      Text('确认清除缓存？')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(Theme.TextPrimary)
        .width('100%')
        .textAlign(TextAlign.Center)
        .padding({ top: Theme.SpacingMD })

      Text('这将清除所有缓存数据，不会删除对话记录')
        .fontSize(Theme.FontBody)
        .fontColor(Theme.TextSecondary)
        .width('100%')
        .textAlign(TextAlign.Center)
        .padding({ top: Theme.SpacingSM })

      Row({ space: Theme.SpacingMD }) {
        Button('取消')
          .layoutWeight(1)
          .height(44)
          .backgroundColor(Theme.GlassBackground)
          .fontColor(Theme.TextPrimary)
          .borderRadius(8)
          .backgroundBlurStyle(BlurStyle.COMPONENT_REGULAR)
          .onClick(() => {
            this.showClearCacheConfirm = false
          })

        Button('清除')
          .layoutWeight(1)
          .height(44)
          .backgroundColor(Theme.WarningColor)
          .fontColor(Color.White)
          .borderRadius(8)
          .backgroundBlurStyle(BlurStyle.COMPONENT_REGULAR)
          .onClick(async () => {
            this.isClearing = true
            this.showClearCacheConfirm = false
            // 模拟清除缓存
            await this.clearCache()
            this.isClearing = false
          })
      }
      .width('100%')
      .padding({ left: Theme.SpacingLG, right: Theme.SpacingLG, top: Theme.SpacingLG })
    }
  }

  @Builder
  DeleteSessionsConfirmSheet() {
    Column() {
      Text('确认删除所有对话？')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(Theme.TextPrimary)
        .width('100%')
        .textAlign(TextAlign.Center)
        .padding({ top: Theme.SpacingMD })

      Text('此操作将永久删除所有本地对话，无法恢复！')
        .fontSize(Theme.FontBody)
        .fontColor(Theme.ErrorColor)
        .width('100%')
        .textAlign(TextAlign.Center)
        .padding({ top: Theme.SpacingSM })

      Row({ space: Theme.SpacingMD }) {
        Button('取消')
          .layoutWeight(1)
          .height(44)
          .backgroundColor(Theme.GlassBackground)
          .fontColor(Theme.TextPrimary)
          .borderRadius(8)
          .backgroundBlurStyle(BlurStyle.COMPONENT_REGULAR)
          .onClick(() => {
            this.showDeleteSessionsConfirm = false
          })

        Button('删除')
          .layoutWeight(1)
          .height(44)
          .backgroundColor(Theme.ErrorColor)
          .fontColor(Color.White)
          .borderRadius(8)
          .backgroundBlurStyle(BlurStyle.COMPONENT_REGULAR)
          .onClick(async () => {
            this.showDeleteSessionsConfirm = false
            await this.deleteAllSessions()
          })
      }
      .width('100%')
      .padding({ left: Theme.SpacingLG, right: Theme.SpacingLG, top: Theme.SpacingLG })
    }
  }

  private async clearCache(): Promise<void> {
    try {
      // 清除 preferences 中的缓存数据（非核心认证数据）
      const prefs = await preferences.getPreferences(getContext(this), 'claude_prefs')
      await prefs.clear()
      await prefs.flush()

      // 重新计算缓存大小
      await this.loadStorageInfo()
      console.info('[StorageManagementPage] Cache cleared')
    } catch (e) {
      console.error(`[StorageManagementPage] Clear cache error: ${e}`)
    }
  }

  private async deleteAllSessions(): Promise<void> {
    sessionStore.clearAllSessions()
    await this.loadStorageInfo()
  }
}
