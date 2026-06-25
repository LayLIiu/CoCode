/**
 * 设置页面 - 与 iOS 端保持一致的实现
 */

import { Theme } from '../common/Theme'
import { authStore } from '../stores/AuthStore'
import { appState, ThemeMode } from '../stores/AppState'
import { sessionStore } from '../stores/SessionStore'
import { ServerMode, ServerProfile } from '../models/Models'
import { HdsNavigation, ScrollEffectType, HdsNavigationTitleMode } from '@hms.hds.hdsBaseComponent'
import { hdsMaterial } from '@hms.hds.hdsMaterial'
import router from '@ohos.router'
import http from '@ohos.net.http'
import { openScanner } from '../services/ScanService'
import { connectionManager, ConnectionType, ConnectionQuality } from '../services/ConnectionManager'


@Component
export struct SettingsPage {
  @State isDarkMode: boolean = true
  @State serverMode: ServerMode = 'lan'
  @State isLoggedIn: boolean = false
  @State lanUrl: string = ''
  @State tunnelUrl: string = ''
  @State currentUrl: string = ''
  @State userName: string = ''
  @State testingLatency: boolean = false
  @State latency: number = 0
  @State showLanEdit: boolean = false
  @State showTunnelEdit: boolean = false
  @State editType: string = '' // 'lan' or 'tunnel'
  @State showEditSheet: boolean = false
  @State showThemeSheet: boolean = false
  @State editUrl: string = ''
  @State themeMode: ThemeMode = 'dark'

  // 生物识别
  @State biometricEnabled: boolean = true

  // 多服务器配置
  @State serverProfiles: ServerProfile[] = []
  @State activeProfileId: string = ''
  @State showAddProfileSheet: boolean = false
  @State newProfileUrl: string = ''
  @State newProfileName: string = ''
  @State showDeleteConfirm: boolean = false
  @State deleteProfileId: string = ''

  // 智能连接状态
  @State connectionType: ConnectionType = 'unknown'
  @State connectionQuality: ConnectionQuality = 'unavailable'
  @State connectionLatency: number = -1

  private readonly appVersion: string = '1.0.0'
  private readonly buildTime: string = '2026-06-25'

  aboutToAppear(): void {
    this.loadSettings()
    this.updateConnectionStatus()
  }

  aboutToDisappear(): void {
  }

  private updateConnectionStatus(): void {
    const status = connectionManager.getStatus()
    if (status) {
      this.connectionType = status.type
      this.connectionQuality = status.quality
      this.connectionLatency = status.latency
    }
  }

  private loadSettings(): void {
    this.isLoggedIn = authStore.isLoggedIn
    this.lanUrl = authStore.lanUrl
    this.tunnelUrl = authStore.tunnelUrl
    this.serverMode = authStore.serverMode
    this.currentUrl = authStore.serverUrl
    this.userName = '用户' // 可以从服务器获取
    this.themeMode = appState.themeMode

    // 加载多服务器配置
    this.serverProfiles = [...authStore.serverProfiles]
    this.activeProfileId = authStore.activeProfileId

    // 加载生物识别设置
    this.biometricEnabled = authStore.biometricEnabled
  }

  build() {
    Stack() {
      HdsNavigation() {
        List({ space: Theme.SpacingMD }) {
          // 顶部留白
          ListItem() {
            Row().width('100%').height(92)
          }

          // 账户
          ListItem() {
            this.SettingSection('账户')
          }

          ListItem() {
            this.AccountItem()
          }

          // 连接设置
          ListItem() {
            this.SettingSection('连接')
          }

          ListItem() {
            this.ConnectionItem()
          }

          // 高级
          if (this.isLoggedIn) {
            ListItem() {
              this.SettingSection('高级')
            }

            ListItem() {
              this.StorageManageItem()
            }
          }

          // 退出登录
          if (this.isLoggedIn) {
            ListItem() {
              this.LogoutButton()
            }
          }

          // 底部信息
          ListItem() {
            this.FooterView()
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
          title: { mainTitle: '设置' },
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
      .hideBackButton(true)
      .backgroundColor('#000000')
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

      // 编辑 Sheet（独立 Column 避免多个 bindSheet 冲突）
      Column()
        .width(0).height(0)
        .bindSheet($$this.showEditSheet, this.editType === 'lan' ? this.LanEditSheet() : this.TunnelEditSheet(), {
          height: 280,
          backgroundColor: Theme.BackgroundSecondary,
          dragBar: true,
          showClose: false,
          blurStyle: BlurStyle.COMPONENT_THICK
        })

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
  SettingSection(title: string) {
    Row() {
      Text(title)
        .fontSize(Theme.FontCaption)
        .fontWeight(FontWeight.Medium)
        .fontColor(Theme.TextSecondary)

      Row()
        .height(1)
        .layoutWeight(1)
        .backgroundColor('rgba(255, 255, 255, 0.06)')
        .margin({ left: Theme.SpacingMD })
    }
      .width('100%')
      .padding({ top: Theme.SpacingSM, bottom: Theme.SpacingXS })
  }

  @Builder
  AccountItem() {
    Column({ space: Theme.SpacingSM }) {
      Row() {
        Text('用户')
          .fontSize(Theme.FontBody)
          .fontColor(Theme.TextPrimary)

        Blank()

        Text(this.userName)
          .fontSize(Theme.FontBody)
          .fontColor(Theme.TextSecondary)

        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(14)
          .fontColor([Theme.TextSecondary])
          .margin({ left: 8 })
      }
      .width('100%')
      .onClick(() => {
        router.pushUrl({ url: 'pages/ProfilePage' })
      })

    }
    .width('100%')
    .padding(Theme.SpacingMD)
    .backgroundColor(Theme.GlassBackground)
    .borderRadius(Theme.RadiusMedium)
    .border({ width: 0.5, color: Theme.GlassBorder })
    .shadow({ radius: Theme.LiquidGlassShadowRadius, color: Theme.LiquidGlassShadowColor, offsetX: 0, offsetY: 4 })
  }

  @Builder
  ConnectionItem() {
    Column({ space: Theme.SpacingMD }) {
      Row({ space: 12 }) {
        // WiFi 图标
        SymbolGlyph(this.currentUrl ? $r('sys.symbol.wifi') : $r('sys.symbol.wifi_slash'))
          .fontSize(28)
          .fontColor([this.currentUrl ? Theme.SuccessColor : Theme.TextTertiary])

        Column({ space: 4 }) {
          Text(this.currentUrl ? '已连接' : '未连接')
            .fontSize(Theme.FontBody)
            .fontWeight(FontWeight.Medium)
            .fontColor(Theme.TextPrimary)

          if (this.currentUrl) {
            Text(this.getProfileDisplayName())
              .fontSize(Theme.FontCaption)
              .fontColor(Theme.TextSecondary)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          } else {
            Text('点击添加服务器')
              .fontSize(Theme.FontCaption)
              .fontColor(Theme.TextTertiary)
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(14)
          .fontColor([Theme.TextSecondary])
      }
      .width('100%')
      .onClick(() => {
        router.pushUrl({ url: 'pages/ConnectionDetailPage' })
      })

      // 分隔线
      Divider()
        .color('rgba(255, 255, 255, 0.08)')

      Row({ space: 12 }) {
        // 测速图标
        SymbolGlyph($r('sys.symbol.clock'))
          .fontSize(28)
          .fontColor([this.testingLatency ? Theme.PrimaryColor : Theme.TextSecondary])

        Column({ space: 4 }) {
          Text('延迟测速')
            .fontSize(Theme.FontBody)
            .fontWeight(FontWeight.Medium)
            .fontColor(Theme.TextPrimary)

          Row({ space: 6 }) {
            if (this.testingLatency) {
              Text('检测中...')
                .fontSize(Theme.FontCaption)
                .fontColor(Theme.PrimaryColor)
            } else if (this.connectionLatency > 0) {
              Text(this.formatLatency(this.connectionLatency))
                .fontSize(Theme.FontCaption)
                .fontColor(this.getLatencyColor(this.connectionLatency))

              if (this.connectionType !== 'unknown') {
                Text('·')
                  .fontSize(Theme.FontCaption)
                  .fontColor(Theme.TextTertiary)

                Text(this.getConnectionTypeText())
                  .fontSize(Theme.FontCaption)
                  .fontColor(Theme.TextSecondary)
              }
            } else {
              Text('点击测速')
                .fontSize(Theme.FontCaption)
                .fontColor(Theme.TextTertiary)
            }
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        // 测速按钮
        Button() {
          if (this.testingLatency) {
            LoadingProgress()
              .width(16)
              .height(16)
              .color(Theme.TextOnPrimary)
          } else {
            Text('测速')
              .fontSize(Theme.FontTiny)
              .fontColor(Theme.TextOnPrimary)
          }
        }
        .height(32)
        .padding({ left: 14, right: 14 })
        .backgroundColor(this.currentUrl ? Theme.PrimaryColor : Theme.BackgroundTertiary)
        .borderRadius(8)
        .enabled(!this.testingLatency && this.currentUrl.length > 0)
        .onClick(() => {
          if (!this.testingLatency && this.currentUrl.length > 0) {
            this.testSmartConnection()
          }
        })
      }
      .width('100%')
    }
    .width('100%')
    .padding(Theme.SpacingMD)
    .backgroundColor(Theme.GlassBackground)
    .borderRadius(Theme.RadiusMedium)
    .border({ width: 0.5, color: Theme.GlassBorder })
  }

  @Builder
  LogoutButton() {
    Button('退出登录')
      .width('100%')
      .height(48)
      .fontSize(Theme.FontBody)
      .fontColor(Color.White)
      .backgroundColor(Theme.ErrorColor)
      .borderRadius(Theme.RadiusMedium)
      .backgroundBlurStyle(BlurStyle.COMPONENT_REGULAR)
      .onClick(() => {
        this.logout()
      })
  }

  @Builder
  FooterView() {
    Column({ space: 8 }) {
      Text(`Claude Code HarmonyOS v${this.appVersion} (${this.buildTime})`)
        .fontSize(Theme.FontCaption)
        .fontColor(Theme.TextTertiary)
        .width('100%')
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .padding({ top: Theme.SpacingXL, bottom: Theme.SpacingXL })
  }

  @Builder
  LanEditSheet() {
    Column() {
      Text('局域网地址')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(Theme.TextPrimary)
        .width('100%')
        .textAlign(TextAlign.Center)
        .padding({ top: Theme.SpacingLG, bottom: Theme.SpacingMD })

      TextInput({ placeholder: 'http://192.168.x.x:3456', text: this.editUrl })
        .width('100%')
        .height(44)
        .backgroundColor(Theme.GlassBackground)
        .borderRadius(8)
        .fontColor(Theme.TextPrimary)
        .border({ width: 1, color: Theme.GlassBorder })
        .padding({ left: 12, right: 12 })
        .margin({ left: Theme.SpacingLG, right: Theme.SpacingLG })
        .backgroundBlurStyle(BlurStyle.COMPONENT_REGULAR)
        .onChange((value: string) => {
          this.editUrl = value
        })

      Text('输入桌面端的地址')
        .fontSize(Theme.FontCaption)
        .fontColor(Theme.TextSecondary)
        .width('100%')
        .textAlign(TextAlign.Start)
        .margin({ left: Theme.SpacingLG, top: Theme.SpacingSM })

      Row({ space: Theme.SpacingMD }) {
        Button('取消')
          .layoutWeight(1)
          .height(44)
          .backgroundColor(Theme.GlassBackground)
          .fontColor(Theme.TextPrimary)
          .borderRadius(8)
          .backgroundBlurStyle(BlurStyle.COMPONENT_REGULAR)
          .onClick(() => {
            this.showEditSheet = false
          })

        Button('保存')
          .layoutWeight(1)
          .height(44)
          .backgroundColor(Theme.PrimaryColor)
          .fontColor(Theme.TextOnPrimary)
          .borderRadius(8)
          .backgroundBlurStyle(BlurStyle.COMPONENT_REGULAR)
          .enabled(this.editUrl.length > 0)
          .onClick(() => {
            this.lanUrl = this.editUrl
            authStore.setLanUrl(this.editUrl)
            this.showEditSheet = false
          })
      }
      .width('100%')
      .padding({ left: Theme.SpacingLG, right: Theme.SpacingLG, top: Theme.SpacingLG })
    }
  }

  @Builder
  TunnelEditSheet() {
    Column() {
      Text('公网地址')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(Theme.TextPrimary)
        .width('100%')
        .textAlign(TextAlign.Center)
        .padding({ top: Theme.SpacingLG, bottom: Theme.SpacingMD })

      TextInput({ placeholder: 'https://xxx.trycloudflare.com', text: this.editUrl })
        .width('100%')
        .height(44)
        .backgroundColor(Theme.GlassBackground)
        .borderRadius(8)
        .fontColor(Theme.TextPrimary)
        .border({ width: 1, color: Theme.GlassBorder })
        .padding({ left: 12, right: 12 })
        .margin({ left: Theme.SpacingLG, right: Theme.SpacingLG })
        .backgroundBlurStyle(BlurStyle.COMPONENT_REGULAR)
        .onChange((value: string) => {
          this.editUrl = value
        })

      Text('输入桌面端的公网地址')
        .fontSize(Theme.FontCaption)
        .fontColor(Theme.TextSecondary)
        .width('100%')
        .textAlign(TextAlign.Start)
        .margin({ left: Theme.SpacingLG, top: Theme.SpacingSM })

      Row({ space: Theme.SpacingMD }) {
        Button('取消')
          .layoutWeight(1)
          .height(44)
          .backgroundColor(Theme.GlassBackground)
          .fontColor(Theme.TextPrimary)
          .borderRadius(8)
          .backgroundBlurStyle(BlurStyle.COMPONENT_REGULAR)
          .onClick(() => {
            this.showEditSheet = false
          })

        Button('保存')
          .layoutWeight(1)
          .height(44)
          .backgroundColor(Theme.PrimaryColor)
          .fontColor(Theme.TextOnPrimary)
          .borderRadius(8)
          .backgroundBlurStyle(BlurStyle.COMPONENT_REGULAR)
          .enabled(this.editUrl.length > 0)
          .onClick(() => {
            this.tunnelUrl = this.editUrl
            authStore.setTunnelUrl(this.editUrl)
            this.showEditSheet = false
          })
      }
      .width('100%')
      .padding({ left: Theme.SpacingLG, right: Theme.SpacingLG, top: Theme.SpacingLG })
    }
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
            // 保存 E2EE 公钥（用于云中继端到端加密）
            if (result.e2eePub) {
              authStore.setRelayE2EEPubKey(result.e2eePub)
              console.info('[Settings] 从二维码解析到 E2EE 公钥')
            }
            // 立即添加其他地址为独立配置
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

  @Builder
  StorageManageItem() {
    Row() {
      Column({ space: 2 }) {
        Text('存储管理')
          .fontSize(Theme.FontBody)
          .fontColor(Theme.TextPrimary)

        Text('查看存储使用情况、清除缓存')
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
      router.pushUrl({ url: 'pages/StorageManagementPage' })
    })
  }

  // MARK: - 多服务器配置

  private async switchProfile(id: string): Promise<void> {
    await authStore.switchProfile(id)
    this.serverProfiles = [...authStore.serverProfiles]
    this.activeProfileId = authStore.activeProfileId
    this.currentUrl = authStore.serverUrl
    this.latency = 0 // 切换后重置测速

    // 同步旧版字段
    const profile = authStore.activeProfile
    if (profile) {
      if (profile.type === 'tunnel') {
        this.tunnelUrl = profile.url
        this.serverMode = 'tunnel'
      } else {
        this.lanUrl = profile.url
        this.serverMode = 'lan'
      }
    }
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
      case 'tunnel': return $r('sys.symbol.square_and_pencil')
      case 'cloud_relay': return $r('sys.symbol.cloud')
      default: return $r('sys.symbol.questionmark_circle')
    }
  }

  private async setServerMode(mode: ServerMode): Promise<void> {
    this.serverMode = mode
    await authStore.setServerMode(mode)
    this.currentUrl = authStore.serverUrl
  }

  private async testLatency(): Promise<void> {
    if (this.currentUrl.length === 0) return

    this.testingLatency = true
    this.latency = 0

    const httpRequest = http.createHttp()
    try {
      const url = this.currentUrl + '/api/status'

      const startTime = Date.now()

      const response = await httpRequest.request(url, {
        method: http.RequestMethod.GET,
        connectTimeout: 15000,
        readTimeout: 15000
      })

      const endTime = Date.now()
      const duration = endTime - startTime

      if (response.responseCode === 200) {
        this.latency = duration
      } else {
        this.latency = -1 * response.responseCode
      }
    } catch (e) {
      this.latency = -1
    } finally {
      httpRequest.destroy()
    }

    this.testingLatency = false
  }

  private formatLatency(ms: number): string {
    if (ms <= -100) return `HTTP ${Math.abs(ms)} 错误`
    if (ms === -1) return '连接失败'
    if (ms < 100) return `${ms}ms (极快)`
    if (ms < 300) return `${ms}ms (很快)`
    if (ms < 500) return `${ms}ms (较快)`
    if (ms < 1000) return `${ms}ms (一般)`
    return `${ms}ms (较慢)`
  }

  private getLatencyColor(ms: number): ResourceColor {
    if (ms < 0) return Theme.ErrorColor
    if (ms < 100) return '#22c55e'
    if (ms < 300) return '#84cc16'
    if (ms < 500) return '#eab308'
    return '#f97316'
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

  private async logout(): Promise<void> {
    await authStore.logout()
    sessionStore.disconnectAllSessions()

    // 跳转到登录页面
    router.replaceUrl({
      url: 'pages/Index'
    })
  }

  // MARK: - 智能连接辅助方法

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

  private getConnectionQualityBackground(): string {
    switch (this.connectionQuality) {
      case 'good': return 'rgba(48, 209, 88, 0.14)'
      case 'poor': return 'rgba(255, 159, 10, 0.14)'
      default: return 'rgba(255, 255, 255, 0.055)'
    }
  }

  private getConnectionStatusText(): string {
    const profileName = this.getProfileDisplayName()
    const qualityText = this.getQualityText()
    return `${profileName} · ${qualityText}`
  }

  private getQualityText(): string {
    switch (this.connectionQuality) {
      case 'good': return '连接良好'
      case 'poor': return '连接较差'
      default: return '已连接'
    }
  }

  private getConnectionQualityColor(): ResourceColor {
    switch (this.connectionQuality) {
      case 'good': return Theme.SuccessColor
      case 'poor': return Theme.WarningColor
      default: return Theme.TextSecondary
    }
  }

  private async testSmartConnection(): Promise<void> {
    this.testingLatency = true
    this.connectionLatency = 0

    try {
      const status = await connectionManager.retestCurrentConnection()
      this.connectionType = status.type
      this.connectionQuality = status.quality
      this.connectionLatency = status.latency
      this.currentUrl = authStore.serverUrl
      this.serverProfiles = [...authStore.serverProfiles]
      this.activeProfileId = authStore.activeProfileId
    } catch (e) {
      console.error(`[Settings] Smart connect error: ${e}`)
      this.connectionLatency = -1
      this.connectionQuality = 'unavailable'
    }

    this.testingLatency = false
  }

}
