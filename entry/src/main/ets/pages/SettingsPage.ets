/**
 * 设置页面 - 与 iOS 端保持一致的实现
 */

import { Theme } from '../common/Theme'
import { authStore } from '../stores/AuthStore'
import { appState, ThemeMode } from '../stores/AppState'
import { sessionStore } from '../stores/SessionStore'
import { ModelInfo, ServerMode, PermissionMode, getPermissionModeDisplayName, getPermissionModeDescription } from '../models/Models'
import router from '@ohos.router'
import http from '@ohos.net.http'

@Component
export struct SettingsPage {
  @State isDarkMode: boolean = true
  @State serverMode: ServerMode = 'lan'
  @State models: ModelInfo[] = []
  @State currentModel: ModelInfo | null = null
  @State currentPermissionMode: PermissionMode = PermissionMode.DEFAULT
  @State isLoggedIn: boolean = false
  @State lanUrl: string = ''
  @State tunnelUrl: string = ''
  @State currentUrl: string = ''
  @State userName: string = ''
  @State testingLatency: boolean = false
  @State latency: number = 0
  @State showLanEdit: boolean = false
  @State showTunnelEdit: boolean = false
  @State showThemeSheet: boolean = false
  @State editUrl: string = ''
  @State themeMode: ThemeMode = 'dark'

  private readonly appVersion: string = '1.0.0'
  private readonly buildTime: string = '2026-05-08'

  aboutToAppear(): void {
    this.loadSettings()
  }

  private loadSettings(): void {
    this.isLoggedIn = authStore.isLoggedIn
    this.lanUrl = authStore.lanUrl
    this.tunnelUrl = authStore.tunnelUrl
    this.serverMode = authStore.serverMode
    this.currentUrl = authStore.serverUrl
    this.models = appState.models
    this.currentModel = appState.currentModel
    this.userName = '用户' // 可以从服务器获取
    this.themeMode = appState.themeMode

    // 设置回调
    appState.onModelsChanged = () => {
      this.models = appState.models
      this.currentModel = appState.currentModel
    }
  }

  build() {
    Column() {
      // 顶部标题
      Text('设置')
        .fontSize(28)
        .fontColor(Theme.TextPrimary)
        .fontWeight(FontWeight.Bold)
        .width('100%')
        .textAlign(TextAlign.Center)
        .padding({ top: 56, bottom: Theme.SpacingLG })

      List({ space: Theme.SpacingMD }) {
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

        // 模型设置
        if (this.isLoggedIn) {
          ListItem() {
            this.SettingSection('模型')
          }

          ListItem() {
            this.ModelItem()
          }

          // 权限模式
          ListItem() {
            this.SettingSection('权限模式')
          }

          ListItem() {
            this.PermissionModeItem()
          }
        }

        // 外观设置
        ListItem() {
          this.SettingSection('外观')
        }

        ListItem() {
          this.ThemeItem()
        }

        // 数据管理
        if (this.isLoggedIn) {
          ListItem() {
            this.SettingSection('数据管理')
          }

          ListItem() {
            this.DataManageItem()
          }
        }

        // 关于
        ListItem() {
          this.SettingSection('关于')
        }

        ListItem() {
          this.VersionItem()
        }

        ListItem() {
          this.BuildTimeItem()
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
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.BackgroundPrimary)
    .bindSheet($$this.showLanEdit, this.LanEditSheet(), {
      height: 280,
      backgroundColor: Theme.BackgroundSecondary,
      dragBar: true
    })
    .bindSheet($$this.showTunnelEdit, this.TunnelEditSheet(), {
      height: 280,
      backgroundColor: Theme.BackgroundSecondary,
      dragBar: true
    })
  }

  @Builder
  SettingSection(title: string) {
    Text(title)
      .fontSize(Theme.FontCaption)
      .fontWeight(FontWeight.Medium)
      .fontColor(Theme.TextSecondary)
      .width('100%')
      .padding({ top: Theme.SpacingSM, bottom: Theme.SpacingXS })
  }

  @Builder
  AccountItem() {
    Row() {
      Text('用户')
        .fontSize(Theme.FontBody)
        .fontColor(Theme.TextPrimary)

      Blank()

      Text(this.userName)
        .fontSize(Theme.FontBody)
        .fontColor(Theme.TextSecondary)
    }
    .width('100%')
    .padding(Theme.SpacingMD)
    .backgroundColor(Theme.BackgroundSecondary)
    .borderRadius(Theme.RadiusMedium)
  }

  @Builder
  ConnectionItem() {
    Column({ space: Theme.SpacingMD }) {
      // 网络模式切换
      Row() {
        Text('当前网络')
          .fontSize(Theme.FontBody)
          .fontColor(Theme.TextPrimary)

        Blank()

        Row({ space: 8 }) {
          Button('局域网')
            .fontSize(Theme.FontTiny)
            .fontColor(this.serverMode === 'lan' ? Theme.TextOnPrimary : Theme.TextSecondary)
            .backgroundColor(this.serverMode === 'lan' ? Theme.PrimaryColor : Theme.BackgroundTertiary)
            .borderRadius(8)
            .height(28)
            .enabled(this.lanUrl.length > 0)
            .onClick(() => {
              this.setServerMode('lan')
            })

          Button('公网')
            .fontSize(Theme.FontTiny)
            .fontColor(this.serverMode === 'tunnel' ? Theme.TextOnPrimary : Theme.TextSecondary)
            .backgroundColor(this.serverMode === 'tunnel' ? Theme.PrimaryColor : Theme.BackgroundTertiary)
            .borderRadius(8)
            .height(28)
            .enabled(this.tunnelUrl.length > 0)
            .onClick(() => {
              this.setServerMode('tunnel')
            })
        }
      }
      .width('100%')

      Divider().color(Theme.Border)

      // 局域网地址
      Row() {
        Column({ space: 2 }) {
          Text('局域网地址')
            .fontSize(Theme.FontBody)
            .fontColor(Theme.TextPrimary)

          Text(this.lanUrl.length > 0 ? this.lanUrl : '未设置')
            .fontSize(Theme.FontCaption)
            .fontColor(Theme.TextSecondary)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Text('编辑')
          .fontSize(Theme.FontCaption)
          .fontColor(Theme.PrimaryColor)
          .onClick(() => {
            this.editUrl = this.lanUrl
            this.showLanEdit = true
          })
      }
      .width('100%')

      Divider().color(Theme.Border)

      // 公网地址
      Row() {
        Column({ space: 2 }) {
          Text('公网地址')
            .fontSize(Theme.FontBody)
            .fontColor(Theme.TextPrimary)

          Text(this.tunnelUrl.length > 0 ? this.tunnelUrl : '未设置')
            .fontSize(Theme.FontCaption)
            .fontColor(Theme.TextSecondary)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Text('编辑')
          .fontSize(Theme.FontCaption)
          .fontColor(Theme.PrimaryColor)
          .onClick(() => {
            this.editUrl = this.tunnelUrl
            this.showTunnelEdit = true
          })
      }
      .width('100%')

      Divider().color(Theme.Border)

      // 当前地址
      Row() {
        Text('当前地址')
          .fontSize(Theme.FontBody)
          .fontColor(Theme.TextPrimary)

        Blank()

        Text(this.currentUrl.length > 0 ? this.currentUrl : '未设置')
          .fontSize(Theme.FontCaption)
          .fontColor(Theme.TextSecondary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')

      Divider().color(Theme.Border)

      // 连接速度
      Row() {
        Text('连接速度')
          .fontSize(Theme.FontBody)
          .fontColor(Theme.TextPrimary)

        Blank()

        if (this.testingLatency) {
          LoadingProgress()
            .width(20)
            .height(20)
            .color(Theme.PrimaryColor)
        } else if (this.latency > 0) {
          Text(this.formatLatency(this.latency))
            .fontSize(Theme.FontCaption)
            .fontColor(this.getLatencyColor(this.latency))
        } else {
          Text('点击测试')
            .fontSize(Theme.FontCaption)
            .fontColor(Theme.TextSecondary)
        }
      }
      .width('100%')
      .onClick(() => {
        if (!this.testingLatency && this.currentUrl.length > 0) {
          this.testLatency()
        }
      })
    }
    .width('100%')
    .padding(Theme.SpacingMD)
    .backgroundColor(Theme.BackgroundSecondary)
    .borderRadius(Theme.RadiusMedium)
  }

  @Builder
  ModelItem() {
    Row() {
      Column({ space: 4 }) {
        Text('当前模型')
          .fontSize(Theme.FontBody)
          .fontColor(Theme.TextPrimary)

        Text(this.currentModel?.name || '未选择')
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
    .backgroundColor(Theme.BackgroundSecondary)
    .borderRadius(Theme.RadiusMedium)
    .onClick(() => {
      // 显示模型选择对话框
    })
  }

  @Builder
  PermissionModeItem() {
    Column({ space: Theme.SpacingSM }) {
      this.PermissionModeRow(PermissionMode.DEFAULT)
      Divider().color(Theme.Border)
      this.PermissionModeRow(PermissionMode.ACCEPT_EDITS)
      Divider().color(Theme.Border)
      this.PermissionModeRow(PermissionMode.PLAN)
      Divider().color(Theme.Border)
      this.PermissionModeRow(PermissionMode.BYPASS_PERMISSIONS)
    }
    .width('100%')
    .padding(Theme.SpacingMD)
    .backgroundColor(Theme.BackgroundSecondary)
    .borderRadius(Theme.RadiusMedium)
  }

  @Builder
  PermissionModeRow(mode: PermissionMode) {
    Row() {
      Column({ space: 2 }) {
        Text(getPermissionModeDisplayName(mode))
          .fontSize(Theme.FontBody)
          .fontColor(Theme.TextPrimary)

        Text(getPermissionModeDescription(mode))
          .fontSize(Theme.FontTiny)
          .fontColor(Theme.TextSecondary)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Radio({ value: mode, group: 'permissionMode' })
        .checked(this.currentPermissionMode === mode)
        .onChange((isChecked: boolean) => {
          if (isChecked) {
            this.currentPermissionMode = mode
            sessionStore.changePermissionMode(mode)
          }
        })
    }
    .width('100%')
  }

  @Builder
  ThemeItem() {
    Row() {
      Text('主题')
        .fontSize(Theme.FontBody)
        .fontColor(Theme.TextPrimary)

      Blank()

      Text(this.getThemeLabel(this.themeMode))
        .fontSize(Theme.FontBody)
        .fontColor(Theme.TextSecondary)

      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(14)
        .fontColor([Theme.TextSecondary])
        .margin({ left: 8 })
    }
    .width('100%')
    .padding(Theme.SpacingMD)
    .backgroundColor(Theme.BackgroundSecondary)
    .borderRadius(Theme.RadiusMedium)
    .onClick(() => {
      // 切换主题
      if (this.themeMode === 'dark') {
        this.themeMode = 'light'
      } else if (this.themeMode === 'light') {
        this.themeMode = 'glass'
      } else {
        this.themeMode = 'dark'
      }
      appState.setThemeMode(this.themeMode)
    })
  }

  @Builder
  DataManageItem() {
    Column({ space: Theme.SpacingSM }) {
      // 导入对话
      Row() {
        Column({ space: 2 }) {
          Text('导入对话')
            .fontSize(Theme.FontBody)
            .fontColor(Theme.TextPrimary)

          Text('从 Cloud Code 导入对话到本地')
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
      .padding({ top: Theme.SpacingSM, bottom: Theme.SpacingSM })
      .onClick(() => {
        // 导航到导入页面
      })

      Divider().color(Theme.Border)

      // 存储管理
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
      .padding({ top: Theme.SpacingSM, bottom: Theme.SpacingSM })
      .onClick(() => {
        // 导航到存储管理页面
      })
    }
    .width('100%')
    .padding(Theme.SpacingMD)
    .backgroundColor(Theme.BackgroundSecondary)
    .borderRadius(Theme.RadiusMedium)
  }

  @Builder
  VersionItem() {
    Row() {
      Text('版本')
        .fontSize(Theme.FontBody)
        .fontColor(Theme.TextPrimary)

      Blank()

      Text(this.appVersion)
        .fontSize(Theme.FontBody)
        .fontColor(Theme.TextSecondary)
    }
    .width('100%')
    .padding(Theme.SpacingMD)
    .backgroundColor(Theme.BackgroundSecondary)
    .borderRadius(Theme.RadiusMedium)
  }

  @Builder
  BuildTimeItem() {
    Row() {
      Text('构建时间')
        .fontSize(Theme.FontBody)
        .fontColor(Theme.TextPrimary)

      Blank()

      Text(this.buildTime)
        .fontSize(Theme.FontBody)
        .fontColor(Theme.TextSecondary)
    }
    .width('100%')
    .padding(Theme.SpacingMD)
    .backgroundColor(Theme.BackgroundSecondary)
    .borderRadius(Theme.RadiusMedium)
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
      .onClick(() => {
        this.logout()
      })
  }

  @Builder
  FooterView() {
    Text(`Claude Code HarmonyOS v${this.appVersion} (${this.buildTime})`)
      .fontSize(Theme.FontCaption)
      .fontColor(Theme.TextTertiary)
      .width('100%')
      .textAlign(TextAlign.Center)
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
        .backgroundColor(Theme.BackgroundTertiary)
        .borderRadius(8)
        .fontColor(Theme.TextPrimary)
        .padding({ left: 12, right: 12 })
        .margin({ left: Theme.SpacingLG, right: Theme.SpacingLG })
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
          .backgroundColor(Theme.BackgroundTertiary)
          .fontColor(Theme.TextPrimary)
          .borderRadius(8)
          .onClick(() => {
            this.showLanEdit = false
          })

        Button('保存')
          .layoutWeight(1)
          .height(44)
          .backgroundColor(Theme.PrimaryColor)
          .fontColor(Theme.TextOnPrimary)
          .borderRadius(8)
          .enabled(this.editUrl.length > 0)
          .onClick(() => {
            this.lanUrl = this.editUrl
            authStore.setLanUrl(this.editUrl)
            this.showLanEdit = false
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
        .backgroundColor(Theme.BackgroundTertiary)
        .borderRadius(8)
        .fontColor(Theme.TextPrimary)
        .padding({ left: 12, right: 12 })
        .margin({ left: Theme.SpacingLG, right: Theme.SpacingLG })
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
          .backgroundColor(Theme.BackgroundTertiary)
          .fontColor(Theme.TextPrimary)
          .borderRadius(8)
          .onClick(() => {
            this.showTunnelEdit = false
          })

        Button('保存')
          .layoutWeight(1)
          .height(44)
          .backgroundColor(Theme.PrimaryColor)
          .fontColor(Theme.TextOnPrimary)
          .borderRadius(8)
          .enabled(this.editUrl.length > 0)
          .onClick(() => {
            this.tunnelUrl = this.editUrl
            authStore.setTunnelUrl(this.editUrl)
            this.showTunnelEdit = false
          })
      }
      .width('100%')
      .padding({ left: Theme.SpacingLG, right: Theme.SpacingLG, top: Theme.SpacingLG })
    }
  }

  private getThemeLabel(mode: string): string {
    if (mode === 'dark') {
      return '深色'
    } else if (mode === 'light') {
      return '浅色'
    } else if (mode === 'glass') {
      return '玻璃'
    }
    return '深色'
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

    try {
      const httpRequest = http.createHttp()
      const url = this.currentUrl + '/api/sessions'

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

      httpRequest.destroy()
    } catch (e) {
      this.latency = -1
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

  private async logout(): Promise<void> {
    await authStore.logout()
    sessionStore.disconnectAllSessions()

    // 跳转到登录页面
    router.pushUrl({
      url: 'pages/Index'
    })
  }
}
