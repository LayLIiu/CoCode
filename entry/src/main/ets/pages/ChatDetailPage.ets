/**
 * 对话详情页 - 实时消息收发
 */

import { Theme } from '../common/Theme'
import { Message, SessionStatus, ModelInfo } from '../models/Models'
import { sessionStore } from '../stores/SessionStore'
import { apiService } from '../services/APIService'
import { MarkdownRenderer } from '../components/MarkdownRenderer'
import router from '@ohos.router'

// 斜杠命令定义
class SlashCommand {
  name: string = ''
  description: string = ''
  example: string = ''
}

@Entry
@Component
struct ChatDetailPage {
  @State messages: Message[] = []
  @State inputText: string = ''
  @State conversationTitle: string = '对话'
  @State sessionId: string = ''
  @State chatStatus: SessionStatus = 'idle'
  @State showMenu: boolean = false
  @State showModelSelector: boolean = false
  @State showSlashCommands: boolean = false
  @State models: ModelInfo[] = []
  @State currentModel: string = ''
  @State isLoadingModels: boolean = false

  private scroller: Scroller = new Scroller()

  // 斜杠命令列表
  private slashCommands: SlashCommand[] = [
    { name: '/compact', description: '压缩对话上下文', example: '/compact' },
    { name: '/cost', description: '显示token使用量', example: '/cost' },
    { name: '/clear', description: '清除当前对话', example: '/clear' },
    { name: '/config', description: '查看当前配置', example: '/config' },
    { name: '/doctor', description: '诊断问题', example: '/doctor' },
    { name: '/init', description: '初始化CLAUDE.md', example: '/init' },
    { name: '/permissions', description: '权限设置', example: '/permissions' },
    { name: '/pr-comments', description: 'PR评论', example: '/pr-comments' },
    { name: '/release', description: '发布相关', example: '/release' },
    { name: '/review', description: '代码审查', example: '/review' },
    { name: '/terminal-setup', description: '终端设置', example: '/terminal-setup' },
    { name: '/vim', description: 'Vim模式', example: '/vim' }
  ]

  aboutToAppear(): void {
    this.getRouterParams()
    this.loadMessages()
    this.setupCallbacks()
  }

  aboutToDisappear(): void {
    sessionStore.setCurrentSession(null)
  }

  private getRouterParams(): void {
    const params = router.getParams() as Record<string, string>
    if (params) {
      if (params['sessionId']) {
        this.sessionId = params['sessionId'] as string
        sessionStore.setCurrentSession(this.sessionId)
      }
      if (params['title']) {
        this.conversationTitle = params['title'] as string
      }
    }
  }

  private async loadMessages(): Promise<void> {
    await sessionStore.loadMessages(this.sessionId)
    const msgs = sessionStore.messages.get(this.sessionId)
    if (msgs) {
      this.messages = msgs
    }
    this.scrollToBottom()
  }

  private setupCallbacks(): void {
    sessionStore.onMessagesChanged = (sid: string) => {
      if (sid === this.sessionId) {
        const msgs = sessionStore.messages.get(this.sessionId)
        if (msgs) {
          this.messages = msgs
        }
        this.scrollToBottom()
      }
    }

    sessionStore.onStatusChanged = (sid: string, status: SessionStatus) => {
      if (sid === this.sessionId) {
        this.chatStatus = status
      }
    }
  }

  private scrollToBottom(): void {
    setTimeout(() => {
      this.scroller.scrollEdge(Edge.Bottom)
    }, 100)
  }

  // 加载模型列表
  private async loadModels(): Promise<void> {
    if (this.models.length > 0) return

    this.isLoadingModels = true
    try {
      const response = await apiService.getModels()
      this.models = response.models || []
      const current = await apiService.getCurrentModel()
      this.currentModel = current.id
    } catch (e) {
      console.error(`[ChatDetailPage] Load models error: ${e}`)
    }
    this.isLoadingModels = false
  }

  // 选择模型
  private async selectModel(modelId: string): Promise<void> {
    try {
      await apiService.setCurrentModel(modelId)
      this.currentModel = modelId
      this.showModelSelector = false
      this.showMenu = false
    } catch (e) {
      console.error(`[ChatDetailPage] Set model error: ${e}`)
    }
  }

  // 选择斜杠命令
  private selectSlashCommand(cmd: string): void {
    this.inputText = cmd + ' '
    this.showSlashCommands = false
    this.showMenu = false
  }

  // 获取工具输入摘要
  private getToolInputSummary(toolName: string, input: Record<string, Object>): string {
    if (toolName === 'Bash') {
      const cmd = input['command']
      if (typeof cmd === 'string') {
        return cmd.length > 50 ? cmd.substring(0, 50) + '...' : cmd
      }
    } else if (toolName === 'Read' || toolName === 'Write' || toolName === 'Edit') {
      const filePath = input['file_path']
      if (typeof filePath === 'string') {
        const parts = filePath.split('/')
        if (parts.length > 0) {
          return parts[parts.length - 1]
        }
        return filePath
      }
    } else if (toolName === 'Glob' || toolName === 'Grep') {
      const pattern = input['pattern']
      if (typeof pattern === 'string') {
        return pattern
      }
    }
    return ''
  }

  build() {
    Column() {
      // 顶部固定标题栏
      Row() {
        // 返回按钮
        Column() {
          SymbolGlyph($r('sys.symbol.chevron_left'))
            .fontSize(20)
            .fontColor([Theme.TextPrimary])
        }
        .width(36)
        .height(36)
        .backgroundColor(Theme.GlassBackground)
        .borderRadius(18)
        .justifyContent(FlexAlign.Center)
        .backgroundBlurStyle(BlurStyle.COMPONENT_THIN)
        .onClick(() => {
          router.back()
        })

        Column({ space: 2 }) {
          Text(this.conversationTitle)
            .fontSize(Theme.FontBody)
            .fontColor(Theme.TextPrimary)
            .fontWeight(FontWeight.Medium)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          Text(this.getStatusText())
            .fontSize(Theme.FontTiny)
            .fontColor(this.getStatusColor())
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Center)
        .margin({ left: 8, right: 8 })

        // 菜单按钮
        Column() {
          SymbolGlyph($r('sys.symbol.ellipsis_circle'))
            .fontSize(20)
            .fontColor([Theme.TextPrimary])
        }
        .width(36)
        .height(36)
        .backgroundColor(Theme.GlassBackground)
        .borderRadius(18)
        .justifyContent(FlexAlign.Center)
        .backgroundBlurStyle(BlurStyle.COMPONENT_THIN)
        .onClick(() => {
          this.showMenu = !this.showMenu
        })
      }
      .width('100%')
      .padding({ left: Theme.SpacingLG, right: Theme.SpacingLG, top: 50, bottom: Theme.SpacingMD })
      .backgroundColor(Theme.BackgroundPrimary)
      .backgroundBlurStyle(BlurStyle.COMPONENT_THIN)

      // 消息列表（可滚动）
      List({ scroller: this.scroller }) {
        if (this.chatStatus === 'thinking' || this.chatStatus === 'streaming' || this.chatStatus === 'tool_executing') {
          ListItem() {
            this.StreamingIndicator()
          }
        }

        ForEach(this.messages, (message: Message) => {
          ListItem() {
            this.MessageBubble(message)
          }
        }, (message: Message) => message.id)

        // 底部留白（给输入框留空间）
        ListItem() {
          Row().width('100%').height(80)
        }
      }
      .width('100%')
      .layoutWeight(1)
      .padding({ left: Theme.SpacingLG, right: Theme.SpacingLG })
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })

      // 底部固定输入框
      Column() {
        this.InputAreaContent()
      }
      .width('100%')
      .padding({ left: Theme.SpacingLG, right: Theme.SpacingLG, bottom: Theme.SpacingLG })
      .backgroundColor(Theme.BackgroundPrimary)
      .backgroundBlurStyle(BlurStyle.COMPONENT_THIN)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.BackgroundPrimary)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
    .bindContentCover(this.showMenu, this.MenuPopup(), {
      modalTransition: ModalTransition.NONE,
      backgroundColor: Color.Transparent,
      onDisappear: () => {
        this.showMenu = false
      }
    })
    .bindContentCover(this.showModelSelector, this.ModelSelectorPopup(), {
      modalTransition: ModalTransition.NONE,
      backgroundColor: Color.Transparent,
      onDisappear: () => {
        this.showModelSelector = false
      }
    })
    .bindContentCover(this.showSlashCommands, this.SlashCommandsPopup(), {
      modalTransition: ModalTransition.NONE,
      backgroundColor: Color.Transparent,
      onDisappear: () => {
        this.showSlashCommands = false
      }
    })
  }

  @Builder
  StreamingIndicator() {
    Row({ space: 8 }) {
      LoadingProgress()
        .width(16)
        .height(16)
        .color(Theme.PrimaryColor)

      Text(this.getStatusText())
        .fontSize(Theme.FontCaption)
        .fontColor(Theme.TextSecondary)
    }
    .width('100%')
    .padding(Theme.SpacingMD)
    .backgroundColor(Theme.BackgroundSecondary)
    .borderRadius(Theme.RadiusMedium)
    .margin({ bottom: Theme.SpacingSM })
  }

  @Builder
  MessageBubble(message: Message) {
    Column() {
      Row() {
        if (message.type === 'user') {
          Blank().layoutWeight(1)
        }

        if (message.type === 'user') {
          this.UserBubble(message)
        } else if (message.type === 'assistant') {
          this.AssistantBubble(message)
        } else if (message.type === 'thinking') {
          this.ThinkingBubble(message)
        } else if (message.type === 'tool_use') {
          this.ToolUseBubble(message)
        } else if (message.type === 'permission_request') {
          this.PermissionBubble(message)
        } else if (message.type === 'question') {
          this.QuestionBubble(message)
        }

        if (message.type !== 'user') {
          Blank().layoutWeight(1)
        }
      }
      .width('100%')
    }
    .width('100%')
    .margin({ bottom: Theme.SpacingMD })
  }

  @Builder
  UserBubble(message: Message) {
    Column() {
      MarkdownRenderer({ content: message.content })
    }
    .padding({ left: 16, right: 16, top: 10, bottom: 10 })
    .backgroundColor(Theme.PrimaryColor)
    .borderRadius(18)
  }

  @Builder
  AssistantBubble(message: Message) {
    Column() {
      MarkdownRenderer({ content: message.content })
    }
    .padding({ left: 14, right: 14, top: 10, bottom: 10 })
    .backgroundColor(Theme.BackgroundSecondary)
    .borderRadius(18)
  }

  @Builder
  ThinkingBubble(message: Message) {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.lightbulb'))
          .fontSize(16)
          .fontColor([Theme.AccentPurple])

        Text('思考过程')
          .fontSize(Theme.FontCaption)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.TextSecondary)
      }

      if (message.content) {
        Text(message.content)
          .fontSize(Theme.FontCaption)
          .fontColor(Theme.TextSecondary)
      }
    }
    .width('100%')
    .padding(Theme.SpacingMD)
    .backgroundColor(Theme.BackgroundSecondary)
    .borderRadius(Theme.RadiusMedium)
  }

  @Builder
  ToolUseBubble(message: Message) {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        this.ToolIcon(message.toolName || 'Tool')

        Text(message.toolName || '工具')
          .fontSize(Theme.FontCaption)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.TextPrimary)

        Blank()

        this.ToolStatusBadge(message.toolStatus)
      }

      if (message.toolInput) {
        Text(this.getToolInputSummary(message.toolName || '', message.toolInput))
          .fontSize(Theme.FontTiny)
          .fontColor(Theme.TextTertiary)
          .fontFamily('monospace')
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }

      if (message.toolResult) {
        this.ToolResultContent(message.toolResult, message.toolStatus === 'failed')
      }
    }
    .width('100%')
    .padding(Theme.SpacingMD)
    .backgroundColor(Theme.BackgroundSecondary)
    .borderRadius(Theme.RadiusMedium)
  }

  @Builder
  ToolIcon(toolName: string) {
    if (toolName === 'Bash') {
      SymbolGlyph($r('sys.symbol.play_fill'))
        .fontSize(16)
        .fontColor([Theme.AccentOrange])
    } else if (toolName === 'Read') {
      SymbolGlyph($r('sys.symbol.doc_text'))
        .fontSize(16)
        .fontColor([Theme.AccentBlue])
    } else if (toolName === 'Write' || toolName === 'Edit') {
      SymbolGlyph($r('sys.symbol.square_and_pencil'))
        .fontSize(16)
        .fontColor([Theme.AccentGreen])
    } else if (toolName === 'Glob' || toolName === 'Grep') {
      SymbolGlyph($r('sys.symbol.magnifyingglass'))
        .fontSize(16)
        .fontColor([Theme.AccentBlue])
    } else if (toolName === 'Agent') {
      SymbolGlyph($r('sys.symbol.person_fill'))
        .fontSize(16)
        .fontColor([Theme.AccentPurple])
    } else {
      SymbolGlyph($r('sys.symbol.gearshape'))
        .fontSize(16)
        .fontColor([Theme.TextSecondary])
    }
  }

  @Builder
  ToolResultContent(result: string, isError: boolean) {
    Column() {
      Text(result.length > 500 ? result.substring(0, 500) + '...' : result)
        .fontSize(Theme.FontTiny)
        .fontColor(isError ? Theme.ErrorColor : Theme.TextSecondary)
        .fontFamily('monospace')
        .maxLines(10)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .padding(Theme.SpacingSM)
    .backgroundColor(isError ? 'rgba(255, 59, 48, 0.1)' : Theme.BackgroundTertiary)
    .borderRadius(Theme.RadiusSmall)
    .margin({ top: Theme.SpacingSM })
  }

  @Builder
  ToolStatusBadge(status?: string) {
    if (status === 'running') {
      Row({ space: 4 }) {
        LoadingProgress().width(12).height(12).color(Theme.PrimaryColor)
        Text('执行中').fontSize(Theme.FontTiny).fontColor(Theme.PrimaryColor)
      }
    } else if (status === 'completed') {
      Row({ space: 4 }) {
        SymbolGlyph($r('sys.symbol.checkmark_circle_fill')).fontSize(12).fontColor([Theme.SuccessColor])
        Text('完成').fontSize(Theme.FontTiny).fontColor(Theme.SuccessColor)
      }
    } else if (status === 'failed') {
      Row({ space: 4 }) {
        SymbolGlyph($r('sys.symbol.xmark_circle_fill')).fontSize(12).fontColor([Theme.ErrorColor])
        Text('失败').fontSize(Theme.FontTiny).fontColor(Theme.ErrorColor)
      }
    } else {
      Row({ space: 4 }) {
        SymbolGlyph($r('sys.symbol.clock')).fontSize(12).fontColor([Theme.TextTertiary])
        Text('等待').fontSize(Theme.FontTiny).fontColor(Theme.TextTertiary)
      }
    }
  }

  @Builder
  PermissionBubble(message: Message) {
    Column({ space: 12 }) {
      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.lock_shield_fill'))
          .fontSize(20)
          .fontColor([Theme.AccentOrange])

        Text('权限请求')
          .fontSize(Theme.FontBody)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.TextPrimary)
      }

      if (message.toolName) {
        Text('工具: ' + message.toolName)
          .fontSize(Theme.FontCaption)
          .fontColor(Theme.TextSecondary)
      }

      if (message.permissionDescription) {
        Text(message.permissionDescription)
          .fontSize(Theme.FontCaption)
          .fontColor(Theme.TextSecondary)
      }

      if (!message.isPermissionHandled) {
        Row({ space: 12 }) {
          Button('拒绝')
            .fontSize(Theme.FontCaption)
            .fontColor(Theme.TextPrimary)
            .backgroundColor(Theme.BackgroundTertiary)
            .borderRadius(8)
            .layoutWeight(1)
            .onClick(() => {
              if (message.permissionId) {
                sessionStore.sendPermissionResponse(message.permissionId, false)
                message.isPermissionHandled = true
                message.permissionResult = false
              }
            })

          Button('允许')
            .fontSize(Theme.FontCaption)
            .fontColor(Theme.TextOnPrimary)
            .backgroundColor(Theme.PrimaryColor)
            .borderRadius(8)
            .layoutWeight(1)
            .onClick(() => {
              if (message.permissionId) {
                sessionStore.sendPermissionResponse(message.permissionId, true)
                message.isPermissionHandled = true
                message.permissionResult = true
              }
            })
        }
        .width('100%')
      } else {
        Row({ space: 4 }) {
          SymbolGlyph($r(message.permissionResult ? 'sys.symbol.checkmark_circle_fill' : 'sys.symbol.xmark_circle_fill'))
            .fontSize(14)
            .fontColor([message.permissionResult ? Theme.SuccessColor : Theme.ErrorColor])
          Text(message.permissionResult ? '已允许' : '已拒绝')
            .fontSize(Theme.FontCaption)
            .fontColor(message.permissionResult ? Theme.SuccessColor : Theme.ErrorColor)
        }
      }
    }
    .width('100%')
    .padding(Theme.SpacingLG)
    .backgroundColor(Theme.BackgroundSecondary)
    .borderRadius(Theme.RadiusMedium)
  }

  @Builder
  QuestionBubble(message: Message) {
    Column({ space: 12 }) {
      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.questionmark_circle_fill'))
          .fontSize(20)
          .fontColor([Theme.AccentPurple])

        Text('请选择')
          .fontSize(Theme.FontBody)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.TextPrimary)
      }

      Text(message.content)
        .fontSize(Theme.FontCaption)
        .fontColor(Theme.TextSecondary)

      if (!message.isQuestionAnswered && message.options && message.options.length > 0) {
        Column({ space: 8 }) {
          ForEach(message.options, (option: string, index: number) => {
            Button(option)
              .fontSize(Theme.FontCaption)
              .fontColor(Theme.TextPrimary)
              .backgroundColor(Theme.BackgroundTertiary)
              .borderRadius(8)
              .width('100%')
              .onClick(() => {
                if (message.questionId) {
                  sessionStore.sendQuestionResponse(message.questionId, option)
                  message.isQuestionAnswered = true
                  message.selectedAnswer = option
                }
              })
          }, (option: string, index: number) => `option-${index}`)
        }
        .width('100%')
      } else if (message.selectedAnswer) {
        Row({ space: 4 }) {
          SymbolGlyph($r('sys.symbol.checkmark_circle_fill'))
            .fontSize(14)
            .fontColor([Theme.SuccessColor])
          Text(message.selectedAnswer)
            .fontSize(Theme.FontCaption)
            .fontColor(Theme.SuccessColor)
        }
      }
    }
    .width('100%')
    .padding(Theme.SpacingLG)
    .backgroundColor(Theme.BackgroundSecondary)
    .borderRadius(Theme.RadiusMedium)
  }

  @Builder
  InputAreaContent() {
    Row({ space: 10 }) {
      // 菜单按钮
      Column() {
        SymbolGlyph($r('sys.symbol.plus'))
          .fontSize(16)
          .fontColor([Theme.TextSecondary])
      }
      .width(36)
      .height(36)
      .backgroundColor(Theme.BackgroundSecondary)
      .borderRadius(18)
      .justifyContent(FlexAlign.Center)
      .onClick(() => {
        this.showMenu = !this.showMenu
        this.showModelSelector = false
        this.showSlashCommands = false
      })

      TextInput({ placeholder: '发送消息...', text: this.inputText })
        .layoutWeight(1)
        .height(36)
        .backgroundColor(Theme.BackgroundSecondary)
        .borderRadius(18)
        .fontColor(Theme.TextPrimary)
        .onChange((value: string) => {
          this.inputText = value
        })
        .onSubmit(() => {
          this.sendMessage()
        })

      Column() {
        SymbolGlyph($r('sys.symbol.arrow_up'))
          .fontSize(16)
          .fontColor([this.inputText ? Theme.TextPrimary : Theme.TextSecondary])
      }
      .width(36)
      .height(36)
      .backgroundColor(this.inputText ? Theme.PrimaryColor : Theme.BackgroundSecondary)
      .borderRadius(18)
      .justifyContent(FlexAlign.Center)
      .onClick(() => {
        this.sendMessage()
      })
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 8, bottom: 8 })
    .backgroundColor(Theme.LiquidGlassBackground)
    .borderRadius(24)
    .backgroundBlurStyle(BlurStyle.COMPONENT_THIN)
  }

  // 菜单弹出
  @Builder
  MenuPopup() {
    Column() {
      Column({ space: 4 }) {
        // 模型选择器
        Row({ space: 12 }) {
          SymbolGlyph($r('sys.symbol.waveform'))
            .fontSize(20)
            .fontColor([Theme.PrimaryColor])

          Text('模型选择器')
            .fontSize(Theme.FontBody)
            .fontColor(Theme.TextPrimary)

          Blank()

          if (this.currentModel) {
            Text(this.currentModel)
              .fontSize(Theme.FontTiny)
              .fontColor(Theme.TextTertiary)
          }

          SymbolGlyph($r('sys.symbol.chevron_right'))
            .fontSize(14)
            .fontColor([Theme.TextTertiary])
        }
        .width('100%')
        .padding(Theme.SpacingMD)
        .backgroundColor(Theme.BackgroundSecondary)
        .borderRadius(12)
        .onClick(() => {
          this.showMenu = false
          this.showModelSelector = true
          this.loadModels()
        })

        // 斜杠命令
        Row({ space: 12 }) {
          SymbolGlyph($r('sys.symbol.folder'))
            .fontSize(20)
            .fontColor([Theme.AccentPurple])

          Text('斜杠命令')
            .fontSize(Theme.FontBody)
            .fontColor(Theme.TextPrimary)

          Blank()

          SymbolGlyph($r('sys.symbol.chevron_right'))
            .fontSize(14)
            .fontColor([Theme.TextTertiary])
        }
        .width('100%')
        .padding(Theme.SpacingMD)
        .backgroundColor(Theme.BackgroundSecondary)
        .borderRadius(12)
        .onClick(() => {
          this.showMenu = false
          this.showSlashCommands = true
        })
      }
      .width(200)
      .padding(Theme.SpacingSM)
      .backgroundColor(Theme.BackgroundPrimary)
      .borderRadius(16)
      .shadow({ radius: 20, color: 'rgba(0,0,0,0.15)', offsetY: 4 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('rgba(0,0,0,0.3)')
    .justifyContent(FlexAlign.End)
    .padding({ left: Theme.SpacingLG, right: Theme.SpacingLG, bottom: 80 })
    .onClick(() => {
      this.showMenu = false
    })
  }

  // 模型选择器弹出
  @Builder
  ModelSelectorPopup() {
    Column() {
      Column({ space: 12 }) {
        // 标题栏
        Row() {
          SymbolGlyph($r('sys.symbol.chevron_left'))
            .fontSize(20)
            .fontColor([Theme.TextPrimary])
            .onClick(() => {
              this.showModelSelector = false
              this.showMenu = true
            })

          Text('选择模型')
            .fontSize(Theme.FontHeading)
            .fontWeight(FontWeight.Bold)
            .fontColor(Theme.TextPrimary)
            .layoutWeight(1)
            .textAlign(TextAlign.Center)

          Row().width(20)
        }
        .width('100%')
        .padding({ bottom: Theme.SpacingSM })

        if (this.isLoadingModels) {
          Column() {
            LoadingProgress()
              .width(40)
              .height(40)
              .color(Theme.PrimaryColor)

            Text('加载中...')
              .fontSize(Theme.FontCaption)
              .fontColor(Theme.TextSecondary)
              .margin({ top: Theme.SpacingMD })
          }
          .width('100%')
          .height(200)
          .justifyContent(FlexAlign.Center)
        } else if (this.models.length === 0) {
          Column() {
            Text('暂无可用模型')
              .fontSize(Theme.FontBody)
              .fontColor(Theme.TextSecondary)
          }
          .width('100%')
          .height(200)
          .justifyContent(FlexAlign.Center)
        } else {
          List({ space: 8 }) {
            ForEach(this.models, (model: ModelInfo) => {
              ListItem() {
                Row({ space: 12 }) {
                  Column({ space: 4 }) {
                    Text(model.name || model.id)
                      .fontSize(Theme.FontBody)
                      .fontColor(Theme.TextPrimary)

                    if (model.description) {
                      Text(model.description)
                        .fontSize(Theme.FontTiny)
                        .fontColor(Theme.TextTertiary)
                        .maxLines(2)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                    }
                  }
                  .layoutWeight(1)
                  .alignItems(HorizontalAlign.Start)

                  if (this.currentModel === model.id) {
                    SymbolGlyph($r('sys.symbol.checkmark_circle_fill'))
                      .fontSize(20)
                      .fontColor([Theme.PrimaryColor])
                  }
                }
                .width('100%')
                .padding(Theme.SpacingMD)
                .backgroundColor(this.currentModel === model.id ? Theme.PrimaryColorLight : Theme.BackgroundSecondary)
                .borderRadius(12)
                .onClick(() => {
                  this.selectModel(model.id)
                })
              }
            }, (model: ModelInfo) => model.id)
          }
          .width('100%')
          .height(Math.min(this.models.length * 80, 300))
          .scrollBar(BarState.Auto)
        }
      }
      .width('85%')
      .padding(Theme.SpacingLG)
      .backgroundColor(Theme.BackgroundPrimary)
      .borderRadius(20)
      .shadow({ radius: 20, color: 'rgba(0,0,0,0.15)', offsetY: 4 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('rgba(0,0,0,0.5)')
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      this.showModelSelector = false
    })
  }

  // 斜杠命令弹出
  @Builder
  SlashCommandsPopup() {
    Column() {
      Column({ space: 12 }) {
        // 标题栏
        Row() {
          SymbolGlyph($r('sys.symbol.chevron_left'))
            .fontSize(20)
            .fontColor([Theme.TextPrimary])
            .onClick(() => {
              this.showSlashCommands = false
              this.showMenu = true
            })

          Text('斜杠命令')
            .fontSize(Theme.FontHeading)
            .fontWeight(FontWeight.Bold)
            .fontColor(Theme.TextPrimary)
            .layoutWeight(1)
            .textAlign(TextAlign.Center)

          Row().width(20)
        }
        .width('100%')
        .padding({ bottom: Theme.SpacingSM })

        List({ space: 8 }) {
          ForEach(this.slashCommands, (cmd: SlashCommand, index: number) => {
            ListItem() {
              Row({ space: 12 }) {
                Column({ space: 4 }) {
                  Text(cmd.name)
                    .fontSize(Theme.FontBody)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(Theme.TextPrimary)

                  Text(cmd.description)
                    .fontSize(Theme.FontTiny)
                    .fontColor(Theme.TextTertiary)
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)
              }
              .width('100%')
              .padding(Theme.SpacingMD)
              .backgroundColor(Theme.BackgroundSecondary)
              .borderRadius(12)
              .onClick(() => {
                this.selectSlashCommand(cmd.name)
              })
            }
          }, (cmd: SlashCommand, index: number) => `cmd-${index}`)
        }
        .width('100%')
        .height(Math.min(this.slashCommands.length * 70, 350))
        .scrollBar(BarState.Auto)
      }
      .width('85%')
      .padding(Theme.SpacingLG)
      .backgroundColor(Theme.BackgroundPrimary)
      .borderRadius(20)
      .shadow({ radius: 20, color: 'rgba(0,0,0,0.15)', offsetY: 4 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('rgba(0,0,0,0.5)')
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      this.showSlashCommands = false
    })
  }

  private getStatusText(): string {
    switch (this.chatStatus) {
      case 'idle': return '空闲'
      case 'thinking': return '思考中'
      case 'streaming': return '工作中'
      case 'tool_executing': return '执行中'
      case 'permission_pending': return '等待权限'
      case 'question_pending': return '等待回答'
      case 'completed': return '已完成'
      default: return ''
    }
  }

  private getStatusColor(): ResourceColor {
    switch (this.chatStatus) {
      case 'thinking':
      case 'streaming':
      case 'tool_executing':
        return Theme.AccentGreen
      case 'permission_pending':
        return Theme.AccentOrange
      case 'question_pending':
        return Theme.AccentPurple
      case 'completed':
        return Theme.SuccessColor
      default:
        return Theme.TextSecondary
    }
  }

  private sendMessage(): void {
    if (!this.inputText.trim()) return

    const content = this.inputText.trim()
    this.inputText = ''

    sessionStore.sendMessage(content)

    this.chatStatus = 'thinking'

    this.scrollToBottom()
  }
}
