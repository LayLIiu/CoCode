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

type ConnectionMode = 'pairing' | 'manual'

@Entry
@Component
export struct LoginPage {
  @State mode: ConnectionMode = 'pairing'
  @State pairingCode: string = ''
  @State serverUrl: string = ''
  @State isConnecting: boolean = false
  @State errorMessage: string = ''
  @State discoveredServers: DiscoveredServer[] = []
  @State isSearching: boolean = false

  aboutToAppear(): void {
    this.startDiscovery()
  }

  aboutToDisappear(): void {
    mdnsDiscoveryService.stopDiscovery()
  }

  build() {
    Column() {
      // Logo
      this.LogoSection()

      // 模式切换
      this.ModeSwitch()

      // 发现服务器列表
      this.DiscoveredServersSection()

      // 输入区域
      if (this.mode === 'pairing') {
        this.PairingInput()
      } else {
        this.ManualInput()
      }

      // 使用说明
      this.Instructions()

      Blank()
    }
    .width('100%')
    .height('100%')
    .linearGradient({
      angle: 180,
      colors: [
        [Theme.BackgroundGradientStart, 0.0],
        [Theme.BackgroundGradientMiddle, 0.5],
        [Theme.BackgroundGradientEnd, 1.0]
      ]
    })
    .padding({ top: 60 })
  }

  @Builder
  LogoSection() {
    Column({ space: 16 }) {
      SymbolGlyph($r('sys.symbol.message_fill'))
        .fontSize(64)
        .fontColor([Theme.TextPrimary])

      Text('Claude Code')
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
        .fontColor(Theme.TextPrimary)

      Text('移动端助手')
        .fontSize(16)
        .fontColor(Theme.TextSecondary)
    }
    .margin({ bottom: 40 })
  }

  @Builder
  ModeSwitch() {
    Row() {
      Button('配对码连接')
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

      Button('手动输入')
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
    .margin({ bottom: 24 })
  }

  @Builder
  PairingInput() {
    Column({ space: 16 }) {
      Column({ space: 8 }) {
        Text('配对码')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.TextPrimary)
          .width('85%')

        TextInput({ placeholder: '粘贴连接串或 IP:端口:配对码' })
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

      Text('支持局域网或公网隧道连接，在桌面端获取配对码')
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
        Text('服务器地址')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.TextPrimary)
          .width('85%')

        Row({ space: 8 }) {
          TextInput({ placeholder: 'http://192.168.1.100:3456', text: this.serverUrl })
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
            }
          })
        }
        .width('85%')
      }

      Text('请输入桌面端服务地址（确保手机和电脑在同一网络）')
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
      Text('使用步骤')
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor(Theme.TextPrimary)

      this.InstructionStep(1, '在电脑上启动 Claude Code 桌面应用')
      this.InstructionStep(2, '设置 → IM 接入 → 生成配对码')
      this.InstructionStep(3, '局域网：输入 IP:端口:配对码')
      this.InstructionStep(4, '公网：粘贴完整连接串')
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

      // 保存到多服务器配置
      await authStore.addFromLogin(url)

      // 登录成功
      const user: User = { id: '1', name: '用户', email: '' }
      await authStore.login(user)

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
