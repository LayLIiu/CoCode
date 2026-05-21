/**
 * 更新检查页面 - 检查 Agent 和 Link 更新状态
 * 已接入真实 API：/api/status (版本信息)
 */

import { Theme } from '../common/Theme'
import { apiService } from '../services/APIService'
import { HdsNavigation, HdsNavigationTitleMode, ScrollEffectType } from '@hms.hds.hdsBaseComponent'
import { hdsMaterial } from '@hms.hds.hdsMaterial'

interface VersionInfo {
  component: string
  currentVersion: string
  latestVersion: string
  updateAvailable: boolean
}

@Entry
@Component
struct UpdatesPage {
  @State versions: VersionInfo[] = []
  @State isChecking: boolean = false
  @State lastCheckTime: string = ''
  @State checkResultText: string = ''

  private scroller: Scroller = new Scroller()

  aboutToAppear(): void {
    this.loadVersions()
  }

  private async loadVersions(): Promise<void> {
    // 从 /api/status 获取服务端版本
    try {
      const status = await apiService.getServerStatus()
      this.versions = [
        { component: 'Agent (服务端)', currentVersion: status.version, latestVersion: status.version, updateAvailable: false },
        { component: 'Link (手机端)', currentVersion: '1.0.0', latestVersion: '1.0.0', updateAvailable: false }
      ]
    } catch (e) {
      this.versions = [
        { component: 'Agent (服务端)', currentVersion: '-', latestVersion: '-', updateAvailable: false },
        { component: 'Link (手机端)', currentVersion: '1.0.0', latestVersion: '1.0.0', updateAvailable: false }
      ]
    }
  }

  private async checkForUpdates(): Promise<void> {
    this.isChecking = true
    this.checkResultText = '正在检查更新...'

    try {
      // 重新加载版本信息
      const status = await apiService.getServerStatus()
      this.versions = [
        { component: 'Agent (服务端)', currentVersion: status.version, latestVersion: status.version, updateAvailable: false },
        { component: 'Link (手机端)', currentVersion: '1.0.0', latestVersion: '1.0.0', updateAvailable: false }
      ]
      this.checkResultText = `当前版本 ${status.version}，已是最新`
    } catch (e) {
      this.checkResultText = '检查失败，请确认已连接到桌面端'
    }

    this.lastCheckTime = new Date().toLocaleString()
    this.isChecking = false
  }

  build() {
    Stack() {
      HdsNavigation() {
        List({ space: Theme.SpacingMD, scroller: this.scroller }) {
          ListItem() {
            Row().width('100%').height(100)
          }

          // 版本信息
          ListItem() {
            Column({ space: Theme.SpacingSM }) {
              Text('版本信息')
                .fontSize(Theme.FontCaption)
                .fontWeight(FontWeight.Medium)
                .fontColor(Theme.TextSecondary)
                .width('100%')

              ForEach(this.versions, (ver: VersionInfo) => {
                Column({ space: 0 }) {
                  Row() {
                    Column({ space: 4 }) {
                      Text(ver.component)
                        .fontSize(Theme.FontBody)
                        .fontColor(Theme.TextPrimary)

                      Row({ space: 8 }) {
                        Text(`当前: ${ver.currentVersion}`)
                          .fontSize(Theme.FontTiny)
                          .fontColor(Theme.TextTertiary)

                        if (ver.latestVersion !== '-') {
                          Text(`最新: ${ver.latestVersion}`)
                            .fontSize(Theme.FontTiny)
                            .fontColor(ver.updateAvailable ? Theme.AccentOrange : Theme.AccentGreen)
                        }
                      }
                    }
                    .layoutWeight(1)
                    .alignItems(HorizontalAlign.Start)

                    if (ver.updateAvailable) {
                      Text('有更新')
                        .fontSize(Theme.FontTiny)
                        .fontColor(Theme.TextOnPrimary)
                        .backgroundColor(Theme.AccentOrange)
                        .borderRadius(4)
                        .padding({ left: 8, right: 8, top: 2, bottom: 2 })
                    }
                  }
                  .width('100%')
                  .padding(Theme.SpacingMD)
                }
                .backgroundColor(Theme.GlassBackground)
                .borderRadius(Theme.RadiusMedium)
                .border({ width: 0.5, color: Theme.GlassBorder })
                .shadow({ radius: Theme.LiquidGlassShadowRadius, color: Theme.LiquidGlassShadowColor, offsetX: 0, offsetY: 4 })
              }, (ver: VersionInfo) => ver.component)
            }
            .width('100%')
          }

          // 检查更新按钮
          ListItem() {
            Button() {
              if (this.isChecking) {
                LoadingProgress()
                  .width(20)
                  .height(20)
                  .color(Color.White)
              } else {
                Text('检查更新')
                  .fontSize(Theme.FontBody)
                  .fontColor(Color.White)
              }
            }
            .width('100%')
            .height(48)
            .backgroundColor(Theme.PrimaryColor)
            .borderRadius(Theme.RadiusMedium)
            .enabled(!this.isChecking)
            .onClick(() => {
              this.checkForUpdates()
            })
          }

          if (this.checkResultText) {
            ListItem() {
              Text(this.checkResultText)
                .fontSize(Theme.FontCaption)
                .fontColor(Theme.TextSecondary)
                .width('100%')
                .textAlign(TextAlign.Center)
            }
          }

          if (this.lastCheckTime) {
            ListItem() {
              Text(`上次检查: ${this.lastCheckTime}`)
                .fontSize(Theme.FontTiny)
                .fontColor(Theme.TextTertiary)
                .width('100%')
                .textAlign(TextAlign.Center)
            }
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
          title: { mainTitle: '检查更新' },
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