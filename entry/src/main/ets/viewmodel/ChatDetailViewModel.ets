/**
 * ChatDetailViewModel - 对话详情页业务逻辑
 * 从 ChatDetailPage 提取的状态管理和业务方法
 */

import { Session, SessionStatus, Message, ModelInfo, WSMessage, TaskItem, AttachmentRef, PermissionMode } from '../models/Models'
import { sessionStore } from '../stores/SessionStore'
import { authStore } from '../stores/AuthStore'
import { appState } from '../stores/AppState'
import { apiService } from '../services/APIService'
import { toastManager } from '../services/ToastManager'
import { translateService } from '../services/TranslateService'
import { speechRecognizer } from '@kit.CoreSpeechKit'
import { audio } from '@kit.AudioKit'
import { BusinessError } from '@kit.BasicServicesKit'

// 斜杠命令定义
export class SlashCommand {
  name: string = ''
  description: string = ''
  example: string = ''
}

// 工具图标信息
export class ToolIconInfo {
  symbol: Resource = $r('sys.symbol.gearshape')
  label: string = ''
  color: string = ''

  constructor(symbol: Resource, label: string, color: string) {
    this.symbol = symbol
    this.label = label
    this.color = color
  }
}

// 状态变更回调类型
export type StatusChangeListener = (sessionId: string, status: SessionStatus) => void
export type MessagesChangeListener = (sessionId: string) => void
export type RawMessageListener = (sessionId: string, msg: WSMessage) => void

// 翻译结果类型
export interface TranslateResult {
  success: boolean
  text?: string
  error?: string
}

export class ChatDetailViewModel {
  // 会话信息
  sessionId: string = ''
  conversationTitle: string = '对话'

  // 消息状态
  messages: Message[] = []
  displayedMessageCount: number = 50
  isLoadingMore: boolean = false
  isMessagesLoaded: boolean = false
  latestMessageId: string = ''

  // 会话状态
  chatStatus: SessionStatus = 'idle'
  currentPermissionMode: PermissionMode = PermissionMode.DEFAULT
  currentModel: string = ''
  models: ModelInfo[] = []
  isLoadingModels: boolean = false

  // 输入状态
  inputText: string = ''
  pendingAttachments: AttachmentRef[] = []

  // 流式状态
  streamingThinking: string = ''
  inThinkingBlock: boolean = false

  // Token 使用量
  tokenUsage: number = 0
  contextUsage: number = 0
  contextModel: string = ''
  contextTotal: number = 0
  contextMax: number = 0

  // 工作计时
  elapsedSeconds: number = 0
  private workTimer: number = -1

  // 任务列表
  taskItems: TaskItem[] = []

  // 折叠状态
  expandedThinkingIds: Set<string> = new Set()
  expandedToolIds: Set<string> = new Set()
  toolGroupExpanded: boolean = true

  // 活动状态
  isPageActive: boolean = true
  isDestroyed: boolean = false

  // 语音识别
  asrEngine: speechRecognizer.SpeechRecognitionEngine | null = null
  asrEngineInitializing: boolean = false
  voiceSessionId: string = ''
  audioCapturer: audio.AudioCapturer | null = null
  audioFeedTimer: number = -1

  // 翻译
  isTranslating: boolean = false
  translateResultText: string = ''
  translateError: string = ''

  // 监听器
  private statusListener: StatusChangeListener | null = null
  private messagesListener: MessagesChangeListener | null = null
  private rawMessageListener: RawMessageListener | null = null
  private sessionsListener: (() => void) | null = null

  // 音效标记
  private hasPlayedConnectSound: boolean = false
  private hasPlayedCompleteSound: boolean = false

  // 斜杠命令列表
  slashCommands: SlashCommand[] = [
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

  // MARK: - 生命周期

  async initialize(sessionId: string, title: string): Promise<void> {
    this.sessionId = sessionId
    this.conversationTitle = title
    sessionStore.setCurrentSession(sessionId)

    // 加载消息
    await this.loadMessages()

    // 同步状态
    this.chatStatus = sessionStore.getSessionStatus(sessionId)
    this.currentPermissionMode = sessionStore.getCurrentPermissionMode()
    this.taskItems = sessionStore.getCurrentTasks()

    // 设置监听器
    this.setupListeners()

    // 初始化语音引擎
    this.initSpeechEngine()
  }

  destroy(): void {
    this.isPageActive = false
    this.isDestroyed = true
    this.stopWorkTimer()
    this.removeListeners()

    // 保存输入草稿
    if (this.inputText) {
      sessionStore.inputDrafts.set(this.sessionId, this.inputText)
    }

    // 清理语音识别
    if (this.asrEngine) {
      try { this.asrEngine.shutdown() } catch (e) {}
      this.asrEngine = null
    }

    // 清理音频采集
    if (this.audioFeedTimer !== -1) {
      clearInterval(this.audioFeedTimer)
      this.audioFeedTimer = -1
    }
    if (this.audioCapturer) {
      try { this.audioCapturer.stop() } catch (e) {}
      try { this.audioCapturer.release() } catch (e) {}
      this.audioCapturer = null
    }

    sessionStore.setCurrentSession(null)
  }

  private setupListeners(): void {
    this.statusListener = (sid: string, status: SessionStatus) => {
      if (sid === this.sessionId) {
        this.chatStatus = status
        this.currentPermissionMode = sessionStore.getCurrentPermissionMode()
        if (status === 'completed') {
          this.stopWorkTimer()
        } else if (status === 'thinking' || status === 'streaming' || status === 'tool_executing') {
          this.startWorkTimer()
        }
      }
    }

    this.messagesListener = (sid: string) => {
      if (sid === this.sessionId) {
        this.refreshMessages()
      }
    }

    this.rawMessageListener = (sid: string, msg: WSMessage) => {
      if (sid === this.sessionId) {
        this.handleStreamingMessage(msg)
      }
    }

    this.sessionsListener = () => {
      this.taskItems = sessionStore.getCurrentTasks()
      this.currentPermissionMode = sessionStore.getCurrentPermissionMode()
    }

    sessionStore.addStatusChangedListener(this.statusListener)
    sessionStore.addMessagesChangedListener(this.messagesListener)
    sessionStore.addRawMessageListener(this.rawMessageListener)
    sessionStore.addSessionsChangedListener(this.sessionsListener)
  }

  private removeListeners(): void {
    if (this.statusListener) sessionStore.removeStatusChangedListener(this.statusListener)
    if (this.messagesListener) sessionStore.removeMessagesChangedListener(this.messagesListener)
    if (this.rawMessageListener) sessionStore.removeRawMessageListener(this.rawMessageListener)
    if (this.sessionsListener) sessionStore.removeSessionsChangedListener(this.sessionsListener)
  }

  // MARK: - 消息加载

  private async loadMessages(): Promise<void> {
    await sessionStore.loadMessages(this.sessionId)
    const msgs = sessionStore.getDedupedMessages(this.sessionId)
    if (msgs && msgs.length > 0) {
      this.messages = msgs
      this.displayedMessageCount = Math.min(100, this.messages.length)
      this.latestMessageId = msgs[msgs.length - 1].id
    }
    this.isMessagesLoaded = true
  }

  private refreshMessages(): void {
    const msgs = sessionStore.getDedupedMessages(this.sessionId)
    if (msgs && msgs.length > 0) {
      this.messages = [...msgs]
      this.displayedMessageCount = Math.max(this.displayedMessageCount, msgs.length)
      this.latestMessageId = msgs[msgs.length - 1].id
    }
    this.taskItems = sessionStore.getCurrentTasks()
  }

  // MARK: - 消息发送

  sendMessage(): boolean {
    const text = this.inputText.trim()
    if (!text && this.pendingAttachments.length === 0) return false

    const sent = sessionStore.sendMessage(text, this.pendingAttachments)
    if (sent) {
      this.inputText = ''
      this.pendingAttachments = []
      this.hasPlayedConnectSound = false
      this.hasPlayedCompleteSound = false
    }
    return sent
  }

  // MARK: - 流式消息处理

  private handleStreamingMessage(msg: WSMessage): void {
    switch (msg.type) {
      case 'thinking':
        if (!this.inThinkingBlock) {
          this.inThinkingBlock = true
          this.streamingThinking = ''
        }
        if (msg.text) {
          this.streamingThinking += msg.text
        }
        break

      case 'tool_use_complete':
      case 'message_complete':
        this.streamingThinking = ''
        this.inThinkingBlock = false
        this.stopWorkTimer()
        if (msg.used) {
          this.tokenUsage = msg.used
        }
        break

      case 'token_usage':
        if (msg.percentage) {
          this.contextUsage = msg.percentage
        }
        break
    }
  }

  // MARK: - 工作计时

  private startWorkTimer(): void {
    if (this.workTimer !== -1) return
    this.elapsedSeconds = 0
    this.workTimer = setInterval(() => {
      if (this.isDestroyed) return
      this.elapsedSeconds++
    }, 1000)
  }

  private stopWorkTimer(): void {
    if (this.workTimer !== -1) {
      clearInterval(this.workTimer)
      this.workTimer = -1
    }
  }

  // MARK: - 模型管理

  async loadModels(): Promise<void> {
    if (this.models.length > 0) return
    this.isLoadingModels = true
    try {
      const providerId = this.getSessionProviderId()
      const response = await apiService.getModels(providerId || undefined)
      this.models = response.models || []
      if (this.isCodexProvider(providerId)) {
        this.currentModel = this.resolveLocalProviderModel(providerId, this.models)
      } else {
        const current = await apiService.getCurrentModel()
        this.currentModel = current.id
      }
    } catch (e) {
      console.error(`[ChatDetailViewModel] Load models error: ${e}`)
    }
    this.isLoadingModels = false
  }

  async selectModel(modelId: string): Promise<void> {
    try {
      const providerId = this.getSessionProviderId()
      if (this.isCodexProvider(providerId)) {
        appState.setSelectedModelForProvider(providerId, modelId)
        this.currentModel = modelId
        return
      }
      await apiService.setCurrentModel(modelId)
      this.currentModel = modelId
    } catch (e) {
      console.error(`[ChatDetailViewModel] Set model error: ${e}`)
    }
  }

  // MARK: - 权限管理

  hasPendingPermission(): boolean {
    const allMessages = sessionStore.messages.get(this.sessionId) || []
    for (let i = allMessages.length - 1; i >= 0; i--) {
      const message = allMessages[i]
      if (message.type === 'permission_request' && !message.isPermissionHandled) return true
    }
    return false
  }

  handlePermission(message: Message, allow: boolean, always?: boolean): void {
    if (message.permissionId) {
      sessionStore.sendPermissionResponse(message.permissionId, allow, always)
      message.isPermissionHandled = true
      message.permissionResult = allow
    }
  }

  // MARK: - 语音输入

  initSpeechEngine(): void {
    if (this.asrEngineInitializing || this.asrEngine) return
    this.asrEngineInitializing = true

    const extraParam: Record<string, Object> = { "locate": "CN", "recognizerMode": "short" }
    const initParamsInfo: speechRecognizer.CreateEngineParams = {
      language: 'zh-CN',
      online: 0,
      extraParams: extraParam
    }

    try {
      speechRecognizer.createEngine(initParamsInfo, (err: BusinessError, engine: speechRecognizer.SpeechRecognitionEngine) => {
        this.asrEngineInitializing = false
        if (!err && engine) {
          this.asrEngine = engine
          engine.setListener({
            onResult: (sessionId: string, result: speechRecognizer.SpeechRecognitionResult) => {
              if (result.result) {
                this.inputText = result.result
              }
            },
            onError: (sessionId: string, errorCode: number, errorMessage: string) => {
              console.error('[Voice] 识别错误: ' + errorMessage)
            },
            onStart: (sessionId: string) => {},
            onComplete: (sessionId: string) => {},
            onEvent: (sessionId: string, eventCode: number, eventMessage: string) => {}
          })
        }
      })
    } catch (error) {
      this.asrEngineInitializing = false
      console.error('[Voice] 创建引擎异常: ' + JSON.stringify(error))
    }
  }

  // MARK: - 翻译

  async translateContent(content: string): Promise<TranslateResult> {
    if (this.isTranslating) {
      const result: TranslateResult = { success: false, error: '正在翻译中' }
      return result
    }

    this.isTranslating = true
    this.translateError = ''
    this.translateResultText = ''

    try {
      const result = await translateService.translate(content)
      this.isTranslating = false
      if (result.success && result.text) {
        this.translateResultText = result.text
        const successResult: TranslateResult = { success: true, text: result.text }
        return successResult
      } else {
        this.translateError = result.error || '翻译失败'
        const failResult: TranslateResult = { success: false, error: this.translateError }
        return failResult
      }
    } catch (e) {
      this.isTranslating = false
      this.translateError = '翻译出错'
      const errorResult: TranslateResult = { success: false, error: this.translateError }
      return errorResult
    }
  }

  // MARK: - 辅助方法

  getSessionProviderId(): string {
    const session = sessionStore.sessions.find((s: Session) => s.id === this.sessionId)
    return session?.aiTool || ''
  }

  private isCodexProvider(providerId: string): boolean {
    return providerId.toLowerCase().indexOf('codex') >= 0
  }

  private resolveLocalProviderModel(providerId: string, models: ModelInfo[]): string {
    const saved = appState.getSelectedModelForProvider(providerId)
    for (let i = 0; i < models.length; i++) {
      if (models[i].id === saved) return saved
    }
    const modelId = models[0]?.id || ''
    if (modelId) appState.setSelectedModelForProvider(providerId, modelId)
    return modelId
  }

  getVisibleMessages(): Message[] {
    let allMessages = sessionStore.getDedupedMessages(this.sessionId)
    if (allMessages.length <= this.displayedMessageCount) {
      return allMessages
    }
    return allMessages.slice(allMessages.length - this.displayedMessageCount)
  }

  hasMoreMessages(): boolean {
    return this.messages.length > this.displayedMessageCount
  }

  loadMoreMessages(): void {
    if (this.isLoadingMore) return
    this.isLoadingMore = true
    setTimeout(() => {
      const increment = 100
      this.displayedMessageCount = Math.min(this.displayedMessageCount + increment, this.messages.length)
      this.isLoadingMore = false
    }, 100)
  }

  toggleThinking(id: string): void {
    const newSet = new Set(this.expandedThinkingIds)
    if (newSet.has(id)) {
      newSet.delete(id)
    } else {
      newSet.add(id)
    }
    this.expandedThinkingIds = newSet
  }

  toggleTool(id: string): void {
    const newSet = new Set(this.expandedToolIds)
    if (newSet.has(id)) {
      newSet.delete(id)
    } else {
      newSet.add(id)
    }
    this.expandedToolIds = newSet
  }
}

// 工具图标映射
export function getToolIcon(toolName: string): ToolIconInfo {
  switch (toolName) {
    case 'Bash':
      return new ToolIconInfo($r('sys.symbol.gearshape'), 'Terminal', '#30D158')
    case 'Read':
      return new ToolIconInfo($r('sys.symbol.doc_text'), 'Read file', '#0A84FF')
    case 'Write':
      return new ToolIconInfo($r('sys.symbol.square_and_pencil'), 'Write file', '#FF9F0A')
    case 'Edit':
      return new ToolIconInfo($r('sys.symbol.square_and_pencil'), 'Edit file', '#FF9F0A')
    case 'Glob':
      return new ToolIconInfo($r('sys.symbol.magnifyingglass'), 'Search files', '#BF5AF2')
    case 'Grep':
      return new ToolIconInfo($r('sys.symbol.magnifyingglass'), 'Search content', '#BF5AF2')
    case 'Agent':
      return new ToolIconInfo($r('sys.symbol.person_fill'), 'Agent', '#0A84FF')
    case 'WebSearch':
      return new ToolIconInfo($r('sys.symbol.magnifyingglass'), 'Web search', '#0A84FF')
    case 'WebFetch':
      return new ToolIconInfo($r('sys.symbol.doc_text'), 'Web fetch', '#0A84FF')
    case 'Skill':
      return new ToolIconInfo($r('sys.symbol.star_fill'), 'Skill', '#FF9F0A')
    default:
      return new ToolIconInfo($r('sys.symbol.gearshape'), toolName, '#8E8E93')
  }
}
