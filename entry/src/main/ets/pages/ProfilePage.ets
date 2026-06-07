/**
 * 用户信息页面 - 显示用户配置、项目列表和用户设置
 * API：/api/status/user, /api/settings/user
 */

import { Theme } from '../common/Theme'
import { apiService } from '../services/APIService'
import { authStore } from '../stores/AuthStore'
import { HdsNavigation, HdsNavigationTitleMode, ScrollEffectType } from '@hms.hds.hdsBaseComponent'
import { hdsMaterial } from '@hms.hds.hdsMaterial'

@Entry
@Component
struct ProfilePage {
  @State configDir: string = ''
  @State projects: string[] = []
  @State settingsSummary: string = ''
  @State isLoading: boolean = false
  @State errorMessage: string = ''

  private scroller: Scroller = new Scroller()

  aboutToAppear(): void {
    this.loadProfile()
  }

  private async loadProfile(): Promise<void> {
    this.isLoading = true
    this.errorMessage = ''

    try {
      const userStatus = await apiService.getUserStatus()
      this.configDir = userStatus.configDir
      if (userStatus.projects && userStatus.projects.length > 0) {
        this.projects = userStatus.projects
      }
    } catch (e) {
      console.error('[ProfilePage] Failed to load user status:', e)
      let msg = (e as Error).message
      if (msg.includes('连接') || msg.includes('网络') || msg.includes('超时')) {
        this.errorMessage = msg
      } else {
        this.errorMessage = '加载用户信息失败，请确认已连接到桌面端'
      }
    }

    // 读取用户设置概要
    try {
      const settings = await apiService.getUserSettings()
      const keys: string[] = []
      if (typeof settings === 'object') {
        // 列出设置中的顶层键
        const settingKeys = Object.keys(settings)
        for (let i = 0; i < settingKeys.length; i++) {
          const key = settingKeys[i]
          if (key.length <= 20) {
            keys.push(key)
          }
        }
      }
      if (keys.length > 0) {
        this.settingsSummary = keys.join('、')
      } else {
        this.settingsSummary = '暂无配置'
      }
    } catch (e) {
      console.error('[ProfilePage] Failed to load settings:', e)
      this.settingsSummary = '未获取'
    }

    this.isLoading = false
  }

  private getConnectionText(): string {
    return authStore.serverUrl ? '已连接' : '未连接'
  }

  private getConnectionColor(): ResourceColor {
    return authStore.serverUrl ? Theme.AccentGreen : Theme.ErrorColor
  }

  build() {
    Stack() {
      HdsNavigation() {
        List({ space: Theme.SpacingMD, scroller: this.scroller }) {
          ListItem() {
            Row().width('100%').height(100)
          }

          ListItem() {
            this.ProfileOverview()
          }

          // 用户信息
          ListItem() {
            Column({ space: Theme.SpacingSM }) {
              Text('用户信息')
                .fontSize(Theme.FontCaption)
                .fontWeight(FontWeight.Medium)
                .fontColor(Theme.TextSecondary)
                .width('100%')

              Column({ space: 0 }) {
                // 头像区域
                Row() {
                  Stack() {
                    Circle()
                      .width(48)
                      .height(48)
                      .fill(Theme.PrimaryColorLight)
                    Text('U')
                      .fontSize(20)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(Theme.PrimaryColor)
                  }
                  .width(48)
                  .height(48)

                  Column({ space: 4 }) {
                    Text('当前用户')
                      .fontSize(Theme.FontBody)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(Theme.TextPrimary)

                    Text(authStore.serverUrl || '未连接')
                      .fontSize(Theme.FontCaption)
                      .fontColor(Theme.TextSecondary)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                  }
                  .margin({ left: 12 })
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

          // 配置目录
          ListItem() {
            Column({ space: Theme.SpacingSM }) {
              Text('配置目录')
                .fontSize(Theme.FontCaption)
                .fontWeight(FontWeight.Medium)
                .fontColor(Theme.TextSecondary)
                .width('100%')

              Column() {
                Row() {
                  if (this.isLoading) {
                    LoadingProgress()
                      .width(20).height(20).color(Theme.PrimaryColor)
                  } else if (this.errorMessage) {
                    Text(this.errorMessage)
                      .fontSize(Theme.FontBody)
                      .fontColor(Theme.ErrorColor)
                  } else {
                    Column({ space: 4 }) {
                      Text(this.configDir || '未获取')
                        .fontSize(Theme.FontBody)
                        .fontColor(this.configDir ? Theme.TextPrimary : Theme.TextSecondary)
                        .maxLines(2)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                    }
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

          // 项目列表
          ListItem() {
            Column({ space: Theme.SpacingSM }) {
              Text('已知项目')
                .fontSize(Theme.FontCaption)
                .fontWeight(FontWeight.Medium)
                .fontColor(Theme.TextSecondary)
                .width('100%')

              Column({ space: 0 }) {
                if (this.isLoading) {
                  Row() {
                    LoadingProgress()
                      .width(20).height(20).color(Theme.PrimaryColor)
                  }
                  .width('100%')
                  .padding(Theme.SpacingMD)
                  .justifyContent(FlexAlign.Center)
                } else if (this.projects.length === 0) {
                  Row() {
                    Text('暂无已发现的项目')
                      .fontSize(Theme.FontBody)
                      .fontColor(Theme.TextSecondary)
                  }
                  .width('100%')
                  .padding(Theme.SpacingMD)
                } else {
                  ForEach(this.projects, (project: string, index: number) => {
                    Row() {
                      SymbolGlyph($r('sys.symbol.folder'))
                        .fontSize(16)
                        .fontColor([Theme.AccentBlue])

                      Text(project)
                        .fontSize(Theme.FontBody)
                        .fontColor(Theme.TextPrimary)
                        .margin({ left: 10 })
                    }
                    .width('100%')
                    .padding({ left: Theme.SpacingMD, right: Theme.SpacingMD, top: 10, bottom: 10 })

                    if (index < this.projects.length - 1) {
                      Divider().color(Theme.GlassBorder)
                    }
                  }, (project: string) => project)
                }
              }
              .backgroundColor(Theme.GlassBackground)
              .borderRadius(Theme.RadiusMedium)
              .border({ width: 0.5, color: Theme.GlassBorder })
              .shadow({ radius: Theme.LiquidGlassShadowRadius, color: Theme.LiquidGlassShadowColor, offsetX: 0, offsetY: 4 })
            }
            .width('100%')
          }

          // 用户设置概要
          ListItem() {
            Column({ space: Theme.SpacingSM }) {
              Text('用户设置')
                .fontSize(Theme.FontCaption)
                .fontWeight(FontWeight.Medium)
                .fontColor(Theme.TextSecondary)
                .width('100%')

              Column() {
                Row() {
                  Column({ space: 2 }) {
                    Text(this.settingsSummary || '加载中...')
                      .fontSize(Theme.FontBody)
                      .fontColor(this.settingsSummary && this.settingsSummary !== '未获取' ?
                        Theme.TextPrimary : Theme.TextSecondary)
                      .maxLines(3)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                  }
                  .layoutWeight(1)
                  .alignItems(HorizontalAlign.Start)
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

          // 提示
          ListItem() {
            Column() {
              Text('配置目录和项目信息来自桌面端 /api/status/user 接口。连接桌面端后可查看详细配置。')
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
          title: { mainTitle: '用户信息' },
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
  }

  @Builder
  ProfileOverview() {
    Column({ space: 14 }) {
      Row() {
        Stack() {
          Circle()
            .width(58)
            .height(58)
            .fill('rgba(10, 132, 255, 0.14)')

          Text('U')
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .fontColor(Theme.AccentBlue)
        }
        .width(58)
        .height(58)

        Column({ space: 5 }) {
          Text('当前用户')
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .fontColor(Theme.TextPrimary)

          Text(authStore.serverUrl || '未连接到桌面端')
            .fontSize(Theme.FontCaption)
            .fontColor(Theme.TextSecondary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        .margin({ left: Theme.SpacingMD })

        Row({ space: 6 }) {
          Row()
            .width(8)
            .height(8)
            .borderRadius(4)
            .backgroundColor(this.getConnectionColor())

          Text(this.getConnectionText())
            .fontSize(Theme.FontTiny)
            .fontColor(this.getConnectionColor())
        }
        .padding({ left: 10, right: 10, top: 6, bottom: 6 })
        .backgroundColor(authStore.serverUrl ? 'rgba(48, 209, 88, 0.14)' : 'rgba(255, 59, 48, 0.12)')
        .borderRadius(10)
      }
      .width('100%')

      Row({ space: 8 }) {
        this.ProfileMetric('项目', this.projects.length.toString(), Theme.AccentBlue)
        this.ProfileMetric('配置', this.configDir ? '已读取' : '未获取', this.configDir ? Theme.AccentGreen : Theme.TextTertiary)
        this.ProfileMetric('设置', this.settingsSummary || '加载中', Theme.AccentOrange)
      }
      .width('100%')
    }
    .width('100%')
    .padding(Theme.SpacingLG)
    .backgroundColor('rgba(255, 255, 255, 0.055)')
    .border({ width: 0.5, color: 'rgba(255, 255, 255, 0.09)' })
    .borderRadius(Theme.RadiusLarge)
  }

  @Builder
  ProfileMetric(label: string, value: string, color: ResourceColor) {
    Column({ space: 4 }) {
      Text(label)
        .fontSize(11)
        .fontColor(Theme.TextTertiary)

      Text(value)
        .fontSize(Theme.FontTiny)
        .fontWeight(FontWeight.Medium)
        .fontColor(color)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .layoutWeight(1)
    .height(50)
    .padding({ left: 10, right: 10 })
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Start)
    .backgroundColor('rgba(255, 255, 255, 0.045)')
    .borderRadius(10)
  }
}
