/**
 * 登录页面
 * 支持配对码连接和手动输入服务器地址
 */

import router from '@ohos.router'
import { Theme } from '../common/Theme'
import { authStore } from '../stores/AuthStore'
import { apiService } from '../services/APIService'
import { wsService } from '../services/WebSocketService'
import { User, DiscoveredServer } from '../models/Models'
import { mdnsDiscoveryService } from '../services/MdnsDiscoveryService'
import { openScanner } from '../services/ScanService'
import { connectionManager } from '../services/ConnectionManager'
import type { Context } from '@kit.AbilityKit'

type ConnectionMode = 'pairing' | 'manual'
type AccessMode = 'lan' | 'remote'

@Entry
@Component
export struct LoginPage {
  @State mode: ConnectionMode = 'manual'
  @State accessMode: AccessMode = 'lan'
  @State pairingCode: string = ''
  @State serverUrl: string = ''
  @State isConnecting: boolean = false
  @State errorMessage: string = ''
  @State discoveredServers: DiscoveredServer[] = []
  @State isSearching: boolean = false
  private scannedType: 'lan' | 'pgy' | 'tunnel' | 'cloud_relay' | null = null

  aboutToAppear(): void {
    this.startDiscovery()
  }

  aboutToDisappear(): void {
    mdnsDiscoveryService.stopDiscovery()
  }

  build() {
    Scroll() {
      Column({ space: 18 }) {
        this.LogoSection()
        this.AccessModeSelector()
        this.ModeSwitch()
        this.DiscoveredServersSection()

        if (this.mode === 'pairing') {
          this.PairingInput()
        } else {
          this.ManualInput()
        }

        this.Instructions()
      }
      .width('100%')
      .padding({ top: 52, bottom: 42 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#101114')
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
  }

  @Builder
  LogoSection() {
    Column({ space: 16 }) {
      Stack() {
        Circle()
          .width(78)
          .height(78)
          .fill('rgba(10, 132, 255, 0.14)')

        SymbolGlyph($r('sys.symbol.message_fill'))
          .fontSize(40)
          .fontColor([Theme.AccentBlue])
      }
      .width(78)
      .height(78)

      Text('远程工作台')
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
        .fontColor(Theme.TextPrimary)

      Text('连接桌面端后，在手机上继续处理会话和项目')
        .fontSize(16)
        .fontColor(Theme.TextSecondary)
        .textAlign(TextAlign.Center)
        .width('82%')

      Row({ space: 8 }) {
        this.LoginMetric('局域网', '低延迟', Theme.AccentGreen)
        this.LoginMetric('公网', '远程访问', Theme.AccentBlue)
      }
      .width('85%')
    }
    .width('100%')
  }

  @Builder
  LoginMetric(label: string, value: string, color: ResourceColor) {
    Column({ space: 3 }) {
      Text(label)
        .fontSize(11)
        .fontColor(Theme.TextTertiary)

      Text(value)
        .fontSize(Theme.FontTiny)
        .fontWeight(FontWeight.Medium)
        .fontColor(color)
    }
    .layoutWeight(1)
    .height(46)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor('rgba(255, 255, 255, 0.045)')
    .borderRadius(10)
  }

  @Builder
  AccessModeSelector() {
    Row({ space: 10 }) {
      this.AccessModeCard('lan', '局域网直连', '手机和电脑在同一个 Wi-Fi 下', $r('sys.symbol.wifi'), Theme.AccentGreen)
      this.AccessModeCard('remote', '公网访问', '外出时使用隧道或中继地址', $r('sys.symbol.cloud'), Theme.AccentBlue)
    }
    .width('85%')
    .alignSelf(ItemAlign.Center)
  }

  @Builder
  AccessModeCard(mode: AccessMode, title: string, desc: string, icon: Resource, color: ResourceColor) {
    Column({ space: 8 }) {
      Row() {
        SymbolGlyph(icon)
          .fontSize(22)
          .fontColor([this.accessMode === mode ? color : Theme.TextSecondary])

        Blank()

        Row()
          .width(8)
          .height(8)
          .borderRadius(4)
          .backgroundColor(this.accessMode === mode ? color : Theme.TextTertiary)
      }
      .width('100%')

      Text(title)
        .fontSize(Theme.FontCaption)
        .fontWeight(FontWeight.Bold)
        .fontColor(Theme.TextPrimary)
        .width('100%')

      Text(desc)
        .fontSize(11)
        .fontColor(Theme.TextTertiary)
        .lineHeight(16)
        .width('100%')
        .maxLines(2)
    }
    .layoutWeight(1)
    .height(116)
    .padding(Theme.SpacingMD)
    .backgroundColor(this.accessMode === mode ? 'rgba(255, 255, 255, 0.075)' : 'rgba(255, 255, 255, 0.045)')
    .border({
      width: 0.8,
      color: this.accessMode === mode ? color : 'rgba(255, 255, 255, 0.08)'
    })
    .borderRadius(Theme.RadiusLarge)
    .onClick(() => {
      this.accessMode = mode
      this.mode = mode === 'lan' ? 'manual' : 'pairing'
    })
  }

  @Builder
  ModeSwitch() {
    Row() {
      Button('配对连接')
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .layoutWeight(1)
        .height(44)
        .backgroundColor(this.mode === 'pairing' ? Theme.PrimaryColor : Theme.GlassBackground)
        .fontColor(this.mode === 'pairing' ? Theme.TextOnPrimary : Theme.TextSecondary)
        .borderRadius(8)
        .backgroundBlurStyle(BlurStyle.COMPONENT_REGULAR)
        .onClick(() => {
          this.mode = 'pairing'
        })

      Button('地址连接')
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .layoutWeight(1)
        .height(44)
        .backgroundColor(this.mode === 'manual' ? Theme.PrimaryColor : Theme.GlassBackground)
        .fontColor(this.mode === 'manual' ? Theme.TextOnPrimary : Theme.TextSecondary)
        .borderRadius(8)
        .backgroundBlurStyle(BlurStyle.COMPONENT_REGULAR)
        .onClick(() => {
          this.mode = 'manual'
        })
    }
    .width('85%')
    .backgroundColor(Theme.GlassBackground)
    .borderRadius(12)
    .border({ width: 0.5, color: Theme.GlassBorder })
    .shadow({ radius: Theme.LiquidGlassShadowRadius, color: Theme.LiquidGlassShadowColor, offsetX: 0, offsetY: 4 })
    .padding(4)
  }

  @Builder
  PairingInput() {
    Column({ space: 16 }) {
      Column({ space: 8 }) {
        Text(this.accessMode === 'remote' ? '公网连接串' : '配对连接串')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.TextPrimary)
          .width('85%')

        TextInput({ placeholder: this.accessMode === 'remote' ? 'https://example.com::ABC123' : '192.168.1.100:3456:ABC123' })
          .width('85%')
          .height(48)
          .backgroundColor(Theme.GlassBackground)
          .borderRadius(8)
          .fontColor(Theme.TextPrimary)
          .border({ width: 1, color: Theme.GlassBorder })
          .backgroundBlurStyle(BlurStyle.COMPONENT_REGULAR)
          .onChange((value: string) => {
            this.pairingCode = value
          })
      }

      Text(this.accessMode === 'remote' ? '适合外出访问桌面端，粘贴公网隧道连接串即可' : '适合家里或办公室同网段访问，延迟更低')
        .fontSize(12)
        .fontColor(Theme.TextSecondary)
        .textAlign(TextAlign.Center)
        .width('85%')

      if (this.errorMessage) {
        Text(this.errorMessage)
          .fontSize(12)
          .fontColor(Theme.ErrorColor)
          .textAlign(TextAlign.Center)
          .width('85%')
      }

      Button(this.isConnecting ? '连接中...' : '配对连接')
        .width('85%')
        .height(48)
        .backgroundColor(this.pairingCode && !this.isConnecting ? Theme.PrimaryColor : Theme.TextTertiary)
        .fontColor(Theme.TextOnPrimary)
        .borderRadius(12)
        .backgroundBlurStyle(BlurStyle.COMPONENT_REGULAR)
        .enabled(!!this.pairingCode && !this.isConnecting)
        .onClick(() => {
          this.connectWithPairingCode()
        })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  ManualInput() {
    Column({ space: 16 }) {
      Column({ space: 8 }) {
        Text(this.accessMode === 'remote' ? '公网地址' : '桌面端地址')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.TextPrimary)
          .width('85%')

        Row({ space: 8 }) {
          TextInput({ placeholder: this.accessMode === 'remote' ? 'https://your-tunnel.example.com' : 'http://192.168.1.100:3456', text: this.serverUrl })
            .layoutWeight(1)
            .height(48)
            .backgroundColor(Theme.GlassBackground)
            .borderRadius(8)
            .fontColor(Theme.TextPrimary)
            .border({ width: 1, color: Theme.GlassBorder })
            .backgroundBlurStyle(BlurStyle.COMPONENT_REGULAR)
            .onChange((value: string) => {
              this.serverUrl = value
            })

          Button() {
            SymbolGlyph($r('sys.symbol.qrcode'))
              .fontSize(22)
              .fontColor([Theme.TextOnPrimary])
          }
          .width(48)
          .height(48)
          .backgroundColor(Theme.PrimaryColor)
          .borderRadius(8)
          .onClick(async () => {
            const result = await openScanner()
            if (result?.bestUrl) {
              this.serverUrl = result.bestUrl
              // 保存 E2EE 公钥（云中继端到端加密用）
              if (result.e2eePub) {
                authStore.setRelayE2EEPubKey(result.e2eePub)
              }
              // 推断扫码得到的连接类型
              if (result.tunnel === result.bestUrl) {
                this.scannedType = 'tunnel'
              } else if (result.pgy === result.bestUrl) {
                this.scannedType = 'pgy'
              } else if (result.cloudRelay === result.bestUrl) {
                this.scannedType = 'cloud_relay'
              } else {
                this.scannedType = 'lan'
              }
            }
          })
        }
        .width('85%')
      }

      Text(this.accessMode === 'remote' ? '请输入公网隧道或云中继地址' : '请输入桌面端局域网地址，或使用扫码填入')
        .fontSize(12)
        .fontColor(Theme.TextSecondary)
        .textAlign(TextAlign.Center)
        .width('85%')

      if (this.errorMessage) {
        Text(this.errorMessage)
          .fontSize(12)
          .fontColor(Theme.ErrorColor)
          .textAlign(TextAlign.Center)
          .width('85%')
      }

      Button(this.isConnecting ? '连接中...' : '连接')
        .width('85%')
        .height(48)
        .backgroundColor(this.serverUrl && !this.isConnecting ? Theme.PrimaryColor : Theme.TextTertiary)
        .fontColor(Theme.TextOnPrimary)
        .borderRadius(12)
        .backgroundBlurStyle(BlurStyle.COMPONENT_REGULAR)
        .enabled(!!this.serverUrl && !this.isConnecting)
        .onClick(() => {
          this.connectManual()
        })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  Instructions() {
    Column({ space: 16 }) {
      Text('连接建议')
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor(Theme.TextPrimary)

      this.InstructionStep(1, '桌面端保持运行，手机才能远程调用能力')
      this.InstructionStep(2, '同一 Wi-Fi 下优先使用局域网直连')
      this.InstructionStep(3, '外出时使用公网隧道或云中继地址')
    }
    .width('85%')
    .padding(20)
    .backgroundColor(Theme.GlassBackground)
    .borderRadius(12)
    .border({ width: 0.5, color: Theme.GlassBorder })
    .shadow({ radius: Theme.LiquidGlassShadowRadius, color: Theme.LiquidGlassShadowColor, offsetX: 0, offsetY: 4 })
    .margin({ top: 24 })
  }

  @Builder
  InstructionStep(number: number, text: string) {
    Row({ space: 12 }) {
      Text(`${number}`)
        .fontSize(12)
        .fontWeight(FontWeight.Bold)
        .fontColor(Theme.TextOnPrimary)
        .width(24)
        .height(24)
        .textAlign(TextAlign.Center)
        .backgroundColor(Theme.PrimaryColor)
        .borderRadius(12)

      Text(text)
        .fontSize(12)
        .fontColor(Theme.TextSecondary)
        .layoutWeight(1)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  // MARK: - 连接逻辑

  private startDiscovery(): void {
    try {
      mdnsDiscoveryService.setListener({
        onServerFound: (server: DiscoveredServer) => {
          // 去重
          const exists = this.discoveredServers.some(s => s.id === server.id)
          if (!exists) {
            this.discoveredServers = [...this.discoveredServers, server]
          }
        },
        onServerLost: (serverId: string) => {
          this.discoveredServers = this.discoveredServers.filter(s => s.id !== serverId)
        },
        onSearchStateChange: (searching: boolean) => {
          this.isSearching = searching
        }
      })
      mdnsDiscoveryService.startDiscovery(getContext(this) as Context)
    } catch (e) {
      console.error('[Login] mDNS discovery start error:', e)
    }
  }

  @Builder
  DiscoveredServersSection() {
    Column() {
      if (this.discoveredServers.length > 0 || this.isSearching) {
        Text('发现服务器')
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.TextPrimary)
          .width('85%')
          .margin({ bottom: 8 })

        if (this.isSearching && this.discoveredServers.length === 0) {
          Text('正在扫描局域网...')
            .fontSize(12)
            .fontColor(Theme.TextTertiary)
            .margin({ bottom: 8 })
        }

        ForEach(this.discoveredServers, (server: DiscoveredServer) => {
          Column() {
            Row({ space: 12 }) {
              SymbolGlyph($r('sys.symbol.wifi'))
                .fontSize(32)
                .fontColor([Theme.AccentGreen])

              Column({ space: 4 }) {
                Text(server.name)
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(Theme.TextPrimary)
                  .lineHeight(18)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })

                Text(server.ip)
                  .fontSize(12)
                  .fontColor(Theme.TextSecondary)
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)

              SymbolGlyph($r('sys.symbol.chevron_forward'))
                .fontSize(14)
                .fontColor([Theme.TextTertiary])
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)
            .padding(12)
          }
          .width('85%')
          .backgroundColor(Theme.GlassBackground)
          .borderRadius(12)
          .border({ width: 0.5, color: Theme.GlassBorder })
          .shadow({ radius: Theme.LiquidGlassShadowRadius, color: Theme.LiquidGlassShadowColor, offsetX: 0, offsetY: 4 })
          .margin({ bottom: 8 })
          .onClick(() => {
            this.connectManual(server.url)
          })
        }, (server: DiscoveredServer) => server.id)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
    .margin({ bottom: 16 })
  }

  private async connectWithPairingCode(): Promise<void> {
    const input = this.pairingCode.trim()
    if (!input) return

    this.isConnecting = true
    this.errorMessage = ''

    let serverAddr: string = ''
    let code: string = ''

    // 解析格式
    if (input.includes('::')) {
      // 格式: https://xxx.trycloudflare.com::ABC123
      const parts = input.split('::')
      serverAddr = parts[0].trim()
      code = parts.length > 1 ? parts[1].toUpperCase() : ''
    } else if (input.startsWith('https://') || input.startsWith('http://')) {
      // 格式: https://xxx.trycloudflare.com:ABC123 或 https://xxx.com:8080:ABC123
      const lastColonIndex = input.lastIndexOf(':')
      if (lastColonIndex > 8) {
        const possibleCode = input.substring(lastColonIndex + 1)
        // 配对码通常是 4-10 位字母数字，不含 /
        if (/^[A-Za-z0-9]{4,10}$/.test(possibleCode) && !possibleCode.includes('/')) {
          serverAddr = input.substring(0, lastColonIndex)
          code = possibleCode.toUpperCase()
        } else {
          // 最后一个冒号后不是有效配对码，整个输入作为地址
          serverAddr = input
          this.errorMessage = '未找到配对码，请使用 地址:配对码 格式'
          this.isConnecting = false
          return
        }
      } else {
        this.errorMessage = '公网地址格式错误'
        this.isConnecting = false
        return
      }
    } else {
      // 格式: 192.168.1.100:3456:ABC123
      const parts = input.split(':')
      if (parts.length === 3) {
        serverAddr = 'http://' + parts[0] + ':' + parts[1]
        code = parts[2].toUpperCase()
      } else {
        this.errorMessage = '配对码格式错误'
        this.isConnecting = false
        return
      }
    }

    if (code.length < 4) {
      this.errorMessage = '配对码无效'
      this.isConnecting = false
      return
    }

    console.info(`[Login] Connecting to: ${serverAddr} with code: ${code}`)

    try {
      apiService.setBaseUrl(serverAddr)
      wsService.setServerUrl(serverAddr)

      const success = await apiService.pair(code)

      if (success) {
        // 保存到多服务器配置
        await authStore.addFromLogin(serverAddr)

        // 登录成功
        const user: User = { id: '1', name: '用户', email: '' }
        await authStore.login(user)

        // 启动智能连接管理器（LAN 优先，Tunnel 回退）
        connectionManager.startPeriodicCheck()

        // 跳转到主页
        try {
          await router.pushUrl({
            url: 'pages/Index'
          })
        } catch (e) {
          console.error(`[Login] Router push error: ${e}`)
        }
      } else {
        this.errorMessage = '配对失败，请检查配对码是否正确'
      }
    } catch (e) {
      this.errorMessage = '连接失败: ' + this.getErrorMessage(e)
    }

    this.isConnecting = false
  }

  private async connectManual(inputUrl?: string): Promise<void> {
    let url = (inputUrl || this.serverUrl).trim()
    if (!url) return

    this.isConnecting = true
    this.errorMessage = ''

    // 检测是否为云服务器中继地址：/relay/desktop_xxx
    const relayMatch = url.match(/^(https?:\/\/[^\/]+\/relay\/desktop_[^\/]+)/i)
    if (relayMatch) {
      // 云服务器中继格式：http://ip/relay/desktop_xxx
      console.info(`[Login] Cloud relay address detected: ${url}`)
      try {
        apiService.setBaseUrl(url)
        wsService.setServerUrl(url)

        // 测试服务器连通性
        await apiService.getSessions()

        // 保存到多服务器配置（类型为 tunnel）
        await authStore.addFromLogin(url)

        // 登录成功
        const user: User = { id: '1', name: '用户', email: '' }
        await authStore.login(user)

        // 启动智能连接管理器
        connectionManager.startPeriodicCheck()

        // 跳转到主页
        try {
          await router.pushUrl({
            url: 'pages/Index'
          })
        } catch (e) {
          console.error(`[Login] Router push error: ${e}`)
        }
      } catch (e) {
        this.errorMessage = '连接失败: ' + this.getErrorMessage(e)
      }
      this.isConnecting = false
      return
    }

    // 处理 host:port:token 格式（仅对非 IPv6 的 URL）
    const isIpv6 = url.includes('[') || (url.match(/:/g) || []).length > 2
    if (!isIpv6 && !url.startsWith('http')) {
      const colonCount = (url.match(/:/g) || []).length
      if (colonCount >= 2) {
        const parts = url.split(':')
        if (parts.length >= 2) {
          url = parts[0] + ':' + parts[1]
        }
      }
    }

    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'http://' + url
    }

    console.info(`[Login] Manual connecting to: ${url}`)

    try {
      apiService.setBaseUrl(url)
      wsService.setServerUrl(url)

      // 测试服务器连通性
      await apiService.getSessions()

      // 保存到多服务器配置（扫码时保留类型信息）
      const typeForAdd = this.scannedType || undefined
      await authStore.addFromLogin(url, typeForAdd)

      // 登录成功
      const user: User = { id: '1', name: '用户', email: '' }
      await authStore.login(user)

      // 启动智能连接管理器（LAN 优先，Tunnel 回退）
      connectionManager.startPeriodicCheck()

      // 跳转到主页
      try {
        await router.pushUrl({
          url: 'pages/Index'
        })
      } catch (e) {
        console.error(`[Login] Router push error: ${e}`)
      }
    } catch (e) {
      this.errorMessage = '连接失败: ' + this.getErrorMessage(e)
    }

    this.isConnecting = false
  }

  private getErrorMessage(e: Object): string {
    if (e instanceof Error) {
      return e.message
    }
    // 尝试转换为字符串
    try {
      return JSON.stringify(e)
    } catch {
      return '未知错误'
    }
  }
}
