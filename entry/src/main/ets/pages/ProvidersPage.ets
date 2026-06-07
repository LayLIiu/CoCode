/**
 * 服务商管理页面
 * 与 iOS 端功能一致
 */

import { Theme } from '../common/Theme'
import { Provider, ProviderPreset, PROVIDER_PRESETS, ProviderInput, NetworkInfo, getBestUrl, getConnectionTypeName } from '../models/Models'
import { providerStore } from '../stores/ProviderStore'
import { apiService } from '../services/APIService'
import { HdsNavigation, ScrollEffectType, HdsNavigationBadgeIconOptions, HdsNavigationTitleMode } from '@hms.hds.hdsBaseComponent'
import { hdsMaterial } from '@hms.hds.hdsMaterial'
import router from '@ohos.router'

@Entry
@Component
struct ProvidersPage {
  @State providers: Provider[] = []
  @State activeProviderId: string | null = null
  @State isLoading: boolean = false

  // 网络信息
  @State networkInfo: NetworkInfo | null = null
  @State isLoadingNetwork: boolean = false

  // 表单
  @State showForm: boolean = false
  @State editingProvider: Provider | null = null
  @State formPresetId: string = 'openai'
  @State formName: string = ''
  @State formApiKey: string = ''
  @State formBaseUrl: string = ''

  // HdsNavigation 菜单项
  private providerMenus: Array<HdsNavigationBadgeIconOptions> = []

  aboutToAppear(): void {
    this.initMenus()
    this.loadProviders()
  }

  private initMenus(): void {
    const iconOpts: HdsNavigationBadgeIconOptions = {
      content: {
        icon: $r('sys.symbol.plus'),
        action: () => { this.openAddForm() }
      }
    }
    this.providerMenus = [iconOpts]
  }

  private async loadProviders(): Promise<void> {
    this.isLoading = true
    await providerStore.loadProviders()
    this.providers = providerStore.providers
    this.activeProviderId = providerStore.activeProviderId
    this.isLoading = false
  }

  private async toggleTunnel(): Promise<void> {
    if (!this.networkInfo) return
    try {
      const result = await apiService.enableTunnel(!this.networkInfo.tunnelEnabled)
      // 刷新网络信息
      await this.loadNetworkInfo()
    } catch (e) {
      console.error(`[ProvidersPage] Toggle tunnel error: ${e}`)
    }
  }

  private async loadNetworkInfo(): Promise<void> {
    this.isLoadingNetwork = true
    try {
      this.networkInfo = await apiService.getNetworkInfo()
    } catch (e) {
      console.error(`[ProvidersPage] Fetch network info error: ${e}`)
    }
    this.isLoadingNetwork = false
  }

  private async activateOfficial(): Promise<void> {
    try {
      await providerStore.activateOfficial()
      this.activeProviderId = null
    } catch (e) {
      console.error(`[ProvidersPage] Activate official error: ${e}`)
    }
  }

  private async activateProvider(id: string): Promise<void> {
    try {
      await providerStore.activateProvider(id)
      this.activeProviderId = id
    } catch (e) {
      console.error(`[ProvidersPage] Activate provider error: ${e}`)
    }
  }

  private async deleteProvider(id: string): Promise<void> {
    try {
      await providerStore.deleteProvider(id)
      this.providers = providerStore.providers
      this.activeProviderId = providerStore.activeProviderId
    } catch (e) {
      console.error(`[ProvidersPage] Delete provider error: ${e}`)
    }
  }

  private openAddForm(): void {
    this.editingProvider = null
    this.formPresetId = 'openai'
    this.formName = ''
    this.formApiKey = ''
    this.formBaseUrl = ''
    this.showForm = true
  }

  private openEditForm(provider: Provider): void {
    this.editingProvider = provider
    this.formPresetId = provider.presetId
    this.formName = provider.name
    this.formApiKey = provider.apiKey
    this.formBaseUrl = provider.baseUrl
    this.showForm = true
  }

  private selectPreset(presetId: string): void {
    this.formPresetId = presetId
    const preset = PROVIDER_PRESETS.find(p => p.id === presetId)
    if (preset) {
      this.formName = preset.name
      this.formBaseUrl = preset.baseUrl
    }
  }

  private async saveProvider(): Promise<void> {
    if (!this.formName || !this.formApiKey) return

    const preset = PROVIDER_PRESETS.find(p => p.id === this.formPresetId)
    if (!preset) return

    const input = new ProviderInput()
    input.presetId = preset.id
    input.name = this.formName
    input.apiKey = this.formApiKey
    input.baseUrl = this.formBaseUrl
    input.apiFormat = preset.apiFormat
    input.models = preset.defaultModels

    try {
      if (this.editingProvider) {
        await providerStore.updateProvider(this.editingProvider.id, input)
      } else {
        await providerStore.createProvider(input)
      }
      this.providers = providerStore.providers
      this.activeProviderId = providerStore.activeProviderId
      this.showForm = false
    } catch (e) {
      console.error(`[ProvidersPage] Save provider error: ${e}`)
    }
  }

  build() {
    Stack() {
      HdsNavigation() {
        Column() {
          // 内容区域
          Scroll() {
            Column({ space: 20 }) {
              this.ProviderOverview()

              // 连接设置
              Column({ space: 8 }) {
                Row() {
                  Text('连接设置')
                    .fontSize(Theme.FontTiny)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(Theme.TextSecondary)
                }
                .width('100%')

                // 获取网络地址按钮
                Row({ space: 12 }) {
                  Column({ space: 4 }) {
                    Text('获取网络地址')
                      .fontSize(Theme.FontCaption)
                      .fontColor(Theme.TextPrimary)
                    Text('从桌面端获取局域网和公网地址')
                      .fontSize(Theme.FontTiny)
                      .fontColor(Theme.TextSecondary)
                  }
                  .layoutWeight(1)
                  .alignItems(HorizontalAlign.Start)

                  if (this.isLoadingNetwork) {
                    LoadingProgress()
                      .width(20)
                      .height(20)
                      .color(Theme.PrimaryColor)
                  } else {
                    SymbolGlyph($r('sys.symbol.arrow_clockwise'))
                      .fontSize(14)
                      .fontColor([Theme.PrimaryColor])
                  }
                }
                .width('100%')
                .padding(12)
                .backgroundColor(Theme.BackgroundSecondary)
                .borderRadius(8)
                .onClick(() => this.loadNetworkInfo())

                // 网络地址列表
                if (this.networkInfo) {
                  if (getBestUrl(this.networkInfo)) {
                    this.NetworkInfoRow('最优连接', getBestUrl(this.networkInfo)!,
                      getConnectionTypeName(this.networkInfo), Theme.AccentGreen)
                  }

                  if (this.networkInfo.lanUrl) {
                    this.NetworkInfoRow('局域网地址', this.networkInfo.lanUrl, '', Theme.AccentGreen)
                  }

                  if (this.networkInfo.tailscaleUrl) {
                    this.NetworkInfoRow('Tailscale', this.networkInfo.tailscaleUrl, '', Theme.AccentBlue)
                  }

                  Column() {
                    Row({ space: 8 }) {
                      SymbolGlyph($r('sys.symbol.magnifyingglass'))
                        .fontSize(14)
                        .fontColor([Theme.AccentOrange])

                      Text('公网隧道')
                        .fontSize(Theme.FontCaption)
                        .fontColor(Theme.TextPrimary)

                      Blank()

                      if (this.networkInfo && this.networkInfo.tunnelEnabled) {
                        Text('已开启')
                          .fontSize(Theme.FontTiny)
                          .fontColor(Theme.AccentGreen)
                      } else {
                        Text('点击开启')
                          .fontSize(Theme.FontTiny)
                          .fontColor(Theme.PrimaryColor)
                      }
                    }
                    .width('100%')

                    if (this.networkInfo.tunnelUrl) {
                      Text(this.networkInfo.tunnelUrl)
                        .fontSize(Theme.FontTiny)
                        .fontColor(Theme.TextSecondary)
                        .width('100%')
                    }
                  }
                  .width('100%')
                  .padding(12)
                  .backgroundColor(Theme.BackgroundSecondary)
                  .borderRadius(8)
                  .onClick(() => this.toggleTunnel())
                }
              }

              // 官方认证
              Column({ space: 8 }) {
                Row() {
                  Text('官方认证')
                    .fontSize(Theme.FontTiny)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(Theme.TextSecondary)
                }
                .width('100%')

                Row({ space: 12 }) {
                  Column({ space: 4 }) {
                    Text('Claude Official')
                      .fontSize(Theme.FontBody)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(Theme.TextPrimary)
                    Text('使用官方 Anthropic 认证')
                      .fontSize(Theme.FontTiny)
                      .fontColor(Theme.TextSecondary)
                  }
                  .layoutWeight(1)
                  .alignItems(HorizontalAlign.Start)

                  if (!this.activeProviderId) {
                    Text('当前')
                      .fontSize(Theme.FontTiny)
                      .fontColor(Theme.TextOnPrimary)
                      .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                      .backgroundColor(Theme.PrimaryColor)
                      .borderRadius(4)
                  }
                }
                .width('100%')
                .padding(12)
                .backgroundColor(Theme.BackgroundSecondary)
                .borderRadius(8)
                .onClick(() => this.activateOfficial())
              }

              // 自定义服务商
              Column({ space: 8 }) {
                Row() {
                  Text('自定义服务商')
                    .fontSize(Theme.FontTiny)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(Theme.TextSecondary)
                }
                .width('100%')

                if (this.providers.length === 0) {
                  Text('暂无自定义服务商，点击右上角添加')
                    .fontSize(Theme.FontCaption)
                    .fontColor(Theme.TextSecondary)
                    .width('100%')
                    .textAlign(TextAlign.Center)
                    .padding(12)
                    .backgroundColor(Theme.BackgroundSecondary)
                    .borderRadius(8)
                } else {
                  ForEach(this.providers, (provider: Provider) => {
                    this.ProviderCard(provider)
                  }, (provider: Provider) => provider.id)
                }
              }
            }
            .padding({ left: Theme.SpacingLG, right: Theme.SpacingLG })
            .margin({ top: Theme.SpacingMD })
          }
          .width('100%')
          .layoutWeight(1)
          .scrollBar(BarState.Off)
        }
        .width('100%')
        .height('100%')
        .padding({ top: 100 })
      }
      .titleBar({
        content: {
          title: { mainTitle: '服务商' },
          menu: { value: this.providerMenus },
        },
        style: {
          scrollEffectOpts: {
            enableScrollEffect: false,
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
      .hideBackButton(false)
      .backgroundColor('#000000')
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    }
    .width('100%')
    .height('100%')
    .bindContentCover(this.showForm, this.ProviderFormSheet(), {
      modalTransition: ModalTransition.NONE,
      backgroundColor: Color.Transparent,
      onDisappear: () => this.showForm = false
    })
  }

  @Builder
  ProviderOverview() {
    Column({ space: 14 }) {
      Row() {
        Column({ space: 5 }) {
          Text('服务商中心')
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .fontColor(Theme.TextPrimary)

          Text(this.activeProviderId ? '正在使用自定义服务商' : '正在使用官方认证')
            .fontSize(Theme.FontCaption)
            .fontColor(Theme.TextSecondary)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Row({ space: 6 }) {
          Row()
            .width(8)
            .height(8)
            .borderRadius(4)
            .backgroundColor(this.activeProviderId ? Theme.AccentBlue : Theme.AccentGreen)

          Text(this.activeProviderId ? '自定义' : '官方')
            .fontSize(Theme.FontTiny)
            .fontColor(this.activeProviderId ? Theme.AccentBlue : Theme.AccentGreen)
        }
        .padding({ left: 10, right: 10, top: 6, bottom: 6 })
        .backgroundColor(this.activeProviderId ? 'rgba(10, 132, 255, 0.14)' : 'rgba(48, 209, 88, 0.14)')
        .borderRadius(10)
      }
      .width('100%')

      Row({ space: 8 }) {
        this.ProviderMetric('自定义', this.providers.length.toString(), Theme.AccentBlue)
        this.ProviderMetric('网络', this.networkInfo ? '已获取' : '未获取', this.networkInfo ? Theme.AccentGreen : Theme.TextTertiary)
        this.ProviderMetric('隧道', this.networkInfo?.tunnelEnabled ? '开启' : '关闭', this.networkInfo?.tunnelEnabled ? Theme.AccentOrange : Theme.TextTertiary)
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
  ProviderMetric(label: string, value: string, color: ResourceColor) {
    Column({ space: 4 }) {
      Text(label)
        .fontSize(11)
        .fontColor(Theme.TextTertiary)

      Text(value)
        .fontSize(Theme.FontTiny)
        .fontWeight(FontWeight.Medium)
        .fontColor(color)
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
  NetworkInfoRow(label: string, url: string, tag: string, color: string) {
    Column({ space: 4 }) {
      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.wifi'))
          .fontSize(14)
          .fontColor([color])

        Text(label)
          .fontSize(Theme.FontCaption)
          .fontColor(Theme.TextPrimary)

        if (tag) {
          Text(tag)
            .fontSize(10)
            .fontColor(color)
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .backgroundColor(`${color}26`)
            .borderRadius(4)
        }

        Blank()
      }
      .width('100%')

      Text(url)
        .fontSize(Theme.FontTiny)
        .fontColor(Theme.TextSecondary)
        .width('100%')
    }
    .width('100%')
    .padding(12)
    .backgroundColor(Theme.BackgroundSecondary)
    .borderRadius(8)
  }

  @Builder
  ProviderCard(provider: Provider) {
    Column({ space: 12 }) {
      Row({ space: 12 }) {
        Column({ space: 4 }) {
          Text(provider.name)
            .fontSize(Theme.FontBody)
            .fontWeight(FontWeight.Medium)
            .fontColor(Theme.TextPrimary)
          Text(provider.apiFormat)
            .fontSize(Theme.FontTiny)
            .fontColor(Theme.TextSecondary)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        if (this.activeProviderId === provider.id) {
          Text('当前')
            .fontSize(Theme.FontTiny)
            .fontColor(Theme.TextOnPrimary)
            .padding({ left: 8, right: 8, top: 4, bottom: 4 })
            .backgroundColor(Theme.PrimaryColor)
            .borderRadius(4)
        }
      }
      .width('100%')
      .onClick(() => this.openEditForm(provider))

      Row({ space: 8 }) {
        Button('激活')
          .fontSize(Theme.FontTiny)
          .fontColor(this.activeProviderId === provider.id ? Theme.TextTertiary : Theme.TextPrimary)
          .backgroundColor(Theme.BackgroundTertiary)
          .borderRadius(8)
          .layoutWeight(1)
          .enabled(this.activeProviderId !== provider.id)
          .onClick(() => this.activateProvider(provider.id))

        Button('编辑')
          .fontSize(Theme.FontTiny)
          .fontColor(Theme.TextPrimary)
          .backgroundColor(Theme.BackgroundTertiary)
          .borderRadius(8)
          .layoutWeight(1)
          .onClick(() => this.openEditForm(provider))

        Button('删除')
          .fontSize(Theme.FontTiny)
          .fontColor(Theme.ErrorColor)
          .backgroundColor(Theme.BackgroundTertiary)
          .borderRadius(8)
          .layoutWeight(1)
          .onClick(() => this.deleteProvider(provider.id))
      }
      .width('100%')
    }
    .width('100%')
    .padding(12)
    .backgroundColor(Theme.BackgroundSecondary)
    .borderRadius(12)
  }

  // 服务商表单
  @Builder
  ProviderFormSheet() {
    Column() {
      Column({ space: 12 }) {
        // 标题栏
        Row() {
          Text('取消')
            .fontSize(Theme.FontCaption)
            .fontColor(Theme.TextSecondary)
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .backgroundColor(Theme.BackgroundSecondary)
            .borderRadius(8)
            .onClick(() => this.showForm = false)

          Text(this.editingProvider ? '编辑服务商' : '添加服务商')
            .fontSize(Theme.FontHeading)
            .fontWeight(FontWeight.Bold)
            .fontColor(Theme.TextPrimary)
            .layoutWeight(1)
            .textAlign(TextAlign.Center)

          Text('保存')
            .fontSize(Theme.FontCaption)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.formName && this.formApiKey ? Theme.PrimaryColor : Theme.TextTertiary)
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .backgroundColor(Theme.BackgroundSecondary)
            .borderRadius(8)
            .onClick(() => this.saveProvider())
        }
        .width('100%')

        // 预设选择（仅在新增时）
        if (!this.editingProvider) {
          Row() {
            Text('选择预设')
              .fontSize(Theme.FontTiny)
              .fontWeight(FontWeight.Bold)
              .fontColor(Theme.TextSecondary)
          }
          .width('100%')

          Scroll() {
            Row({ space: 8 }) {
              ForEach(PROVIDER_PRESETS.filter(p => p.id !== 'custom'), (preset: ProviderPreset) => {
                Text(preset.name)
                  .fontSize(Theme.FontTiny)
                  .fontColor(this.formPresetId === preset.id ? Theme.TextOnPrimary : Theme.TextPrimary)
                  .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                  .backgroundColor(this.formPresetId === preset.id ? Theme.PrimaryColor : Theme.BackgroundTertiary)
                  .borderRadius(8)
                  .onClick(() => this.selectPreset(preset.id))
              }, (preset: ProviderPreset) => preset.id)
            }
          }
          .scrollable(ScrollDirection.Horizontal)
          .scrollBar(BarState.Off)
          .width('100%')
        }

        // 表单字段
        Column({ space: 12 }) {
          TextInput({ placeholder: '名称', text: this.formName })
            .fontSize(Theme.FontBody)
            .fontColor(Theme.TextPrimary)
            .backgroundColor(Theme.BackgroundSecondary)
            .borderRadius(8)
            .onChange((value: string) => this.formName = value)

          TextInput({ placeholder: 'API Key', text: this.formApiKey })
            .fontSize(Theme.FontBody)
            .fontColor(Theme.TextPrimary)
            .backgroundColor(Theme.BackgroundSecondary)
            .borderRadius(8)
            .type(InputType.Password)
            .onChange((value: string) => this.formApiKey = value)

          TextInput({ placeholder: 'Base URL', text: this.formBaseUrl })
            .fontSize(Theme.FontBody)
            .fontColor(Theme.TextPrimary)
            .backgroundColor(Theme.BackgroundSecondary)
            .borderRadius(8)
            .onChange((value: string) => this.formBaseUrl = value)
        }
        .width('100%')
      }
      .width('100%')
      .padding(Theme.SpacingLG)
      .backgroundColor(Theme.BackgroundPrimary)
      .borderRadius({ topLeft: 20, topRight: 20 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('rgba(0,0,0,0.5)')
    .justifyContent(FlexAlign.End)
    .onClick(() => {
      this.showForm = false
    })
  }
}
