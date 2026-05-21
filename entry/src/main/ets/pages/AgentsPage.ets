/**
 * Agent 管理页面 - 浏览和查看 Claude Agent
 * API：/api/agents, /api/agents/:name
 */

import { Theme } from '../common/Theme'
import { apiService, AgentListItem, AgentDefinition } from '../services/APIService'
import { HdsNavigation, HdsNavigationTitleMode, ScrollEffectType } from '@hms.hds.hdsBaseComponent'
import { hdsMaterial } from '@hms.hds.hdsMaterial'

@Entry
@Component
struct AgentsPage {
  @State activeAgents: AgentListItem[] = []
  @State allAgents: AgentListItem[] = []
  @State isLoading: boolean = false
  @State errorMessage: string = ''
  @State showDetail: boolean = false
  @State detailAgent: AgentDetailState = new AgentDetailState()

  private scroller: Scroller = new Scroller()

  aboutToAppear(): void {
    this.loadAgents()
  }

  private async loadAgents(): Promise<void> {
    this.isLoading = true
    this.errorMessage = ''

    try {
      const response = await apiService.getAgents()
      if (response.activeAgents) {
        this.activeAgents = response.activeAgents
      }
      if (response.allAgents) {
        this.allAgents = response.allAgents
      }
    } catch (e) {
      console.error('[AgentsPage] Failed to load agents:', e)
      this.errorMessage = '加载失败: ' + (e as Error).message
    }

    this.isLoading = false
  }

  private async showAgentDetail(agentType: string): Promise<void> {
    try {
      const response = await apiService.getAgentDetail(agentType)
      if (response && response.agent) {
        this.detailAgent.name = response.agent.name
        this.detailAgent.description = response.agent.description
        this.detailAgent.model = response.agent.model
        this.detailAgent.tools = response.agent.tools
        this.detailAgent.systemPrompt = response.agent.systemPrompt
        this.detailAgent.color = response.agent.color
        this.showDetail = true
      }
    } catch (e) {
      console.error('[AgentsPage] Failed to load agent detail:', e)
    }
  }

  private getSourceLabel(source: string): string {
    switch (source) {
      case 'built-in': return '内置'
      case 'userSettings': return '用户'
      case 'projectSettings': return '项目'
      case 'localSettings': return '本地'
      case 'policySettings': return '策略'
      case 'flagSettings': return '标记'
      case 'plugin': return '插件'
      default: return source || '未知'
    }
  }

  build() {
    Stack() {
      HdsNavigation() {
        List({ space: Theme.SpacingMD, scroller: this.scroller }) {
          ListItem() {
            Row().width('100%').height(100)
          }

          // 活跃 Agent
          ListItem() {
            Column({ space: Theme.SpacingSM }) {
              Text('当前活跃 Agent')
                .fontSize(Theme.FontCaption)
                .fontWeight(FontWeight.Medium)
                .fontColor(Theme.TextSecondary)
                .width('100%')

              if (this.isLoading) {
                Column() {
                  LoadingProgress()
                    .width(24).height(24).color(Theme.PrimaryColor)
                }
                .width('100%')
                .height(80)
                .justifyContent(FlexAlign.Center)
                .backgroundColor(Theme.GlassBackground)
                .borderRadius(Theme.RadiusMedium)
                .border({ width: 0.5, color: Theme.GlassBorder })
              } else if (this.errorMessage) {
                Column() {
                  Text(this.errorMessage)
                    .fontSize(Theme.FontBody)
                    .fontColor(Theme.ErrorColor)
                }
                .width('100%')
                .padding(Theme.SpacingMD)
                .backgroundColor(Theme.GlassBackground)
                .borderRadius(Theme.RadiusMedium)
                .border({ width: 0.5, color: Theme.GlassBorder })
              } else if (this.activeAgents.length === 0) {
                Column() {
                  Text('暂无活跃 Agent')
                    .fontSize(Theme.FontBody)
                    .fontColor(Theme.TextSecondary)
                }
                .width('100%')
                .padding(Theme.SpacingMD)
                .backgroundColor(Theme.GlassBackground)
                .borderRadius(Theme.RadiusMedium)
                .border({ width: 0.5, color: Theme.GlassBorder })
              } else {
                ForEach(this.activeAgents, (agent: AgentListItem) => {
                  this.AgentCard(agent, true)
                }, (agent: AgentListItem) => agent.agentType)
              }
            }
            .width('100%')
          }

          // 全部 Agent
          ListItem() {
            Column({ space: Theme.SpacingSM }) {
              Text('全部 Agent')
                .fontSize(Theme.FontCaption)
                .fontWeight(FontWeight.Medium)
                .fontColor(Theme.TextSecondary)
                .width('100%')

              if (this.isLoading) {
                // loading already shown above
              } else if (this.allAgents.length === 0) {
                Column() {
                  Text('没有更多 Agent')
                    .fontSize(Theme.FontBody)
                    .fontColor(Theme.TextSecondary)
                }
                .width('100%')
                .padding(Theme.SpacingMD)
                .backgroundColor(Theme.GlassBackground)
                .borderRadius(Theme.RadiusMedium)
                .border({ width: 0.5, color: Theme.GlassBorder })
              } else {
                ForEach(this.allAgents, (agent: AgentListItem) => {
                  this.AgentCard(agent, false)
                }, (agent: AgentListItem) => agent.agentType + '-' + agent.source)
              }
            }
            .width('100%')
          }

          // 说明
          ListItem() {
            Column() {
              Text('Agent 是 Claude 的预设角色配置，可通过桌面端管理。点击 Agent 查看详情。')
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
          title: { mainTitle: 'Agent 管理' },
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

      // Agent 详情弹窗
      if (this.showDetail) {
        this.AgentDetailSheet()
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  AgentCard(agent: AgentListItem, showActiveBadge: boolean) {
    Column({ space: 0 }) {
      Row() {
        // 颜色标记
        Circle()
          .width(12)
          .height(12)
          .fill(this.parseColor(agent.color))

        Column({ space: 4 }) {
          Row({ space: 8 }) {
            Text(agent.agentType)
              .fontSize(Theme.FontBody)
              .fontWeight(FontWeight.Medium)
              .fontColor(Theme.TextPrimary)

            if (agent.isActive && showActiveBadge) {
              Text('活跃')
                .fontSize(10)
                .fontColor(Theme.AccentGreen)
                .backgroundColor(Color.Green)
                .opacity(0.15)
                .borderRadius(4)
                .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            }
          }

          if (agent.description) {
            Text(agent.description)
              .fontSize(Theme.FontCaption)
              .fontColor(Theme.TextSecondary)
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }

          Row({ space: 8 }) {
            if (agent.modelDisplay) {
              Text(agent.modelDisplay)
                .fontSize(Theme.FontTiny)
                .fontColor(Theme.AccentBlue)
            }

            Text(this.getSourceLabel(agent.source))
              .fontSize(Theme.FontTiny)
              .fontColor(Theme.TextTertiary)
              .backgroundColor(Theme.BackgroundTertiary)
              .borderRadius(4)
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          }
          .margin({ top: 4 })
        }
        .margin({ left: 10 })
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(14)
          .fontColor([Theme.TextSecondary])
      }
      .width('100%')
      .padding(Theme.SpacingMD)
    }
    .backgroundColor(Theme.GlassBackground)
    .borderRadius(Theme.RadiusMedium)
    .border({ width: 0.5, color: Theme.GlassBorder })
    .shadow({ radius: Theme.LiquidGlassShadowRadius, color: Theme.LiquidGlassShadowColor, offsetX: 0, offsetY: 4 })
    .margin({ bottom: Theme.SpacingSM })
    .onClick(() => {
      this.showAgentDetail(agent.agentType)
    })
  }

  @Builder
  AgentDetailSheet() {
    Column() {
      // 遮罩
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#66000000')
        .onClick(() => {
          this.showDetail = false
        })

      // 内容
      Column({ space: Theme.SpacingSM }) {
        // 标题
        Row() {
          Circle()
            .width(16)
            .height(16)
            .fill(this.parseColor(this.detailAgent.color))

          Text(this.detailAgent.name)
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(Theme.TextPrimary)
            .margin({ left: 10 })
        }
        .width('100%')

        if (this.detailAgent.description) {
          Text(this.detailAgent.description)
            .fontSize(Theme.FontBody)
            .fontColor(Theme.TextSecondary)
            .width('100%')
        }

        // 模型
        if (this.detailAgent.model) {
          Row({ space: 8 }) {
            Text('模型')
              .fontSize(Theme.FontCaption)
              .fontColor(Theme.TextTertiary)
            Text(this.detailAgent.model)
              .fontSize(Theme.FontBody)
              .fontColor(Theme.TextPrimary)
          }
          .width('100%')
        }

        // 工具列表
        if (this.detailAgent.tools && this.detailAgent.tools.length > 0) {
          Column({ space: 6 }) {
            Text('工具')
              .fontSize(Theme.FontCaption)
              .fontColor(Theme.TextTertiary)
              .width('100%')

            Flex({ wrap: FlexWrap.Wrap }) {
              ForEach(this.detailAgent.tools, (tool: string) => {
                Text(tool)
                  .fontSize(Theme.FontTiny)
                  .fontColor(Theme.AccentBlue)
                  .backgroundColor(Theme.PrimaryColorLight)
                  .borderRadius(6)
                  .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                  .margin({ right: 6, bottom: 6 })
              }, (tool: string) => tool)
            }
            .width('100%')
          }
          .width('100%')
        }

        // 系统提示词
        if (this.detailAgent.systemPrompt) {
          Column({ space: 6 }) {
            Text('系统提示词')
              .fontSize(Theme.FontCaption)
              .fontColor(Theme.TextTertiary)
              .width('100%')

            Text(this.detailAgent.systemPrompt)
              .fontSize(Theme.FontTiny)
              .fontColor(Theme.TextSecondary)
              .lineHeight(18)
              .width('100%')
          }
          .width('100%')
        }

        // 关闭按钮
        Button() {
          Text('关闭')
            .fontSize(Theme.FontBody)
            .fontColor(Color.White)
        }
        .width('100%')
        .height(44)
        .backgroundColor(Theme.PrimaryColor)
        .borderRadius(Theme.RadiusMedium)
        .onClick(() => {
          this.showDetail = false
        })
        .margin({ top: 8 })
      }
      .width('100%')
      .padding(Theme.SpacingLG)
      .backgroundColor(Theme.BackgroundPrimary)
      .borderRadius({ topLeft: 20, topRight: 20 })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.End)
  }

  private parseColor(color: string): ResourceColor {
    if (!color) return Theme.PrimaryColor
    switch (color) {
      case 'blue': return '#007AFF'
      case 'green': return '#34C759'
      case 'orange': return '#FF9500'
      case 'red': return '#FF3B30'
      case 'purple': return '#AF52DE'
      case 'yellow': return '#FFCC00'
      case 'pink': return '#FF2D55'
      case 'teal': return '#5AC8FA'
      case 'indigo': return '#5856D6'
      default: return color as string
    }
  }
}

class AgentDetailState {
  name: string = ''
  description: string = ''
  model: string = ''
  tools: string[] = []
  systemPrompt: string = ''
  color: string = ''
}