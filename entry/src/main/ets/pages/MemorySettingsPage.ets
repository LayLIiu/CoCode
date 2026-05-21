/**
 * 记忆设置页面 - 管理 Claude 的记忆和上下文
 * 已接入真实 API：/api/settings/user, /api/settings (合并设置)
 */

import { Theme } from '../common/Theme'
import { apiService } from '../services/APIService'
import { HdsNavigation, HdsNavigationTitleMode, ScrollEffectType } from '@hms.hds.hdsBaseComponent'
import { hdsMaterial } from '@hms.hds.hdsMaterial'

@Entry
@Component
struct MemorySettingsPage {
  @State memoryEnabled: boolean = true
  @State memorySummary: string = ''
  @State isLoading: boolean = false
  @State showClearConfirm: boolean = false

  private scroller: Scroller = new Scroller()

  aboutToAppear(): void {
    this.loadMemorySettings()
  }

  private async loadMemorySettings(): Promise<void> {
    this.isLoading = true
    try {
      // 从用户设置中读取记忆相关配置
      const settings = await apiService.getUserSettings()
      // 服务端 settings 中可能包含 memory 相关字段
      if (settings && typeof settings['memory'] === 'object') {
        const mem = settings['memory'] as Record<string, Object>
        this.memoryEnabled = mem['enabled'] === true
        if (mem['summary']) {
          this.memorySummary = mem['summary'] as string
        }
      }
      if (!this.memorySummary) {
        this.memorySummary = '通过桌面端 Claude 设置记忆内容'
      }
    } catch (e) {
      console.error('[MemorySettingsPage] Failed to load settings:', e)
      this.memorySummary = '加载失败，请确认已连接到桌面端'
    }
    this.isLoading = false
  }

  private async toggleMemory(enabled: boolean): Promise<void> {
    this.memoryEnabled = enabled
    try {
      const settings: Record<string, Object> = {}
      const mem: Record<string, Object> = {}
      mem['enabled'] = enabled
      settings['memory'] = mem
      await apiService.updateUserSettings(settings)
    } catch (e) {
      console.error('[MemorySettingsPage] Failed to update memory setting:', e)
      // 回滚
      this.memoryEnabled = !enabled
    }
  }

  private async clearMemory(): Promise<void> {
    this.showClearConfirm = false
    try {
      const settings: Record<string, Object> = {}
      const mem: Record<string, Object> = {}
      mem['enabled'] = this.memoryEnabled
      mem['summary'] = ''
      settings['memory'] = mem
      await apiService.updateUserSettings(settings)
      this.memorySummary = '记忆已清除'
    } catch (e) {
      console.error('[MemorySettingsPage] Failed to clear memory:', e)
    }
  }

  build() {
    Stack() {
      HdsNavigation() {
        List({ space: Theme.SpacingMD, scroller: this.scroller }) {
          ListItem() {
            Row().width('100%').height(100)
          }

          // 记忆设置
          ListItem() {
            Column({ space: Theme.SpacingSM }) {
              Text('记忆设置')
                .fontSize(Theme.FontCaption)
                .fontWeight(FontWeight.Medium)
                .fontColor(Theme.TextSecondary)
                .width('100%')

              Column({ space: 0 }) {
                Row() {
                  Column({ space: 2 }) {
                    Text('启用记忆')
                      .fontSize(Theme.FontBody)
                      .fontColor(Theme.TextPrimary)

                    Text('允许 Claude 记住对话上下文')
                      .fontSize(Theme.FontCaption)
                      .fontColor(Theme.TextSecondary)
                  }
                  .layoutWeight(1)
                  .alignItems(HorizontalAlign.Start)

                  if (this.isLoading) {
                    LoadingProgress()
                      .width(20)
                      .height(20)
                      .color(Theme.PrimaryColor)
                  } else {
                    Toggle({ type: ToggleType.Switch, isOn: this.memoryEnabled })
                      .onChange((isOn: boolean) => {
                        this.toggleMemory(isOn)
                      })
                  }
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

          // 记忆内容
          ListItem() {
            Column({ space: Theme.SpacingSM }) {
              Text('记忆内容')
                .fontSize(Theme.FontCaption)
                .fontWeight(FontWeight.Medium)
                .fontColor(Theme.TextSecondary)
                .width('100%')

              Column({ space: 0 }) {
                Row() {
                  Text(this.memorySummary || '暂无记忆内容')
                    .fontSize(Theme.FontBody)
                    .fontColor(this.memorySummary && this.memorySummary !== '记忆已清除' &&
                      this.memorySummary !== '加载失败，请确认已连接到桌面端' ?
                      Theme.TextPrimary : Theme.TextSecondary)
                    .maxLines(3)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                .width('100%')
                .padding(Theme.SpacingMD)

                Divider().color(Theme.GlassBorder)

                Row() {
                  Text('清除记忆')
                    .fontSize(Theme.FontBody)
                    .fontColor(Theme.ErrorColor)
                }
                .width('100%')
                .padding(Theme.SpacingMD)
                .onClick(() => {
                  AlertDialog.show({
                    title: '清除记忆',
                    message: '确定要清除所有记忆内容吗？',
                    primaryButton: {
                      value: '取消',
                      action: () => {}
                    },
                    secondaryButton: {
                      value: '清除',
                      fontColor: Theme.ErrorColor,
                      action: () => {
                        this.clearMemory()
                      }
                    }
                  })
                })
              }
              .backgroundColor(Theme.GlassBackground)
              .borderRadius(Theme.RadiusMedium)
              .border({ width: 0.5, color: Theme.GlassBorder })
              .shadow({ radius: Theme.LiquidGlassShadowRadius, color: Theme.LiquidGlassShadowColor, offsetX: 0, offsetY: 4 })
            }
            .width('100%')
          }

          // 说明
          ListItem() {
            Column() {
              Text('记忆功能依赖于桌面端 Claude 的配置。可在桌面端通过 /api/settings/user 接口的 memory 字段管理记忆内容。')
                .fontSize(Theme.FontTiny)
                .fontColor(Theme.TextTertiary)
                .lineHeight(18)
            }
            .width('100%')
            .padding(Theme.SpacingMD)
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
          title: { mainTitle: '记忆设置' },
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