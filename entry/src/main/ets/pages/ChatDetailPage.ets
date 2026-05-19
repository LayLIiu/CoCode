/**
 * 对话详情页 - 实时消息收发
 * 与 iOS 端完全一致的聊天体验
 */

import { Theme } from '../common/Theme'
import { Message, Session, SessionStatus, ModelInfo, WSMessage, TaskItem, TaskStatus, AttachmentRef, QuestionOption, QuestionItem, PermissionMode, PendingPermission, getPermissionModeDisplayName, getPermissionModeDescription } from '../models/Models'
import { HdsNavigation, ScrollEffectType, HdsNavigationBadgeIconOptions, HdsNavigationTitleMode } from '@hms.hds.hdsBaseComponent'
import { hdsMaterial } from '@hms.hds.hdsMaterial'
import { sessionStore } from '../stores/SessionStore'
import { authStore } from '../stores/AuthStore'
import { apiService } from '../services/APIService'
import { MarkdownRenderer } from '../components/MarkdownRenderer'
import { FileAttachmentBubble } from '../components/FileAttachmentBubble'
import { ImagePreviewDialog } from '../components/ImagePreviewDialog'
import { fileService, FileInfo } from '../services/FileService'
import { PixelMascot, MascotStatus, getMascotColorForSession, getMascotTypeForProvider } from '../components/PixelMascot'
import { StatusIcon, WorkStatus } from '../components/StatusIcon'
import { DotMatrixBackground } from '../components/DotMatrixBackground'
import { HdsMiniBarButton } from '../components/HdsMiniBarButton'
import { HdsGlassInput } from '../components/HdsGlassInput'
import { translateService } from '../services/TranslateService'
import router from '@ohos.router'
import pasteboard from '@ohos.pasteboard'
import vibrator from '@ohos.vibrator'
import photoViewPicker from '@ohos.file.picker'
import fileIo from '@ohos.file.fs'
import util from '@ohos.util'

// 斜杠命令定义
class SlashCommand {
  name: string = ''
  description: string = ''
  example: string = ''
}

// 工具图标映射（与 iOS 端一致）
class ToolIconInfo {
  symbol: Resource = $r('sys.symbol.gearshape')
  label: string = ''
  color: string = ''

  constructor(symbol: Resource, label: string, color: string) {
    this.symbol = symbol
    this.label = label
    this.color = color
  }
}

function getToolIcon(toolName: string): ToolIconInfo {
  switch (toolName) {
    case 'Bash':
      return new ToolIconInfo($r('sys.symbol.gearshape'), 'Terminal', Theme.AccentGreen)
    case 'Read':
      return new ToolIconInfo($r('sys.symbol.doc_text'), 'Read file', Theme.AccentBlue)
    case 'Write':
      return new ToolIconInfo($r('sys.symbol.square_and_pencil'), 'Write file', Theme.AccentOrange)
    case 'Edit':
      return new ToolIconInfo($r('sys.symbol.square_and_pencil'), 'Edit file', Theme.WarningColor)
    case 'Glob':
      return new ToolIconInfo($r('sys.symbol.magnifyingglass'), 'Search files', Theme.AccentPurple)
    case 'Grep':
      return new ToolIconInfo($r('sys.symbol.magnifyingglass'), 'Search content', Theme.AccentPurple)
    case 'Agent':
      return new ToolIconInfo($r('sys.symbol.person_fill'), 'Agent', Theme.AccentBlue)
    case 'WebSearch':
      return new ToolIconInfo($r('sys.symbol.magnifyingglass'), 'Web search', Theme.AccentBlue)
    case 'WebFetch':
      return new ToolIconInfo($r('sys.symbol.doc_text'), 'Web fetch', Theme.AccentBlue)
    case 'Skill':
      return new ToolIconInfo($r('sys.symbol.star_fill'), 'Skill', Theme.WarningColor)
    default:
      return new ToolIconInfo($r('sys.symbol.gearshape'), toolName, Theme.TextSecondary)
  }
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
  @State showModelSheet: boolean = false
  @State showSlashSheet: boolean = false
  @State showPermSheet: boolean = false
  @State showAttachSheet: boolean = false
  @State showSheet: boolean = false
  @State sheetType: string = ''
  @State models: ModelInfo[] = []
  @State currentModel: string = ''
  @State isLoadingModels: boolean = false
  @State expandedThinkingIds: Set<string> = new Set()
  @State expandedToolIds: Set<string> = new Set()
  @State currentPermissionMode: PermissionMode = PermissionMode.DEFAULT
  @State showCopyToast: boolean = false
  @State copyToastText: string = ''
  @State showCustomInput: boolean = false
  @State customInputText: string = ''
  @State activeQuestionMessageId: string = ''
  @State isPageActive: boolean = true

  // 附件（图片发送）
  @State pendingAttachments: AttachmentRef[] = []

  // 文件图片预览
  @State filePreviewSrc: string = ''
  @State filePreviewAlt: string = ''
  @State filePreviewName: string = ''
  @State showFilePreview: boolean = false

  // AskUserQuestion 选项（多问题支持）
  @State questionActiveTab: number = 0
  @State questionSelections: Map<number, string[]> = new Map()
  @State questionFreeText: string = ''
  @State questionHasSubmitted: boolean = false

  // 流式文本本地缓冲（与 iOS 端一致）
  @State streamingText: string = ''
  @State streamingThinking: string = ''
  private inTextBlock: boolean = false
  private inThinkingBlock: boolean = false

  // 消息去重
  private recentlySentMessages: Set<string> = new Set()

  // 复制按钮
  @State activeCopyMessageId: string = ''

  // 翻译
  @State showTranslateResult: boolean = false
  @State translateResultText: string = ''
  @State isTranslating: boolean = false
  @State translateError: string = ''

  // thinking 自动展开/合上（与 iOS 一致：最新 thinking 自动展开，新工具/内容出现后自动合上）
  private latestThinkingId: string = ''

  // 强制重绘计数器（ArkTS @State 不追踪嵌套对象属性变更）
  @State messageUpdateCounter: number = 0

  // "最新消息"浮动按钮
  @State showNewMessageButton: boolean = false
  @State userIsViewingHistory: boolean = false

  // 用户触控追踪：手指在屏幕上时不自动滚动
  @State isUserTouchingList: boolean = false
  private touchTimer: number = -1

  // 输入栏收缩动画
  @State animationProgress: number = 0

  // Token 使用量
  @State tokenUsage: number = 0
  @State contextUsage: number = 0
  @State showContextDetail: boolean = false
  @State contextModel: string = ''
  @State contextTotal: number = 0
  @State contextMax: number = 0
  private contextPollTimer: number = -1
  private isDestroyed: boolean = false

  // 工作中计时（与 iOS StreamingStatusView 一致）
  @State elapsedSeconds: number = 0
  @State mascotScale: number = 1.0
  private workTimer: number = -1

  // 分页加载
  @State displayedMessageCount: number = 50
  @State isLoadingMore: boolean = false
  @State isMessagesLoaded: boolean = false
  @State isListReady: boolean = false

  // 标题栏动态模糊（滚动时背景渐变透明）
  @State scrollOffset: number = 0
  private readonly blurThreshold: number = 30

  private scroller: Scroller = new Scroller()

  // 流式 thinking 自动滚动
  private streamingThinkingScroller: Scroller = new Scroller()
  private thinkingScrollTimer: number = -1

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
    // 同步当前会话的工作状态（避免从对话列表页进入时状态显示为"空闲"）
    this.chatStatus = sessionStore.getSessionStatus(this.sessionId || '')
    this.setupCallbacks()
    // 加载当前会话权限模式
    this.currentPermissionMode = sessionStore.getCurrentPermissionMode()
    // 恢复输入框草稿
    // 确保弹窗不会在进入页面时意外弹出
    this.showModelSheet = false
    this.showSlashSheet = false
    this.showPermSheet = false
    this.showAttachSheet = false

    // 定时拉取上下文使用率
    setTimeout(() => { if (!this.isDestroyed) this.fetchContextUsage() }, 1000)
    this.contextPollTimer = setInterval(() => { if (!this.isDestroyed) this.fetchContextUsage() }, 15000)

    const draft = sessionStore.inputDrafts.get(this.sessionId)
    if (draft) {
      this.inputText = draft
    }
  }

  aboutToDisappear(): void {
    this.isPageActive = false
    this.isDestroyed = true
    // 保存输入框草稿
    if (this.inputText) {
      sessionStore.inputDrafts.set(this.sessionId, this.inputText)
    } else {
      sessionStore.inputDrafts.delete(this.sessionId)
    }
    this.stopWorkTimer()
    if (this.touchTimer >= 0) {
      clearTimeout(this.touchTimer)
      this.touchTimer = -1
    }
    if (this.thinkingScrollTimer !== -1) {
      clearTimeout(this.thinkingScrollTimer)
      this.thinkingScrollTimer = -1
    }
    if (this.contextPollTimer >= 0) { clearInterval(this.contextPollTimer); this.contextPollTimer = -1 }
    this.removeCallbacks()
    sessionStore.setCurrentSession(null)
  }

  onPageShow(): void {
    this.isPageActive = true
    this.getRouterParams()
    // 回到页面时重新同步工作状态
    if (this.sessionId) {
      this.chatStatus = sessionStore.getSessionStatus(this.sessionId)
    }
  }

  onPageHide(): void {
    this.isPageActive = false
  }

  private async fetchContextUsage(): Promise<void> {
    if (!this.sessionId) return
    try {
      const res = await apiService.getInspection(this.sessionId)
      if (res) {
        if (res.percentage > 0) this.contextUsage = res.percentage
        if (res.model) this.contextModel = res.model
        this.contextTotal = res.totalTokens
        this.contextMax = res.maxTokens
      }
    } catch (e) { /* ignore */ }
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
      // 从工作区/文件查看页传来的附件
      if (params['attachFile']) {
        setTimeout(() => {
          this.loadFileAsAttachment(params['attachFile'], params['attachFileName'] || 'file')
        }, 500)
      }
    }
  }

  private async loadFileAsAttachment(filePath: string, fileName: string): Promise<void> {
    if (!filePath || filePath.trim() === '') return
    this.pendingAttachments = [...this.pendingAttachments, {
      type: 'file',
      name: fileName || 'file',
      path: filePath
    }]
  }

  private async loadMessages(): Promise<void> {
    await sessionStore.loadMessages(this.sessionId)
    const msgs = sessionStore.messages.get(this.sessionId)
    if (msgs) {
      this.messages = msgs
      // 初始显示最后100条
      this.displayedMessageCount = Math.min(100, this.messages.length)
    }
    // 倒序列表默认就在最新消息位置，无需scrollTo
    this.isMessagesLoaded = true
    this.isListReady = true
  }

  private messagesChangedListener = (sid: string) => {
    if (sid === this.sessionId) {
      const msgs = sessionStore.messages.get(this.sessionId)
      if (msgs) {
        this.messages = msgs
      }
      // 查看历史或用户触控时不强制滚动，避免打断用户
      if (!this.userIsViewingHistory && !this.isUserTouchingList) {
        this.scrollToBottom()
      }
    }
  }

  private statusChangedListener = (sid: string, status: SessionStatus) => {
    if (sid === this.sessionId) {
      this.chatStatus = status
      // 同步当前会话的权限模式
      this.currentPermissionMode = sessionStore.getCurrentPermissionMode()
      // 状态变为 completed 或 idle 时停止计时器
      if (status === 'completed' || status === 'idle') {
        this.stopWorkTimer()
      }
      // 状态变为 working 时启动计时器
      if (status === 'thinking' || status === 'streaming' || status === 'tool_executing') {
        this.startWorkTimer()
      }
    }
  }

  private rawMessageListener = (sid: string, msg: WSMessage) => {
    if (sid === this.sessionId) {
      this.handleStreamingMessage(msg)
    }
  }

  // 任务列表更新监听器
  private sessionsChangedListener = () => {
    // 触发重绘以更新 TaskBarView
    this.messageUpdateCounter++
  }

  private setupCallbacks(): void {
    sessionStore.addMessagesChangedListener(this.messagesChangedListener)
    sessionStore.addStatusChangedListener(this.statusChangedListener)
    sessionStore.addRawMessageListener(this.rawMessageListener)
    sessionStore.addSessionsChangedListener(this.sessionsChangedListener)
  }

  private removeCallbacks(): void {
    sessionStore.removeMessagesChangedListener(this.messagesChangedListener)
    sessionStore.removeStatusChangedListener(this.statusChangedListener)
    sessionStore.removeRawMessageListener(this.rawMessageListener)
    sessionStore.removeSessionsChangedListener(this.sessionsChangedListener)
  }

  private scrollToBottom(): void {
    // 倒序列表：最新消息在顶部（视觉底部），scrollEdge(Top) 就是回到最新消息
    this.scroller.scrollEdge(Edge.Top)
  }

  // 标题栏动态模糊：根据滚动位置计算背景透明度
  private getTitleBarBackgroundColor(): string {
    const progress = Math.min(this.scrollOffset / this.blurThreshold, 1.0)
    const alpha = 1.0 - progress * 0.3
    return `rgba(18, 18, 18, ${alpha})`
  }

  // 标题栏动态模糊：根据滚动位置返回模糊样式
  private getTitleBarBlurStyle(): BlurStyle {
    return this.scrollOffset > this.blurThreshold ? BlurStyle.COMPONENT_THICK : BlurStyle.COMPONENT_REGULAR
  }

  // 加载模型列表
  private async loadModels(): Promise<void> {
    if (this.models.length > 0) return

    this.isLoadingModels = true
    try {
      // 根据当前会话的 AI 工具类型获取对应模型列表
      const providerId = this.getSessionProviderId()
      const response = await apiService.getModels(providerId || undefined)
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
      this.showModelSheet = false
      this.showMenu = false
    } catch (e) {
      console.error(`[ChatDetailPage] Set model error: ${e}`)
    }
  }

  // 选择斜杠命令
  private selectSlashCommand(cmd: string): void {
    this.inputText = cmd + ' '
    this.showSlashSheet = false
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

  /**
   * 从工具输入中提取文件路径，用于显示文件预览
   */
  private getFileInfoFromTool(message: Message): FileInfo | null {
    if (!message.toolInput || !message.toolName) return null
    // 只对 Write/Edit 工具显示文件预览
    if (message.toolName !== 'Write' && message.toolName !== 'Edit') return null

    const filePath = message.toolInput['file_path']
    if (typeof filePath !== 'string' || !filePath) return null

    const info = fileService.analyzeFilePath(filePath)
    // 只对图片和代码文件显示预览
    if (!info.isImage && !info.isSvg && !info.isCode) return null
    return info
  }

  // MARK: - 剪贴板

  private copyToClipboard(text: string): void {
    this.copyToastText = '已复制'
    this.showCopyToast = true
    setTimeout(() => {
      this.showCopyToast = false
    }, 1500)

    try {
      const systemPasteboard = pasteboard.getSystemPasteboard()
      const pasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text)
      systemPasteboard.setData(pasteData)
    } catch (e) {
      console.error(`[ChatDetailPage] pasteboard error: ${e}`)
    }
  }

  // MARK: - 翻译

  private async translateMessageContent(content: string): Promise<void> {
    if (this.isTranslating) return

    this.isTranslating = true
    this.translateError = ''
    this.translateResultText = ''

    // 显示加载中
    this.showTranslateResult = true

    try {
      const result = await translateService.translate(content)
      if (result.success && result.text) {
        this.translateResultText = result.text
        this.translateError = ''
      } else {
        this.translateResultText = ''
        this.translateError = result.error || '翻译失败'

        // 翻译失败时回退：复制到剪贴板
        this.copyToClipboard(content)
      }
    } catch (e) {
      this.translateError = '翻译出错'
      this.translateResultText = ''
      this.copyToClipboard(content)
    }

    this.isTranslating = false
  }

  // MARK: - 流式消息处理（本地 buffering，与 iOS 一致）

  private handleStreamingMessage(msg: WSMessage): void {
    switch (msg.type) {
      case 'content_start':
        // 启动工作计时器（如果当前不在工作状态）
        if (this.chatStatus === 'idle' || this.chatStatus === 'completed') {
          this.startWorkTimer()
        }
        if (msg.blockType === 'text') {
          this.inTextBlock = true
          this.streamingText = ''
        }
        break

      case 'content_delta':
        // 启动工作计时器（如果当前不在工作状态）
        if (this.chatStatus === 'idle' || this.chatStatus === 'completed') {
          this.startWorkTimer()
        }
        if (msg.text) {
          this.streamingText += msg.text
          // 流式文本实时滚动：仅当用户未查看历史且未触控时
          if (!this.userIsViewingHistory && !this.isUserTouchingList) {
            this.scrollToBottom()
          }
        }
        break

      case 'thinking':
        // 启动工作计时器（如果当前不在工作状态）
        if (this.chatStatus === 'idle' || this.chatStatus === 'completed') {
          this.startWorkTimer()
        }
        if (!this.inThinkingBlock) {
          this.inThinkingBlock = true
          this.streamingThinking = ''
        }
        if (msg.text) {
          this.streamingThinking += msg.text
          if (!this.userIsViewingHistory && !this.isUserTouchingList) {
            this.scrollToBottom()
          }
          // 流式 thinking 自动滚动到底部（根据内容长度控制速度）
          if (!this.isUserTouchingList) {
            this.scheduleThinkingScroll(msg.text.length)
          }
        }
        break

      case 'tool_use_complete':
        this.flushStreamingBuffers()
        this.inTextBlock = false
        this.inThinkingBlock = false
        // 状态由 SessionStore 更新
        // 新工具出现 → 合上最新 thinking（与 iOS 一致）
        this.collapseLatestThinking()
        break

      case 'tool_result':
        this.messageUpdateCounter++
        break

      case 'message_complete':
        this.flushStreamingBuffers()
        this.inTextBlock = false
        this.inThinkingBlock = false
        // 状态由 SessionStore 更新，这里只停止计时器和更新 token
        this.stopWorkTimer()
        if (msg.used) {
          this.tokenUsage = msg.used
        }
        if (!this.userIsViewingHistory && !this.isUserTouchingList) {
          this.scrollToBottom()
        }
        // 消息完成 → 合上最新 thinking
        this.collapseLatestThinking()
        break

      case 'status':
        break

      case 'permission_request':
        this.flushStreamingBuffers()
        // 状态由 SessionStore 更新
        // 重置 AskUserQuestion 相关状态
        this.questionHasSubmitted = false
        this.questionSelections = new Map()
        this.questionFreeText = ''
        this.questionActiveTab = 0
        this.vibrateAlert()
        break

      case 'question':
      case 'questions':
        this.flushStreamingBuffers()
        // 状态由 SessionStore 更新
        this.vibrateAlert()
        break

      case 'user_message_echo':
        if (msg.content) {
          let contentString = ''
          if (typeof msg.content === 'string') {
            contentString = msg.content
          } else {
            contentString = JSON.stringify(msg.content)
          }
          if (this.recentlySentMessages.has(contentString)) {
            this.recentlySentMessages.delete(contentString)
          }
        }
        break

      case 'token_usage':
        if (msg.percentage) {
          this.contextUsage = msg.percentage
        }
        break

      case 'system_notification':
        // Agent task_notification 等触发重绘以显示最新的 agentTaskStatus
        if (msg.subtype === 'task_notification') {
          this.messageUpdateCounter++
        }
        break
    }
  }

  private flushStreamingBuffers(): void {
    // 先 flush thinking：自动展开最新 thinking，合上旧 thinking
    if (this.streamingThinking) {
      const thinkId = 'thinking-' + Date.now()
      const thinkMsg: Message = {
        id: thinkId,
        type: 'thinking',
        content: this.streamingThinking,
        timestamp: new Date().toISOString()
      }
      sessionStore.addMessage(this.sessionId, thinkMsg)

      // 自动展开最新 thinking，同时合上旧的
      const newSet = new Set(this.expandedThinkingIds)
      if (this.latestThinkingId) {
        newSet.delete(this.latestThinkingId)
      }
      newSet.add(thinkId)
      this.expandedThinkingIds = newSet
      this.latestThinkingId = thinkId

      this.streamingThinking = ''
    }

    // 再 flush 文本：thinking 应在 text 之前
    if (this.streamingText) {
      const trimmed = this.streamingText.trim()
      const shouldHide = trimmed.startsWith('[{') &&
        (trimmed.includes('"tool_use_id"') || trimmed.includes('"tool_result"'))

      if (!shouldHide) {
        const textMsg: Message = {
          id: 'assistant-' + Date.now(),
          type: 'assistant',
          content: this.streamingText,
          timestamp: new Date().toISOString()
        }
        sessionStore.addMessage(this.sessionId, textMsg)

        // 文本出现 → 合上最新 thinking（与 iOS 一致）
        if (this.latestThinkingId) {
          const newSet = new Set(this.expandedThinkingIds)
          newSet.delete(this.latestThinkingId)
          this.expandedThinkingIds = newSet
          this.latestThinkingId = ''
        }
      }
      this.streamingText = ''
    }
  }

  // HdsNavigation 右侧按钮
  private menus: Array<HdsNavigationBadgeIconOptions> = [
    {
      content: {
        icon: $r('sys.symbol.folder'),
        action: () => {
          router.pushUrl({
            url: 'pages/WorkspacePage',
            params: { sessionId: this.sessionId }
          })
        }
      }
    }
  ]

  build() {
    Stack() {
      // 点阵背景 - 最底层，穿透触控
      DotMatrixBackground({ active: this.isPageActive })

      HdsNavigation() {
        // 消息列表 — 倒序+翻转：默认就在"底部"（最新消息），无需scrollTo
        List({ scroller: this.scroller }) {
          // 顶部留白（翻转后视觉在底部，给悬浮输入框留空间）
          ListItem() {
            Row().width('100%').height(120)
          }
          .rotate({ angle: 180 })

          // 流式文本实时渲染（翻转后视觉在消息列表最前面=最新位置）
          if (this.streamingText) {
            ListItem() {
              this.StreamingTextBubble()
            }
            .rotate({ angle: 180 })
          }

          // 流式思考实时渲染
          if (this.streamingThinking) {
            ListItem() {
              this.StreamingThinkingBubble()
            }
            .rotate({ angle: 180 })
          }

          // AI 工作状态指示器（吉祥物动画）
          if (this.chatStatus === 'thinking' || this.chatStatus === 'streaming' ||
            this.chatStatus === 'tool_executing' || this.chatStatus === 'permission_pending' ||
            this.chatStatus === 'question_pending') {
            ListItem() {
              this.StreamingIndicator()
            }
            .rotate({ angle: 180 })
          }

          // 消息倒序排列（最新在前=视觉底部）
          ForEach([...this.getVisibleMessages()].reverse(), (message: Message) => {
            ListItem() {
              this.MessageBubble(message)
            }
            .rotate({ angle: 180 })
          }, (message: Message) => {
            if (message.type === 'tool_use') {
              return message.id + '_' + (message.toolStatus || '')
            }
            if (message.type === 'permission_request') {
              return message.id + '_' + (message.isPermissionHandled ? 'done' : 'pending')
            }
            if (message.type === 'question') {
              return message.id + '_' + (message.isQuestionAnswered ? 'done' : 'pending')
            }
            return message.id
          })

          // 加载更多历史提示（翻转后视觉在顶部）
          if (this.hasMoreMessages()) {
            ListItem() {
              Column({ space: 2 }) {
                Row({ space: 8 }) {
                  LoadingProgress()
                    .width(14)
                    .height(14)
                    .color(Theme.TextSecondary)
                  Text('下滑加载更早消息')
                    .fontSize(12)
                    .fontColor(Theme.TextSecondary)
                }
                .width('100%')
                .justifyContent(FlexAlign.Center)
                .padding({ left: 8, right: 8, top: 8, bottom: 4 })

                Text(`已显示 ${this.displayedMessageCount}/${this.messages.length} 条`)
                  .fontSize(10)
                  .fontColor(Theme.TextTertiary)
                  .width('100%')
                  .textAlign(TextAlign.Center)
                  .padding({ top: 2, bottom: 8 })
              }
            }
            .rotate({ angle: 180 })
          }

          // 底部占位（翻转后视觉在顶部）
          ListItem() {
            Row().width('100%').height(8)
          }
          .rotate({ angle: 180 })
        }
        .width('100%')
        .height('100%')
        .padding({ left: Theme.SpacingLG, right: Theme.SpacingLG })
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
        .rotate({ angle: 180 })  // 整体翻转，使列表默认在最新消息位置
        .onScrollIndex((start: number, end: number) => {
          // 翻转后：滚到底部=视觉顶部=加载更多历史
          const totalItems = this.getListItemCount()
          if (end >= totalItems - 1 && this.hasMoreMessages() && !this.isLoadingMore) {
            this.loadMoreMessages()
          }
          // 翻转后：start=0 表示在列表顶部=视觉底部=最新消息
          if (start === 0) {
            // 在最新消息位置
            if (this.showNewMessageButton) {
              this.showNewMessageButton = false
              this.userIsViewingHistory = false
              this.animationProgress = 0
            }
          } else {
            // 向上滚动查看历史
            if (!this.showNewMessageButton && start > 2) {
              this.showNewMessageButton = true
              this.userIsViewingHistory = true
            }
          }
        })
        .onDidScroll((xOffset: number, yOffset: number) => {
          // 翻转后滚动方向反转
          if (-yOffset !== this.scrollOffset) {
            this.scrollOffset = -yOffset
          }
        })
        .onTouch((event: TouchEvent) => {
          if (event.type === TouchType.Down) {
            // 清除上一个待处理的抬起重置
            if (this.touchTimer >= 0) {
              clearTimeout(this.touchTimer)
              this.touchTimer = -1
            }
            this.isUserTouchingList = true
          } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
            // 手指抬起后延迟重置，等惯性滑动结束
            this.touchTimer = setTimeout(() => {
              this.isUserTouchingList = false
              this.touchTimer = -1
            }, 600)
          }
        })
        }
        .opacity(this.isMessagesLoaded ? 1.0 : 0.0)
      .titleBar({
        content: {
          title: {
            mainTitle: this.conversationTitle,
          },
          menu: { value: this.menus },
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
      .backgroundColor('#00000000')
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .bindSheet($$this.showModelSheet, this.ModelSelectorSheet(), {
        height: 480, backgroundColor: '#1C1C1E', dragBar: true, showClose: false, blurStyle: BlurStyle.NONE
      })

      // 工作状态 & 上下文使用率（标题栏下方，永远显示）
      Row({ space: 6 }) {
        this.ContextRing()
        if (this.chatStatus === 'idle' || this.chatStatus === 'completed') {
          Text('休闲中').fontSize(11).fontColor(Theme.TextSecondary)
        } else {
          StatusIcon({ status: this.mapToWorkStatus(this.chatStatus) })
          Text(this.getStatusText()).fontSize(11).fontColor(this.getStatusColor())
          if (this.elapsedSeconds > 0) {
            Text(this.formatElapsed(this.elapsedSeconds)).fontSize(10).fontColor(Theme.TextTertiary)
          }
        }
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .padding({ left: Theme.SpacingLG, right: Theme.SpacingLG })
      .position({ x: 0, y: 88 })
      .zIndex(5)

      // 斜杠命令 Sheet（独立 Column 避免多个 bindSheet 冲突）
      Column()
        .width(0).height(0)
        .bindSheet($$this.showSlashSheet, this.SlashCommandsSheet(), {
          height: 480, backgroundColor: '#1C1C1E', dragBar: true, showClose: false, blurStyle: BlurStyle.NONE
        })

      // 上下文详情 Sheet
      Column()
        .width(0).height(0)
        .bindSheet($$this.showContextDetail, this.ContextDetailSheet(), {
          height: 380, backgroundColor: '#1C1C1E', dragBar: true, showClose: false, blurStyle: BlurStyle.NONE
        })

      // 翻译结果 Sheet
      Column()
        .width(0).height(0)
        .bindSheet($$this.showTranslateResult, this.TranslateResultSheet(), {
          height: 420, backgroundColor: '#1C1C1E', dragBar: true, showClose: false, blurStyle: BlurStyle.NONE
        })

      // 任务面板
      this.TaskBarView()

      // 底部悬浮输入框（包含最新消息按钮）
      Column({ space: 8 }) {
        // "最新消息"按钮 - 跟随输入框移动
        if (this.showNewMessageButton) {
          Row() {
            HdsMiniBarButton({
              barWidth: 100,
              barHeight: 32,
              contentPadding: 6,
              maskColor: 'rgba(255,255,255,0.15)',
              barBottomMargin: 0,
              onButtonClick: () => {
                this.showNewMessageButton = false
                this.userIsViewingHistory = false
                this.animationProgress = 0
                this.scrollToBottom()
              }
            }) {
              Row({ space: 4 }) {
                SymbolGlyph($r('sys.symbol.arrow_down'))
                  .fontSize(12)
                  .fontColor([Theme.TextSecondary])
                Text('最新消息')
                  .fontSize(11)
                  .fontColor(Theme.TextPrimary)
              }
            }
          }
          .justifyContent(FlexAlign.Center)
          .width('100%')
        }

        this.InputAreaContent()
      }
      .width('100%')
      .padding({ left: Theme.SpacingLG, right: Theme.SpacingLG, bottom: 28 })
      .backgroundColor(Color.Transparent)
      .position({ x: 0, y: '100%' })
      .translate({ y: '-100%' })
      .zIndex(2)
      .opacity(this.userIsViewingHistory ? 0.7 : 1.0)
      .animation({ duration: 300, curve: Curve.EaseInOut })
      .clip(false)
      .bindSheet($$this.showAttachSheet, this.AttachmentActionSheet(), {
        height: 200, backgroundColor: '#1C1C1E', dragBar: true, showClose: false, blurStyle: BlurStyle.NONE
      })  // 禁用裁切，让按钮形变效果可以超出边界

    // 菜单气泡 - 从按钮左下角扩散
      if (this.showMenu) {
        this.MenuBubble()
      }

      // 文件/图片全屏预览（只在需要显示时渲染，避免阻止触摸事件）
      if (this.showFilePreview) {
        ImagePreviewDialog({
          imageSrc: this.filePreviewSrc,
          imageAlt: this.filePreviewAlt,
          fileName: this.filePreviewName,
          isVisible: $showFilePreview
        })
      }

    }
    .width('100%')
    .height('100%')
    .backgroundColor('#121214')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .clip(false)
    .bindSheet($$this.showPermSheet, this.PermissionSheet(), {
      height: 480, backgroundColor: '#1C1C1E', dragBar: true, showClose: false, blurStyle: BlurStyle.NONE
    })
    .width('100%')
    .height('100%')
  }

  // 标题栏状态行（与 iOS 一致：状态指示器 + 状态文字 + 上下文用量）
  @Builder
  TitleStatusView() {
    Row({ space: 4 }) {
      if (this.chatStatus !== 'idle' && this.chatStatus !== 'completed') {
        StatusIcon({ status: this.mapToWorkStatus(this.chatStatus) })
      }
      Text(this.getStatusText())
        .fontSize(10)
        .fontColor(this.getStatusColor())
      if (this.contextUsage > 0) {
        Text(`(${this.contextUsage}%)`)
          .fontSize(9)
          .fontColor(Theme.TextTertiary)
      }
    }
  }

  @Builder
  StreamingIndicator() {
    Row() {
      Row({ space: 6 }) {
        // 像素吉祥物 — 根据工作状态实时变化
        PixelMascot({
          mascotSize: 27,
          status: this.getMascotStatus(),
          bodyColor: getMascotColorForSession(this.sessionId),
          mascotType: getMascotTypeForProvider(this.getSessionProviderId())
        })

        // 状态文字
        Text(this.getStatusText())
          .fontSize(11)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.TextSecondary)

        // 已用时间
        if (this.elapsedSeconds > 0) {
          Text(this.formatElapsed(this.elapsedSeconds))
            .fontSize(10)
            .fontColor(Theme.TextTertiary)
        }

        // Token 数
        if (this.tokenUsage > 0) {
          Text(`· ↓ ${this.tokenUsage}`)
            .fontSize(10)
            .fontColor(Theme.TextTertiary)
        }
      }
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .backgroundColor(Theme.GlassBackground)
      .borderRadius(18)
      .border({
        width: 0.5,
        color: Theme.GlassBorder
      })

      Blank()
    }
    .width('100%')
    .margin({ bottom: Theme.SpacingXS })
  }

  // 映射 chatStatus 到 MascotStatus
  private getMascotStatus(): MascotStatus {
    switch (this.chatStatus) {
      case 'thinking':
      case 'streaming':
      case 'tool_executing':
        return MascotStatus.PROCESSING
      case 'permission_pending':
      case 'question_pending':
        return MascotStatus.WAITING_APPROVAL
      case 'completed':
        return MascotStatus.COMPLETED
      default:
        return MascotStatus.IDLE
    }
  }

  private getSessionProviderId(): string {
    const session = sessionStore.sessions.find((s: Session) => s.id === this.sessionId)
    return session?.aiTool || ''
  }

  // 获取可见消息（分页），过滤掉 Agent 子工具（由 AgentToolUseBubble 嵌套渲染）
  private getVisibleMessages(): Message[] {
    const allMessages = this.messages
    // 过滤：排除有 parentToolUseId 的子工具，它们在 Agent 卡片内嵌套渲染
    const filtered = allMessages.filter(m => !(m.type === 'tool_use' && m.parentToolUseId))
    if (filtered.length <= this.displayedMessageCount) {
      return filtered
    }
    return filtered.slice(filtered.length - this.displayedMessageCount)
  }

  private hasMoreMessages(): boolean {
    return this.messages.length > this.displayedMessageCount
  }

  // 计算 List 总项数（用于 onScrollIndex）
  private getListItemCount(): number {
    let count = 2 // 顶部留白 + 底部占位
    count += this.getVisibleMessages().length
    if (this.streamingText) count++
    if (this.streamingThinking) count++
    if (this.chatStatus === 'thinking' || this.chatStatus === 'streaming' ||
      this.chatStatus === 'tool_executing' || this.chatStatus === 'permission_pending' ||
      this.chatStatus === 'question_pending') count++
    if (this.hasMoreMessages()) count++
    return count
  }

  private loadMoreMessages(): void {
    if (this.isLoadingMore) return
    this.isLoadingMore = true
    setTimeout(() => {
      const increment = 100
      const newCount = Math.min(this.displayedMessageCount + increment, this.messages.length)
      this.displayedMessageCount = newCount
      this.isLoadingMore = false
    }, 100)
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
          if (message.toolName === 'Agent') {
            this.AgentToolUseBubble(message)
          } else if (message.toolName === 'AskUserQuestion') {
            this.AskUserQuestionBubble(message)
          } else {
            this.ToolUseBubble(message)
          }
        } else if (message.type === 'tool_result') {
          this.ToolResultBubble(message)
        } else if (message.type === 'permission_request') {
          if (message.toolName === 'AskUserQuestion') {
            this.AskUserQuestionBubble(message)
          } else {
            this.PermissionBubble(message)
          }
        } else if (message.type === 'question') {
          this.QuestionBubble(message)
        } else if (message.type === 'error') {
          this.ErrorBubble(message)
        } else if (message.type === 'system_notification' || message.type === 'system') {
          this.SystemBubble(message)
        } else if (message.type === 'task_list') {
          this.TaskSummaryBubble(message)
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
    Column({ space: 4 }) {
      Text(message.content)
        .fontSize(15)
        .fontColor(Theme.TextPrimary)
        .lineHeight(22)

      if (this.activeCopyMessageId === message.id) {
        Row({ space: 4 }) {
          // 复制按钮
          Row({ space: 4 }) {
            SymbolGlyph($r('sys.symbol.doc_text'))
              .fontSize(11)
              .fontColor([Theme.TextPrimary])
            Text('复制')
              .fontSize(11)
              .fontColor(Theme.TextPrimary)
          }
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
          .backgroundColor(Theme.GlassBackground)
          .borderRadius(10)
          .border({ width: 0.5, color: Theme.GlassBorder })
          .onClick(() => {
            this.copyToClipboard(message.content)
            this.activeCopyMessageId = ''
          })

          // 翻译按钮
          Row({ space: 4 }) {
            SymbolGlyph($r('sys.symbol.character'))
              .fontSize(11)
              .fontColor([Theme.AccentBlue])
            Text('翻译')
              .fontSize(11)
              .fontColor(Theme.AccentBlue)
          }
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
          .backgroundColor(Theme.GlassBackground)
          .borderRadius(10)
          .border({ width: 0.5, color: Theme.GlassBorder })
          .onClick(() => {
            this.activeCopyMessageId = ''
            this.translateMessageContent(message.content)
          })
        }
      }
    }
    .padding({ left: 16, right: 16, top: 10, bottom: 10 })
    .backgroundColor('rgba(255,255,255,0.22)')
    .borderRadius(18)
    .gesture(
      LongPressGesture()
        .onAction(() => {
          if (this.activeCopyMessageId === message.id) {
            this.activeCopyMessageId = ''
          } else {
            this.activeCopyMessageId = message.id
          }
        })
    )
  }

  @Builder
  AssistantBubble(message: Message) {
    Column({ space: 4 }) {
      if (this.shouldHideContent(message.content)) {
        // 隐藏工具调用 JSON
      } else {
        MarkdownRenderer({ content: message.content })
      }

      if (this.activeCopyMessageId === message.id) {
        Row({ space: 4 }) {
          // 复制按钮
          Row({ space: 4 }) {
            SymbolGlyph($r('sys.symbol.doc_text'))
              .fontSize(11)
              .fontColor([Theme.TextPrimary])
            Text('复制')
              .fontSize(11)
              .fontColor(Theme.TextPrimary)
          }
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
          .backgroundColor(Theme.GlassBackground)
          .borderRadius(10)
          .border({ width: 0.5, color: Theme.GlassBorder })
          .onClick(() => {
            this.copyToClipboard(message.content)
            this.activeCopyMessageId = ''
          })

          // 翻译按钮
          Row({ space: 4 }) {
            SymbolGlyph($r('sys.symbol.character'))
              .fontSize(11)
              .fontColor([Theme.AccentBlue])
            Text('翻译')
              .fontSize(11)
              .fontColor(Theme.AccentBlue)
          }
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
          .backgroundColor(Theme.GlassBackground)
          .borderRadius(10)
          .border({ width: 0.5, color: Theme.GlassBorder })
          .onClick(() => {
            this.activeCopyMessageId = ''
            this.translateMessageContent(message.content)
          })
        }
      }
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 10, bottom: 10 })
    .backgroundColor('rgba(255,255,255,0.16)')
    .borderRadius(18)
    .gesture(
      LongPressGesture()
        .onAction(() => {
          if (this.activeCopyMessageId === message.id) {
            this.activeCopyMessageId = ''
          } else {
            this.activeCopyMessageId = message.id
          }
        })
    )
  }

  // 流式文本气泡（实时渲染 AI 输出）
  @Builder
  StreamingTextBubble() {
    Row() {
      Column() {
        MarkdownRenderer({ content: this.streamingText })
      }
      .width('100%')
      .padding({ left: 14, right: 14, top: 10, bottom: 10 })
      .backgroundColor('rgba(255,255,255,0.16)')
      .borderRadius(18)
    }
    .width('100%')
    .margin({ bottom: Theme.SpacingMD })
  }

  // 流式思考气泡（实时渲染 thinking 输出）
  @Builder
  StreamingThinkingBubble() {
    Row() {
      Column({ space: 0 }) {
        Row({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.lightbulb'))
            .fontSize(12)
            .fontColor([Theme.AccentOrange])

          Text('thinking...')
            .fontSize(11)
            .fontWeight(FontWeight.Medium)
            .fontColor(Theme.TextSecondary)

          Blank()
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 10, bottom: 6 })

        Scroll(this.streamingThinkingScroller) {
          Text(this.streamingThinking)
            .fontSize(11)
            .fontColor(Theme.TextSecondary)
            .fontFamily('monospace')
            .width('100%')
        }
        .height(Math.max(60, Math.min(200, this.streamingThinking.split('\n').length * 20)))
        .scrollBar(BarState.Off)
        .padding({ left: 12, right: 12, bottom: 10 })
      }
      .width('100%')
      .backgroundColor('rgba(255,255,255,0.10)')
      .borderRadius(10)
      .border({ width: 0.5, color: 'rgba(255,255,255,0.1)' })
    }
    .width('100%')
    .margin({ bottom: Theme.SpacingMD })
  }

  // 隐藏工具调用 JSON 格式的内容
  private shouldHideContent(content: string): boolean {
    const trimmed = content.trim()
    if (!trimmed.startsWith('[{')) return false
    return trimmed.includes('"tool_use_id"') || trimmed.includes('"tool_result"')
  }

  private copyMessage(text: string): void {
    this.copyToClipboard(text)
  }

  @Builder
  ThinkingBubble(message: Message) {
    Column({ space: 0 }) {
      // Header
      Row({ space: 8 }) {
        // 思考图标
        SymbolGlyph($r('sys.symbol.lightbulb'))
          .fontSize(12)
          .fontColor([Theme.AccentOrange])

        Text('thinking')
          .fontSize(11)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.TextSecondary)

        // 折叠时显示摘要
        if (!this.expandedThinkingIds.has(message.id) && message.content) {
          Text(this.getThinkingSummary(message.content))
            .fontSize(11)
            .fontColor(Theme.TextTertiary)
            .maxLines(1)
            .layoutWeight(1)
        }

        Blank()

        if (this.expandedThinkingIds.has(message.id)) {
          SymbolGlyph($r('sys.symbol.chevron_down'))
            .fontSize(9)
            .fontColor([Theme.TextTertiary])
        } else {
          SymbolGlyph($r('sys.symbol.chevron_right'))
            .fontSize(9)
            .fontColor([Theme.TextTertiary])
        }
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 10, bottom: 10 })

      // 展开内容
      if (this.expandedThinkingIds.has(message.id) && message.content) {
        Scroll() {
          Row({ space: 0 }) {
            Text(message.content)
              .fontSize(11)
              .fontColor(Theme.TextSecondary)
              .fontFamily('monospace')
              .layoutWeight(1)

            // 流式输出时显示光标
            if (message.isStreaming) {
              Column()
                .width(2)
                .height(12)
                .backgroundColor(Theme.TextTertiary)
                .borderRadius(1)
                .margin({ left: 2 })
            }
          }
          .width('100%')
        }
        .height(Math.max(100, Math.min(400, message.content ? message.content.split('\n').length * 22 : 200)))
        .scrollBar(BarState.Off)
        .padding({ left: 12, right: 12, top: 10, bottom: 10 })
      }
    }
    .width('100%')
    .onClick(() => {
      this.toggleThinking(message.id)
    })
    .backgroundColor('rgba(255,255,255,0.10)')
    .borderRadius(10)
    .border({
      width: 0.5,
      color: 'rgba(255,255,255,0.1)'
    })
  }

  // 思考摘要
  private getThinkingSummary(content: string): string {
    const lines = content.split('\n')
    let firstLine = ''
    for (let i = 0; i < lines.length; i++) {
      const trimmed = lines[i].trim()
      if (trimmed) {
        firstLine = trimmed
        break
      }
    }
    return firstLine.length > 60 ? firstLine.substring(0, 60) + '...' : firstLine
  }

  private toggleThinking(id: string): void {
    const newSet = new Set(this.expandedThinkingIds)
    if (newSet.has(id)) {
      newSet.delete(id)
    } else {
      newSet.add(id)
    }
    this.expandedThinkingIds = newSet
  }

  // 流式 thinking 自动滚动（根据新增内容长度控制速度）
  private scheduleThinkingScroll(deltaLength: number): void {
    if (this.thinkingScrollTimer !== -1) {
      clearTimeout(this.thinkingScrollTimer)
    }
    // 速度策略：内容少时快速跟随，内容多时稍慢让用户能阅读
    // deltaLength 越大 → 延迟越长（给渲染时间）
    // 整体内容越长 → 滚动间隔稍长
    const totalLength = this.streamingThinking.length
    const baseDelay = Math.max(30, Math.min(150, deltaLength * 2))
    const contentFactor = Math.max(1, Math.min(3, totalLength / 2000))
    const delay = Math.round(baseDelay * contentFactor)

    this.thinkingScrollTimer = setTimeout(() => {
      try {
        this.streamingThinkingScroller.scrollEdge(Edge.Bottom)
      } catch (e) {
        // scroller 可能尚未绑定，忽略
      }
      this.thinkingScrollTimer = -1
    }, delay)
  }

  // 合上最新 thinking（与 iOS 一致：新工具或内容出现后自动合上）
  private collapseLatestThinking(): void {
    if (this.latestThinkingId) {
      const newSet = new Set(this.expandedThinkingIds)
      newSet.delete(this.latestThinkingId)
      this.expandedThinkingIds = newSet
      this.latestThinkingId = ''
    }
  }

  @Builder
  ToolUseBubble(message: Message) {
    Column({ space: 0 }) {
      // Header
      Row({ space: 8 }) {
        // 图标
        SymbolGlyph(getToolIcon(message.toolName || 'Tool').symbol)
          .fontSize(14)
          .fontColor([getToolIcon(message.toolName || 'Tool').color])

        // 工具名
        Text(getToolIcon(message.toolName || 'Tool').label.toUpperCase())
          .fontSize(10)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.TextSecondary)

        // 摘要
        if (!this.expandedToolIds.has(message.id)) {
          Text(this.getToolInputSummary(message.toolName || '', message.toolInput || {}))
            .fontSize(11)
            .fontColor(Theme.TextTertiary)
            .maxLines(1)
            .layoutWeight(1)
        }

        Blank()

        // 状态图标
        this.ToolStatusIcon(message.toolStatus)

        // 展开箭头
        if (this.isToolExpandable(message.toolName)) {
          if (this.expandedToolIds.has(message.id)) {
            SymbolGlyph($r('sys.symbol.chevron_down'))
              .fontSize(10)
              .fontColor([Theme.TextSecondary])
          } else {
            SymbolGlyph($r('sys.symbol.chevron_right'))
              .fontSize(10)
              .fontColor([Theme.TextSecondary])
          }
        }
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 10, bottom: 10 })

      // 展开区域
      if (this.expandedToolIds.has(message.id)) {
        Divider()
          .color('rgba(255,255,255,0.1)')
          .width('100%')

        Column({ space: 8 }) {
          // INPUT
          if (message.toolInput) {
            Column({ space: 4 }) {
              Text('INPUT')
                .fontSize(9)
                .fontWeight(FontWeight.Bold)
                .fontColor(Theme.TextSecondary)

              Text(this.formatToolInput(message.toolInput))
                .fontSize(11)
                .fontColor(Theme.TextPrimary)
                .fontFamily('monospace')
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
          }

          // OUTPUT
          if (message.toolResult) {
            Column({ space: 4 }) {
              Text('OUTPUT')
                .fontSize(9)
                .fontWeight(FontWeight.Bold)
                .fontColor(Theme.TextSecondary)

              MarkdownRenderer({ content: message.toolResult.length > 2000 ?
                message.toolResult.substring(0, 2000) + '...' : message.toolResult })
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
          }

          // 文件附件预览（Write/Edit 工具）
          if (message.toolStatus === 'completed') {
            if (message.toolName === 'Write' || message.toolName === 'Edit') {
              Column({ space: 4 }) {
                Text('FILE')
                  .fontSize(9)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(Theme.TextSecondary)

                FileAttachmentBubble({
                  filePath: (message.toolInput ? message.toolInput['file_path'] : '') as string,
                  onImageTap: (src: string, alt: string, name: string) => {
                    this.openFilePreview(src, alt, name)
                  }
                })
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)
            }
          }
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 10, bottom: 10 })
      }
    }
    .width('100%')
    .backgroundColor('rgba(255,255,255,0.13)')
    .borderRadius(10)
    .border({
      width: 0.5,
      color: 'rgba(255,255,255,0.12)'
    })
    .onClick(() => {
      if (this.isToolExpandable(message.toolName)) {
        this.toggleTool(message.id)
      }
    })
  }

  // MARK: - Agent 派遣消息

  /**
   * 获取 Agent 的子工具列表（通过 parentToolUseId 关联）
   */
  private getChildToolCalls(parentToolUseId: string): Message[] {
    const children: Message[] = []
    for (let i = 0; i < this.messages.length; i++) {
      const m = this.messages[i]
      if (m.type === 'tool_use' && m.parentToolUseId === parentToolUseId) {
        children.push(m)
      }
    }
    return children
  }

  /**
   * 获取 Agent 状态文本
   */
  private getAgentStatusLabel(status?: string): string {
    switch (status) {
      case 'starting':
        return '启动中'
      case 'running':
        return '工作中'
      case 'done':
        return '已完成'
      case 'failed':
        return '失败'
      case 'stopped':
        return '已停止'
      default:
        return '等待中'
    }
  }

  /**
   * 获取 Agent 状态颜色
   */
  private getAgentStatusColor(status?: string): string {
    switch (status) {
      case 'starting':
        return Theme.TextSecondary
      case 'running':
        return Theme.WarningColor
      case 'done':
        return Theme.SuccessColor
      case 'failed':
        return Theme.ErrorColor
      case 'stopped':
        return Theme.TextTertiary
      default:
        return Theme.TextSecondary
    }
  }

  /**
   * 获取 Agent 状态的背景色
   */
  private getAgentStatusBgColor(status?: string): string {
    switch (status) {
      case 'running':
        return 'rgba(255,204,0,0.12)'
      case 'done':
        return 'rgba(52,199,89,0.12)'
      case 'failed':
        return 'rgba(255,69,58,0.12)'
      case 'stopped':
        return 'rgba(255,255,255,0.08)'
      default:
        return 'rgba(255,255,255,0.08)'
    }
  }

  @Builder
  AgentToolUseBubble(message: Message) {
    Column({ space: 0 }) {
      // Header
      Row({ space: 8 }) {
        // Agent 图标
        SymbolGlyph($r('sys.symbol.person_fill'))
          .fontSize(14)
          .fontColor([Theme.AccentBlue])

        // AGENT 标签
        Text('AGENT')
          .fontSize(10)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.TextSecondary)

        // 描述（未展开时显示）
        if (!this.expandedToolIds.has(message.id) && this.getAgentDescription(message)) {
          Text(this.getAgentDescription(message))
            .fontSize(11)
            .fontColor(Theme.TextTertiary)
            .maxLines(1)
            .layoutWeight(1)
        }

        Blank()

        // 子工具摘要（未展开时显示）
        if (!this.expandedToolIds.has(message.id) && !this.getAgentDescription(message)) {
          if (this.getAgentOutputSummary(message)) {
            Text(this.getAgentOutputSummary(message).length > 30 ? this.getAgentOutputSummary(message).substring(0, 30) + '...' : this.getAgentOutputSummary(message))
              .fontSize(11)
              .fontColor(Theme.TextTertiary)
              .maxLines(1)
              .layoutWeight(1)
          } else if (this.getAgentRecentToolsSummary(message)) {
            Text(this.getAgentRecentToolsSummary(message))
              .fontSize(11)
              .fontColor(Theme.TextTertiary)
              .maxLines(1)
              .layoutWeight(1)
          }
        }

        // 状态徽章
        {
          const s = this.getAgentStatusValue(message)
          if (s) {
            Text(this.getAgentStatusLabel(s))
              .fontSize(9)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.getAgentStatusColor(s))
              .padding({ left: 8, right: 8, top: 3, bottom: 3 })
              .borderRadius(8)
              .backgroundColor(this.getAgentStatusBgColor(s))
          }
        }

        // 展开箭头
        if (this.expandedToolIds.has(message.id)) {
          SymbolGlyph($r('sys.symbol.chevron_down'))
            .fontSize(10)
            .fontColor([Theme.TextSecondary])
        } else {
          SymbolGlyph($r('sys.symbol.chevron_right'))
            .fontSize(10)
            .fontColor([Theme.TextSecondary])
        }
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 10, bottom: 10 })

      // 展开内容
      if (this.expandedToolIds.has(message.id)) {
        Divider()
          .color('rgba(255,255,255,0.1)')
          .width('100%')

        Column({ space: 8 }) {
          // 描述
          if (this.getAgentDescription(message)) {
            Text(this.getAgentDescription(message))
              .fontSize(11)
              .fontColor(Theme.TextPrimary)
              .lineHeight(16)
              .width('100%')
          }

          // 错误
          if (message.toolStatus === 'failed') {
            Row({ space: 4 }) {
              SymbolGlyph($r('sys.symbol.exclamationmark_triangle_fill'))
                .fontSize(12)
                .fontColor([Theme.ErrorColor])
              Text(message.agentSummary || '')
                .fontSize(11)
                .fontColor(Theme.ErrorColor)
                .layoutWeight(1)
            }
            .padding(10)
            .backgroundColor('rgba(255,69,58,0.10)')
            .borderRadius(8)
            .width('100%')
          }

          // 输出摘要
          if (this.getAgentOutputSummary(message) && message.toolStatus !== 'failed') {
            Text(this.getAgentOutputSummary(message))
              .fontSize(11)
              .fontColor(Theme.TextTertiary)
              .lineHeight(16)
              .width('100%')
          }

          // 子工具渲染（嵌套）
          {
            const childToolCalls = this.getChildToolCalls(message.toolUseId || '')
            if (childToolCalls.length > 0) {
              Column({ space: 4 }) {
                ForEach(childToolCalls, (child: Message) => {
                  Row({ space: 0 }) {
                    // 连接线+节点
                    Column() {
                      Row()
                        .width(8)
                        .height(8)
                        .borderRadius(4)
                        .border({ width: 1, color: 'rgba(255,255,255,0.25)' })
                        .backgroundColor('#1C1C1E')
                        .margin({ left: 0, top: 4 })
                    }
                    .width(12)
                    .alignItems(HorizontalAlign.Center)
                    .padding({ top: 4 })

                    // 子工具卡片（紧凑版）
                    Column({ space: 0 }) {
                      Row({ space: 6 }) {
                        SymbolGlyph(getToolIcon(child.toolName || 'Tool').symbol)
                          .fontSize(12)
                          .fontColor([getToolIcon(child.toolName || 'Tool').color])

                        Text(getToolIcon(child.toolName || 'Tool').label)
                          .fontSize(10)
                          .fontWeight(FontWeight.Medium)
                          .fontColor(Theme.TextSecondary)

                        Text(this.getToolInputSummary(child.toolName || '', child.toolInput || {}))
                          .fontSize(10)
                          .fontColor(Theme.TextTertiary)
                          .maxLines(1)
                          .layoutWeight(1)

                        Blank()

                        this.ToolStatusIcon(child.toolStatus)
                      }
                      .width('100%')
                      .padding({ left: 8, right: 8, top: 6, bottom: 6 })
                      .borderRadius(6)
                      .backgroundColor('rgba(255,255,255,0.05)')
                    }
                    .layoutWeight(1)
                    .onClick(() => {
                      this.toggleTool(child.id)
                    })
                  }
                  .width('100%')
                  .alignItems(VerticalAlign.Top)
                }, (child: Message) => child.id + '_' + (child.toolStatus || ''))
              }
              .width('100%')
            } else if (!this.getAgentOutputSummary(message) && message.toolStatus !== 'failed') {
              Text(this.getAgentStatusValue(message) === 'starting' ? '正在启动 Agent...' : 'Agent 执行中')
                .fontSize(11)
                .fontColor(Theme.TextTertiary)
            }
          }

          // INPUT（展开时显示）
          if (message.toolInput) {
            Column({ space: 4 }) {
              Text('INPUT')
                .fontSize(9)
                .fontWeight(FontWeight.Bold)
                .fontColor(Theme.TextSecondary)

              Text(this.formatToolInput(message.toolInput))
                .fontSize(11)
                .fontColor(Theme.TextPrimary)
                .fontFamily('monospace')
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
          }
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 10, bottom: 10 })
      }
    }
    .width('100%')
    .backgroundColor('rgba(255,255,255,0.13)')
    .borderRadius(10)
    .border({
      width: 0.5,
      color: 'rgba(255,255,255,0.12)'
    })
    .onClick(() => {
      this.toggleTool(message.id)
    })
  }

  private getAgentStatusValue(message: Message): string {
    const childToolCalls = this.getChildToolCalls(message.toolUseId || '')
    const result = message.agentTaskStatus || (
      childToolCalls.length > 0 ? 'running' :
      message.toolStatus === 'running' ? 'starting' : 'done'
    )
    return result
  }

  private getAgentDescription(message: Message): string {
    const input = message.toolInput || {}
    return input['description'] as string || ''
  }

  private getAgentOutputSummary(message: Message): string {
    const s = this.getAgentStatusValue(message)
    if ((s === 'done' || s === 'stopped') && message.agentSummary) {
      return message.agentSummary
    }
    return ''
  }

  private getAgentRecentToolsSummary(message: Message): string {
    const childToolCalls = this.getChildToolCalls(message.toolUseId || '')
    if (childToolCalls.length === 0) return ''
    const recent = childToolCalls.slice(-2)
    const parts: string[] = []
    for (let i = 0; i < recent.length; i++) {
      const tc = recent[i]
      const name = tc.toolName || 'Tool'
      const summary = this.getToolInputSummary(name, tc.toolInput || {})
      const suffix = tc.toolStatus === 'completed' ? ' ✓' : tc.toolStatus === 'failed' ? ' ✗' : ' ···'
      parts.push(summary ? `${name} ${summary}${suffix}` : `${name}${suffix}`)
    }
    return parts.join('  ')
  }

  @Builder
  ToolStatusIcon(status?: string) {
    if (status === 'running') {
      LoadingProgress()
        .width(12)
        .height(12)
        .color(Theme.PrimaryColor)
    } else if (status === 'completed') {
      SymbolGlyph($r('sys.symbol.checkmark_circle_fill'))
        .fontSize(12)
        .fontColor([Theme.SuccessColor])
    } else if (status === 'failed') {
      SymbolGlyph($r('sys.symbol.xmark_circle_fill'))
        .fontSize(12)
        .fontColor([Theme.ErrorColor])
    } else {
      SymbolGlyph($r('sys.symbol.clock'))
        .fontSize(10)
        .fontColor([Theme.TextTertiary])
    }
  }

  private isToolExpandable(toolName?: string): boolean {
    if (!toolName) return false
    return ['Edit', 'Write', 'Bash', 'Read', 'Grep', 'WebFetch', 'Agent'].indexOf(toolName) >= 0
  }

  private toggleTool(id: string): void {
    const newSet = new Set(this.expandedToolIds)
    if (newSet.has(id)) {
      newSet.delete(id)
    } else {
      newSet.add(id)
    }
    this.expandedToolIds = newSet
  }

  private formatToolInput(input: Record<string, Object>): string {
    const lines: string[] = []
    const keys = Object.keys(input).sort()
    for (let i = 0; i < keys.length; i++) {
      const key = keys[i]
      const value = input[key]
      if (typeof value === 'string') {
        const str = value as string
        if (str.length > 100) {
          lines.push(`${key}: "${str.substring(0, 100)}..."`)
        } else {
          lines.push(`${key}: "${str}"`)
        }
      } else if (typeof value === 'number') {
        lines.push(`${key}: ${value}`)
      } else if (typeof value === 'boolean') {
        lines.push(`${key}: ${value}`)
      } else if (value !== null && value !== undefined) {
        lines.push(`${key}: ${JSON.stringify(value)}`)
      }
    }
    return lines.join('\n')
  }

  // 打开文件/图片预览
  private openFilePreview(src: string, alt: string, name: string): void {
    this.filePreviewSrc = src
    this.filePreviewAlt = alt
    this.filePreviewName = name
    this.showFilePreview = true
  }


  // 工具结果气泡（独立显示，与 iOS toolResultBubble 一致）
  @Builder
  ToolResultBubble(message: Message) {
    Column({ space: 4 }) {
      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.doc_text'))
          .fontSize(12)
          .fontColor([Theme.TextSecondary])

        Text('结果')
          .fontSize(Theme.FontTiny)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.TextSecondary)

        Blank()

        if (message.toolStatus === 'completed') {
          SymbolGlyph($r('sys.symbol.checkmark_circle_fill'))
            .fontSize(12)
            .fontColor([Theme.SuccessColor])
        } else if (message.toolStatus === 'failed') {
          SymbolGlyph($r('sys.symbol.xmark_circle_fill'))
            .fontSize(12)
            .fontColor([Theme.ErrorColor])
        }
      }
      .width('100%')

      if (message.toolResult) {
        MarkdownRenderer({ content: message.toolResult })
      }
    }
    .width('100%')
    .padding(12)
    .backgroundColor('rgba(255,255,255,0.16)')
    .borderRadius(12)
  }

  // AskUserQuestion 工具气泡（参照桌面端 AskUserQuestion.tsx）
  @Builder
  AskUserQuestionBubble(message: Message) {
    Column({ space: 12 }) {
      // Header
      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.questionmark_circle_fill'))
          .fontSize(20)
          .fontColor([Theme.AccentPurple])

        Text('需要输入')
          .fontSize(Theme.FontBody)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.TextPrimary)

        if (this.questionHasSubmitted || message.toolStatus === 'completed') {
          Text('已回答')
            .fontSize(Theme.FontTiny)
            .fontColor(Theme.TextTertiary)
            .backgroundColor(Theme.BackgroundTertiary)
            .borderRadius(4)
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
        }
      }

      // 获取问题列表
      if (this.parseAskUserQuestions(message).length > 0) {
        // 多问题 Tab
        if (this.parseAskUserQuestions(message).length > 1) {
          Row({ space: 0 }) {
            ForEach(this.parseAskUserQuestions(message), (q: QuestionItem, index: number) => {
              Button(q.header || `Q${index + 1}`)
                .fontSize(Theme.FontTiny)
                .fontColor(this.questionActiveTab === index ? Theme.AccentPurple : Theme.TextSecondary)
                .backgroundColor(this.questionActiveTab === index ? 'rgba(175,82,222,0.15)' : 'transparent')
                .borderRadius(0)
                .onClick(() => { this.questionActiveTab = index })
            }, (q: QuestionItem, index: number) => `qtab-${index}`)
          }
          .width('100%')
        }

        // 当前问题
        if (this.parseAskUserQuestions(message)[this.questionActiveTab]) {
          this.QuestionCard(message, this.questionActiveTab)
        }
      }
    }
    .width('100%')
    .padding(Theme.SpacingLG)
    .backgroundColor(Theme.BackgroundSecondary)
    .borderRadius(Theme.RadiusMedium)
    .border({ width: 1, color: this.questionHasSubmitted ? Theme.GlassBorder : Theme.AccentPurple })
  }

  @Builder
  QuestionCard(message: Message, qIndex: number) {
    Column({ space: 12 }) {
      // 问题文本
      Text(this.getQuestionText(message, qIndex))
        .fontSize(Theme.FontCaption)
        .fontColor(Theme.TextPrimary)

      // 选项
      if (this.hasQuestionOptions(message, qIndex) && !this.questionHasSubmitted) {
        Column({ space: 8 }) {
          ForEach(this.getQuestionOptions(message, qIndex), (opt: QuestionOption, optIndex: number) => {
            this.QuestionOptionCard(message, qIndex, opt, optIndex, this.isQuestionMultiSelect(message, qIndex))
          }, (opt: QuestionOption, optIndex: number) => `opt-${qIndex}-${optIndex}`)
        }
        .width('100%')
      }

      // 自定义输入
      if (!this.questionHasSubmitted) {
        Row({ space: 8 }) {
          TextInput({ placeholder: '自定义回答...', text: this.questionFreeText })
            .layoutWeight(1)
            .height(36)
            .backgroundColor(Theme.BackgroundTertiary)
            .borderRadius(8)
            .fontSize(Theme.FontCaption)
            .fontColor(Theme.TextPrimary)
            .onChange((value: string) => {
              this.questionFreeText = value
            })

          Button('发送')
            .fontSize(Theme.FontTiny)
            .fontColor(Theme.TextOnPrimary)
            .backgroundColor(Theme.PrimaryColor)
            .borderRadius(8)
            .height(36)
            .enabled(this.questionFreeText.trim().length > 0)
            .onClick(() => {
              this.submitQuestionAnswer(message, this.questionFreeText.trim())
            })
        }
        .width('100%')
      }

      // 已提交显示
      if (this.questionHasSubmitted) {
        Row({ space: 4 }) {
          SymbolGlyph($r('sys.symbol.checkmark_circle_fill'))
            .fontSize(14)
            .fontColor([Theme.SuccessColor])
          Text('已提交')
            .fontSize(Theme.FontCaption)
            .fontColor(Theme.SuccessColor)
        }
      }
    }
  }

  // QuestionCard 辅助方法
  private getQuestionText(message: Message, qIndex: number): string {
    const questions = this.parseAskUserQuestions(message)
    return questions[qIndex]?.question || ''
  }

  private hasQuestionOptions(message: Message, qIndex: number): boolean {
    const questions = this.parseAskUserQuestions(message)
    const opts = questions[qIndex]?.options
    return opts !== undefined && opts.length > 0
  }

  private getQuestionOptions(message: Message, qIndex: number): QuestionOption[] {
    const questions = this.parseAskUserQuestions(message)
    return questions[qIndex]?.options || []
  }

  private isQuestionMultiSelect(message: Message, qIndex: number): boolean {
    const questions = this.parseAskUserQuestions(message)
    return questions[qIndex]?.multiSelect || false
  }

  private isOptionSelected(qIndex: number, label: string): boolean {
    return (this.questionSelections.get(qIndex) || []).includes(label || '')
  }

  @Builder
  QuestionOptionCard(message: Message, qIndex: number, opt: QuestionOption, optIndex: number, isMultiSelect: boolean) {
    Row({ space: 12 }) {
      // 选择指示器
      if (isMultiSelect) {
        Row() {
          if (this.isOptionSelected(qIndex, opt.label || '')) {
            Text('✓')
              .fontSize(12)
              .fontColor(Theme.TextOnPrimary)
          }
        }
        .width(18)
        .height(18)
        .borderRadius(4)
        .backgroundColor(this.isOptionSelected(qIndex, opt.label || '') ? Theme.AccentPurple : 'transparent')
        .border({ width: 2, color: this.isOptionSelected(qIndex, opt.label || '') ? Theme.AccentPurple : Theme.GlassBorder })
      } else {
        Row() {
          if (this.isOptionSelected(qIndex, opt.label || '')) {
            Text('✓')
              .fontSize(12)
              .fontColor(Theme.TextOnPrimary)
          }
        }
        .width(18)
        .height(18)
        .borderRadius(9)
        .backgroundColor(this.isOptionSelected(qIndex, opt.label || '') ? Theme.AccentPurple : 'transparent')
        .border({ width: 2, color: this.isOptionSelected(qIndex, opt.label || '') ? Theme.AccentPurple : Theme.GlassBorder })
      }

      // 选项文本
      Column({ space: 2 }) {
        Text(opt.label || '')
          .fontSize(Theme.FontCaption)
          .fontColor(this.isOptionSelected(qIndex, opt.label || '') ? Theme.AccentPurple : Theme.TextPrimary)

        if (opt.description) {
          Text(opt.description)
            .fontSize(Theme.FontTiny)
            .fontColor(Theme.TextTertiary)
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .padding(12)
    .backgroundColor(this.isOptionSelected(qIndex, opt.label || '') ? 'rgba(175,82,222,0.1)' : Theme.BackgroundTertiary)
    .borderRadius(8)
    .border({ width: this.isOptionSelected(qIndex, opt.label || '') ? 1 : 0, color: Theme.AccentPurple })
    .onClick(() => {
      this.toggleQuestionOption(message, qIndex, opt.label || '', isMultiSelect)
    })
  }

  // 解析 AskUserQuestion 工具的 input
  private parseAskUserQuestions(message: Message): QuestionItem[] {
    const input = message.toolInput
    if (!input || typeof input !== 'object') return []

    const obj = input as Record<string, Object>

    // 格式1: { questions: [...] }
    if (obj['questions'] && Array.isArray(obj['questions'])) {
      return obj['questions'] as QuestionItem[]
    }

    // 格式2: { question: "...", options: [...] }
    if (obj['question'] && typeof obj['question'] === 'string') {
      return [{
        question: obj['question'] as string,
        header: obj['header'] as string,
        options: obj['options'] as QuestionOption[],
        multiSelect: obj['multiSelect'] as boolean
      }]
    }

    return []
  }

  // 切换问题选项
  private toggleQuestionOption(message: Message, qIndex: number, label: string, isMultiSelect: boolean): void {
    const current = this.questionSelections.get(qIndex) || []

    if (isMultiSelect) {
      const newSelections = current.includes(label)
        ? current.filter(s => s !== label)
        : [...current, label]
      this.questionSelections.set(qIndex, newSelections)
    } else {
      this.questionSelections.set(qIndex, [label])
    }

    // 触发更新
    const newMap = new Map(this.questionSelections)
    this.questionSelections = newMap
  }

  // 提交问题答案
  private submitQuestionAnswer(message: Message, answer: string): void {
    const pendingPermission = sessionStore.pendingPermissions.get(this.sessionId || '')
    if (!pendingPermission) return

    const questions = this.parseAskUserQuestions(message)
    const answers: Record<string, string> = {}

    if (this.questionFreeText.trim()) {
      // 使用自定义文本
      for (const q of questions) {
        if (q.question) {
          answers[q.question] = this.questionFreeText.trim()
        }
      }
    } else {
      // 使用选择的选项
      for (let i = 0; i < questions.length; i++) {
        const selected = this.questionSelections.get(i) || []
        if (selected.length > 0 && questions[i].question) {
          answers[questions[i].question!] = selected.join(', ')
        }
      }
    }

    // 发送响应 - AskUserQuestion 使用专门的响应方法
    const updatedInput: Record<string, string> = {}
    const keys = Object.keys(answers)
    for (let i = 0; i < keys.length; i++) {
      updatedInput[keys[i]] = answers[keys[i]]
    }
    sessionStore.sendAskUserQuestionResponse(pendingPermission.requestId, updatedInput)

    this.questionHasSubmitted = true
  }

  @Builder
  PermissionBubble(message: Message) {
    Column({ space: 12 }) {
      // Header
      Row({ space: 8 }) {
        SymbolGlyph(this.getPermissionToolIcon(message.toolName || '').symbol)
          .fontSize(20)
          .fontColor([this.getPermissionToolIcon(message.toolName || '').color])

        Text(this.getPermissionTitle(message.toolName || '', message.toolInput))
          .fontSize(Theme.FontBody)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.TextPrimary)
          .layoutWeight(1)

        if (message.isPermissionHandled) {
          Text(message.permissionResult ? '已允许' : '已拒绝')
            .fontSize(Theme.FontTiny)
            .fontColor(message.permissionResult ? Theme.SuccessColor : Theme.ErrorColor)
            .backgroundColor(message.permissionResult ? 'rgba(52,199,89,0.15)' : 'rgba(255,69,58,0.15)')
            .borderRadius(4)
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
        }
      }

      // 描述
      if (message.permissionDescription) {
        Text(message.permissionDescription)
          .fontSize(Theme.FontCaption)
          .fontColor(Theme.TextSecondary)
      }

      // Diff 预览（Edit/Write 工具）
      if ((message.toolName === 'Edit' || message.toolName === 'Write') && message.toolInput) {
        this.PermissionDiffPreview(message.toolName, message.toolInput)
      }

      // Bash 命令预览
      if (message.toolName === 'Bash' && message.toolInput) {
        if ((message.toolInput as Record<string, Object>)['command']) {
          Row() {
            Text('$ ')
              .fontSize(Theme.FontTiny)
              .fontColor(Theme.AccentGreen)
            Text((message.toolInput as Record<string, Object>)['command'] as string)
              .fontSize(Theme.FontTiny)
              .fontColor(Theme.TextPrimary)
              .layoutWeight(1)
          }
          .width('100%')
          .padding(8)
          .backgroundColor(Theme.BackgroundTertiary)
          .borderRadius(8)
        }
      }

      // 操作按钮
      if (!message.isPermissionHandled) {
        Column({ space: 8 }) {
          Row({ space: 8 }) {
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
                  this.messageUpdateCounter++
                }
              })

            Button('始终允许')
              .fontSize(Theme.FontCaption)
              .fontColor(Theme.PrimaryColor)
              .backgroundColor('rgba(0,122,255,0.15)')
              .borderRadius(8)
              .layoutWeight(1)
              .onClick(() => {
                if (message.permissionId) {
                  sessionStore.sendPermissionResponse(message.permissionId, true, true)
                  message.isPermissionHandled = true
                  message.permissionResult = true
                  this.messageUpdateCounter++
                }
              })
          }
          .width('100%')

          Button('拒绝')
            .fontSize(Theme.FontCaption)
            .fontColor(Theme.TextSecondary)
            .backgroundColor(Theme.BackgroundTertiary)
            .borderRadius(8)
            .width('100%')
            .onClick(() => {
              if (message.permissionId) {
                sessionStore.sendPermissionResponse(message.permissionId, false)
                message.isPermissionHandled = true
                message.permissionResult = false
                this.messageUpdateCounter++
              }
            })
        }
      }
    }
    .width('100%')
    .padding(Theme.SpacingLG)
    .backgroundColor(Theme.BackgroundSecondary)
    .borderRadius(Theme.RadiusMedium)
    .border({ width: 1, color: message.isPermissionHandled ? Theme.GlassBorder : Theme.AccentOrange })
  }

  // 权限工具图标
  private getPermissionToolIcon(toolName: string): ToolIconInfo {
    switch (toolName) {
      case 'Edit': return new ToolIconInfo($r('sys.symbol.square_and_pencil'), '编辑文件', Theme.WarningColor)
      case 'Write': return new ToolIconInfo($r('sys.symbol.doc_text'), '写入文件', Theme.AccentGreen)
      case 'Bash': return new ToolIconInfo($r('sys.symbol.gearshape'), '执行命令', Theme.AccentOrange)
      case 'Read': return new ToolIconInfo($r('sys.symbol.doc_text'), '读取文件', Theme.AccentBlue)
      case 'Glob': return new ToolIconInfo($r('sys.symbol.folder'), '搜索文件', Theme.AccentPurple)
      case 'Grep': return new ToolIconInfo($r('sys.symbol.magnifyingglass'), '搜索内容', Theme.AccentPurple)
      default: return new ToolIconInfo($r('sys.symbol.lock_shield_fill'), toolName, Theme.AccentOrange)
    }
  }

  // 权限标题
  private getPermissionTitle(toolName: string, input?: Record<string, Object>): string {
    const obj = input || {}
    const filePath = obj['file_path'] as string || ''
    const fileName = filePath ? filePath.split('/').pop() || filePath : ''

    switch (toolName) {
      case 'Edit': return fileName ? `编辑 ${fileName}` : '编辑文件'
      case 'Write': return fileName ? `写入 ${fileName}` : '写入文件'
      case 'Bash': return '执行命令'
      case 'Read': return fileName ? `读取 ${fileName}` : '读取文件'
      default: return `权限请求: ${toolName}`
    }
  }

  // Diff 预览
  @Builder
  PermissionDiffPreview(toolName: string, input: Record<string, Object>) {
    Column({ space: 4 }) {
      // 文件路径
      Text(input['file_path'] as string || 'file')
        .fontSize(Theme.FontTiny)
        .fontColor(Theme.TextTertiary)
        .width('100%')

      // 简化 diff 显示
      Scroll() {
        Column({ space: 2 }) {
          // 删除的内容（old_string）
          if (toolName === 'Edit' && (input['old_string'] as string)) {
            ForEach((input['old_string'] as string).split('\n').slice(0, 10), (line: string, idx: number) => {
              Row() {
                Text('-')
                  .fontSize(Theme.FontTiny)
                  .fontColor(Theme.ErrorColor)
                  .width(12)
                Text(line || ' ')
                  .fontSize(Theme.FontTiny)
                  .fontColor(Theme.ErrorColor)
                  .backgroundColor('rgba(255,69,58,0.1)')
                  .layoutWeight(1)
              }
              .width('100%')
              .padding({ left: 4, right: 4 })
            }, (line: string, idx: number) => `old-${idx}`)
            if ((input['old_string'] as string).split('\n').length > 10) {
              Text(`... 还有 ${(input['old_string'] as string).split('\n').length - 10} 行`)
                .fontSize(Theme.FontTiny)
                .fontColor(Theme.TextTertiary)
            }
          }

          // 添加的内容（new_string / content）
          if ((input['new_string'] as string) || (toolName === 'Write' ? input['content'] as string : '')) {
            ForEach(((input['new_string'] as string) || (toolName === 'Write' ? input['content'] as string : '')).split('\n').slice(0, 10), (line: string, idx: number) => {
              Row() {
                Text('+')
                  .fontSize(Theme.FontTiny)
                  .fontColor(Theme.SuccessColor)
                  .width(12)
                Text(line || ' ')
                  .fontSize(Theme.FontTiny)
                  .fontColor(Theme.SuccessColor)
                  .backgroundColor('rgba(52,199,89,0.1)')
                  .layoutWeight(1)
              }
              .width('100%')
              .padding({ left: 4, right: 4 })
            }, (line: string, idx: number) => `new-${idx}`)
            if (((input['new_string'] as string) || (toolName === 'Write' ? input['content'] as string : '')).split('\n').length > 10) {
              Text(`... 还有 ${((input['new_string'] as string) || (toolName === 'Write' ? input['content'] as string : '')).split('\n').length - 10} 行`)
                .fontSize(Theme.FontTiny)
                .fontColor(Theme.TextTertiary)
            }
          }
        }
        .width('100%')
      }
      .width('100%')
      .constraintSize({ maxHeight: 150 })
      .padding(8)
      .backgroundColor(Theme.BackgroundTertiary)
      .borderRadius(8)
    }
    .width('100%')
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
                  this.messageUpdateCounter++
                }
              })
          }, (option: string, index: number) => `option-${index}`)

          // 自定义输入（与 iOS 一致）
          if (this.showCustomInput && this.activeQuestionMessageId === message.id) {
            Row({ space: 8 }) {
              TextInput({ placeholder: '输入自定义回答...', text: this.customInputText })
                .layoutWeight(1)
                .height(36)
                .backgroundColor(Theme.BackgroundTertiary)
                .borderRadius(8)
                .fontSize(Theme.FontCaption)
                .fontColor(Theme.TextPrimary)
                .onChange((value: string) => {
                  this.customInputText = value
                })
                .onSubmit(() => {
                  if (this.customInputText.trim() && message.questionId) {
                    sessionStore.sendQuestionResponse(message.questionId, this.customInputText.trim())
                    message.isQuestionAnswered = true
                    message.selectedAnswer = this.customInputText.trim()
                    this.messageUpdateCounter++
                    this.showCustomInput = false
                    this.customInputText = ''
                  }
                })

              Button('发送')
                .fontSize(Theme.FontTiny)
                .fontColor(Theme.TextOnPrimary)
                .backgroundColor(Theme.PrimaryColor)
                .borderRadius(8)
                .height(36)
                .padding({ left: 12, right: 12 })
                .onClick(() => {
                  if (this.customInputText.trim() && message.questionId) {
                    sessionStore.sendQuestionResponse(message.questionId, this.customInputText.trim())
                    message.isQuestionAnswered = true
                    message.selectedAnswer = this.customInputText.trim()
                    this.messageUpdateCounter++
                    this.showCustomInput = false
                    this.customInputText = ''
                  }
                })
            }
            .width('100%')
          } else {
            Button('自定义输入...')
              .fontSize(Theme.FontCaption)
              .fontColor(Theme.TextSecondary)
              .backgroundColor(Theme.BackgroundTertiary)
              .borderRadius(8)
              .width('100%')
              .onClick(() => {
                this.showCustomInput = true
                this.activeQuestionMessageId = message.id
                this.customInputText = ''
              })
          }
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

  private getQuestionTitle(message: Message): string {
    if (message.questions && message.questions.length > 0) {
      const q = message.questions[0]
      return q.header || '请选择'
    }
    return '请选择'
  }

  private getQuestionContent(message: Message): string {
    if (message.questions && message.questions.length > 0) {
      return message.questions[0].question || message.content
    }
    return message.content
  }

  @Builder
  ErrorBubble(message: Message) {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.exclamationmark_triangle_fill'))
          .fontSize(16).fontColor([Theme.ErrorColor])
        Text('错误').fontSize(14).fontWeight(FontWeight.Bold).fontColor(Theme.ErrorColor)
      }
      if (message.content) {
        Text(message.content).fontSize(13).fontColor(Theme.TextSecondary)
      }
      if (this.activeCopyMessageId === message.id) {
        Row({ space: 6 }) {
          SymbolGlyph($r('sys.symbol.doc_text'))
            .fontSize(12).fontColor([Theme.TextPrimary])
          Text('复制').fontSize(11).fontColor(Theme.TextPrimary)
        }
        .padding({ left: 10, right: 10, top: 5, bottom: 5 })
        .backgroundColor(Theme.GlassBackground)
        .borderRadius(12)
        .border({ width: 0.5, color: Theme.GlassBorder })
        .onClick(() => {
          this.copyToClipboard(message.content)
          this.activeCopyMessageId = ''
        })
      }
    }
    .width('100%').padding(14)
    .backgroundColor(Theme.ErrorColor + '20')
    .borderRadius(10).border({ width: 0.5, color: Theme.ErrorColor + '40' })
    .gesture(
      LongPressGesture()
        .onAction(() => {
          if (this.activeCopyMessageId === message.id) {
            this.activeCopyMessageId = ''
          } else {
            this.activeCopyMessageId = message.id
          }
        })
    )
  }

  @Builder
  SystemBubble(message: Message) {
    Row() {
      Text(message.content || '系统消息')
        .fontSize(12).fontColor(Theme.TextTertiary)
    }
    .width('100%').justifyContent(FlexAlign.Center).padding({ top: 4, bottom: 4 })
  }

  @Builder
  TaskSummaryBubble(message: Message) {
    if (message.tasks && message.tasks.length > 0) {
      Column({ space: 6 }) {
        Row({ space: 6 }) {
          SymbolGlyph($r('sys.symbol.checkmark_circle_fill'))
            .fontSize(14).fontColor([Theme.AccentBlue])
          Text('任务').fontSize(13).fontWeight(FontWeight.Bold).fontColor(Theme.TextPrimary)
        }
        Column({ space: 4 }) {
          ForEach(message.tasks, (task: TaskItem, ti: number) => {
            Row({ space: 6 }) {
              if (task.status === 'completed') {
                SymbolGlyph($r('sys.symbol.checkmark_circle_fill'))
                  .fontSize(12).fontColor([Theme.SuccessColor])
              } else if (task.status === 'in_progress') {
                SymbolGlyph($r('sys.symbol.clock')).fontSize(12).fontColor([Theme.AccentBlue])
              } else if (task.status === 'failed') {
                SymbolGlyph($r('sys.symbol.xmark_circle_fill'))
                  .fontSize(12).fontColor([Theme.ErrorColor])
              } else {
                SymbolGlyph($r('sys.symbol.circle')).fontSize(12).fontColor([Theme.TextTertiary])
              }
              Text(task.content)
                .fontSize(12)
                .fontColor(task.status === 'completed' ? Theme.TextTertiary : Theme.TextPrimary)
                .decoration(task.status === 'completed' ? { type: TextDecorationType.LineThrough } : undefined)
                .layoutWeight(1)
            }.width('100%').alignItems(VerticalAlign.Center)
          }, (task: TaskItem, ti: number) => `tsk-${ti}`)
        }.width('100%')
      }
      .width('100%').padding(14)
      .backgroundColor('#FFFFFF18').borderRadius(10)
    }
  }

  @Builder
  ContextRing() {
    Row({ space: 4 }) {
      Stack() {
        Progress({ value: this.contextUsage, total: 100, type: ProgressType.Ring })
          .width(22).height(22)
          .color(this.getRingColor())
          .backgroundColor('#333333')
          .style({ strokeWidth: 4 })
        Text(`${this.contextUsage}%`)
          .fontSize(6).fontColor(Theme.TextPrimary).lineHeight(7)
      }
      .width(22).height(22)
    }
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      this.showContextDetail = true
      this.fetchContextUsage()
    })
  }

  // 上下文详情 Sheet
  @Builder
  ContextDetailSheet() {
    Column({ space: 12 }) {
      Row() {
        Text('上下文使用量')
          .fontSize(18).fontWeight(FontWeight.Bold).fontColor(Theme.TextPrimary)
          .layoutWeight(1).textAlign(TextAlign.Center)
      }.width('100%').padding({ bottom: 4 })

      // 模型名称
      if (this.contextModel) {
        Text('模型: ' + this.contextModel)
          .fontSize(13).fontColor(Theme.TextSecondary).width('100%')
      }

      // 用量
      Row({ space: 12 }) {
        Column({ space: 2 }) {
          Text(this.formatTokens(this.contextTotal))
            .fontSize(16).fontWeight(FontWeight.Bold).fontColor(Theme.TextPrimary)
          Text('已用').fontSize(10).fontColor(Theme.TextTertiary)
        }.alignItems(HorizontalAlign.Center)

        Column({ space: 2 }) {
          Text(this.formatTokens(this.contextMax - this.contextTotal))
            .fontSize(16).fontWeight(FontWeight.Bold).fontColor(Theme.SuccessColor)
          Text('剩余').fontSize(10).fontColor(Theme.TextTertiary)
        }.alignItems(HorizontalAlign.Center)

        Column({ space: 2 }) {
          Text(this.formatTokens(this.contextMax))
            .fontSize(16).fontWeight(FontWeight.Bold).fontColor(Theme.TextSecondary)
          Text('上限').fontSize(10).fontColor(Theme.TextTertiary)
        }.alignItems(HorizontalAlign.Center)
      }
      .width('100%').justifyContent(FlexAlign.SpaceAround).padding({ top: 8, bottom: 8 })

      // 圆环
      Row({ space: 12 }) {
        Progress({ value: this.contextUsage, total: 100, type: ProgressType.Ring })
          .width(60).height(60).color(this.getRingColor()).backgroundColor('#333333')
          .style({ strokeWidth: 8 })
      }.width('100%').justifyContent(FlexAlign.Center)
    }
    .width('100%').padding(Theme.SpacingLG)
  }

  // MARK: - 翻译结果

  @Builder
  TranslateResultSheet() {
    Column({ space: 12 }) {
      // 标题栏
      Row() {
        Text('翻译结果')
          .fontSize(18).fontWeight(FontWeight.Bold).fontColor(Theme.TextPrimary)
          .layoutWeight(1).textAlign(TextAlign.Center)
        Button() {
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(16).fontColor([Theme.TextSecondary])
        }
        .width(32).height(32)
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          this.showTranslateResult = false
        })
      }
      .width('100%').padding({ bottom: 8 })

      // 原文
      if (this.isTranslating) {
        Row({ space: 8 }) {
          LoadingProgress().width(16).height(16).color(Theme.PrimaryColor)
          Text('翻译中...').fontSize(13).fontColor(Theme.TextSecondary)
        }
        .width('100%').justifyContent(FlexAlign.Center).padding({ top: 20, bottom: 20 })
      } else if (this.translateError) {
        Column({ space: 8 }) {
          Row({ space: 6 }) {
            SymbolGlyph($r('sys.symbol.exclamationmark_triangle_fill'))
              .fontSize(16).fontColor([Theme.WarningColor])
            Text('翻译失败').fontSize(14).fontWeight(FontWeight.Medium).fontColor(Theme.WarningColor)
          }
          Text(this.translateError)
            .fontSize(12).fontColor(Theme.TextTertiary)
          Text('已将原文复制到剪贴板')
            .fontSize(11).fontColor(Theme.TextTertiary)
        }
        .width('100%')
        .padding(16)
        .backgroundColor('rgba(255,204,0,0.08)')
        .borderRadius(12)
      } else if (this.translateResultText) {
        // 翻译后的文本
        Text(this.translateResultText)
          .fontSize(15)
          .fontColor(Theme.TextPrimary)
          .lineHeight(24)
          .width('100%')

        // 操作按钮
        Row({ space: 12 }) {
          Button() {
            Text('复制翻译结果').fontSize(13).fontColor(Theme.TextOnPrimary)
          }
          .backgroundColor(Theme.PrimaryColor)
          .borderRadius(10)
          .layoutWeight(1)
          .height(40)
          .onClick(() => {
            this.copyToClipboard(this.translateResultText)
            this.showTranslateResult = false
          })

          Button() {
            Text('关闭').fontSize(13).fontColor(Theme.TextPrimary)
          }
          .backgroundColor(Theme.GlassBackground)
          .borderRadius(10)
          .layoutWeight(1)
          .height(40)
          .onClick(() => {
            this.showTranslateResult = false
          })
        }
        .width('100%')
        .padding({ top: 8 })
      }
    }
    .width('100%').padding(Theme.SpacingLG)
  }

  private formatTokens(count: number): string {
    if (count >= 1000000) return (count / 1000000).toFixed(1) + 'M'
    if (count >= 1000) return (count / 1000).toFixed(1) + 'K'
    return count.toString()
  }

  @Builder
  PermissionSheet() {
    Column({ space: 4 }) {
      Row() {
        Text('权限模式')
          .fontSize(18).fontWeight(FontWeight.Bold).fontColor(Theme.TextPrimary)
          .layoutWeight(1).textAlign(TextAlign.Center)
      }
      .width('100%').padding({ bottom: 12 })

      ForEach([PermissionMode.DEFAULT, PermissionMode.ACCEPT_EDITS, PermissionMode.PLAN, PermissionMode.BYPASS_PERMISSIONS],
        (mode: PermissionMode) => {
        Row({ space: 12 }) {
          Column({ space: 2 }) {
            Text(getPermissionModeDisplayName(mode))
              .fontSize(15).fontColor(Theme.TextPrimary)

            Text(getPermissionModeDescription(mode))
              .fontSize(12).fontColor(Theme.TextTertiary)
          }
          .layoutWeight(1).alignItems(HorizontalAlign.Start)

          Radio({ value: mode, group: 'chatPermission' })
            .checked(this.currentPermissionMode === mode)
            .onChange((checked: boolean) => {
              if (checked) {
                this.currentPermissionMode = mode
                sessionStore.changePermissionMode(mode)
                this.showPermSheet = false
              }
            })
        }
        .width('100%').padding({ top: 8, bottom: 8 })
      }, (mode: PermissionMode) => mode)
    }
    .width('100%').padding(Theme.SpacingLG)
  }

  @Builder
  InputAreaContent() {
    Column({ space: 8 }) {
      // 附件预览 - 水平滚动缩略图
      if (this.pendingAttachments.length > 0) {
        this.AttachmentPreviewRow()
      }

      Row({ space: 8 }) {
        // 菜单按钮 - 沉浸光感浮动按钮
        HdsMiniBarButton({
          barWidth: 36,
          barHeight: 36,
          contentPadding: 4,
          iconResource: $r('sys.symbol.plus'),
          iconSize: 16,
          iconColor: [Theme.TextSecondary],
          maskColor: 'rgba(255,255,255,0.15)',
          barBottomMargin: 0,
          onButtonClick: () => {
            this.showMenu = !this.showMenu
          }
        })

        // 输入框 - 液态玻璃效果
        TextArea({ placeholder: this.pendingAttachments.length > 0 ? '添加描述或直接发送...' : '发送消息...', text: this.inputText })
          .layoutWeight(1)
          .constraintSize({ minHeight: 36, maxHeight: 120 })
          .backgroundColor('rgba(255,255,255,0.16)')
          .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
          .borderRadius(18)
          .fontColor(Theme.TextPrimary)
          .placeholderColor('rgba(255,255,255,0.3)')
          .fontSize(Theme.FontBody)
          .padding({ left: 14, right: 14, top: 8, bottom: 8 })
          .onChange((value: string) => {
            this.inputText = value
          })

        // 始终显示发送按钮（不显示停止按钮，以免阻塞用户发送新消息）
        HdsMiniBarButton({
          barWidth: 36,
          barHeight: 36,
          contentPadding: 4,
          iconResource: this.inputText.trim() || this.pendingAttachments.length > 0 ?
            $r('sys.symbol.arrow_up') : $r('sys.symbol.arrow_up'),
          iconSize: 16,
          iconColor: this.inputText.trim() || this.pendingAttachments.length > 0 ?
            [Theme.TextOnPrimary] : [Theme.TextSecondary],
          maskColor: this.inputText.trim() || this.pendingAttachments.length > 0 ?
            Theme.PrimaryColor : 'rgba(255,255,255,0.15)',
          barBottomMargin: 0,
          onButtonClick: () => {
            if (this.inputText.trim() || this.pendingAttachments.length > 0) {
              this.sendMessage()
            }
          }
        })
      }
      .width('100%')
      .alignItems(VerticalAlign.Bottom)
      .padding({ left: 0, right: 0, top: 0, bottom: 0 })
      .clip(false)
    }
    .width('100%')
  }

  @Builder
  AttachmentPreviewRow() {
    Scroll() {
      Row({ space: 8 }) {
        ForEach(this.pendingAttachments, (attachment: AttachmentRef, index: number) => {
          Stack() {
            if (attachment.type === 'image') {
              // 图片预览
              Image('data:' + (attachment.mimeType || 'image/jpeg') + ';base64,' + attachment.data)
                .width(64).height(64).borderRadius(10).objectFit(ImageFit.Cover)
            } else {
              // 文件图标
              Column({ space: 4 }) {
                SymbolGlyph($r('sys.symbol.doc_text'))
                  .fontSize(22).fontColor([Theme.TextSecondary])
                Text(attachment.name || '文件')
                  .fontSize(8).fontColor(Theme.TextPrimary).maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis }).width(52).textAlign(TextAlign.Center)
              }
              .width(64).height(64).justifyContent(FlexAlign.Center)
              .backgroundColor('#2C2C2E').borderRadius(10)
            }

            // 删除按钮
            Column() {
              SymbolGlyph($r('sys.symbol.xmark')).fontSize(8).fontColor([Color.White])
            }
            .width(18).height(18)
            .backgroundColor('rgba(0,0,0,0.6)').borderRadius(9)
            .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
            .position({ x: 0, y: 0 }).margin({ left: -4, top: -4 })
            .onClick(() => {
              const newList = [...this.pendingAttachments]
              newList.splice(index, 1)
              this.pendingAttachments = newList
            })
          }
          .width(64).height(64)
        })
      }
      .width('100%').padding({ left: 4, right: 4 })
    }
    .height(76).scrollBar(BarState.Off).width('100%')
  }

  @Builder
  AttachmentActionSheet() {
    Column({ space: 0 }) {
      // 标题
      Text('发送图片')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(Theme.TextPrimary)
        .width('100%')
        .textAlign(TextAlign.Center)
        .padding({ top: Theme.SpacingLG, bottom: Theme.SpacingLG })

      // 从相册选择
      Row({ space: 12 }) {
        SymbolGlyph($r('sys.symbol.folder'))
          .fontSize(22)
          .fontColor([Theme.AccentBlue])

        Column({ space: 2 }) {
          Text('从相册选择')
            .fontSize(Theme.FontBody)
            .fontColor(Theme.TextPrimary)

          Text('选择手机中的图片发送给 AI')
            .fontSize(Theme.FontCaption)
            .fontColor(Theme.TextSecondary)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(14)
          .fontColor([Theme.TextTertiary])
      }
      .width('100%')
      .padding(Theme.SpacingMD)
      .backgroundColor(Theme.GlassBackground)
      .borderRadius(Theme.RadiusMedium)
      .border({ width: 0.5, color: Theme.GlassBorder })
      .onClick(() => {
        this.showAttachSheet = false
        this.pickPhotoFromGallery()
      })
    }
    .width('100%')
    .padding({ left: Theme.SpacingLG, right: Theme.SpacingLG })
  }

  // 菜单气泡 - 从按钮左下角扩散
  @Builder
  MenuBubble() {
    Stack() {
      // 菜单卡片 - 磨砂背景，靠左下角
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
        .backgroundColor(Theme.BackgroundTertiary)
        .borderRadius(12)
        .onClick(() => {
          this.showMenu = false
          this.showModelSheet = true
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
        .backgroundColor(Theme.BackgroundTertiary)
        .borderRadius(12)
        .onClick(() => {
          this.showMenu = false
          this.showSlashSheet = true
        })

        // 权限模式
        Row({ space: 12 }) {
          SymbolGlyph($r('sys.symbol.lock_shield'))
            .fontSize(20)
            .fontColor([Theme.AccentOrange])

          Column({ space: 2 }) {
            Text('权限模式')
              .fontSize(Theme.FontBody)
              .fontColor(Theme.TextPrimary)

            Text(getPermissionModeDisplayName(this.currentPermissionMode))
              .fontSize(Theme.FontTiny)
              .fontColor(Theme.TextTertiary)
              .maxLines(1)
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)

          SymbolGlyph($r('sys.symbol.chevron_right'))
            .fontSize(14)
            .fontColor([Theme.TextTertiary])
        }
        .width('100%')
        .padding(Theme.SpacingMD)
        .backgroundColor(Theme.BackgroundTertiary)
        .borderRadius(12)
        .onClick(() => {
          this.showMenu = false
          this.showPermSheet = true
        })

        // 发送图片
        Row({ space: 12 }) {
          SymbolGlyph($r('sys.symbol.folder'))
            .fontSize(20)
            .fontColor([Theme.AccentBlue])

          Text('发送图片')
            .fontSize(Theme.FontBody)
            .fontColor(Theme.TextPrimary)

          Blank()

          SymbolGlyph($r('sys.symbol.chevron_right'))
            .fontSize(14)
            .fontColor([Theme.TextTertiary])
        }
        .width('100%')
        .padding(Theme.SpacingMD)
        .backgroundColor(Theme.BackgroundTertiary)
        .borderRadius(12)
        .onClick(() => {
          this.showMenu = false
          this.showAttachSheet = true
        })
      }
      .width(220)
      .padding(Theme.SpacingSM)
      .backgroundColor(Theme.BackgroundSecondary)
      .borderRadius(16)
      .shadow({ radius: 20, color: 'rgba(0,0,0,0.3)', offsetY: 4 })
      .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
      // 扩散动画：从左下角缩放 + 渐显
      .transition(TransitionEffect.scale({ x: 0.3, y: 0.3 }).animation({ duration: 250, curve: Curve.FastOutSlowIn })
        .combine(TransitionEffect.OPACITY.animation({ duration: 250, curve: Curve.FastOutSlowIn })))
    }
    .width('100%')
    .height('100%')
    .backgroundColor('rgba(0,0,0,0.3)')
    .alignContent(Alignment.BottomStart)
    .padding({ left: Theme.SpacingLG, bottom: 85 })
    .transition(TransitionEffect.OPACITY.animation({ duration: 200 }))
    .onClick(() => {
      this.showMenu = false
    })
  }

  // 模型选择器 Sheet（底部弹出）
  @Builder
  ModelSelectorSheet() {
    Column({ space: 12 }) {
      // 标题栏
      Row() {
        Text('选择模型')
          .fontSize(Theme.FontHeading)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.TextPrimary)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
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
              .backgroundColor(this.currentModel === model.id ? Theme.PrimaryColorLight : Theme.BackgroundTertiary)
              .borderRadius(12)
              .onClick(() => {
                this.selectModel(model.id)
              })
            }
          }, (model: ModelInfo) => model.id)
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Auto)
      }
    }
    .width('100%')
    .padding(Theme.SpacingLG)
  }

  // 斜杠命令 Sheet — 与模型选择器完全一致的布局
  @Builder
  SlashCommandsSheet() {
    Column({ space: 12 }) {
      // 标题栏
      Row() {
        Text('斜杠命令')
          .fontSize(Theme.FontHeading)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.TextPrimary)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
      }
      .width('100%')
      .padding({ bottom: Theme.SpacingSM })

      List({ space: 8 }) {
        ForEach(this.slashCommands, (cmd: SlashCommand) => {
          ListItem() {
            Row({ space: 12 }) {
              Column({ space: 4 }) {
                Text(cmd.name)
                  .fontSize(Theme.FontBody)
                  .fontColor(Theme.TextPrimary)

                Text(cmd.description)
                  .fontSize(Theme.FontTiny)
                  .fontColor(Theme.TextTertiary)
                  .maxLines(2)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)
            }
            .width('100%')
            .padding(Theme.SpacingMD)
            .backgroundColor(Theme.BackgroundTertiary)
            .borderRadius(12)
            .onClick(() => {
              this.selectSlashCommand(cmd.name)
            })
          }
        }, (cmd: SlashCommand) => cmd.name)
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Auto)
    }
    .width('100%')
    .padding(Theme.SpacingLG)
  }

  // MARK: - 任务面板（与 iOS SessionTaskBarView 一致）

  @Builder
  TaskBarView() {
    if (sessionStore.getCurrentTasks() && sessionStore.getCurrentTasks().length > 0 && !sessionStore.taskBarDismissed) {
      Column({ space: 0 }) {
        Divider()
          .color('rgba(255,255,255,0.08)')
          .width('100%')

        Column({ space: 0 }) {
          // 标题栏
          Row({ space: 8 }) {
            Column() {
              SymbolGlyph($r('sys.symbol.checkmark_circle_fill'))
                .fontSize(13)
                .fontColor([Theme.AccentBlue])
            }
            .width(26)
            .height(26)
            .backgroundColor('rgba(10, 132, 255, 0.1)')
            .borderRadius(6)
            .justifyContent(FlexAlign.Center)

            Text('任务')
              .fontSize(13)
              .fontWeight(FontWeight.Bold)
              .fontColor(Theme.TextPrimary)

            // 进度条
            Row() {
              Row()
                .width(this.getTaskProgress(sessionStore.getCurrentTasks()) + '%')
                .height('100%')
                .backgroundColor(this.areAllTasksCompleted(sessionStore.getCurrentTasks()) ? Theme.SuccessColor : Theme.AccentBlue)
                .borderRadius(2)
            }
            .width(120)
            .height(4)
            .backgroundColor('rgba(255,255,255,0.1)')
            .borderRadius(2)

            Text(this.getCompletedTaskCount(sessionStore.getCurrentTasks()) + '/' + sessionStore.getCurrentTasks().length)
              .fontSize(11)
              .fontFamily('monospace')
              .fontColor(Theme.TextSecondary)

            Blank()

            SymbolGlyph($r('sys.symbol.chevron_down'))
              .fontSize(11)
              .fontColor([Theme.TextSecondary])
              .rotate({ angle: sessionStore.taskBarExpanded ? 0 : 180 })

            if (this.areAllTasksCompleted(sessionStore.getCurrentTasks())) {
              SymbolGlyph($r('sys.symbol.xmark'))
                .fontSize(10)
                .fontColor([Theme.TextSecondary])
                .onClick(() => {
                  sessionStore.dismissTaskBar()
                })
            }
          }
          .width('100%')
          .padding({ left: 12, right: 12, top: 8, bottom: 8 })
          .onClick(() => {
            sessionStore.toggleTaskBarExpanded()
          })

          // 展开任务列表
          if (sessionStore.taskBarExpanded) {
            Divider()
              .color('rgba(255,255,255,0.05)')
              .width('100%')

            Scroll() {
              Column({ space: 2 }) {
                ForEach(sessionStore.getCurrentTasks(), (task: TaskItem) => {
                  this.TaskItemRow(task)
                }, (task: TaskItem) => task.id)
              }
              .width('100%')
              .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            }
            .height(Math.min(sessionStore.getCurrentTasks().length * 50, 200))
            .scrollBar(BarState.Off)
          }
        }
        .width('100%')
        .backgroundColor('rgba(255,255,255,0.03)')
        .margin({ bottom: 8 })
      }
      .width('100%')
    }
  }

  @Builder
  TaskItemRow(task: TaskItem) {
    Row({ space: 8 }) {
      // 状态图标
      if (task.status === 'in_progress') {
        LoadingProgress()
          .width(12)
          .height(12)
          .color(Theme.AccentBlue)
      } else {
        SymbolGlyph(this.getTaskStatusIcon(task.status))
          .fontSize(12)
          .fontColor([this.getTaskStatusColor(task.status)])
      }

      // 内容
      Column({ space: 2 }) {
        Row({ space: 4 }) {
          Text(`#${task.id}`)
            .fontSize(10)
            .fontFamily('monospace')
            .fontColor(Theme.TextTertiary)
          Text(task.content)
            .fontSize(12)
            .fontColor(task.status === 'completed' ? Theme.TextSecondary : Theme.TextPrimary)
            .decoration(task.status === 'completed' ?
              { type: TextDecorationType.LineThrough, color: Theme.TextSecondary } :
              undefined)
        }

        if (task.status === 'in_progress' && task.activeForm) {
          Row({ space: 4 }) {
            Row()
              .width(5)
              .height(5)
              .backgroundColor(Theme.AccentOrange)
              .borderRadius(2.5)
            Text(task.activeForm)
              .fontSize(10)
              .fontColor(Theme.AccentOrange)
          }
        }

        if (task.owner) {
          Row({ space: 3 }) {
            SymbolGlyph($r('sys.symbol.person_fill'))
              .fontSize(8)
              .fontColor([Theme.TextTertiary])
            Text(task.owner)
              .fontSize(10)
              .fontColor(Theme.TextTertiary)
          }
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .padding({ top: 4, bottom: 4, left: 4, right: 4 })
    .backgroundColor(task.status === 'in_progress' ? 'rgba(10, 132, 255, 0.06)' : Color.Transparent)
    .borderRadius(4)
  }

  private getTaskProgress(tasks: TaskItem[]): number {
    const completed = tasks.filter(t => t.status === 'completed').length
    return tasks.length > 0 ? Math.round((completed / tasks.length) * 100) : 0
  }

  private getCompletedTaskCount(tasks: TaskItem[]): number {
    return tasks.filter(t => t.status === 'completed').length
  }

  private areAllTasksCompleted(tasks: TaskItem[]): boolean {
    return tasks.length > 0 && tasks.every(t => t.status === 'completed')
  }

  private getTaskStatusIcon(status: TaskStatus): Resource {
    switch (status) {
      case 'completed': return $r('sys.symbol.checkmark_circle_fill')
      case 'failed': return $r('sys.symbol.xmark_circle_fill')
      default: return $r('sys.symbol.clock')
    }
  }

  private getTaskStatusColor(status: TaskStatus): ResourceColor {
    switch (status) {
      case 'completed': return Theme.SuccessColor
      case 'failed': return Theme.ErrorColor
      default: return Theme.TextTertiary
    }
  }

  private startWorkTimer(): void {
    if (this.workTimer !== -1) return
    this.elapsedSeconds = 0
    this.workTimer = setInterval(() => {
      if (this.isDestroyed) return
      this.elapsedSeconds++
    }, 1000)
    // 启动吉祥物慢速脉冲动画
    this.mascotScale = 0.85
    animateTo({
      duration: 3000,
      curve: Curve.EaseInOut,
      iterations: -1,
      playMode: PlayMode.Alternate
    }, () => {
      this.mascotScale = 1.15
    })
  }

  // 等待用户操作时振动提醒
  private vibrateAlert(): void {
    try {
      vibrator.startVibration({
        type: 'time',
        duration: 300
      }, {
        id: 0,
        usage: 'alarm'
      })
    } catch (e) {
      // 振动失败忽略，不影响功能
    }
  }

  private stopWorkTimer(): void {
    if (this.workTimer !== -1) {
      clearInterval(this.workTimer)
      this.workTimer = -1
    }
    // 停止吉祥物脉冲动画，回到静止状态（组件未销毁时才执行动画）
    if (!this.isDestroyed) {
      animateTo({ duration: 300 }, () => {
        this.mascotScale = 0.85
      })
    }
  }

  private formatElapsed(seconds: number): string {
    if (seconds < 60) return `${seconds}s`
    const m = Math.floor(seconds / 60)
    const s = seconds % 60
    return `${m}m ${s}s`
  }

  private getStatusText(): string {
    switch (this.chatStatus) {
      case 'idle': return '空闲'
      case 'thinking': return '思考中...'
      case 'streaming': return '工作中...'
      case 'tool_executing': return '执行中...'
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

  private mapToWorkStatus(status: SessionStatus): WorkStatus {
    switch (status) {
      case 'thinking': return WorkStatus.THINKING
      case 'streaming': return WorkStatus.STREAMING
      case 'tool_executing': return WorkStatus.TOOL_EXECUTING
      case 'permission_pending': return WorkStatus.PERMISSION_PENDING
      case 'question_pending': return WorkStatus.QUESTION_PENDING
      case 'completed': return WorkStatus.COMPLETED
      default: return WorkStatus.IDLE
    }
  }

  // MARK: - 连接指示

  private getConnectionIcon(): Resource {
    const profile = authStore.activeProfile
    if (!profile) return $r('sys.symbol.questionmark_circle')
    switch (profile.type) {
      case 'lan': return $r('sys.symbol.gearshape')
      case 'pgy': return $r('sys.symbol.questionmark_circle')
      case 'tunnel': return $r('sys.symbol.square_and_pencil')
      default: return $r('sys.symbol.questionmark_circle')
    }
  }

  private getConnectionLabel(): string {
    const profile = authStore.activeProfile
    if (!profile) return '未连接'
    switch (profile.type) {
      case 'lan': return `${profile.name} · 局域网`
      case 'pgy': return `${profile.name} · 蒲公英`
      case 'tunnel': return `${profile.name} · 隧道`
      default: return profile.name
    }
  }

  private getConnectionColor(): ResourceColor {
    const profile = authStore.activeProfile
    if (!profile) return Theme.ErrorColor
    switch (profile.type) {
      case 'lan': return Theme.AccentGreen
      case 'pgy': return Theme.AccentBlue
      case 'tunnel': return Theme.AccentOrange
      default: return Theme.TextSecondary
    }
  }

  private sendMessage(): void {
    const hasAttachments = this.pendingAttachments.length > 0
    if (!this.inputText.trim() && !hasAttachments) return

    const content = this.inputText.trim() || (hasAttachments ? ' ' : '')
    const attachments = hasAttachments ? [...this.pendingAttachments] : undefined
    this.pendingAttachments = []
    this.inputText = ''
    sessionStore.inputDrafts.delete(this.sessionId)

    // 去重：记录最近发送的消息
    if (content.trim()) {
      this.recentlySentMessages.add(content)
      if (this.recentlySentMessages.size > 100) {
        // 清除旧条目：转数组去前50个再转回Set
        const arr = Array.from(this.recentlySentMessages)
        this.recentlySentMessages = new Set(arr.slice(-50))
      }
    }
    this.userIsViewingHistory = false

    sessionStore.sendMessage(content, attachments)

    // 重置流式缓冲区
    this.streamingText = ''
    this.streamingThinking = ''
    this.inTextBlock = false
    this.inThinkingBlock = false
    this.latestThinkingId = ''

    // 状态由 SessionStore 更新，启动计时器
    this.startWorkTimer()

    this.scrollToBottom()
  }

  // MARK: - 附件处理

  /**
   * 从相册选择图片
   */
  private async pickPhotoFromGallery(): Promise<void> {
    try {
      const picker = new photoViewPicker.PhotoViewPicker()
      const result = await picker.select()
      const uris = result['photoUris'] || result['uri']
      if (!uris) {
        console.error('[ChatDetailPage] No photo selected')
        return
      }
      if (uris.length > 0) {
        await this.loadAttachmentFromUri(uris[0])
      }
    } catch (e) {
      console.error(`[ChatDetailPage] Pick photo error: ${e}`)
    }
  }

  /**
   * 从 URI 读取图片文件并转为 base64 附件
   */
  private async loadAttachmentFromUri(uri: string): Promise<void> {
    try {
      const file = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY)
      const stat = fileIo.statSync(file.fd)

      // 限制 10MB
      if (stat.size > 10 * 1024 * 1024) {
        console.error('[ChatDetailPage] File too large, max 10MB')
        fileIo.closeSync(file)
        return
      }

      const buf = new ArrayBuffer(stat.size)
      fileIo.readSync(file.fd, buf)
      fileIo.closeSync(file)

      const base64 = this.bufferToBase64(buf)

      const name = uri.split('/').pop() || 'photo.jpg'
      const mimeType = this.guessMimeType(name)

      this.pendingAttachments = [...this.pendingAttachments, {
        type: 'image',
        name: name,
        data: base64,
        mimeType: mimeType
      }]
    } catch (e) {
      console.error(`[ChatDetailPage] Load attachment error: ${e}`)
    }
  }

  /**
   * ArrayBuffer 转 base64
   */
  private bufferToBase64(buf: ArrayBuffer): string {
    const uint8Arr = new Uint8Array(buf)
    let binary = ''
    for (let i = 0; i < uint8Arr.length; i++) {
      binary += String.fromCharCode(uint8Arr[i])
    }
    // ArkTS 不支持 btoa，用 Uint8Array 转 base64 的替代方案
    const helper = new util.Base64Helper()
    return helper.encodeToStringSync(uint8Arr)
  }

  /**
   * 根据文件名猜测 MIME 类型
   */

  private getRingColor(): string {
    if (this.contextUsage >= 90) return '#FF3B30'
    if (this.contextUsage >= 75) return '#FF9500'
    return '#0A84FF'
  }

  private guessMimeType(fileName: string): string {
    const ext = fileName.toLowerCase().split('.').pop() || ''
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg'
      case 'png':
        return 'image/png'
      case 'gif':
        return 'image/gif'
      case 'webp':
        return 'image/webp'
      case 'heic':
      case 'heif':
        return 'image/heic'
      case 'bmp':
        return 'image/bmp'
      default:
        return 'image/jpeg'
    }
  }
}
