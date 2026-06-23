/**
 * 设置页面 - 与 iOS 端保持一致的实现
 */

import { Theme } from '../common/Theme'
import { authStore } from '../stores/AuthStore'
import { appState, ThemeMode } from '../stores/AppState'
import { sessionStore } from '../stores/SessionStore'
import { ModelInfo, ServerMode, PermissionMode, getPermissionModeDescription, ServerProfile } from '../models/Models'
import { HdsNavigation, ScrollEffectType, HdsNavigationTitleMode } from '@hms.hds.hdsBaseComponent'
import { hdsMaterial } from '@hms.hds.hdsMaterial'
import router from '@ohos.router'
import http from '@ohos.net.http'
import { openScanner, ScannedAddresses } from '../services/ScanService'
import { connectionManager, ConnectionType, ConnectionQuality } from '../services/ConnectionManager'

import { apiService, DesktopCapabilityItem } from '../services/APIService'

class OfficialCodexControllerAccountItem {
  accountId: string = ''
  clientId: string = ''
  updatedAt: number = 0
  isCurrentAuthAccount: boolean = false
  isSelected: boolean = false
}

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
  @State editType: string = '' // 'lan' or 'tunnel'
  @State showEditSheet: boolean = false
  @State showThemeSheet: boolean = false
  @State editUrl: string = ''
  @State themeMode: ThemeMode = 'dark'
  @State showAdvancedTools: boolean = false

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
  @State checkingCapabilities: boolean = false
  @State desktopCapabilities: DesktopCapabilityItem[] = []
  @State capabilityCheckedAt: number = 0
  @State capabilityOk: boolean = false

  // Official Codex 远程控制
  @State codexControllerStatus: string = '未知'
  @State codexControllerClientId: string = ''
  @State codexControllerWsConnected: boolean = false
  @State codexControllerLoading: boolean = false
  @State codexControllerError: string = ''
  @State codexAutomationFallbackAvailable: boolean = false
  @State officialCodexThreadCount: number = 0
  @State officialCodexSyncLoading: boolean = false
  @State officialCodexSendMode: 'auto' | 'remote_control' | 'script_fallback' = 'script_fallback'
  @State officialCodexAccounts: OfficialCodexControllerAccountItem[] = []
  @State officialCodexCurrentAuthAccountId: string = ''
  @State officialCodexSelectedAccountId: string = ''
  @State officialCodexSwitchingAccount: boolean = false

  // 模型选择
  @State showModelSheet: boolean = false
  @State isLoadingModels: boolean = false

  private readonly appVersion: string = '1.0.0'
  private readonly buildTime: string = '2026-06-25'
  private modelsChangedListener: (() => void) | null = null

  aboutToAppear(): void {
    this.loadSettings()
    this.updateConnectionStatus()
    this.refreshCodexControllerStatus()
    this.refreshOfficialCodexAccounts()
    this.refreshOfficialCodexThreadCount()
  }

  aboutToDisappear(): void {
    if (this.modelsChangedListener) {
      appState.removeModelsChangedListener(this.modelsChangedListener)
      this.modelsChangedListener = null
    }
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
    this.models = appState.models
    this.currentModel = appState.currentModel
    this.userName = '用户' // 可以从服务器获取
    this.themeMode = appState.themeMode

    // 加载多服务器配置
    this.serverProfiles = [...authStore.serverProfiles]
    this.activeProfileId = authStore.activeProfileId

    // 加载生物识别设置
    this.biometricEnabled = authStore.biometricEnabled
    this.officialCodexSendMode = authStore.officialCodexSendMode

    // 注册监听
    this.modelsChangedListener = () => {
      this.models = appState.models
      this.currentModel = appState.currentModel
    }
    appState.addModelsChangedListener(this.modelsChangedListener)
  }

  private async loadModels(): Promise<void> {
    if (this.models.length > 0) return
    this.isLoadingModels = true
    try {
      await appState.fetchModels()
      this.models = appState.models
      this.currentModel = appState.currentModel
    } catch (e) {
      console.error('[Settings] loadModels error:', e)
    }
    this.isLoadingModels = false
  }

  private async selectModel(modelId: string): Promise<void> {
    try {
      await appState.setCurrentModel(modelId)
      this.currentModel = appState.currentModel
      this.showModelSheet = false
    } catch (e) {
      console.error('[Settings] selectModel error:', e)
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

          // Official Codex 远程控制
          ListItem() {
            this.SettingSection('Official Codex 远程控制')
          }

          ListItem() {
            this.OfficialCodexControllerPanel()
          }

          // 模型与权限
          if (this.isLoggedIn) {
            ListItem() {
              this.SettingSection('模型与权限')
            }

            ListItem() {
              this.ModelAndPermissionItem()
            }
          }

          // 高级工具
          if (this.isLoggedIn) {
            ListItem() {
              this.SettingSection('高级')
            }

            ListItem() {
              this.AdvancedToolsPanel()
            }

            if (this.showAdvancedTools) {
              ListItem() {
                this.DashboardLinkItem()
              }

              ListItem() {
                this.SkillsLinkItem()
              }

              ListItem() {
                this.MemoryLinkItem()
              }

              ListItem() {
                this.AgentLinkItem()
              }

              ListItem() {
                this.ScheduledTaskLinkItem()
              }

              ListItem() {
                this.DataManageItem()
              }

              ListItem() {
                this.CheckUpdateItem()
              }

              ListItem() {
                this.VersionItem()
              }

              ListItem() {
                this.BuildTimeItem()
              }
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

      // 模型选择 Sheet
      Column()
        .width(0).height(0)
        .bindSheet($$this.showModelSheet, this.ModelSelectorSheet(), {
          height: 480,
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
  DesktopCapabilityPanel() {
    Column({ space: Theme.SpacingMD }) {
      Row() {
        Column({ space: 5 }) {
          Text('桌面端能力')
            .fontSize(Theme.FontHeading)
            .fontWeight(FontWeight.Bold)
            .fontColor(Theme.TextPrimary)

          Text(this.getCapabilitySummaryText())
            .fontSize(Theme.FontCaption)
            .fontColor(Theme.TextSecondary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Button() {
          if (this.checkingCapabilities) {
            LoadingProgress()
              .width(18)
              .height(18)
              .color(Theme.TextOnPrimary)
          } else {
            Row({ space: 6 }) {
              SymbolGlyph($r('sys.symbol.checkmark_circle'))
                .fontSize(14)
                .fontColor([Theme.TextOnPrimary])

              Text('自检')
                .fontSize(Theme.FontTiny)
                .fontColor(Theme.TextOnPrimary)
            }
          }
        }
        .height(34)
        .padding({ left: 12, right: 12 })
        .backgroundColor(this.currentUrl ? Theme.PrimaryColor : Theme.BackgroundTertiary)
        .borderRadius(9)
        .enabled(!this.checkingCapabilities && this.currentUrl.length > 0)
        .onClick(() => {
          if (!this.checkingCapabilities && this.currentUrl.length > 0) {
            this.runDesktopCapabilityCheck()
          }
        })
      }
      .width('100%')

      if (this.desktopCapabilities.length > 0) {
        Row({ space: 8 }) {
          this.ConnectionMetric('核心能力', this.getRequiredCapabilityText(),
            this.capabilityOk ? Theme.SuccessColor : Theme.ErrorColor,
            this.capabilityOk ? 'rgba(48, 209, 88, 0.12)' : 'rgba(255, 59, 48, 0.12)')
          this.ConnectionMetric('已接通', this.getAvailableCapabilityText(),
            Theme.AccentBlue, 'rgba(10, 132, 255, 0.12)')
          this.ConnectionMetric('未接通', this.getMissingCapabilityText(),
            this.getMissingCapabilityCount() > 0 ? Theme.AccentOrange : Theme.SuccessColor,
            'rgba(255, 255, 255, 0.045)')
        }
        .width('100%')

        ForEach(this.desktopCapabilities, (item: DesktopCapabilityItem) => {
          Row({ space: 10 }) {
            Row()
              .width(3)
              .height(34)
              .borderRadius(2)
              .backgroundColor(this.getCapabilityColor(item))

            Column() {
              SymbolGlyph(item.available ? $r('sys.symbol.checkmark_circle') : $r('sys.symbol.questionmark_circle'))
                .fontSize(15)
                .fontColor([this.getCapabilityColor(item)])
            }
            .width(28)
            .height(28)
            .backgroundColor(this.getCapabilityBackground(item))
            .borderRadius(7)

            Column({ space: 2 }) {
              Row({ space: 6 }) {
                Text(item.title)
                  .fontSize(Theme.FontBody)
                  .fontWeight(item.required ? FontWeight.Medium : FontWeight.Normal)
                  .fontColor(Theme.TextPrimary)

                if (item.required) {
                  Text('核心')
                    .fontSize(10)
                    .fontColor(Theme.AccentBlue)
                    .padding({ left: 5, right: 5, top: 1, bottom: 1 })
                    .backgroundColor('rgba(10, 132, 255, 0.12)')
                    .borderRadius(4)
                }
              }

              Text(item.description)
                .fontSize(Theme.FontTiny)
                .fontColor(Theme.TextTertiary)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)

            Text(item.message)
              .fontSize(Theme.FontTiny)
              .fontColor(this.getCapabilityColor(item))
              .maxLines(1)
          }
          .width('100%')
          .padding({ top: 8, bottom: 8 })
        }, (item: DesktopCapabilityItem) => item.key)
      } else {
        Text('点击自检后，会实际访问桌面端 API，确认手机端哪些功能可以真正工作。')
          .fontSize(Theme.FontCaption)
          .fontColor(Theme.TextTertiary)
          .lineHeight(19)
      }
    }
    .width('100%')
    .padding(Theme.SpacingLG)
    .backgroundColor('rgba(255, 255, 255, 0.055)')
    .borderRadius(Theme.RadiusLarge)
    .border({ width: 0.5, color: 'rgba(255, 255, 255, 0.09)' })
  }

  @Builder
  OfficialCodexControllerPanel() {
    Column({ space: Theme.SpacingMD }) {
      Row() {
        Column({ space: 5 }) {
          Text('Codex 控制器')
            .fontSize(Theme.FontHeading)
            .fontWeight(FontWeight.Bold)
            .fontColor(Theme.TextPrimary)

          Text(this.getCodexControllerSummaryText())
            .fontSize(Theme.FontCaption)
            .fontColor(Theme.TextSecondary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')

      // 状态指标
      Row({ space: 8 }) {
        this.ConnectionMetric('状态', this.codexControllerStatus, this.getCodexControllerStatusColor(), this.getCodexControllerStatusBackground())
        this.ConnectionMetric('WS', this.codexControllerWsConnected ? '已连接' : '未连接',
          this.codexControllerWsConnected ? Theme.SuccessColor : Theme.TextTertiary,
          this.codexControllerWsConnected ? 'rgba(48, 209, 88, 0.14)' : 'rgba(255, 255, 255, 0.045)')
        this.ConnectionMetric('对话', `${this.officialCodexThreadCount}`,
          this.officialCodexThreadCount > 0 ? Theme.SuccessColor : Theme.TextTertiary,
          this.officialCodexThreadCount > 0 ? 'rgba(48, 209, 88, 0.14)' : 'rgba(255, 255, 255, 0.045)')
        this.ConnectionMetric('兜底', this.codexAutomationFallbackAvailable ? '可用' : '关闭',
          this.codexAutomationFallbackAvailable ? Theme.SuccessColor : Theme.TextTertiary,
          this.codexAutomationFallbackAvailable ? 'rgba(48, 209, 88, 0.14)' : 'rgba(255, 255, 255, 0.045)')
        if (this.codexControllerClientId) {
          Text(this.codexControllerClientId.substring(0, 8) + '...')
            .fontSize(Theme.FontTiny)
            .fontColor(Theme.TextTertiary)
            .maxLines(1)
        }
      }
      .width('100%')

      Divider()
        .color('rgba(255, 255, 255, 0.08)')

      Column({ space: 8 }) {
        Text('发送方式')
          .fontSize(Theme.FontBody)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.TextPrimary)

        Text(this.getOfficialCodexSendModeSummary())
          .fontSize(Theme.FontCaption)
          .fontColor(Theme.TextSecondary)

        Row({ space: 6 }) {
          this.OfficialCodexSendModeChip('auto', '自动')
          this.OfficialCodexSendModeChip('remote_control', '官方')
          this.OfficialCodexSendModeChip('script_fallback', '脚本')
        }
        .width('100%')
      }
      .width('100%')

      if (this.officialCodexAccounts.length > 0) {
        Divider()
          .color('rgba(255, 255, 255, 0.08)')

        Column({ space: 8 }) {
          Text('官方账号')
            .fontSize(Theme.FontBody)
            .fontWeight(FontWeight.Medium)
            .fontColor(Theme.TextPrimary)

          Text('点选当前要走官方 Remote Control 的账号。桌面端切账号后，这里也要切到同一个账号。')
            .fontSize(Theme.FontCaption)
            .fontColor(Theme.TextSecondary)

          if (this.officialCodexCurrentAuthAccountId && this.officialCodexSelectedAccountId &&
            this.officialCodexCurrentAuthAccountId !== this.officialCodexSelectedAccountId) {
            Text('当前使用账号和桌面当前账号不一致，官方发送可能失败。')
              .fontSize(Theme.FontCaption)
              .fontColor(Theme.ErrorColor)
          }

          ForEach(this.officialCodexAccounts, (account: OfficialCodexControllerAccountItem) => {
            this.OfficialCodexAccountRow(account)
          }, (account: OfficialCodexControllerAccountItem) => account.accountId)
        }
        .width('100%')
      }

      // 操作按钮
      Row({ space: Theme.SpacingMD }) {
        Button() {
          if (this.codexControllerLoading) {
            LoadingProgress().width(16).height(16).color(Theme.TextOnPrimary)
          } else {
            Text(this.codexControllerWsConnected ? '断开' : '恢复 & 连接')
              .fontSize(Theme.FontTiny)
              .fontColor(Theme.TextOnPrimary)
          }
        }
        .layoutWeight(1)
        .height(36)
        .backgroundColor(this.codexControllerWsConnected ? Theme.ErrorColor : Theme.PrimaryColor)
        .borderRadius(9)
        .enabled(!this.codexControllerLoading)
        .onClick(() => {
          if (this.codexControllerWsConnected) {
            this.disconnectCodexController()
          } else {
            this.restoreAndConnectCodexController()
          }
        })

        Button() {
          if (this.codexControllerLoading) {
            LoadingProgress().width(16).height(16).color(Theme.TextOnPrimary)
          } else {
            Text('刷新')
              .fontSize(Theme.FontTiny)
              .fontColor(Theme.TextOnPrimary)
          }
        }
        .height(36)
        .width(80)
        .backgroundColor('rgba(255, 255, 255, 0.1)')
        .borderRadius(9)
        .enabled(!this.codexControllerLoading)
        .onClick(() => {
          this.refreshCodexControllerStatus()
        })
      }
      .width('100%')

      Button() {
        if (this.officialCodexSyncLoading) {
          LoadingProgress().width(16).height(16).color(Theme.TextOnPrimary)
        } else {
          Text('同步 Codex Desktop 对话')
            .fontSize(Theme.FontTiny)
            .fontColor(Theme.TextOnPrimary)
        }
      }
      .height(36)
      .width('100%')
      .backgroundColor('rgba(10, 132, 255, 0.18)')
      .borderRadius(9)
      .enabled(!this.officialCodexSyncLoading && !this.codexControllerLoading)
      .onClick(() => {
        this.syncOfficialCodexThreadsFromSettings()
      })
    }
    .width('100%')
    .padding(Theme.SpacingLG)
    .backgroundColor('rgba(255, 255, 255, 0.055)')
    .borderRadius(Theme.RadiusLarge)
    .border({ width: 0.5, color: 'rgba(255, 255, 255, 0.09)' })
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

  private getOfficialCodexSendModeSummary(): string {
    switch (this.officialCodexSendMode) {
      case 'remote_control':
        return '只走官方 Remote Control，失败直接报错，不自动兜底'
      case 'script_fallback':
        return '直接调用你本机的脚本发送，不依赖 controller WebSocket'
      default:
        return '自动模式当前优先尝试本机脚本发送'
    }
  }

  @Builder
  OfficialCodexSendModeChip(mode: 'auto' | 'remote_control' | 'script_fallback', label: string) {
    Text(label)
      .fontSize(Theme.FontTiny)
      .fontWeight(this.officialCodexSendMode === mode ? FontWeight.Bold : FontWeight.Medium)
      .fontColor(this.officialCodexSendMode === mode ? Theme.TextOnPrimary : Theme.TextSecondary)
      .textAlign(TextAlign.Center)
      .layoutWeight(1)
      .height(30)
      .backgroundColor(this.officialCodexSendMode === mode ? Theme.PrimaryColor : 'rgba(255, 255, 255, 0.055)')
      .borderRadius(8)
      .onClick(() => {
        this.officialCodexSendMode = mode
        authStore.setOfficialCodexSendMode(mode).catch((e: Error) => {
          console.error(`[Settings] Save Official Codex send mode error: ${e.message}`)
        })
      })
  }

  @Builder
  ModelAndPermissionItem() {
    Column({ space: Theme.SpacingMD }) {
      // 当前模型
      Row({ space: 12 }) {
        SymbolGlyph($r('sys.symbol.gearshape'))
          .fontSize(28)
          .fontColor([Theme.TextSecondary])

        Column({ space: 4 }) {
          Text('当前模型')
            .fontSize(Theme.FontBody)
            .fontWeight(FontWeight.Medium)
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
      .onClick(() => {
        this.loadModels()
        this.showModelSheet = true
      })

      // 分隔线
      Divider()
        .color('rgba(255, 255, 255, 0.08)')

      // 权限模式
      Row({ space: 12 }) {
        SymbolGlyph($r('sys.symbol.lock_shield'))
          .fontSize(28)
          .fontColor([Theme.TextSecondary])

        Column({ space: 8 }) {
          Text('权限模式')
            .fontSize(Theme.FontBody)
            .fontWeight(FontWeight.Medium)
            .fontColor(Theme.TextPrimary)

          Row({ space: 6 }) {
            this.PermissionChip(PermissionMode.DEFAULT, '询问')
            this.PermissionChip(PermissionMode.ACCEPT_EDITS, '自动')
            this.PermissionChip(PermissionMode.PLAN, '计划')
            this.PermissionChip(PermissionMode.BYPASS_PERMISSIONS, '跳过')
          }
          .width('100%')
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')

      // 分隔线
      Divider()
        .color('rgba(255, 255, 255, 0.08)')

      // 推理深度
      Row({ space: 12 }) {
        SymbolGlyph($r('sys.symbol.gearshape'))
          .fontSize(28)
          .fontColor([Theme.TextSecondary])

        Column({ space: 8 }) {
          Text('推理深度')
            .fontSize(Theme.FontBody)
            .fontWeight(FontWeight.Medium)
            .fontColor(Theme.TextPrimary)

          Row({ space: 6 }) {
            ForEach(appState.availableEfforts, (level: string) => {
              Text(this.getEffortLabelShort(level))
                .fontSize(Theme.FontTiny)
                .fontWeight(appState.effortLevel === level ? FontWeight.Bold : FontWeight.Medium)
                .fontColor(appState.effortLevel === level ? Theme.TextOnPrimary : Theme.TextSecondary)
                .textAlign(TextAlign.Center)
                .layoutWeight(1)
                .height(30)
                .backgroundColor(appState.effortLevel === level ? Theme.PrimaryColor : 'rgba(255, 255, 255, 0.055)')
                .borderRadius(8)
                .onClick(() => {
                  appState.setEffortLevel(level)
                })
            }, (level: string) => level)
          }
          .width('100%')
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')

      // 分隔线
      Divider()
        .color('rgba(255, 255, 255, 0.08)')

      // 服务商管理
      Row({ space: 12 }) {
        SymbolGlyph($r('sys.symbol.cloud'))
          .fontSize(28)
          .fontColor([Theme.TextSecondary])

        Column({ space: 4 }) {
          Text('服务商管理')
            .fontSize(Theme.FontBody)
            .fontWeight(FontWeight.Medium)
            .fontColor(Theme.TextPrimary)

          Text('管理自定义 API 服务商')
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
      .onClick(() => {
        router.pushUrl({ url: 'pages/ProvidersPage' })
      })
    }
    .width('100%')
    .padding(Theme.SpacingMD)
    .backgroundColor(Theme.GlassBackground)
    .borderRadius(Theme.RadiusMedium)
    .border({ width: 0.5, color: Theme.GlassBorder })
  }

  @Builder
  PermissionChip(mode: PermissionMode, label: string) {
    Text(label)
      .fontSize(Theme.FontTiny)
      .fontWeight(this.currentPermissionMode === mode ? FontWeight.Bold : FontWeight.Medium)
      .fontColor(this.currentPermissionMode === mode ? Theme.TextOnPrimary : Theme.TextSecondary)
      .textAlign(TextAlign.Center)
      .layoutWeight(1)
      .height(30)
      .backgroundColor(this.currentPermissionMode === mode ? Theme.PrimaryColor : 'rgba(255, 255, 255, 0.055)')
      .borderRadius(8)
      .onClick(() => {
        this.currentPermissionMode = mode
        sessionStore.changePermissionMode(mode)
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

      Divider().color(Theme.GlassBorder)

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
        router.pushUrl({ url: 'pages/StorageManagementPage' })
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
  VersionItem() {
    Column({ space: Theme.SpacingSM }) {
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

    }
    .width('100%')
    .padding(Theme.SpacingMD)
    .backgroundColor(Theme.GlassBackground)
    .borderRadius(Theme.RadiusMedium)
    .border({ width: 0.5, color: Theme.GlassBorder })
    .shadow({ radius: Theme.LiquidGlassShadowRadius, color: Theme.LiquidGlassShadowColor, offsetX: 0, offsetY: 4 })
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
    .backgroundColor(Theme.GlassBackground)
    .borderRadius(Theme.RadiusMedium)
    .border({ width: 0.5, color: Theme.GlassBorder })
    .shadow({ radius: Theme.LiquidGlassShadowRadius, color: Theme.LiquidGlassShadowColor, offsetX: 0, offsetY: 4 })
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
  ModelSelectorSheet() {
    Column() {
      Text('选择模型')
        .fontSize(Theme.FontHeading)
        .fontWeight(FontWeight.Bold)
        .fontColor(Theme.TextPrimary)
        .width('100%')
        .textAlign(TextAlign.Center)
        .padding({ top: Theme.SpacingLG, bottom: Theme.SpacingMD })

      if (this.isLoadingModels) {
        LoadingProgress()
          .width(40)
          .height(40)
          .color(Theme.PrimaryColor)
          .margin({ top: Theme.SpacingXL })
      } else if (this.models.length === 0) {
        Text('暂无可用模型')
          .fontSize(Theme.FontCaption)
          .fontColor(Theme.TextSecondary)
          .margin({ top: Theme.SpacingXL })
      } else {
        List({ space: Theme.SpacingSM }) {
          ForEach(this.models, (model: ModelInfo) => {
            ListItem() {
              Row() {
                Column({ space: 4 }) {
                  Text(model.name || model.id)
                    .fontSize(Theme.FontBody)
                    .fontColor(this.currentModel?.id === model.id ? Theme.PrimaryColor : Theme.TextPrimary)

                  if (model.description) {
                    Text(model.description)
                      .fontSize(Theme.FontTiny)
                      .fontColor(Theme.TextSecondary)
                      .maxLines(2)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                  }
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)

                if (this.currentModel?.id === model.id) {
                  SymbolGlyph($r('sys.symbol.checkmark_circle_fill'))
                    .fontSize(20)
                    .fontColor([Theme.PrimaryColor])
                }
              }
              .width('100%')
              .padding(Theme.SpacingMD)
              .backgroundColor(this.currentModel?.id === model.id ?
                Theme.PrimaryColorLight : Theme.BackgroundTertiary)
              .borderRadius(Theme.RadiusMedium)
              .onClick(() => {
                this.selectModel(model.id)
              })
            }
          }, (model: ModelInfo) => model.id)
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .padding({ left: Theme.SpacingLG, right: Theme.SpacingLG, bottom: Theme.SpacingLG })
    .height('100%')
  }

  @Builder
  AdvancedToolsPanel() {
    Column({ space: Theme.SpacingMD }) {
      Row() {
        Column({ space: 4 }) {
          Text('高级工具')
            .fontSize(Theme.FontHeading)
            .fontWeight(FontWeight.Bold)
            .fontColor(Theme.TextPrimary)

          Text(this.showAdvancedTools ? '已展开桌面端高级能力入口' : '技能、记忆、Agent、任务、数据和更新')
            .fontSize(Theme.FontCaption)
            .fontColor(Theme.TextSecondary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Row({ space: 6 }) {
          Text(this.showAdvancedTools ? '收起' : '展开')
            .fontSize(Theme.FontTiny)
            .fontColor(Theme.PrimaryColor)

          SymbolGlyph(this.showAdvancedTools ? $r('sys.symbol.chevron_up') : $r('sys.symbol.chevron_down'))
            .fontSize(12)
            .fontColor([Theme.PrimaryColor])
        }
        .padding({ left: 10, right: 10, top: 6, bottom: 6 })
        .backgroundColor('rgba(10, 132, 255, 0.12)')
        .borderRadius(9)
      }
      .width('100%')

      Row({ space: 8 }) {
        this.AdvancedToolMetric('工具', '5 项', Theme.AccentBlue)
        this.AdvancedToolMetric('维护', '数据/更新', Theme.AccentOrange)
        this.AdvancedToolMetric('默认', '已隐藏', Theme.TextSecondary)
      }
      .width('100%')
    }
    .width('100%')
    .padding(Theme.SpacingLG)
    .backgroundColor('rgba(255, 255, 255, 0.055)')
    .borderRadius(Theme.RadiusLarge)
    .border({ width: 0.5, color: 'rgba(255, 255, 255, 0.09)' })
    .onClick(() => {
      this.showAdvancedTools = !this.showAdvancedTools
    })
  }

  @Builder
  AdvancedToolMetric(label: string, value: string, color: ResourceColor) {
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
    .height(48)
    .padding({ left: 10, right: 10 })
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Start)
    .backgroundColor('rgba(255, 255, 255, 0.045)')
    .borderRadius(10)
  }

  @Builder
  DashboardLinkItem() {
    Row() {
      Column({ space: 2 }) {
        Text('仪表盘')
          .fontSize(Theme.FontBody)
          .fontColor(Theme.TextPrimary)

        Text('设备状态、用量统计、实时日志')
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
      router.pushUrl({ url: 'pages/DashboardPage' })
    })
  }

  @Builder
  SkillsLinkItem() {
    Row() {
      Column({ space: 2 }) {
        Text('技能管理')
          .fontSize(Theme.FontBody)
          .fontColor(Theme.TextPrimary)

        Text('管理自定义技能和工具权限')
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
      router.pushUrl({ url: 'pages/SkillsPage' })
    })
  }

  @Builder
  MemoryLinkItem() {
    Row() {
      Column({ space: 2 }) {
        Text('记忆设置')
          .fontSize(Theme.FontBody)
          .fontColor(Theme.TextPrimary)

        Text('管理 Claude 的记忆和上下文')
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
      router.pushUrl({ url: 'pages/MemorySettingsPage' })
    })
  }

  @Builder
  AgentLinkItem() {
    Row() {
      Column({ space: 2 }) {
        Text('Agent 管理')
          .fontSize(Theme.FontBody)
          .fontColor(Theme.TextPrimary)

        Text('浏览 Claude 预设角色配置')
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
      router.pushUrl({ url: 'pages/AgentsPage' })
    })
  }

  @Builder
  ScheduledTaskLinkItem() {
    Row() {
      Column({ space: 2 }) {
        Text('定时任务')
          .fontSize(Theme.FontBody)
          .fontColor(Theme.TextPrimary)

        Text('管理和执行定时任务')
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
      router.pushUrl({ url: 'pages/ScheduledTasksPage' })
    })
  }

  @Builder
  CheckUpdateItem() {
    Row() {
      Column({ space: 2 }) {
        Text('检查更新')
          .fontSize(Theme.FontBody)
          .fontColor(Theme.TextPrimary)

        Text('检查 Agent 和 Link 更新状态')
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
      router.pushUrl({ url: 'pages/UpdatesPage' })
    })
  }

  private getEffortLabel(level: string): string {
    switch (level) {
      case 'low': return '低 (更快速)'
      case 'medium': return '中 (平衡)'
      case 'high': return '高 (更深入)'
      case 'max': return '最大 (最强推理)'
      default: return level
    }
  }

  private getEffortLabelShort(level: string): string {
    switch (level) {
      case 'low': return '低'
      case 'medium': return '中'
      case 'high': return '高'
      case 'max': return '最大'
      default: return level
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

  private async runDesktopCapabilityCheck(): Promise<void> {
    if (this.currentUrl.length === 0) return

    this.checkingCapabilities = true
    try {
      apiService.setBaseUrl(this.currentUrl)
      const report = await apiService.checkDesktopCapabilities()
      this.desktopCapabilities = report.items
      this.capabilityCheckedAt = report.checkedAt
      this.capabilityOk = report.ok
    } catch (e) {
      console.error(`[Settings] Desktop capability check error: ${e}`)
      this.desktopCapabilities = []
      this.capabilityOk = false
    }
    this.checkingCapabilities = false
  }

  private getCapabilitySummaryText(): string {
    if (this.checkingCapabilities) return '正在逐项检测桌面端 API'
    if (this.desktopCapabilities.length === 0) return '确认手机端是否真的能调用桌面端功能'
    if (this.capabilityOk) return '核心能力已接通，可进行真实操作'
    return '核心能力未完全接通，需要修复桌面端接口'
  }

  private getAvailableCapabilityCount(): number {
    return this.desktopCapabilities.filter((item: DesktopCapabilityItem) => item.available).length
  }

  private getMissingCapabilityCount(): number {
    return this.desktopCapabilities.filter((item: DesktopCapabilityItem) => !item.available).length
  }

  private getRequiredCapabilityText(): string {
    const required = this.desktopCapabilities.filter((item: DesktopCapabilityItem) => item.required)
    const available = required.filter((item: DesktopCapabilityItem) => item.available)
    return `${available.length}/${required.length}`
  }

  private getAvailableCapabilityText(): string {
    return `${this.getAvailableCapabilityCount()}/${this.desktopCapabilities.length}`
  }

  private getMissingCapabilityText(): string {
    return `${this.getMissingCapabilityCount()} 项`
  }

  @Builder
  OfficialCodexAccountRow(account: OfficialCodexControllerAccountItem) {
    Row({ space: 10 }) {
      Column({ space: 4 }) {
        Row({ space: 6 }) {
          Text(this.formatOfficialCodexAccountId(account.accountId))
            .fontSize(Theme.FontBody)
            .fontWeight(account.isSelected ? FontWeight.Bold : FontWeight.Medium)
            .fontColor(Theme.TextPrimary)

          if (account.isSelected) {
            Text('当前使用')
              .fontSize(Theme.FontTiny)
              .fontColor(Theme.TextOnPrimary)
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
              .backgroundColor(Theme.PrimaryColor)
              .borderRadius(999)
          }

          if (account.isCurrentAuthAccount) {
            Text('桌面当前')
              .fontSize(Theme.FontTiny)
              .fontColor(Theme.SuccessColor)
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
              .backgroundColor('rgba(48, 209, 88, 0.14)')
              .borderRadius(999)
          }
        }

        Text(`clientId ${this.formatOfficialCodexClientId(account.clientId)} · ${this.formatOfficialCodexUpdatedAt(account.updatedAt)}`)
          .fontSize(Theme.FontCaption)
          .fontColor(Theme.TextSecondary)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      if (this.officialCodexSwitchingAccount && account.isSelected) {
        LoadingProgress()
          .width(16)
          .height(16)
          .color(Theme.PrimaryColor)
      } else {
        Text(account.isSelected ? '已选中' : '切换')
          .fontSize(Theme.FontTiny)
          .fontColor(account.isSelected ? Theme.TextTertiary : Theme.PrimaryColor)
      }
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 12, bottom: 12 })
    .backgroundColor(account.isSelected ? 'rgba(10, 132, 255, 0.12)' : 'rgba(255, 255, 255, 0.035)')
    .borderRadius(12)
    .border({
      width: 0.5,
      color: account.isSelected ? 'rgba(10, 132, 255, 0.3)' : 'rgba(255,255,255,0.08)'
    })
    .onClick(() => {
      if (!this.officialCodexSwitchingAccount && !account.isSelected) {
        this.selectOfficialCodexAccount(account.accountId)
      }
    })
  }

  private getCapabilityColor(item: DesktopCapabilityItem): ResourceColor {
    if (item.available) return Theme.SuccessColor
    if (item.required) return Theme.ErrorColor
    return Theme.AccentOrange
  }

  private getCapabilityBackground(item: DesktopCapabilityItem): string {
    if (item.available) return 'rgba(48, 209, 88, 0.14)'
    if (item.required) return 'rgba(255, 59, 48, 0.12)'
    return 'rgba(255, 159, 10, 0.12)'
  }

  // MARK: - Official Codex Controller 操作方法

  private getCodexControllerSummaryText(): string {
    if (this.codexControllerLoading) return '正在查询状态...'
    if (this.codexControllerStatus === '未知') return '点击刷新查询 Official Codex 控制器状态'
    if (this.codexControllerWsConnected) return `控制器已连接，已同步 ${this.officialCodexThreadCount} 个官方对话`
    if (this.codexControllerStatus === '已就绪') return '已授权，点击"恢复 & 连接"建立远程连接'
    if (this.codexControllerStatus === '未授权' && this.codexAutomationFallbackAvailable) return '官方未授权；已启用本机自动化兜底发送'
    if (this.codexControllerStatus === '未授权' && this.codexControllerError) return this.codexControllerError
    return `状态: ${this.codexControllerStatus}`
  }

  private refreshOfficialCodexThreadCount(): void {
    let count = 0
    const sessions = sessionStore.sessions || []
    for (let i = 0; i < sessions.length; i++) {
      if (sessions[i].officialCodexThreadId) count++
    }
    this.officialCodexThreadCount = count
  }

  private formatOfficialCodexAccountId(accountId: string): string {
    if (!accountId) return '未知账号'
    if (accountId.length <= 18) return accountId
    return accountId.substring(0, 8) + '...' + accountId.substring(accountId.length - 6)
  }

  private formatOfficialCodexClientId(clientId: string): string {
    if (!clientId) return '未知'
    if (clientId.length <= 10) return clientId
    return clientId.substring(0, 6) + '...' + clientId.substring(clientId.length - 4)
  }

  private formatOfficialCodexUpdatedAt(updatedAt: number): string {
    if (!updatedAt || updatedAt <= 0) return '未知时间'
    const diff = Date.now() - updatedAt
    if (diff < 60 * 1000) return '刚更新'
    if (diff < 60 * 60 * 1000) return `${Math.floor(diff / 60000)} 分钟前`
    if (diff < 24 * 60 * 60 * 1000) return `${Math.floor(diff / 3600000)} 小时前`
    return `${Math.floor(diff / 86400000)} 天前`
  }

  private async refreshOfficialCodexAccounts(): Promise<void> {
    if (!apiService.getBaseUrl()) return
    try {
      const result = await apiService.listCodexControllerAccounts()
      const list = (result['accounts'] as Array<Record<string, Object>> | undefined) || []
      const next: OfficialCodexControllerAccountItem[] = []
      for (let i = 0; i < list.length; i++) {
        const raw = list[i]
        const item = new OfficialCodexControllerAccountItem()
        item.accountId = (raw['accountId'] as string) || ''
        item.clientId = (raw['clientId'] as string) || ''
        item.updatedAt = Number(raw['updatedAt'] as number) || 0
        item.isCurrentAuthAccount = ((raw['isCurrentAuthAccount'] as boolean) || false) === true
        item.isSelected = ((raw['isSelected'] as boolean) || false) === true
        next.push(item)
      }
      this.officialCodexAccounts = next
      this.officialCodexCurrentAuthAccountId = (result['currentAuthAccountId'] as string) || ''
      this.officialCodexSelectedAccountId = (result['selectedAccountId'] as string) || ''
    } catch (e) {
      console.error(`[Settings] refresh Codex accounts error: ${e}`)
      this.officialCodexAccounts = []
      this.officialCodexCurrentAuthAccountId = ''
      this.officialCodexSelectedAccountId = ''
    }
  }

  private async syncOfficialCodexThreadsFromSettings(): Promise<void> {
    this.officialCodexSyncLoading = true
    try {
      if (!this.codexControllerWsConnected && this.codexControllerStatus === '已就绪') {
        await apiService.restoreCodexControllerSession(true)
      }
      await sessionStore.syncOfficialCodexThreadsToLocal(50)
      this.refreshOfficialCodexThreadCount()
      await this.refreshCodexControllerStatus()
    } catch (e) {
      console.error(`[Settings] Sync Official Codex threads error: ${e}`)
    }
    this.officialCodexSyncLoading = false
  }

  private getCodexControllerStatusColor(): ResourceColor {
    switch (this.codexControllerStatus) {
      case '已连接': return Theme.SuccessColor
      case '已就绪': return Theme.AccentBlue
      case '未授权': return Theme.AccentOrange
      case '未知': return Theme.TextTertiary
      default: return Theme.TextSecondary
    }
  }

  private getCodexControllerStatusBackground(): string {
    switch (this.codexControllerStatus) {
      case '已连接': return 'rgba(48, 209, 88, 0.14)'
      case '已就绪': return 'rgba(10, 132, 255, 0.14)'
      case '未授权': return 'rgba(255, 159, 10, 0.14)'
      default: return 'rgba(255, 255, 255, 0.045)'
    }
  }

  private async refreshCodexControllerStatus(): Promise<void> {
    if (!apiService.getBaseUrl()) return
    this.codexControllerLoading = true
    try {
      // 先查 WS 状态
      let wsConnected = false
      try {
        const wsStatus = await apiService.getCodexControllerWsStatus()
        wsConnected = (wsStatus['connected'] as boolean) || false
      } catch (_e) { /* WS status endpoint may fail if not enrolled */ }

      // 再查整体状态
      let statusText = '未知'
      let clientId = ''
      let errorMsg = ''
      let fallbackAvailable = false
      try {
        const status = await apiService.getCodexRemoteStatus()
        fallbackAvailable = (status['automationFallbackAvailable'] as boolean) || false
        const controllerSession = status['controllerSession'] as Record<string, Object> | null
        if (controllerSession) {
          statusText = wsConnected ? '已连接' : '已就绪'
          clientId = (controllerSession['clientId'] as string) || ''
        } else {
          statusText = '未授权'
          // 捕获具体错误原因
          errorMsg = (status['controllerError'] as string) || ''
        }
      } catch (_e) {
        statusText = '未授权'
      }

      this.codexControllerStatus = statusText
      this.codexControllerClientId = clientId
      this.codexControllerWsConnected = wsConnected
      this.codexControllerError = errorMsg
      this.codexAutomationFallbackAvailable = fallbackAvailable
      await this.refreshOfficialCodexAccounts()
    } catch (e) {
      console.error(`[Settings] Codex controller status error: ${e}`)
      this.codexControllerStatus = '未授权'
      this.codexAutomationFallbackAvailable = false
    }
    this.codexControllerLoading = false
  }

  private async restoreAndConnectCodexController(): Promise<void> {
    this.codexControllerLoading = true
    try {
      const result = await apiService.restoreCodexControllerSession(true)
      if ((result['ok'] as boolean)) {
        this.codexControllerStatus = '已连接'
        this.codexControllerWsConnected = true
        // 获取 clientId
        const session = result['session'] as Record<string, Object> | null
        if (session) {
          this.codexControllerClientId = (session['clientId'] as string) || ''
        }
      } else {
        this.codexControllerStatus = '未授权'
      }
      await this.refreshOfficialCodexAccounts()
    } catch (e) {
      console.error(`[Settings] Restore controller error: ${e}`)
      this.codexControllerStatus = '未授权'
    }
    this.codexControllerLoading = false
  }

  private async disconnectCodexController(): Promise<void> {
    this.codexControllerLoading = true
    try {
      await apiService.disconnectCodexController()
      this.codexControllerWsConnected = false
      this.codexControllerStatus = '已就绪'
      await this.refreshOfficialCodexAccounts()
    } catch (e) {
      console.error(`[Settings] Disconnect controller error: ${e}`)
    }
    this.codexControllerLoading = false
  }

  private async selectOfficialCodexAccount(accountId: string): Promise<void> {
    this.officialCodexSwitchingAccount = true
    try {
      const result = await apiService.selectCodexControllerAccount(accountId, true)
      const ok = ((result['ok'] as boolean) || false) === true
      if (ok) {
        const ws = result['ws'] as Record<string, Object> | null
        this.codexControllerWsConnected = !!(ws && (ws['connected'] as boolean))
        const session = result['session'] as Record<string, Object> | null
        if (session) {
          this.codexControllerClientId = (session['clientId'] as string) || ''
          this.codexControllerStatus = this.codexControllerWsConnected ? '已连接' : '已就绪'
        }
      }
      await this.refreshOfficialCodexAccounts()
    } catch (e) {
      console.error(`[Settings] select Codex account error: ${e}`)
    }
    this.officialCodexSwitchingAccount = false
  }
}
