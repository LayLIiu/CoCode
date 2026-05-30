/**
 * 连接详情页面 - 展示服务器连接详情和管理
 */

import { Theme } from '../common/Theme'
import { authStore } from '../stores/AuthStore'
import { appState } from '../stores/AppState'
import { ServerProfile } from '../models/Models'
import { HdsNavigation, ScrollEffectType, HdsNavigationTitleMode } from '@hms.hds.hdsBaseComponent'
import { hdsMaterial } from '@hms.hds.hdsMaterial'
import router from '@ohos.router'
import { openScanner } from '../services/ScanService'
import { connectionManager, ConnectionType, ConnectionQuality } from '../services/ConnectionManager'

@Entry
@Component
struct ConnectionDetailPage {
  @State serverProfiles: ServerProfile[] = []
  @State activeProfileId: string = ''
  @State currentUrl: string = ''
  @State connectionType: ConnectionType = 'unknown'
  @State connectionQuality: ConnectionQuality = 'unavailable'
  @State connectionLatency: number = -1
  @State testingLatency: boolean = false
  @State showAddProfileSheet: boolean = false
  @State newProfileUrl: string = ''
  @State newProfileName: string = ''
  @State showDeleteConfirm: boolean = false
  @State deleteProfileId: string = ''

  aboutToAppear(): void {
    this.loadSettings()
    this.updateConnectionStatus()
  }

  private loadSettings(): void {
    this.serverProfiles = [...authStore.serverProfiles]
    this.activeProfileId = authStore.activeProfileId
    this.currentUrl = authStore.serverUrl
  }

  private updateConnectionStatus(): void {
    const status = connectionManager.getStatus()
    if (status) {
      this.connectionType = status.type
      this.connectionQuality = status.quality
      this.connectionLatency = status.latency
    }
  }

  build() {
    Stack() {
      HdsNavigation() {
        List({ space: Theme.SpacingMD }) {
          // 顶部留白
          ListItem() {
            Row().width('100%').height(92)
          }

          // 连接状态概览
          ListItem() {
            this.ConnectionOverviewCard()
          }

          // 服务器列表
          ListItem() {
            this.ServerListSection()
          }

          // 添加服务器
          ListItem() {
            this.AddServerSection()
          }

          // 底部留白
          ListItem() {
            Row().width('100%').height(Theme.SpacingXL)
          }
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: Theme.SpacingLG, right: Theme.SpacingLG })
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
      }
      .titleBar({
        content: {
          title: { mainTitle: '连接管理' },
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
      .titleMode(HdsNavigationTitleMode.MINI)
      .backgroundColor('#101114')
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

      // 添加配置 Sheet
      Column()
        .width(0).height(0)
        .bindSheet($$this.showAddProfileSheet, this.AddProfileSheet(), {
          height: 320,
          backgroundColor: Theme.BackgroundSecondary,
          dragBar: true,
          showClose: false,
          blurStyle: BlurStyle.COMPONENT_THICK
        })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  ConnectionOverviewCard() {
    Column({ space: Theme.SpacingMD }) {
      // 连接状态图标和文字
      Row({ space: 16 }) {
        // 状态图标
        SymbolGlyph(this.connectionQuality === 'good' ? $r('sys.symbol.wifi') :
          this.connectionQuality === 'poor' ? $r('sys.symbol.wifi') :
            $r('sys.symbol.wifi_slash'))
          .fontSize(36)
          .fontColor([this.currentUrl ? this.getConnectionQualityColor() : Theme.TextTertiary])

        Column({ space: 6 }) {
          Text(this.currentUrl ? '已连接' : '未连接')
            .fontSize(Theme.FontHeading)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.currentUrl ? Theme.TextPrimary : Theme.TextSecondary)

          if (this.currentUrl) {
            Text(this.getConnectionSummaryText())
              .fontSize(Theme.FontCaption)
              .fontColor(Theme.TextSecondary)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          } else {
            Text('请添加服务器地址')
              .fontSize(Theme.FontCaption)
              .fontColor(Theme.TextTertiary)
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')

      // 连接指标
      if (this.currentUrl) {
        Row({ space: 8 }) {
          this.ConnectionMetric('方式', this.connectionType !== 'unknown' ? this.getConnectionTypeText() : '未知',
            this.getConnectionTypeColor(), this.getConnectionTypeBackground())
          this.ConnectionMetric('质量', this.getQualityText(),
            this.getConnectionQualityColor(), this.getConnectionQualityBackground())
          this.LatencyMetric()
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding(Theme.SpacingLG)
    .backgroundColor('rgba(255, 255, 255, 0.055)')
    .borderRadius(Theme.RadiusLarge)
    .border({ width: 0.5, color: 'rgba(255, 255, 255, 0.09)' })
  }

  @Builder
  ServerListSection() {
    Column({ space: Theme.SpacingSM }) {
      Text('服务器列表')
        .fontSize(Theme.FontBody)
        .fontWeight(FontWeight.Medium)
        .fontColor(Theme.TextSecondary)
        .width('100%')
        .padding({ top: Theme.SpacingSM })

      if (this.serverProfiles.length > 0) {
        Column({ space: 0 }) {
          ForEach(this.serverProfiles, (profile: ServerProfile, index: number) => {
            Column() {
              Row() {
                // 类型指示条
                Row()
                  .width(3)
                  .height(36)
                  .borderRadius(2)
                  .backgroundColor(this.activeProfileId === profile.id ?
                    this.getProfileTypeColor(profile.type) : 'rgba(255, 255, 255, 0.08)')
                  .margin({ right: 10 })

                // 类型图标
                SymbolGlyph(this.getProfileIcon(profile.type))
                  .fontSize(18)
                  .fontColor([this.activeProfileId === profile.id ?
                    this.getProfileTypeColor(profile.type) : Theme.TextSecondary])
                  .margin({ right: 12 })

                Column({ space: 2 }) {
                  Text(profile.name)
                    .fontSize(Theme.FontBody)
                    .fontWeight(this.activeProfileId === profile.id ? FontWeight.Bold : FontWeight.Normal)
                    .fontColor(Theme.TextPrimary)

                  Text(profile.url)
                    .fontSize(Theme.FontTiny)
                    .fontColor(Theme.TextTertiary)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)

                // 活跃指示
                if (this.activeProfileId === profile.id) {
                  Text('使用中')
                    .fontSize(Theme.FontTiny)
                    .fontColor(Theme.PrimaryColor)
                    .backgroundColor('rgba(10, 132, 255, 0.14)')
                    .borderRadius(4)
                    .padding({ left: 8, right: 8, top: 2, bottom: 2 })
                }

                SymbolGlyph($r('sys.symbol.chevron_right'))
                  .fontSize(12)
                  .fontColor([Theme.TextTertiary])
              }
              .width('100%')
              .padding({ top: 12, bottom: 12, left: Theme.SpacingMD, right: Theme.SpacingMD })
              .onClick(() => {
                this.switchProfile(profile.id)
              })

              if (index < this.serverProfiles.length - 1) {
                Divider()
                  .color('rgba(255, 255, 255, 0.06)')
                  .margin({ left: 45 })
              }
            }
          }, (profile: ServerProfile) => profile.id)
        }
        .width('100%')
        .backgroundColor(Theme.GlassBackground)
        .borderRadius(Theme.RadiusMedium)
        .border({ width: 0.5, color: Theme.GlassBorder })
      } else {
        Text('暂无服务器，请添加')
          .fontSize(Theme.FontCaption)
          .fontColor(Theme.TextTertiary)
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding(Theme.SpacingLG)
      }
    }
    .width('100%')
  }

  @Builder
  AddServerSection() {
    Column({ space: Theme.SpacingMD }) {
      Row({ space: 12 }) {
        // 扫码添加
        Row({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.qrcode'))
            .fontSize(20)
            .fontColor([Theme.PrimaryColor])

          Text('扫码添加')
            .fontSize(Theme.FontBody)
            .fontColor(Theme.PrimaryColor)
        }
        .layoutWeight(1)
        .height(52)
        .justifyContent(FlexAlign.Center)
        .backgroundColor('rgba(10, 132, 255, 0.12)')
        .borderRadius(Theme.RadiusMedium)
        .onClick(async () => {
          const result = await openScanner()
          if (result?.bestUrl) {
            this.newProfileName = ''
            this.newProfileUrl = result.bestUrl
            this.showAddProfileSheet = true
          }
        })

        // 手动输入
        Row({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.square_and_pencil'))
            .fontSize(20)
            .fontColor([Theme.PrimaryColor])

          Text('手动输入')
            .fontSize(Theme.FontBody)
            .fontColor(Theme.PrimaryColor)
        }
        .layoutWeight(1)
        .height(52)
        .justifyContent(FlexAlign.Center)
        .backgroundColor('rgba(10, 132, 255, 0.12)')
        .borderRadius(Theme.RadiusMedium)
        .onClick(() => {
          this.newProfileUrl = ''
          this.newProfileName = ''
          this.showAddProfileSheet = true
        })
      }
      .width('100%')

      // 移除按钮
      if (this.serverProfiles.length > 0 && this.activeProfileId) {
        Button() {
          Row({ space: 8 }) {
            SymbolGlyph($r('sys.symbol.trash'))
              .fontSize(16)
              .fontColor([Theme.ErrorColor])

            Text('移除当前服务器')
              .fontSize(Theme.FontBody)
              .fontColor(Theme.ErrorColor)
          }
        }
        .width('100%')
        .height(52)
        .backgroundColor('rgba(255, 59, 48, 0.12)')
        .borderRadius(Theme.RadiusMedium)
        .onClick(() => {
          if (this.activeProfileId) {
            this.showDeleteProfileDialog(this.activeProfileId)
          }
        })
      }
    }
    .width('100%')
  }

  @Builder
  ConnectionMetric(label: string, value: string, color: ResourceColor, bgColor: string) {
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
    .backgroundColor(bgColor)
    .borderRadius(10)
  }

  @Builder
  LatencyMetric() {
    Column({ space: 4 }) {
      Text('延迟')
        .fontSize(11)
        .fontColor(Theme.TextTertiary)

      Text(this.testingLatency ? '检测中' :
        (this.connectionLatency > 0 ? this.formatLatency(this.connectionLatency) : '未检测'))
        .fontSize(Theme.FontTiny)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.testingLatency ? Theme.PrimaryColor :
          (this.connectionLatency > 0 ? this.getLatencyColor(this.connectionLatency) : Theme.TextTertiary))
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

  @Builder
  AddProfileSheet() {
    Column() {
      Text('添加服务器')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(Theme.TextPrimary)
        .width('100%')
        .textAlign(TextAlign.Center)
        .padding({ top: Theme.SpacingLG, bottom: Theme.SpacingMD })

      TextInput({ placeholder: '名称（如：家里、办公室）', text: this.newProfileName })
        .width('100%')
        .height(44)
        .backgroundColor(Theme.GlassBackground)
        .borderRadius(8)
        .fontColor(Theme.TextPrimary)
        .border({ width: 1, color: Theme.GlassBorder })
        .padding({ left: 12, right: 12 })
        .margin({ bottom: Theme.SpacingSM })
        .backgroundBlurStyle(BlurStyle.COMPONENT_REGULAR)
        .onChange((value: string) => {
          this.newProfileName = value
        })

      Row({ space: 8 }) {
        TextInput({ placeholder: 'http://192.168.x.x:3456', text: this.newProfileUrl })
          .layoutWeight(1)
          .height(44)
          .backgroundColor(Theme.GlassBackground)
          .borderRadius(8)
          .fontColor(Theme.TextPrimary)
          .border({ width: 1, color: Theme.GlassBorder })
          .padding({ left: 12, right: 12 })
          .backgroundBlurStyle(BlurStyle.COMPONENT_REGULAR)
          .onChange((value: string) => {
            this.newProfileUrl = value
          })

        Button() {
          SymbolGlyph($r('sys.symbol.qrcode'))
            .fontSize(20)
            .fontColor([Theme.TextOnPrimary])
        }
        .width(44)
        .height(44)
        .backgroundColor(Theme.PrimaryColor)
        .borderRadius(8)
        .onClick(async () => {
          const result = await openScanner()
          if (result?.bestUrl) {
            this.newProfileUrl = result.bestUrl
            if (result.e2eePub) {
              authStore.setRelayE2EEPubKey(result.e2eePub)
            }
            if (result.lan && result.lan !== result.bestUrl) {
              authStore.addFromLogin(result.lan, 'lan')
            }
            if (result.pgy && result.pgy !== result.bestUrl) {
              authStore.addFromLogin(result.pgy, 'pgy')
            }
            if (result.tunnel && result.tunnel !== result.bestUrl) {
              authStore.addFromLogin(result.tunnel, 'tunnel')
            }
            if (result.cloudRelay && result.cloudRelay !== result.bestUrl) {
              authStore.addFromLogin(result.cloudRelay, 'cloud_relay')
            }
          }
        })
      }
      .width('100%')

      Text('输入桌面端的服务器地址')
        .fontSize(Theme.FontCaption)
        .fontColor(Theme.TextSecondary)
        .width('100%')
        .textAlign(TextAlign.Start)
        .margin({ top: Theme.SpacingSM })

      Row({ space: Theme.SpacingMD }) {
        Button('取消')
          .layoutWeight(1)
          .height(44)
          .backgroundColor(Theme.GlassBackground)
          .fontColor(Theme.TextPrimary)
          .borderRadius(8)
          .backgroundBlurStyle(BlurStyle.COMPONENT_REGULAR)
          .onClick(() => {
            this.showAddProfileSheet = false
          })

        Button('添加')
          .layoutWeight(1)
          .height(44)
          .backgroundColor(Theme.PrimaryColor)
          .fontColor(Theme.TextOnPrimary)
          .borderRadius(8)
          .backgroundBlurStyle(BlurStyle.COMPONENT_REGULAR)
          .enabled(this.newProfileUrl.length > 0)
          .onClick(async () => {
            const name = this.newProfileName.trim() || `服务器 ${this.serverProfiles.length + 1}`
            await authStore.addFromLogin(this.newProfileUrl)
            this.serverProfiles = [...authStore.serverProfiles]
            this.activeProfileId = authStore.activeProfileId
            this.currentUrl = authStore.serverUrl
            this.showAddProfileSheet = false
          })
      }
      .width('100%')
      .padding({ left: Theme.SpacingLG, right: Theme.SpacingLG, top: Theme.SpacingLG })
    }
    .width('100%')
    .padding({ left: Theme.SpacingLG, right: Theme.SpacingLG })
  }

  // MARK: - Helper Methods

  private async switchProfile(id: string): Promise<void> {
    await authStore.switchProfile(id)
    this.serverProfiles = [...authStore.serverProfiles]
    this.activeProfileId = authStore.activeProfileId
    this.currentUrl = authStore.serverUrl
    this.updateConnectionStatus()
  }

  private showDeleteProfileDialog(id: string): void {
    const profile = this.serverProfiles.find(p => p.id === id)
    AlertDialog.show({
      title: '移除服务器',
      message: `确定要移除 "${profile?.name || ''}" 吗？`,
      primaryButton: {
        value: '取消',
        action: () => {}
      },
      secondaryButton: {
        value: '移除',
        fontColor: Theme.ErrorColor,
        action: async () => {
          await authStore.removeProfile(id)
          this.serverProfiles = [...authStore.serverProfiles]
          this.activeProfileId = authStore.activeProfileId
          this.currentUrl = authStore.serverUrl
        }
      }
    })
  }

  private getConnectionSummaryText(): string {
    const profileName = this.getProfileDisplayName()
    return profileName || '已连接'
  }

  private getProfileDisplayName(): string {
    const profile = this.serverProfiles.find(p => p.id === this.activeProfileId)
    return profile ? `${profile.name} (${this.getProfileTypeLabel(profile.type)})` : ''
  }

  private getProfileTypeLabel(type: string): string {
    switch (type) {
      case 'lan': return '局域网'
      case 'pgy': return '蒲公英'
      case 'tunnel': return '公网隧道'
      case 'cloud_relay': return '云中继'
      default: return type
    }
  }

  private getProfileTypeColor(type: string): ResourceColor {
    switch (type) {
      case 'lan':
      case 'pgy': return Theme.AccentGreen
      case 'cloud_relay': return Theme.AccentBlue
      case 'tunnel': return Theme.AccentPurple
      default: return Theme.TextSecondary
    }
  }

  private getProfileIcon(type: string): Resource {
    switch (type) {
      case 'lan': return $r('sys.symbol.gearshape')
      case 'pgy': return $r('sys.symbol.questionmark_circle')
      case 'tunnel': return $r('sys.symbol.chevron_right')
      case 'cloud_relay': return $r('sys.symbol.cloud')
      default: return $r('sys.symbol.questionmark_circle')
    }
  }

  private getConnectionTypeText(): string {
    switch (this.connectionType) {
      case 'lan':
      case 'pgy': return '局域网'
      case 'tunnel': return '远程隧道'
      case 'cloud_relay': return '云中继'
      default: return '未知'
    }
  }

  private getConnectionTypeColor(): ResourceColor {
    switch (this.connectionType) {
      case 'lan':
      case 'pgy': return Theme.AccentGreen
      case 'cloud_relay': return Theme.AccentBlue
      case 'tunnel': return Theme.AccentPurple
      default: return Theme.TextSecondary
    }
  }

  private getConnectionTypeBackground(): string {
    switch (this.connectionType) {
      case 'lan':
      case 'pgy': return 'rgba(48, 209, 88, 0.14)'
      case 'cloud_relay': return 'rgba(10, 132, 255, 0.14)'
      case 'tunnel': return 'rgba(191, 90, 242, 0.14)'
      default: return 'rgba(255, 255, 255, 0.055)'
    }
  }

  private getQualityText(): string {
    switch (this.connectionQuality) {
      case 'good': return '良好'
      case 'poor': return '较差'
      default: return '一般'
    }
  }

  private getConnectionQualityColor(): ResourceColor {
    switch (this.connectionQuality) {
      case 'good': return Theme.SuccessColor
      case 'poor': return Theme.WarningColor
      default: return Theme.TextSecondary
    }
  }

  private getConnectionQualityBackground(): string {
    switch (this.connectionQuality) {
      case 'good': return 'rgba(48, 209, 88, 0.14)'
      case 'poor': return 'rgba(255, 159, 10, 0.14)'
      default: return 'rgba(255, 255, 255, 0.055)'
    }
  }

  private formatLatency(ms: number): string {
    if (ms < 100) return `${ms}ms`
    if (ms < 300) return `${ms}ms`
    if (ms < 500) return `${ms}ms`
    return `${ms}ms`
  }

  private getLatencyColor(ms: number): ResourceColor {
    if (ms < 0) return Theme.ErrorColor
    if (ms < 100) return '#22c55e'
    if (ms < 300) return '#84cc16'
    if (ms < 500) return '#eab308'
    return '#f97316'
  }
}

export default ConnectionDetailPage
