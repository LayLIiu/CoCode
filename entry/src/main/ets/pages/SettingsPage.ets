/**
 * 设置页面 - 与 iOS 端保持一致的实现
 */

import { Theme } from '../common/Theme'
import { authStore } from '../stores/AuthStore'
import { appState, ThemeMode } from '../stores/AppState'
import { sessionStore } from '../stores/SessionStore'
import { ModelInfo, ServerMode, PermissionMode, getPermissionModeDisplayName, getPermissionModeDescription, ServerProfile } from '../models/Models'
import { HdsNavigation, ScrollEffectType, HdsNavigationTitleMode } from '@hms.hds.hdsBaseComponent'
import { hdsMaterial } from '@hms.hds.hdsMaterial'
import router from '@ohos.router'
import http from '@ohos.net.http'
import { openScanner, ScannedAddresses } from '../services/ScanService'
import { connectionManager, ConnectionType, ConnectionQuality } from '../services/ConnectionManager'

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

  // 模型选择
  @State showModelSheet: boolean = false
  @State isLoadingModels: boolean = false

  private readonly appVersion: string = '1.0.0'
  private readonly buildTime: string = '2026-05-08'
  private modelsChangedListener: (() => void) | null = null

  aboutToAppear(): void {
    this.loadSettings()
    this.updateConnectionStatus()
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
            Row().width('100%').height(100)
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

          // 模型与权限
          if (this.isLoggedIn) {
            ListItem() {
              this.SettingSection('模型与权限')
            }

            ListItem() {
              this.ModelItem()
            }

            ListItem() {
              this.PermissionModeItem()
            }

            ListItem() {
              this.EffortItem()
            }

            ListItem() {
              this.ProviderManageItem()
            }
          }

          // 功能
          if (this.isLoggedIn) {
            ListItem() {
              this.SettingSection('功能')
            }

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
          }

          // 外观设置
          ListItem() {
            this.SettingSection('外观')
          }

          ListItem() {
            this.ThemeItem()
          }

          // 安全与隐私
          if (this.isLoggedIn) {
            ListItem() {
              this.SettingSection('安全与隐私')
            }

            ListItem() {
              this.BiometricItem()
            }
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

          // 关于与更新
          ListItem() {
            this.SettingSection('关于与更新')
          }

          ListItem() {
            this.VersionItem()
          }

          ListItem() {
            this.BuildTimeItem()
          }

          ListItem() {
            this.CheckUpdateItem()
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
      .linearGradient({
        angle: 180,
        colors: [
          [Theme.BackgroundGradientStart, 0.0],
          [Theme.BackgroundGradientMiddle, 0.5],
          [Theme.BackgroundGradientEnd, 1.0]
        ]
      })
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

      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(14)
        .fontColor([Theme.TextSecondary])
        .margin({ left: 8 })
    }
    .width('100%')
    .padding(Theme.SpacingMD)
    .backgroundColor(Theme.GlassBackground)
    .borderRadius(Theme.RadiusMedium)
    .border({ width: 0.5, color: Theme.GlassBorder })
    .shadow({ radius: Theme.LiquidGlassShadowRadius, color: Theme.LiquidGlassShadowColor, offsetX: 0, offsetY: 4 })
    .onClick(() => {
      router.pushUrl({ url: 'pages/ProfilePage' })
    })
  }

  @Builder
  ConnectionItem() {
    Column({ space: Theme.SpacingSM }) {
      // 当前连接状态
      Row() {
        Column({ space: 2 }) {
          Text('当前连接')
            .fontSize(Theme.FontBody)
            .fontColor(Theme.TextPrimary)

          if (this.currentUrl) {
            Row({ space: 6 }) {
              Text('●')
                .fontSize(8)
                .fontColor(this.getConnectionQualityColor())
              Text(this.getConnectionStatusText())
                .fontSize(Theme.FontCaption)
                .fontColor(this.getConnectionQualityColor())
            }
          } else {
            Text('未连接')
              .fontSize(Theme.FontCaption)
              .fontColor(Theme.ErrorColor)
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        // 连接类型标签
        if (this.connectionType !== 'unknown') {
          Text(this.getConnectionTypeText())
            .fontSize(Theme.FontTiny)
            .fontColor(this.connectionType === 'lan' ? Theme.AccentGreen : Theme.AccentBlue)
            .backgroundColor(this.connectionType === 'lan' ? Theme.AccentGreen + '20' : Theme.AccentBlue + '20')
            .borderRadius(4)
            .padding({ left: 8, right: 8, top: 2, bottom: 2 })
            .margin({ right: 8 })
        }

        // 连接速度
        if (this.testingLatency) {
          LoadingProgress()
            .width(20)
            .height(20)
            .color(Theme.PrimaryColor)
        } else if (this.connectionLatency > 0) {
          Text(this.formatLatency(this.connectionLatency))
            .fontSize(Theme.FontCaption)
            .fontColor(this.getLatencyColor(this.connectionLatency))
        } else {
          Text('测速').fontSize(Theme.FontCaption).fontColor(Theme.TextSecondary)
        }
      }
      .width('100%')
      .onClick(() => {
        if (!this.testingLatency && this.currentUrl.length > 0) {
          this.testSmartConnection()
        }
      })

      Divider().color(Theme.GlassBorder)

      // 服务器列表
      if (this.serverProfiles.length > 0) {
        ForEach(this.serverProfiles, (profile: ServerProfile) => {
          Row() {
            // 类型图标
            Column() {
              SymbolGlyph(this.getProfileIcon(profile.type))
                .fontSize(14)
                .fontColor([this.activeProfileId === profile.id ? Theme.PrimaryColor : Theme.TextSecondary])
            }
            .width(28)
            .height(28)
            .backgroundColor(this.activeProfileId === profile.id ?
              Theme.PrimaryColor + '20' : Theme.GlassBackground)
            .borderRadius(7)

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
            .margin({ left: 10 })

            // 活跃指示
            if (this.activeProfileId === profile.id) {
              Text('使用中')
                .fontSize(Theme.FontTiny)
                .fontColor(Theme.PrimaryColor)
                .backgroundColor(Theme.PrimaryColor + '20')
                .borderRadius(4)
                .padding({ left: 8, right: 8, top: 2, bottom: 2 })
            }

            SymbolGlyph($r('sys.symbol.chevron_right'))
              .fontSize(12)
              .fontColor([Theme.TextTertiary])
          }
          .width('100%')
          .padding({ top: 8, bottom: 8 })
          .onClick(() => {
            this.switchProfile(profile.id)
          })
        }, (profile: ServerProfile) => profile.id)
      }

      Divider().color(Theme.GlassBorder)

      // 添加服务器 + 管理按钮
      Row({ space: 12 }) {
        Row({ space: 6 }) {
          SymbolGlyph($r('sys.symbol.qrcode'))
            .fontSize(14)
            .fontColor([Theme.PrimaryColor])

          Text('扫码添加')
            .fontSize(Theme.FontCaption)
            .fontColor(Theme.PrimaryColor)
        }
        .onClick(async () => {
          const result = await openScanner()
          if (result?.bestUrl) {
            this.newProfileName = ''
            this.newProfileUrl = result.bestUrl
            this.showAddProfileSheet = true
          }
        })

        Row({ space: 6 }) {
          SymbolGlyph($r('sys.symbol.plus_circle'))
            .fontSize(14)
            .fontColor([Theme.PrimaryColor])

          Text('手动输入')
            .fontSize(Theme.FontCaption)
            .fontColor(Theme.PrimaryColor)
        }
        .onClick(() => {
          this.newProfileUrl = ''
          this.newProfileName = ''
          this.showAddProfileSheet = true
        })

        if (this.serverProfiles.length > 0) {
          Blank()

          Row({ space: 6 }) {
            SymbolGlyph($r('sys.symbol.trash'))
              .fontSize(14)
              .fontColor([Theme.ErrorColor])

            Text('移除当前')
              .fontSize(Theme.FontCaption)
              .fontColor(Theme.ErrorColor)
          }
          .onClick(() => {
            if (this.activeProfileId) {
              this.showDeleteProfileDialog(this.activeProfileId)
            }
          })
        }
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
    .backgroundColor(Theme.GlassBackground)
    .borderRadius(Theme.RadiusMedium)
    .border({ width: 0.5, color: Theme.GlassBorder })
    .shadow({ radius: Theme.LiquidGlassShadowRadius, color: Theme.LiquidGlassShadowColor, offsetX: 0, offsetY: 4 })
    .onClick(() => {
      this.loadModels()
      this.showModelSheet = true
    })
  }

  @Builder
  PermissionModeItem() {
    Column({ space: Theme.SpacingSM }) {
      this.PermissionModeRow(PermissionMode.DEFAULT)
      Divider().color(Theme.GlassBorder)
      this.PermissionModeRow(PermissionMode.ACCEPT_EDITS)
      Divider().color(Theme.GlassBorder)
      this.PermissionModeRow(PermissionMode.PLAN)
      Divider().color(Theme.GlassBorder)
      this.PermissionModeRow(PermissionMode.BYPASS_PERMISSIONS)
    }
    .width('100%')
    .padding(Theme.SpacingMD)
    .backgroundColor(Theme.GlassBackground)
    .borderRadius(Theme.RadiusMedium)
    .border({ width: 0.5, color: Theme.GlassBorder })
    .shadow({ radius: Theme.LiquidGlassShadowRadius, color: Theme.LiquidGlassShadowColor, offsetX: 0, offsetY: 4 })
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
  BiometricItem() {
    Row() {
      Column({ space: 2 }) {
        Text('生物识别锁屏')
          .fontSize(Theme.FontBody)
          .fontColor(Theme.TextPrimary)

        Text('切回前台时验证指纹/面部')
          .fontSize(Theme.FontTiny)
          .fontColor(Theme.TextSecondary)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Toggle({ type: ToggleType.Switch, isOn: this.biometricEnabled })
        .onChange(async (isOn: boolean) => {
          this.biometricEnabled = isOn
          await authStore.setBiometricEnabled(isOn)
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
    .backgroundColor(Theme.GlassBackground)
    .borderRadius(Theme.RadiusMedium)
    .border({ width: 0.5, color: Theme.GlassBorder })
    .shadow({ radius: Theme.LiquidGlassShadowRadius, color: Theme.LiquidGlassShadowColor, offsetX: 0, offsetY: 4 })
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
  EffortItem() {
    Column({ space: Theme.SpacingSM }) {
      ForEach(appState.availableEfforts, (level: string) => {
        Row() {
          Text(this.getEffortLabel(level))
            .fontSize(Theme.FontBody)
            .fontColor(Theme.TextPrimary)

          Blank()

          Radio({ value: level, group: 'effort' })
            .checked(appState.effortLevel === level)
            .onChange((isChecked: boolean) => {
              if (isChecked) {
                appState.setEffortLevel(level)
              }
            })
        }
        .width('100%')
        .padding({ top: 8, bottom: 8 })

        if (level !== appState.availableEfforts[appState.availableEfforts.length - 1]) {
          Divider().color(Theme.GlassBorder)
        }
      }, (level: string) => level)
    }
    .width('100%')
    .padding(Theme.SpacingMD)
    .backgroundColor(Theme.GlassBackground)
    .borderRadius(Theme.RadiusMedium)
    .border({ width: 0.5, color: Theme.GlassBorder })
    .shadow({ radius: Theme.LiquidGlassShadowRadius, color: Theme.LiquidGlassShadowColor, offsetX: 0, offsetY: 4 })
  }

  @Builder
  ProviderManageItem() {
    Row() {
      Column({ space: 2 }) {
        Text('服务商管理')
          .fontSize(Theme.FontBody)
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
    .padding(Theme.SpacingMD)
    .backgroundColor(Theme.GlassBackground)
    .borderRadius(Theme.RadiusMedium)
    .border({ width: 0.5, color: Theme.GlassBorder })
    .shadow({ radius: Theme.LiquidGlassShadowRadius, color: Theme.LiquidGlassShadowColor, offsetX: 0, offsetY: 4 })
    .onClick(() => {
      router.pushUrl({ url: 'pages/ProvidersPage' })
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

    try {
      const status = await connectionManager.smartConnect()
      this.connectionType = status.type
      this.connectionQuality = status.quality
      this.connectionLatency = status.latency
      this.currentUrl = authStore.serverUrl
      this.serverProfiles = [...authStore.serverProfiles]
      this.activeProfileId = authStore.activeProfileId
    } catch (e) {
      console.error(`[Settings] Smart connect error: ${e}`)
    }

    this.testingLatency = false
  }
}
