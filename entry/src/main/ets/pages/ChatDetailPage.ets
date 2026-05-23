/**
 * 对话详情页 - 实时消息收发
 * 与 iOS 端完全一致的聊天体验
 */

import { Theme } from '../common/Theme'
import { Message, Session, SessionStatus, ModelInfo, WSMessage, TaskItem, TaskStatus, AttachmentRef, QuestionOption, QuestionItem, PermissionMode, PendingPermission, getPermissionModeDisplayName, getPermissionModeDescription, MessageImage } from '../models/Models'
import { HdsNavigation, ScrollEffectType, HdsNavigationBadgeIconOptions, HdsNavigationTitleMode } from '@hms.hds.hdsBaseComponent'
import { hdsMaterial, HdsTabs, hdsEffect } from '@kit.UIDesignKit'
import { curves, RectShape } from '@kit.ArkUI'
import { speechRecognizer } from '@kit.CoreSpeechKit'
import { audio } from '@kit.AudioKit'
import { abilityAccessCtrl, common } from '@kit.AbilityKit'
import { BusinessError } from '@kit.BasicServicesKit'
import { sessionStore } from '../stores/SessionStore'
import { authStore } from '../stores/AuthStore'
import { apiService } from '../services/APIService'
import { MarkdownRenderer } from '../components/MarkdownRenderer'
import { FileAttachmentBubble } from '../components/FileAttachmentBubble'
import { ImagePreviewDialog } from '../components/ImagePreviewDialog'
import { toastManager } from '../services/ToastManager'
import { notificationHelper } from '../services/NotificationHelper'
import { fileService, FileInfo } from '../services/FileService'
import { downloadService } from '../services/DownloadService'
import { PixelMascot, MascotStatus, getMascotColorForSession, getMascotTypeForProvider } from '../components/PixelMascot'

import { StatusIcon, WorkStatus } from '../components/StatusIcon'
import { DotMatrixBackground } from '../components/DotMatrixBackground'
import { HdsMiniBarButton } from '../components/HdsMiniBarButton'
import { HdsGlassInput } from '../components/HdsGlassInput'
import { translateService } from '../services/TranslateService'
import { KeyboardAvoidMode } from '@kit.ArkUI'
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
  @State showTaskBarExpanded: boolean = false

  @State showSheet: boolean = false
  @State sheetType: string = ''
  @State models: ModelInfo[] = []
  @State currentModel: string = ''
  @State isLoadingModels: boolean = false
  @State expandedThinkingIds: Set<string> = new Set()
  @State expandedToolIds: Set<string> = new Set()
  @State currentPermissionMode: PermissionMode = PermissionMode.DEFAULT
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
  @State streamingThinking: string = ''
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

  // 工具组折叠状态
  @State toolGroupExpanded: boolean = true

  // 强制重绘计数器（ArkTS @State 不追踪嵌套对象属性变更）
  @State messageUpdateCounter: number = 0

  // 任务列表本地 @State 副本（@Builder 读取全局 Store 不被 ArkTS 追踪）
  @State taskItems: TaskItem[] = []

  // 最新消息 ID（用于条件过渡动画，只有最新消息才用弹簧效果）
  @State latestMessageId: string = ''

  // "最新消息"浮动按钮
  @State showNewMessageButton: boolean = false

  // 沉浸光感追光效果状态
  @State lightIntensity: number = 0
  @State lightFingerX: number = 0
  @State lightFingerY: number = 0
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

  // 音效：标记本轮 AI 回复是否已播放"已连接"和"已完成"音效，发送新消息时重置
  private hasPlayedConnectSound: boolean = false
  private hasPlayedCompleteSound: boolean = false

  // 分页加载
  @State displayedMessageCount: number = 50
  @State isLoadingMore: boolean = false
  @State isMessagesLoaded: boolean = false
  @State isListReady: boolean = false

  // 标题栏动态模糊（滚动时背景渐变透明）
  @State scrollOffset: number = 0
  private readonly blurThreshold: number = 30

  // 语音输入
  @State isVoiceMode: boolean = false
  @State isRecording: boolean = false
  @State voiceText: string = ''
  private audioCapturer: audio.AudioCapturer | null = null
  private audioFeedTimer: number = -1

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
    // 同步任务列表本地 @State 副本
    this.taskItems = sessionStore.getCurrentTasks()
    // 恢复输入框草稿
    // 确保弹窗不会在进入页面时意外弹出
    this.showModelSheet = false
    this.showSlashSheet = false
    this.showPermSheet = false
    this.showAttachSheet = false

    // 初始化语音识别引擎
    this.initSpeechEngine()

    // 键盘避让
    try {
      this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE)
    } catch (e) {}

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
    // 清理流式缓冲，防止页面重新进入时残留 Head 被刷入 Tail 导致重复
    sessionStore.streamHeads.delete(this.sessionId)
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
    // 停止音频采集
    if (this.audioFeedTimer !== -1) {
      clearInterval(this.audioFeedTimer)
      this.audioFeedTimer = -1
    }
    if (this.audioCapturer) {
      try { this.audioCapturer.stop() } catch (e) {}
      try { this.audioCapturer.release() } catch (e) {}
      this.audioCapturer = null
    }
    // 释放语音识别引擎
    if (this.asrEngine) {
      try {
        this.asrEngine.shutdown()
      } catch (e) {}
      this.asrEngine = null
    }
    this.removeCallbacks()
    sessionStore.setCurrentSession(null)
  }

  onPageShow(): void {
    this.isPageActive = true
    this.getRouterParams()
    // 回到页面时重新同步工作状态和权限模式
    if (this.sessionId) {
      this.chatStatus = sessionStore.getSessionStatus(this.sessionId)
      this.currentPermissionMode = sessionStore.getCurrentPermissionMode()
      // 取消该会话的旧通知（后台时可能收到了通知）
      notificationHelper.cancelNotification(this.sessionId)
      // 消息同步由 onForeground → messagesChangedListener 处理，此处不做避免重复
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

  // MARK: - 语音输入
  private asrEngine: speechRecognizer.SpeechRecognitionEngine | null = null
  private asrEngineInitializing: boolean = false  // 防止重复初始化
  private voiceSessionId: string = ''

  private initSpeechEngine(): void {
    // 防止重复初始化
    if (this.asrEngineInitializing || this.asrEngine) {
      console.info('[Voice] 引擎已存在或正在初始化，跳过')
      return
    }
    this.asrEngineInitializing = true

    let extraParam: Record<string, Object> = { "locate": "CN", "recognizerMode": "short" }
    let initParamsInfo: speechRecognizer.CreateEngineParams = {
      language: 'zh-CN',
      online: 0, // 0=云端识别, 1=离线
      extraParams: extraParam
    }
    try {
      speechRecognizer.createEngine(initParamsInfo, (err: BusinessError, engine: speechRecognizer.SpeechRecognitionEngine) => {
        this.asrEngineInitializing = false  // 初始化完成
        if (!err && engine) {
          this.asrEngine = engine
          // 设置识别结果监听器
          engine.setListener({
            onResult: (sessionId: string, result: speechRecognizer.SpeechRecognitionResult) => {
              console.info('[Voice] onResult sessionId=' + sessionId + ' result="' + result.result + '" isFinal=' + result.isFinal + ' isLast=' + result.isLast)
              // 无论 isFinal 还是中间结果，只要有文本就显示到输入框
              if (result.result) {
                this.voiceText = result.result
                this.inputText = result.result
              }
            },
            onError: (sessionId: string, errorCode: number, errorMessage: string) => {
              console.error('[Voice] 识别错误: ' + errorMessage + ' (code=' + errorCode + ')')
              this.isRecording = false
            },
            onStart: (sessionId: string) => {
              console.info('[Voice] 识别开始: ' + sessionId)
            },
            onComplete: (sessionId: string) => {
              console.info('[Voice] 识别完成: ' + sessionId + ' voiceText="' + this.voiceText + '"')
              // onComplete 时如果 voiceText 有内容，确保填入输入框
              if (this.voiceText) {
                this.inputText = this.voiceText
              }
              this.isRecording = false
            },
            onEvent: (sessionId: string, eventCode: number, eventMessage: string) => {
              console.info('[Voice] 识别事件: ' + eventCode + ' - ' + eventMessage)
            }
          })
          console.info('[Voice] 语音识别引擎初始化成功')
        } else {
          console.error('[Voice] 引擎初始化失败: ' + JSON.stringify(err))
        }
      })
    } catch (error) {
      this.asrEngineInitializing = false
      console.error('[Voice] 创建引擎异常: ' + JSON.stringify(error))
    }
  }

  private requestMicrophonePermission(): void {
    try {
      const atManager = abilityAccessCtrl.createAtManager()
      const ctx = getContext(this) as common.UIAbilityContext
      atManager.requestPermissionsFromUser(ctx, ['ohos.permission.MICROPHONE'])
        .then(() => {
          console.info('[Voice] 麦克风权限已获取')
        })
        .catch((err: BusinessError) => {
          console.error('[Voice] 麦克风权限被拒绝: ' + err.message)
        })
    } catch (error) {
      console.error('[Voice] 请求权限异常: ' + JSON.stringify(error))
    }
  }

  private startVoiceRecording(): void {
    // 1. 请求麦克风权限（异步弹窗，不阻塞）
    this.requestMicrophonePermission()

    // 2. 检查引擎状态
    if (this.asrEngineInitializing) {
      // 正在初始化，提示用户稍等
      toastManager.info('语音引擎初始化中，请稍后重试')
      console.warn('[Voice] 引擎正在初始化，请稍等')
      return
    }

    if (!this.asrEngine) {
      // 引擎未初始化，触发初始化并提示
      this.initSpeechEngine()
      toastManager.info('语音引擎初始化中，请稍后重试')
      console.warn('[Voice] 语音引擎尚未就绪，请稍后再试')
      return
    }

    // 3. 启动语音识别引擎
    this.isRecording = true
    this.voiceText = ''
    this.voiceSessionId = 'voice-session-' + Date.now()
    console.info('[Voice] 开始录音, sessionId=' + this.voiceSessionId)

    try {
      let audioInfo: speechRecognizer.AudioInfo = {
        audioType: 'pcm',
        sampleRate: 16000,
        soundChannel: 1,
        sampleBit: 16
      }
      let extraParams: Record<string, Object> = { "locate": "CN", "recognizerMode": "short" }
      let startParams: speechRecognizer.StartParams = {
        sessionId: this.voiceSessionId,
        audioInfo: audioInfo,
        extraParams: extraParams
      }
      // 必须先 startListening，然后才能 writeAudio
      this.asrEngine.startListening(startParams)

      // 4. 创建 AudioCapturer 采集麦克风音频
      let capturerOptions: audio.AudioCapturerOptions = {
        streamInfo: {
          samplingRate: audio.AudioSamplingRate.SAMPLE_RATE_16000,
          channels: audio.AudioChannel.CHANNEL_1,
          sampleFormat: audio.AudioSampleFormat.SAMPLE_FORMAT_S16LE,
          encodingType: audio.AudioEncodingType.ENCODING_TYPE_RAW
        },
        capturerInfo: {
          source: audio.SourceType.SOURCE_TYPE_MIC,
          capturerFlags: 0
        }
      }

      audio.createAudioCapturer(capturerOptions).then((capturer: audio.AudioCapturer) => {
        this.audioCapturer = capturer
        return capturer.start()
      }).then(() => {
        console.info('[Voice] AudioCapturer 已启动')
        // 5. 开始循环喂音频数据给识别引擎
        this.startAudioFeeder()
      }).catch((err: BusinessError) => {
        console.error('[Voice] 麦克风采集启动失败: ' + JSON.stringify(err))
        this.isRecording = false
        toastManager.error('麦克风启动失败: ' + err.message)
      })
    } catch (error) {
      console.error('[Voice] 启动语音识别失败: ' + JSON.stringify(error))
      this.isRecording = false
      toastManager.error('语音识别启动失败: ' + (error as BusinessError).message)
    }
  }

  private startAudioFeeder(): void {
    // 每 40ms 读取 1280 字节音频（16kHz 16bit 单声道 40ms 的数据量）
    const CHUNK_SIZE = 1280
    this.audioFeedTimer = setInterval(() => {
      if (!this.isRecording || !this.asrEngine || !this.audioCapturer) {
        clearInterval(this.audioFeedTimer)
        this.audioFeedTimer = -1
        return
      }
      this.audioCapturer.read(CHUNK_SIZE, false).then((buffer: ArrayBuffer) => {
        if (buffer && buffer.byteLength > 0 && this.asrEngine) {
          let audioData = new Uint8Array(buffer)
          this.asrEngine.writeAudio(this.voiceSessionId, audioData)
        }
      }).catch(() => {
        // 读取失败不中断，继续下一轮
      })
    }, 40)
  }

  private stopVoiceRecording(): void {
    console.info('[Voice] 停止录音')

    // 1. 停止音频采集
    if (this.audioFeedTimer !== -1) {
      clearInterval(this.audioFeedTimer)
      this.audioFeedTimer = -1
    }
    if (this.audioCapturer) {
      try {
        this.audioCapturer.stop()
        this.audioCapturer.release()
      } catch (e) {
        console.error('[Voice] 释放录音器失败: ' + JSON.stringify(e))
      }
      this.audioCapturer = null
    }

    // 2. 结束语音识别获取最终结果
    if (this.asrEngine && this.voiceSessionId) {
      try {
        // finish 会触发 onComplete 回调（isRecording 在 onComplete 里置 false）
        this.asrEngine.finish(this.voiceSessionId)
      } catch (error) {
        console.error('[Voice] 停止识别失败: ' + JSON.stringify(error))
        this.isRecording = false
      }
    } else {
      this.isRecording = false
    }
  }

  private async loadMessages(): Promise<void> {
    await sessionStore.loadMessages(this.sessionId)
    // 使用 getDedupedMessages 确保加载时就是去重的（防御性）
    const msgs = sessionStore.getDedupedMessages(this.sessionId)
    if (msgs && msgs.length > 0) {
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
      const oldCount = this.messages.length
      // 使用 getDedupedMessages 获取去重后的消息，防止 Store 中的重复消息传递到 UI
      const msgs = sessionStore.getDedupedMessages(this.sessionId)
      if (msgs && msgs.length > 0) {
        // 检查消息是否真的变化了（避免重复触发导致 UI 闪烁）
        if (msgs.length === oldCount && this.messages.length > 0) {
          // 数量相同，检查最后一条消息是否相同
          const lastOld = this.messages[this.messages.length - 1]
          const lastNew = msgs[msgs.length - 1]
          if (lastOld.id === lastNew.id && lastOld.content === lastNew.content) {
            // 消息没有实质变化，跳过更新
            return
          }
        }
        // 展开为新数组，确保 ArkTS @State 能检测到引用变化并触发重绘
        this.messages = [...msgs]
        // 自动更新分页数，确保新消息不被分页截断
        this.displayedMessageCount = Math.max(this.displayedMessageCount, msgs.length)
        // 更新最新消息 ID（用于条件过渡动画）
        if (msgs.length > 0) {
          this.latestMessageId = msgs[msgs.length - 1].id
        }
        // 兜底检测：消息已包含 assistant 回复但状态仍卡在工作状态
        if (msgs.length > 0) {
          const lastMsg = msgs[msgs.length - 1]
          if (lastMsg.type === 'assistant' && lastMsg.content && lastMsg.content.length > 0) {
            if (this.chatStatus === 'thinking' || this.chatStatus === 'streaming' ||
                this.chatStatus === 'tool_executing') {
              console.info(`[ChatDetailPage] Fallback: detected assistant message but status=${this.chatStatus}, forcing completed`)
              sessionStore.updateSessionStatus(this.sessionId, 'completed')
            }
          }
        }
      }
      // 消息变化时同步任务列表状态（最新任务状态在 sessionStore 里更新）
      this.taskItems = sessionStore.getCurrentTasks()
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
      if (status === 'completed') {
        this.stopWorkTimer()
        this.vibrateReplyCompleted()
        if (!this.hasPlayedCompleteSound) {
          this.hasPlayedCompleteSound = true
          this.playSound('staplebops-02.wav')
          console.info('[ChatDetailPage] status=completed, played end sound')
        }
      } else if (status === 'idle') {
        this.stopWorkTimer()
      }
      // 状态变为 working 时启动计时器
      if (status === 'thinking' || status === 'streaming' || status === 'tool_executing') {
        this.startWorkTimer()
        // 进入工作状态时重置音效标志（为下一轮做准备）
        if (!this.hasPlayedConnectSound) {
          this.hasPlayedConnectSound = true
          this.hasPlayedCompleteSound = false
          this.playSound('staplebops-02.wav')
          console.info('[ChatDetailPage] status=' + status + ', played start sound')
        }
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
    // 同步本地 @State 副本（@Builder 读取全局 Store 不被 ArkTS 追踪）
    this.taskItems = sessionStore.getCurrentTasks()
    // 同步权限模式（服务端或其他端更改时更新）
    this.currentPermissionMode = sessionStore.getCurrentPermissionMode()
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
    toastManager.copied()

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
        // 回复内容改为生成完成后直接弹出气泡，不流式显示
        // 文本缓冲仍在 SessionStore.streamHeads 中积累，message_complete 时刷入 tail
        break

      case 'content_delta':
        // 启动工作计时器（如果当前不在工作状态）
        if (this.chatStatus === 'idle' || this.chatStatus === 'completed') {
          this.startWorkTimer()
        }
        // 回复内容不流式显示，SessionStore.streamHeads 在后台积累
        // 等待 message_complete → flushHeadToTail → 完整 MessageBubble 出现
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
        // 流式缓冲已由 SessionStore.flushHeadToTail 持久化，这里只需要清理本地的 thinking @State
        this.streamingThinking = ''
        this.inThinkingBlock = false
        break

      case 'tool_result':
        this.messageUpdateCounter++
        break

      case 'message_complete':
        // 流式缓冲已由 SessionStore.flushHeadToTail 持久化，这里只需要清理本地的 thinking @State
        this.streamingThinking = ''
        this.inThinkingBlock = false
        // 状态由 SessionStore 更新，这里只停止计时器和更新 token
        this.stopWorkTimer()
        if (msg.used) {
          this.tokenUsage = msg.used
        }
        if (!this.userIsViewingHistory && !this.isUserTouchingList) {
          this.scrollToBottom()
        }
        break

      case 'status':
        break

      case 'permission_request':
        // 流式缓冲已由 SessionStore.flushHeadToTail 持久化，这里只需要清理本地的 thinking @State
        this.streamingThinking = ''
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
        // 流式缓冲已由 SessionStore.flushHeadToTail 持久化，这里只需要清理本地的 thinking @State
        this.streamingThinking = ''
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
          this.taskItems = sessionStore.getCurrentTasks()
          this.messageUpdateCounter++
        }
        break
    }
  }

  // HdsNavigation 右侧按钮 - 打开 Preview 页面
  private menus: Array<HdsNavigationBadgeIconOptions> = [
    {
      content: {
        icon: $r('sys.symbol.folder'),
        action: () => {
          router.pushUrl({
            url: 'pages/PreviewPage',
            params: { sessionId: this.sessionId }
          })
        }
      }
    }
  ]

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
        return Theme.AccentBlue
      case 'permission_pending':
      case 'question_pending':
        return Theme.WarningColor
      case 'completed':
        return Theme.SuccessColor
      default:
        return Theme.TextSecondary
    }
  }

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

  private vibrateAlert(): void {
    try {
      vibrator.startVibration({
        type: 'time',
        duration: 300
      }, {
        id: 0,
        usage: 'alarm'
      })
    } catch (e) {}
  }

  // AI 回复完成时短振动提示（轻柔脉冲）
  private vibrateReplyCompleted(): void {
    try {
      vibrator.startVibration({
        type: 'time',
        duration: 50
      }, {
        id: 0,
        usage: 'notification'
      })
    } catch (e) {}
  }

  // 播放 rawfile 音效（使用 AudioRenderer 播放 WAV PCM）
  private async playSound(fileName: string): Promise<void> {
    try {
      console.info(`[ChatDetailPage] playSound: ${fileName}`)
      const ctx: common.Context = getContext(this) as common.Context
      const fileData: Uint8Array = await ctx.resourceManager.getRawFileContent(fileName)
      if (!fileData || fileData.length <= 44) {
        console.error(`[ChatDetailPage] playSound: invalid file data for ${fileName}`)
        return
      }

      // 动态扫描 WAV 头，找到 data chunk 偏移和大小
      let dataOffset = 12
      let dataSize = 0
      let foundData = false
      while (dataOffset + 8 <= fileData.length) {
        const chunkId = String.fromCharCode(fileData[dataOffset], fileData[dataOffset + 1],
          fileData[dataOffset + 2], fileData[dataOffset + 3])
        const chunkSize = fileData[dataOffset + 4] | (fileData[dataOffset + 5] << 8) |
          (fileData[dataOffset + 6] << 16) | (fileData[dataOffset + 7] << 24)
        if (chunkId === 'data') {
          dataOffset += 8
          dataSize = chunkSize
          foundData = true
          break
        }
        dataOffset += 8 + chunkSize
      }
      if (!foundData || dataSize <= 0) {
        console.error(`[ChatDetailPage] playSound: no data chunk found`)
        return
      }

      // 提取 PCM 数据
      const pcmData = fileData.subarray(dataOffset, dataOffset + dataSize)
      const pcmBuffer: ArrayBuffer = new ArrayBuffer(pcmData.length)
      new Uint8Array(pcmBuffer).set(pcmData)

      // 固定参数：已知 WAV 为 44100Hz / 单声道 / 16bit
      const audioRendererOptions: audio.AudioRendererOptions = {
        streamInfo: {
          samplingRate: audio.AudioSamplingRate.SAMPLE_RATE_44100,
          channels: audio.AudioChannel.CHANNEL_1,
          sampleFormat: audio.AudioSampleFormat.SAMPLE_FORMAT_S16LE,
          encodingType: audio.AudioEncodingType.ENCODING_TYPE_RAW
        },
        rendererInfo: {
          usage: audio.StreamUsage.STREAM_USAGE_MUSIC,
          rendererFlags: 0
        }
      }
      const audioRenderer: audio.AudioRenderer = await audio.createAudioRenderer(audioRendererOptions)
      await audioRenderer.start()
      await audioRenderer.write(pcmBuffer)
      await audioRenderer.stop()
      await audioRenderer.release()
      console.info(`[ChatDetailPage] playSound: ${fileName} played successfully`)
    } catch (e) {
      console.error(`[ChatDetailPage] playSound exception: ${e}`)
    }
  }

  private getTaskProgress(tasks: TaskItem[]): number {
    if (!tasks || tasks.length === 0) return 0
    const done = tasks.filter(t => t.status === 'completed' ).length
    return Math.round((done / tasks.length) * 100)
  }

  private areAllTasksCompleted(tasks: TaskItem[]): boolean {
    return tasks.every(t => t.status === 'completed' )
  }

  private getCompletedTaskCount(tasks: TaskItem[]): number {
    return tasks.filter(t => t.status === 'completed' ).length
  }

  private formatElapsed(seconds: number): string {
    if (seconds < 60) return `${seconds}秒`
    const mins = Math.floor(seconds / 60)
    const secs = seconds % 60
    if (mins < 60) return `${mins}分${secs}秒`
    const hours = Math.floor(mins / 60)
    const remainMins = mins % 60
    return `${hours}时${remainMins}分`
  }

  private getBottomSpacerHeight(): number {
    const inputAreaHeight = 120
    const tasks = this.taskItems
    if (tasks.length === 0 || sessionStore.taskBarDismissed) {
      return inputAreaHeight
    }
    // 折叠状态：分隔线 + 标题行(~44) + 间距 + 输入框
    const collapsedHeight = 57
    if (!sessionStore.taskBarExpanded) {
      return inputAreaHeight + collapsedHeight
    }
    // 展开状态：折叠高度 + 任务列表行数
    const expandedHeight = Math.min(tasks.length * 50, 200)
    return inputAreaHeight + collapsedHeight + expandedHeight
  }

  @Builder
  TaskBarView() {
    if (this.taskItems && this.taskItems.length > 0 && !sessionStore.taskBarDismissed) {
      Column({ space: 0 }) {
        Divider()
          .color('rgba(255,255,255,0.08)')
          .width('100%')

        Column({ space: 0 }) {
          Row({ space: 8 }) {
            Column() {
              SymbolGlyph($r('sys.symbol.checkmark_circle_fill'))
                .fontSize(13)
                .fontColor([Theme.AccentBlue])
            }
            .width(26).height(26)
            .backgroundColor('rgba(10, 132, 255, 0.1)')
            .borderRadius(6)
            .justifyContent(FlexAlign.Center)

            Text('任务')
              .fontSize(13).fontWeight(FontWeight.Bold).fontColor(Theme.TextPrimary)

            Row() {
              Row()
                .width(this.getTaskProgress(this.taskItems) + '%')
                .height('100%')
                .backgroundColor(this.areAllTasksCompleted(this.taskItems) ? Theme.SuccessColor : Theme.AccentBlue)
                .borderRadius(2)
            }
            .width(120).height(4)
            .backgroundColor('rgba(255,255,255,0.1)')
            .borderRadius(2)

            Text(this.getCompletedTaskCount(this.taskItems) + '/' + this.taskItems.length)
              .fontSize(11).fontFamily('monospace').fontColor(Theme.TextSecondary)

            Blank()

            SymbolGlyph($r('sys.symbol.chevron_down'))
              .fontSize(11).fontColor([Theme.TextSecondary])
              .rotate({ angle: this.showTaskBarExpanded ? 0 : 180 })
              .animation({ duration: 200, curve: Curve.EaseInOut })
          }
          .width('100%')
          .onClick(() => {
            this.showTaskBarExpanded = !this.showTaskBarExpanded
            sessionStore.taskBarExpanded = this.showTaskBarExpanded
          })

          // 展开的任务列表
          if (this.showTaskBarExpanded && this.taskItems.length > 0) {
            Column({ space: 4 }) {
              ForEach(this.taskItems, (task: TaskItem) => {
                Row({ space: 8 }) {
                  SymbolGlyph(task.status === 'completed' 
                    ? $r('sys.symbol.checkmark_circle_fill')
                    : $r('sys.symbol.circle'))
                    .fontSize(12)
                    .fontColor([task.status === 'completed'  ? Theme.SuccessColor : Theme.TextTertiary])

                  Text(task.content || '')
                    .fontSize(12).fontColor(Theme.TextPrimary)
                    .layoutWeight(1)
                    .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                .width('100%')
                .padding({ left: 34, right: 8, top: 6, bottom: 6 })
              })
            }
            .width('100%')
            .padding({ top: 4, bottom: 4 })
          }
        }
        .width('100%')
        .padding(12)
      }
      .width('100%')
      .backgroundColor('#1C1C1E')
      .borderRadius(12)
      .border({ width: 0.5, color: 'rgba(255,255,255,0.1)' })
      .margin({ bottom: 8 })
    }
  }

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

  @Builder
  AttachmentActionSheet() {
    Column({ space: 16 }) {
      Text('添加附件').fontSize(18).fontWeight(FontWeight.Bold).fontColor(Theme.TextPrimary)

      Row({ space: 24 }) {
        // 图片
        Column({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.camera'))
            .fontSize(28).fontColor([Theme.AccentBlue])
          Text('图片').fontSize(13).fontColor(Theme.TextSecondary)
        }
        .padding(16)
        .backgroundColor('rgba(255,255,255,0.08)')
        .borderRadius(12)
        .onClick(() => {
          this.showAttachSheet = false
          this.pickImage()
        })

        // 文件
        Column({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.doc'))
            .fontSize(28).fontColor([Theme.AccentGreen])
          Text('文件').fontSize(13).fontColor(Theme.TextSecondary)
        }
        .padding(16)
        .backgroundColor('rgba(255,255,255,0.08)')
        .borderRadius(12)
        .onClick(() => {
          this.showAttachSheet = false
          this.pickFile()
        })
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
    }
    .width('100%')
    .padding(24)
  }

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
          SymbolGlyph($r('sys.symbol.camera'))
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
          this.pickImage()
        })
      }
      .width(220)
      .padding(Theme.SpacingSM)
      .backgroundColor(Theme.BackgroundSecondary)
      .borderRadius(16)
      .shadow({ radius: 20, color: 'rgba(0,0,0,0.3)', offsetY: 4 })
      .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
      .transition(TransitionEffect.scale({ x: 0.3, y: 0.3 }).animation({ duration: 250, curve: Curve.FastOutSlowIn })
        .combine(TransitionEffect.OPACITY.animation({ duration: 250, curve: Curve.FastOutSlowIn })))
    }
    .width('100%')
    .height('100%')
    .backgroundColor('rgba(0,0,0,0.3)')
    .alignContent(Alignment.BottomStart)
    .padding({ left: Theme.SpacingLG, bottom: 85 })
    .transition(TransitionEffect.OPACITY.animation({ duration: 200 }))
    .zIndex(10)
    .onClick(() => {
      this.showMenu = false
    })
  }

  @Builder
  AttachmentPreviewRow() {
    Row({ space: 6 }) {
      ForEach(this.pendingAttachments, (att: AttachmentRef) => {
        Row({ space: 4 }) {
          // 文件类型标签
          if (att.mimeType) {
            Text(this.getAttachmentTypeLabel(att.mimeType))
              .fontSize(10).fontWeight(FontWeight.Bold)
              .fontColor(this.getAttachmentTypeColor(att.mimeType))
          }

          Text(att.name || '附件')
            .fontSize(12).fontColor(Theme.TextSecondary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          if (att.size && att.size > 0) {
            Text(this.formatFileSize(att.size))
              .fontSize(10).fontColor(Theme.TextTertiary)
          }
        }
        .padding({ left: 8, right: 8, top: 4, bottom: 4 })
        .backgroundColor('rgba(255,255,255,0.08)')
        .borderRadius(8)
      })
    }
    .width('100%')
    .padding({ bottom: 8 })
  }



  build() {
    Stack() {
      // 点阵背景 - 最底层，穿透触控
      DotMatrixBackground({ active: this.isPageActive })

      HdsNavigation() {
        // 消息列表 — 倒序+翻转：默认就在"底部"（最新消息），无需scrollTo
        List({ scroller: this.scroller }) {
          // 顶部留白（翻转后视觉在底部，给悬浮输入框留空间）
          ListItem() {
            Row().width('100%').height(this.getBottomSpacerHeight())
          }
          .rotate({ angle: 180 })

          // 流式思考实时渲染（回复内容不流式显示，生成完后直接弹完整气泡）
          if (this.streamingThinking) {
            ListItem() {
              this.StreamingThinkingBubble()
            }
            .rotate({ angle: 180 })
          }

          // 消息倒序排列（最新在前=视觉底部），工具消息合组
          ForEach([...this.getVisibleMessages()].reverse(), (message: Message) => {
            ListItem() {
              if (message.type === 'tool_use' && (message.toolName === 'Agent' || message.toolName === 'AskUserQuestion')) {
                // Agent / AskUserQuestion 有特殊渲染，不参与合组
                this.MessageBubble(message)
              } else if ((message.type === 'tool_use' || message.type === 'tool_result') && !message.parentToolUseId) {
                // 工具组：仅在组内第一条渲染 ToolGroupBubble，其余跳过
                if (this.isFirstToolInReverseGroup(message)) {
                  this.ToolGroupBubble(this.collectToolGroup(message))
                }
              } else {
                this.MessageBubble(message)
              }
            }
            .rotate({ angle: 180 })
            .transition(this.getMessageTransition(message))
          }, (message: Message) => {
            // 生成稳定且唯一的 key，防止重复渲染
            if (message.toolUseId && message.type === 'tool_use') {
              return 'tool_' + message.toolUseId
            }
            if (message.toolUseId && message.type === 'tool_result') {
              return 'result_' + message.toolUseId
            }
            if (message.type === 'permission_request') {
              return message.id + '_' + (message.isPermissionHandled ? 'done' : 'pending')
            }
            if (message.type === 'question') {
              return message.id + '_' + (message.isQuestionAnswered ? 'done' : 'pending')
            }
            if (message.id && !message.id.startsWith('stream-') && !message.id.startsWith('thinking-')) {
              return message.id
            }
            return message.type + '_' + (message.content || message.toolResult || '').substring(0, 30)
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
        if (this.streamingThinking) {
          // 有思考内容时显示思考中
          StatusIcon({ status: WorkStatus.THINKING })
          Text('思考中...').fontSize(11).fontColor(Theme.AccentBlue)
          if (this.elapsedSeconds > 0) {
            Text(this.formatElapsed(this.elapsedSeconds)).fontSize(10).fontColor(Theme.TextTertiary)
          }
        } else if (this.chatStatus === 'idle') {
          Text('休闲中').fontSize(11).fontColor(Theme.TextSecondary)
        } else if (this.chatStatus === 'completed') {
          Text('已完成').fontSize(11).fontColor(Theme.SuccessColor)
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

      // 底部悬浮区域：任务面板 + 最新消息按钮 + 输入框
      Column({ space: 0 }) {
        // 吉祥物 + 用时（固定左下角，不随消息列表滚动）
        if (this.chatStatus === 'thinking' || this.chatStatus === 'streaming' ||
          this.chatStatus === 'tool_executing' || this.chatStatus === 'completed' ||
          this.chatStatus === 'permission_pending' ||
          this.chatStatus === 'question_pending') {
          Row() {
            this.StreamingIndicator()
          }
          .width('100%')
          .padding({ left: 0 })
        }

        // 任务面板
        this.TaskBarView()

        // "最新消息"胶囊按钮
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
      .padding({ left: Theme.SpacingLG, right: Theme.SpacingLG, bottom: 20 })
      .backgroundColor(Color.Transparent)
      .position({ x: 0, y: '100%' })
      .translate({ y: '-100%' })
      .zIndex(2)
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

  // 流式思考气泡是否展开
  private isStreamingThinkingExpanded(): boolean {
    return this.expandedThinkingIds.has('streaming-thinking')
  }

  // 切换流式思考气泡展开/折叠
  private toggleStreamingThinking(): void {
    if (this.isStreamingThinkingExpanded()) {
      const newSet = new Set(this.expandedThinkingIds)
      newSet.delete('streaming-thinking')
      this.expandedThinkingIds = newSet
    } else {
      const newSet = new Set(this.expandedThinkingIds)
      newSet.add('streaming-thinking')
      this.expandedThinkingIds = newSet
    }
  }

  // 消息进入动画：只有最新的一条用弹簧效果，其余直接淡入
  private getMessageTransition(message: Message): TransitionEffect {
    if (this.isNewestMessage(message)) {
      return TransitionEffect.asymmetric(
        TransitionEffect.OPACITY
          .combine(TransitionEffect.translate({ y: -50 }))
          .animation({ duration: 600, curve: curves.springCurve(0.3, 1, 200, 25) }),
        TransitionEffect.OPACITY.animation({ duration: 150 })
      )
    }
    return TransitionEffect.OPACITY.animation({ duration: 100 })
  }

  private isNewestMessage(message: Message): boolean {
    return message.id === this.latestMessageId
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

  // 获取可见消息（分页 + 展示层内容去重），过滤掉 Agent 子工具（由 AgentToolUseBubble 嵌套渲染）
  private getVisibleMessages(): Message[] {
    // 用 getDedupedMessages 作为展示层安全网，过滤内容重复的消息
    const allMessages = sessionStore.getDedupedMessages(this.sessionId)
    // 过滤：排除有 parentToolUseId 的子工具，它们在 Agent 卡片内嵌套渲染
    const filtered = allMessages.filter(m => !(m.type === 'tool_use' && m.parentToolUseId))
    // DEBUG: 统计 tool_use 消息
    const toolCount = filtered.filter(m => m.type === 'tool_use').length
    console.info(`[ChatDetailPage] getVisibleMessages: total=${allMessages.length}, filtered=${filtered.length}, tool_use=${toolCount}, displayedMessageCount=${this.displayedMessageCount}`)
    if (filtered.length <= this.displayedMessageCount) {
      return filtered
    }
    const sliced = filtered.slice(filtered.length - this.displayedMessageCount)
    const slicedToolCount = sliced.filter(m => m.type === 'tool_use').length
    console.info(`[ChatDetailPage] getVisibleMessages: SLICED to ${sliced.length}, tool_use=${slicedToolCount}`)
    return sliced
  }

  /**
   * 在逆序列表中判断当前 tool 消息是否是组的第一个（即最新的一条）。
   * 用于在 ForEach 逆序渲染时，只在第一条渲染 ToolGroupBubble，
   * 其余工具消息跳过（渲染空 Column）。
   * Agent / AskUserQuestion 有特殊渲染，不参与合组。
   */
  private isFirstToolInReverseGroup(message: Message): boolean {
    if (message.type !== 'tool_use' && message.type !== 'tool_result') return false
    if (message.parentToolUseId) return false
    if (message.toolName === 'Agent' || message.toolName === 'AskUserQuestion') return false
    const reversed = [...this.getVisibleMessages()].reverse()
    let idx = reversed.indexOf(message)
    // 引用不匹配时用 ID 回退（组件重建后引用会变）
    if (idx < 0) {
      for (let i = 0; i < reversed.length; i++) {
        if (reversed[i].id === message.id) { idx = i; break }
      }
    }
    if (idx <= 0) {
      console.info(`[ChatDetailPage] isFirstToolInReverseGroup=true id=${message.id} toolName=${message.toolName} idx=${idx}`)
      return true
    }
    const prev = reversed[idx - 1]
    // Agent / AskUserQuestion 会打断连续的工具组
    if (prev.toolName === 'Agent' || prev.toolName === 'AskUserQuestion') {
      console.info(`[ChatDetailPage] isFirstToolInReverseGroup=true(id=${message.id}) prev is Agent`)
      return true
    }
    const result = prev.type !== 'tool_use' && prev.type !== 'tool_result'
    console.info(`[ChatDetailPage] isFirstToolInReverseGroup=${result} id=${message.id} idx=${idx} prevType=${prev.type}`)
    return result
  }

  /**
   * 从当前 tool 消息开始收集连续的 tool_use/tool_result 消息（按正序）
   * 遇到 Agent / AskUserQuestion 时停止收集。
   * 先向后找到组起点，再向前收集全部，解决逆序渲染时 first 是组内最后一条的问题。
   */
  private collectToolGroup(anyToolInGroup: Message): Message[] {
    const group: Message[] = []
    const allMessages = sessionStore.messages.get(this.sessionId) || []
    // 先用引用匹配，失败后用 ID 回退（组件重建后引用会变）
    let startIdx = allMessages.indexOf(anyToolInGroup)
    if (startIdx < 0) {
      startIdx = 0
      for (let i = 0; i < allMessages.length; i++) {
        if (allMessages[i].id === anyToolInGroup.id) {
          startIdx = i
          break
        }
      }
    }
    // 仍找不到 → 只返回自身
    if (startIdx >= allMessages.length || allMessages[startIdx].id !== anyToolInGroup.id) {
      console.warn(`[ChatDetailPage] collectToolGroup: message not found in store, returning self only. id=${anyToolInGroup.id}`)
      return [anyToolInGroup]
    }

    // 向后找组的起点（第一个 tool 消息）
    let groupStart = startIdx
    for (let i = startIdx - 1; i >= 0; i--) {
      const m = allMessages[i]
      if ((m.type === 'tool_use' || m.type === 'tool_result') &&
        !m.parentToolUseId &&
        m.toolName !== 'Agent' &&
        m.toolName !== 'AskUserQuestion') {
        groupStart = i
      } else {
        break
      }
    }

    // 从起点向前收集全部工具消息
    for (let i = groupStart; i < allMessages.length; i++) {
      const m = allMessages[i]
      if ((m.type === 'tool_use' || m.type === 'tool_result') &&
        !m.parentToolUseId &&
        m.toolName !== 'Agent' &&
        m.toolName !== 'AskUserQuestion') {
        group.push(m)
      } else {
        break
      }
    }
    console.info(`[ChatDetailPage] collectToolGroup: startIdx=${startIdx} groupStart=${groupStart} totalMsgs=${allMessages.length} groupSize=${group.length} toolNames=[${group.filter(m=>m.type==='tool_use').map(m=>m.toolName).join(',')}]`)
    return group
  }

  private hasMoreMessages(): boolean {
    return this.messages.length > this.displayedMessageCount
  }

  // 计算 List 总项数（用于 onScrollIndex）
  private getListItemCount(): number {
    let count = 2 // 顶部留白 + 底部占位
    count += this.getVisibleMessages().length
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
    .backgroundColor('#3A3A3C')
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
        MarkdownRenderer({ content: message.content, onLinkClick: (url: string) => { this.openExternalLink(url) } })
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
    .backgroundColor('#2C2C2E')
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

  // 流式思考气泡（实时渲染 thinking 输出）
  @Builder
  StreamingThinkingBubble() {
    Row() {
      Column({ space: 0 }) {
        // 可点击头部
        Row({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.lightbulb'))
            .fontSize(12)
            .fontColor([Theme.AccentOrange])

          Text('thinking...')
            .fontSize(11)
            .fontWeight(FontWeight.Medium)
            .fontColor(Theme.TextSecondary)

          Blank()

          // 箭头指示展开/折叠
          if (this.isStreamingThinkingExpanded()) {
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
        .padding({ left: 12, right: 12, top: 10, bottom: this.isStreamingThinkingExpanded() ? 6 : 10 })
        .onClick(() => {
          this.toggleStreamingThinking()
        })

        // 展开时显示内容
        if (this.isStreamingThinkingExpanded()) {
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
      }
      .width('100%')
      .backgroundColor('#2C2C2E')
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
    .backgroundColor('#2C2C2E')
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

  /** 获取工具结果行数摘要（如 "23 lines"） */
  private getToolResultLineCount(message: Message): string {
    if (!message.toolResult || message.toolStatus !== 'completed') return ''
    const lines = message.toolResult.split('\n').length
    if (lines <= 1) return ''
    return lines + ' 行输出'
  }

  private isToolExpandableWithResult(message: Message): boolean {
    return this.isToolExpandable(message.toolName) ||
      (message.toolResult !== undefined && message.toolResult.length > 0)
  }

  private getBashCommand(message: Message): string {
    if (!message.toolInput) return ''
    const cmd = message.toolInput['command']
    return typeof cmd === 'string' ? cmd : ''
  }

  private getToolFilePath(message: Message): string {
    if (!message.toolInput) return ''
    const fp = message.toolInput['file_path']
    return typeof fp === 'string' ? fp : ''
  }

  private truncateToolResult(message: Message): string {
    if (!message.toolResult) return ''
    return message.toolResult.length > 2000
      ? message.toolResult.substring(0, 2000) + '...'
      : message.toolResult
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

        // 文件名/命令摘要
        if (this.getToolInputSummary(message.toolName || '', message.toolInput || {})) {
          Text(this.getToolInputSummary(message.toolName || '', message.toolInput || {}))
            .fontSize(11)
            .fontColor(Theme.TextTertiary)
            .maxLines(1)
            .layoutWeight(1)
        } else {
          Blank().layoutWeight(1)
        }

        // 结果行数
        if (this.getToolResultLineCount(message)) {
          Text(this.getToolResultLineCount(message))
            .fontSize(10)
            .fontColor(Theme.TextTertiary)
        }

        // 状态图标
        this.ToolStatusIcon(message.toolStatus)

        // 展开箭头
        if (this.isToolExpandableWithResult(message)) {
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

      // 展开内容
      if (this.expandedToolIds.has(message.id) && this.isToolExpandableWithResult(message)) {
        Divider()
          .color('rgba(255,255,255,0.1)')
          .width('100%')

        Column({ space: 8 }) {
          // Bash 工具：显示命令
          if (message.toolName === 'Bash' && this.getBashCommand(message)) {
            Text('$ ' + this.getBashCommand(message))
              .fontSize(11)
              .fontColor(Theme.TextPrimary)
              .fontFamily('monospace')
              .width('100%')
              .padding(10)
              .borderRadius(6)
              .backgroundColor('#1C1C1E')
          }

          // 文件内容预览（Write/Edit）
          if ((message.toolName === 'Write' || message.toolName === 'Edit') &&
            this.getToolFilePath(message) && message.toolStatus === 'completed') {
            FileAttachmentBubble({
              filePath: this.getToolFilePath(message),
              onImageTap: (src: string, alt: string, name: string) => {
                this.openFilePreview(src, alt, name)
              }
            })
          }

          // 输出结果
          if (message.toolResult) {
            Column({ space: 4 }) {
              Text('OUTPUT')
                .fontSize(9)
                .fontWeight(FontWeight.Bold)
                .fontColor(Theme.TextSecondary)

              // 检测是否有图片
              if (message.images && message.images.length > 0) {
                ForEach(message.images, (img: MessageImage, idx: number) => {
                  Image('data:' + img.mediaType + ';base64,' + img.data)
                    .width('100%')
                    .constraintSize({ maxHeight: 300 })
                    .objectFit(ImageFit.Contain)
                    .borderRadius(8)
                })
              }

              MarkdownRenderer({ content: this.truncateToolResult(message),
                onLinkClick: (url: string) => { this.openExternalLink(url) } })
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
    .backgroundColor('#2C2C2E')
    .borderRadius(10)
    .border({
      width: 0.5,
      color: 'rgba(255,255,255,0.12)'
    })
    .onClick(() => {
      if (this.isToolExpandableWithResult(message)) {
        this.toggleTool(message.id)
      }
    })
  }

  // MARK: - 工具组折叠容器

  /**
   * 工具组折叠容器 — 将连续的 tool_use/tool_result 合并为一个可折叠气泡
   */
  @Builder
  ToolGroupBubble(messages: Message[]) {
    Column({ space: 0 }) {
      // Header: 图标 + 动词摘要 + 进度状态 + 箭头
      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.hammer_fill'))
          .fontSize(12)
          .fontColor([Theme.AccentBlue])

        Text(this.getToolGroupSummary(messages))
          .fontSize(12)
          .fontColor(Theme.TextPrimary)
          .layoutWeight(1)

        // 状态指示
        if (this.toolGroupExpanded) {
          // 已完成统计
          Text(this.getToolGroupCountText(messages))
            .fontSize(10)
            .fontColor(Theme.TextTertiary)
            .maxLines(1)
        } else {
          // 折叠时显示完整度标记
          Text('已完成')
            .fontSize(10)
            .fontColor(Theme.SuccessColor)
            .opacity(this.isToolGroupComplete(messages) ? 1 : 0)
        }

        SymbolGlyph(this.toolGroupExpanded
          ? $r('sys.symbol.chevron_up')
          : $r('sys.symbol.chevron_down'))
          .fontSize(10)
          .fontColor([Theme.TextSecondary])
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 10, bottom: 10 })

      // 展开内容
      if (this.toolGroupExpanded) {
        Divider().color('rgba(255,255,255,0.1)').width('100%')

        Column({ space: 0 }) {
          ForEach(messages, (msg: Message) => {
            if (msg.type === 'tool_use') {
              this.ToolUseBubble(msg)
            } else if (msg.type === 'tool_result') {
              this.ToolResultBubble(msg)
            }
          }, (msg: Message) => msg.id + '_' + (msg.toolStatus || ''))
        }
        .width('100%')
      }
    }
    .width('100%')
    .backgroundColor('#2C2C2E')
    .borderRadius(10)
    .border({ width: 0.5, color: 'rgba(255,255,255,0.12)' })
    .margin({ bottom: Theme.SpacingMD })
    .onClick(() => {
      this.toolGroupExpanded = !this.toolGroupExpanded
    })
  }

  // MARK: - 工具组辅助方法

  /**
   * 工具组折叠态摘要文字（如 "调用 3 个工具 · 执行 2 个命令"）
   */
  private getToolVerb(name: string, count: number): string {
    if (name === 'Read') return count === 1 ? '读取 1 个文件' : '读取 ' + count + ' 个文件'
    if (name === 'Write') return count === 1 ? '写入 1 个文件' : '写入 ' + count + ' 个文件'
    if (name === 'Edit') return count === 1 ? '编辑 1 个文件' : '编辑 ' + count + ' 个文件'
    if (name === 'Bash') return count === 1 ? '执行 1 条命令' : '执行 ' + count + ' 条命令'
    if (name === 'Grep') return count === 1 ? '搜索 1 处' : '搜索 ' + count + ' 处'
    if (name === 'Glob') return '查找文件'
    if (name === 'WebFetch') return count === 1 ? '获取 1 个页面' : '获取 ' + count + ' 个页面'
    if (name === 'Agent') return count === 1 ? '派遣 1 个代理' : '派遣 ' + count + ' 个代理'
    return name + ' ' + count
  }

  private getToolGroupSummary(messages: Message[]): string {
    const typeCounts: Record<string, number> = {}
    for (let i = 0; i < messages.length; i++) {
      const m = messages[i]
      if (m.type === 'tool_use' && m.toolName) {
        const prev = typeCounts[m.toolName]
        typeCounts[m.toolName] = (prev !== undefined ? prev : 0) + 1
      }
    }
    const keys = Object.keys(typeCounts)
    if (keys.length === 0) return '调用工具'

    const parts: string[] = []
    for (let i = 0; i < keys.length; i++) {
      const name = keys[i]
      const count = typeCounts[name] !== undefined ? typeCounts[name] : 0
      parts.push(this.getToolVerb(name, count))
    }
    return parts.join('，')
  }

  private isToolGroupComplete(messages: Message[]): boolean {
    for (let i = 0; i < messages.length; i++) {
      const m = messages[i]
      if (m.type === 'tool_use' && m.toolStatus !== 'completed' && m.toolStatus !== 'failed') {
        return false
      }
    }
    return true
  }

  /**
   * 工具组右侧进度文字（如 "已完成" 或 "2/3"）
   */
  private getToolGroupCountText(messages: Message[]): string {
    let toolCount = 0
    let doneCount = 0
    for (let i = 0; i < messages.length; i++) {
      const m = messages[i]
      if (m.type === 'tool_use') {
        toolCount++
        if (m.toolStatus === 'completed') doneCount++
      }
    }
    if (doneCount === toolCount) return '已完成'
    return doneCount + '/' + toolCount
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

  // 筛选子代理（toolName === 'Agent' 的子工具）
  private filterSubAgents(children: Message[]): Message[] {
    const result: Message[] = []
    for (let i = 0; i < children.length; i++) {
      if (children[i].toolName === 'Agent') result.push(children[i])
    }
    return result
  }

  // 筛选普通子工具（非 Agent 类型）
  private filterRegularChildTools(children: Message[]): Message[] {
    const result: Message[] = []
    for (let i = 0; i < children.length; i++) {
      if (children[i].toolName !== 'Agent') result.push(children[i])
    }
    return result
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
        this.AgentStatusBadge(this.getAgentStatusValue(message))

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

          // 子代理 & 子工具渲染
          {
            const childToolCalls = this.getChildToolCalls(message.toolUseId || '')
            const subAgents = this.filterSubAgents(childToolCalls)
            const regularTools = this.filterRegularChildTools(childToolCalls)

            if (childToolCalls.length > 0) {
              Column({ space: 6 }) {
                // 子代理卡片列表
                if (subAgents.length > 0) {
                  Text('派遣了 ' + subAgents.length + ' 个代理去调查')
                    .fontSize(12)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(Theme.TextPrimary)
                    .width('100%')

                  ForEach(subAgents, (subAgent: Message) => {
                    this.SubAgentCard(subAgent)
                  }, (subAgent: Message) => subAgent.id)
                }

                // 普通子工具（非 Agent）
                if (regularTools.length > 0) {
                  ForEach(regularTools, (child: Message) => {
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
    .backgroundColor('#2C2C2E')
    .borderRadius(10)
    .border({
      width: 0.5,
      color: 'rgba(255,255,255,0.12)'
    })
    .onClick(() => {
      this.toggleTool(message.id)
    })
  }

  // MARK: - 子代理卡片

  @Builder
  SubAgentCard(subAgent: Message) {
    Column({ space: 0 }) {
      // 卡片头部：图标 + 描述 + 状态徽章 + 查看/收起按钮
      Row({ space: 6 }) {
        SymbolGlyph($r('sys.symbol.person_fill'))
          .fontSize(12)
          .fontColor([Theme.AccentBlue])

        Text(this.getAgentDescription(subAgent) || '子代理')
          .fontSize(12)
          .fontColor(Theme.TextPrimary)
          .maxLines(1)
          .layoutWeight(1)

        // 状态
        this.AgentStatusBadge(this.getAgentStatusValue(subAgent))

        // 查看/收起按钮
        Text(this.expandedToolIds.has(subAgent.id) ? '收起' : '查看')
          .fontSize(11)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.AccentBlue)
          .padding({ left: 8, right: 8, top: 3, bottom: 3 })
          .borderRadius(6)
          .backgroundColor('rgba(10, 132, 255, 0.1)')
      }
      .width('100%')
      .padding({ left: 10, right: 10, top: 8, bottom: 8 })

      // 展开后：显示该子代理调用的工具
      if (this.expandedToolIds.has(subAgent.id)) {
        Divider()
          .color('rgba(255,255,255,0.08)')
          .width('100%')

        Column({ space: 4 }) {
          if (this.getChildToolCalls(subAgent.toolUseId || '').length > 0) {
            ForEach(this.getChildToolCalls(subAgent.toolUseId || ''), (child: Message) => {
              Row({ space: 0 }) {
                // 连接线
                Column() {
                  Row()
                    .width(6)
                    .height(6)
                    .borderRadius(3)
                    .border({ width: 1, color: 'rgba(255,255,255,0.2)' })
                    .backgroundColor('#1C1C1E')
                    .margin({ left: 0, top: 4 })
                }
                .width(10)
                .alignItems(HorizontalAlign.Center)
                .padding({ top: 4 })

                // 工具卡片
                Column({ space: 0 }) {
                  Row({ space: 6 }) {
                    SymbolGlyph(getToolIcon(child.toolName || 'Tool').symbol)
                      .fontSize(11)
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
                  .padding({ left: 8, right: 8, top: 5, bottom: 5 })
                  .borderRadius(6)
                  .backgroundColor('rgba(255,255,255,0.04)')
                }
                .layoutWeight(1)
                .onClick(() => {
                  this.toggleTool(child.id)
                })
              }
              .width('100%')
              .alignItems(VerticalAlign.Top)
            }, (child: Message) => child.id + '_' + (child.toolStatus || ''))
          } else {
            Text('等待子代理启动...')
              .fontSize(10)
              .fontColor(Theme.TextTertiary)
              .padding({ left: 10, top: 4, bottom: 4 })
          }
        }
        .width('100%')
        .padding({ left: 10, right: 10, top: 6, bottom: 6 })
      }
    }
    .width('100%')
    .backgroundColor('#2C2C2E')
    .borderRadius(8)
    .border({ width: 0.5, color: 'rgba(255,255,255,0.1)' })
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
    // 按工具类型统计实际调用次数，不去重
    const typeCounts: Record<string, number> = {}
    for (let i = 0; i < childToolCalls.length; i++) {
      const name = childToolCalls[i].toolName || 'Tool'
      const prev = typeCounts[name]
      typeCounts[name] = (prev !== undefined ? prev : 0) + 1
    }
    const parts: string[] = []
    const readCount = typeCounts['Read'] !== undefined ? typeCounts['Read'] : 0
    const writeCount = typeCounts['Write'] !== undefined ? typeCounts['Write'] : 0
    const editCount = typeCounts['Edit'] !== undefined ? typeCounts['Edit'] : 0
    const grepCount = typeCounts['Grep'] !== undefined ? typeCounts['Grep'] : 0
    const globCount = typeCounts['Glob'] !== undefined ? typeCounts['Glob'] : 0
    const bashCount = typeCounts['Bash'] !== undefined ? typeCounts['Bash'] : 0
    if (readCount > 0) parts.push('读取 ' + readCount + ' 个文件')
    if (writeCount > 0) parts.push('写入 ' + writeCount + ' 个文件')
    if (editCount > 0) parts.push('编辑 ' + editCount + ' 个文件')
    if (grepCount > 0) parts.push('搜索 ' + grepCount + ' 处')
    if (globCount > 0) parts.push('查找 ' + globCount + ' 处')
    if (bashCount > 0) parts.push('执行 ' + bashCount + ' 条命令')
    // 其他工具
    const knownTypes = ['Read', 'Write', 'Edit', 'Bash', 'Grep', 'Glob']
    const keys = Object.keys(typeCounts)
    for (let i = 0; i < keys.length; i++) {
      const k = keys[i]
      if (knownTypes.indexOf(k) === -1) {
        parts.push(k + ' ' + typeCounts[k])
      }
    }
    return parts.join(' · ')
  }

  @Builder
  AgentStatusBadge(statusValue: string) {
    if (statusValue) {
      Text(this.getAgentStatusLabel(statusValue))
        .fontSize(9)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.getAgentStatusColor(statusValue))
        .padding({ left: 6, right: 6, top: 2, bottom: 2 })
        .borderRadius(6)
        .backgroundColor(this.getAgentStatusBgColor(statusValue))
    }
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

  // 从 toolResult 文本中检测文件路径
  private detectFilePath(toolResult: string): string | null {
    if (!toolResult) return null
    const trimmed = toolResult.trim()
    // 文件协议路径
    if (trimmed.startsWith('file://')) return trimmed
    // 绝对路径（如 /Users/xxx/project/file.txt）
    if (trimmed.startsWith('/') && trimmed.length < 300 && !trimmed.includes('\n')) return trimmed
    // 相对路径（如 ./output/file.txt）
    if (trimmed.startsWith('./') && trimmed.length < 300 && !trimmed.includes('\n')) return trimmed
    return null
  }

  // @Builder 辅助方法：判断是否展示文件附件（替代本地变量声明，ArkTS @Builder 限制）
  private shouldShowFileAttachment(message: Message): boolean {
    return message.toolStatus === 'completed' && (this.getFileAttachmentPath(message).length > 0)
  }

  // @Builder 辅助方法：从消息中提取文件附件路径
  private getFileAttachmentPath(message: Message): string {
    if (message.toolInput && message.toolInput['file_path']) {
      return message.toolInput['file_path'] as string
    }
    const detected = this.detectFilePath(message.toolResult || '')
    return detected !== null ? detected : ''
  }

  // 打开外部链接（系统浏览器）
  private openExternalLink(url: string): void {
    try {
      let context = getContext(this) as common.UIAbilityContext
      context.startAbility({
        action: 'ohos.want.action.viewData',
        uri: url,
        type: 'text/html'
      }).catch((err: Error) => {
        console.error('[ChatDetail] Open link error:', err.message)
        toastManager.error('无法打开链接')
      })
    } catch (e) {
      console.error('[ChatDetail] Open link error:', e)
    }
  }

  // 保存图片到相册（用于 ToolResultBubble 的保存按钮）
  private async saveImageToGallery(dataUri: string, baseName: string): Promise<void> {
    try {
      toastManager.info('正在保存图片...')
      await downloadService.downloadImage(dataUri, baseName + '.png')
      toastManager.success('已保存到相册')
    } catch (e) {
      console.error('[ChatDetail] Save image error:', e)
      toastManager.error('保存失败')
    }
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

      // 渲染 Claude 生成的图片（来自 tool_result content blocks）
      if (message.images && message.images.length > 0) {
        ForEach(message.images, (img: MessageImage, idx: number) => {
          Column({ space: 6 }) {
            Image('data:' + img.mediaType + ';base64,' + img.data)
              .width('100%')
              .constraintSize({ maxHeight: 300 })
              .objectFit(ImageFit.Contain)
              .borderRadius(8)
              .onClick(() => {
                this.openFilePreview('data:' + img.mediaType + ';base64,' + img.data,
                  'Claude 图片', 'claude_image_' + idx + '.png')
              })

            // 保存按钮
            Row({ space: 4 }) {
              Text('↓')
                .fontSize(16)
                .fontColor(Theme.AccentBlue)
              Text('保存到相册')
                .fontSize(12)
                .fontColor(Theme.AccentBlue)
            }
            .padding({ top: 4, bottom: 4, left: 12, right: 12 })
            .onClick(() => {
              this.saveImageToGallery('data:' + img.mediaType + ';base64,' + img.data, 'claude_image_' + idx)
            })
          }
          .width('100%')
          .margin({ top: 8 })
        })
      }

      // 检测 toolResult 中的文件路径，优先展示文件卡片
      if (this.shouldShowFileAttachment(message)) {
        FileAttachmentBubble({
          filePath: this.getFileAttachmentPath(message),
          onImageTap: (src: string, alt: string, name: string) => {
            this.openFilePreview(src, alt, name)
          }
        })
      }

      if (message.toolResult) {
        MarkdownRenderer({ content: message.toolResult, onLinkClick: (url: string) => { this.openExternalLink(url) } })
      }
    }
    .width('100%')
    .padding(12)
    .backgroundColor('#2C2C2E')
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

  private getRingColor(): ResourceColor {
    if (this.contextUsage > 80) return Theme.ErrorColor
    if (this.contextUsage > 50) return Theme.WarningColor
    return Theme.PrimaryColor
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

  private getAttachmentTypeLabel(mimeType: string): string {
    if (mimeType.startsWith('image/')) return 'IMG'
    if (mimeType.startsWith('audio/')) return 'AUDIO'
    if (mimeType === 'application/pdf') return 'PDF'
    if (mimeType.startsWith('video/')) return 'VIDEO'
    return 'FILE'
  }

  private getAttachmentTypeColor(mimeType: string): ResourceColor {
    if (mimeType.startsWith('image/')) return '#30D158'
    if (mimeType.startsWith('audio/')) return '#BF5AF2'
    if (mimeType === 'application/pdf') return '#FF3B30'
    return '#0A84FF'
  }

  private formatFileSize(bytes: number): string {
    if (bytes < 1024) return bytes + 'B'
    if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + 'KB'
    return (bytes / (1024 * 1024)).toFixed(1) + 'MB'
  }

  private sendMessage(): void {
    const text = this.inputText.trim()
    if (!text && this.pendingAttachments.length === 0) return
    const sent = sessionStore.sendMessage(text, this.pendingAttachments)
    if (sent) {
      this.inputText = ''
      this.pendingAttachments = []
      // 重置音效标志，下一轮 AI 回复时重新播放开始/结束音效
      this.hasPlayedConnectSound = false
      this.hasPlayedCompleteSound = false
    }
  }

  private async pickImage(): Promise<void> {
    try {
      const picker = new photoViewPicker.PhotoViewPicker()
      const result: photoViewPicker.PhotoSelectResult = await picker.select({
        MIMEType: photoViewPicker.PhotoViewMIMETypes.IMAGE_TYPE,
        maxSelectNumber: 5
      })
      const uris: string[] = result.photoUris as string[] || []
      if (uris.length > 0) {
        for (let i = 0; i < uris.length; i++) {
          const uri: string = uris[i]
          this.pendingAttachments.push({
            type: 'image',
            path: uri,
            name: uri.split('/').pop() || 'image'
          })
        }
      }
    } catch (e) {
      console.error('pickImage error:', e)
    }
  }

  private async pickFile(): Promise<void> {
    try {
      const docPicker = new photoViewPicker.DocumentViewPicker()
      const result: string[] = await docPicker.select({
        maxSelectNumber: 5
      })
      if (result && result.length > 0) {
        for (let i = 0; i < result.length; i++) {
          const uri: string = result[i]
          const name: string = uri.split('/').pop() || 'file'
          const parts: string[] = name.split('.')
          const ext: string = parts.length > 1 ? parts[parts.length - 1].toLowerCase() : ''
          const mimeMap: Record<string, string> = {
            'pdf': 'application/pdf',
            'mp3': 'audio/mpeg',
            'wav': 'audio/wav',
            'ogg': 'audio/ogg',
            'aac': 'audio/aac',
            'm4a': 'audio/mp4',
            'wma': 'audio/x-ms-wma',
            'flac': 'audio/flac',
            'png': 'image/png',
            'jpg': 'image/jpeg',
            'jpeg': 'image/jpeg',
            'gif': 'image/gif',
            'webp': 'image/webp',
            'svg': 'image/svg+xml',
            'bmp': 'image/bmp',
            'doc': 'application/msword',
            'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
            'xls': 'application/vnd.ms-excel',
            'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
            'zip': 'application/zip',
            'txt': 'text/plain',
            'json': 'application/json',
            'csv': 'text/csv'
          }
          const mimeType: string = mimeMap[ext] || 'application/octet-stream'
          this.pendingAttachments.push({
            type: mimeType.startsWith('image/') ? 'image' : 'file',
            path: uri,
            name: name,
            mimeType: mimeType
          })
        }
      }
    } catch (e) {
      console.error('pickFile error:', e)
    }
  }

  @Builder
  InputAreaContent() {
    // Stack 包裹：手指追光（Flex 在上层）+ 内容行
    Stack() {
      // 手指追光组件 —— 在内容行之上，不触控
      if (this.lightIntensity > 0) {
        Flex()
          .size({ width: 1, height: 1 })
          .backgroundColor(Color.Transparent)
          .visualEffect(
            new hdsEffect.HdsEffectBuilder()
              .pointLight({
                options: {
                  color: Color.White,
                  intensity: this.lightIntensity,
                  height: 100
                }
              })
              .buildEffect()
          )
          .position({ x: this.lightFingerX, y: this.lightFingerY })
      }

      // 内容行
      Row() {
        // 附件按钮
        Column() {
          SymbolGlyph($r('sys.symbol.plus'))
            .fontSize(20)
            .fontColor([Color.White])
        }
        .width(32)
        .height(32)
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          this.showMenu = !this.showMenu
        })

        // 输入框
        TextArea({ placeholder: this.pendingAttachments.length > 0 ? '添加描述...' : 'Chat with Claude', text: this.inputText })
          .layoutWeight(1)
          .constraintSize({ minHeight: 28, maxHeight: 100 })
          .backgroundColor(Color.Transparent)
          .fontColor(Theme.TextPrimary)
          .placeholderColor('rgba(200, 200, 200, 0.6)')
          .fontSize(14)
          .textAlign(TextAlign.Start)
          .padding({ left: 8, right: 8, top: 6, bottom: 6 })
          .keyboardAppearance(KeyboardAppearance.IMMERSIVE)
          .onChange((value: string) => {
            this.inputText = value
          })
          .onSubmit(() => {
            if (this.inputText.trim() || this.pendingAttachments.length > 0) {
              this.sendMessage()
            }
          })

        // 语音按钮
        Column() {
          SymbolGlyph($r('sys.symbol.mic'))
            .fontSize(20)
            .fontColor([this.isRecording ? Theme.ErrorColor : Theme.TextSecondary])
        }
        .width(32)
        .height(32)
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          if (this.isRecording) {
            this.stopVoiceRecording()
          } else {
            this.startVoiceRecording()
          }
        })

        // 发送按钮
        Column() {
          Image($r('app.media.ic_send'))
            .width(20)
            .height(20)
            .fillColor(this.inputText.trim() || this.pendingAttachments.length > 0 ? Theme.AccentBlue : Theme.TextTertiary)
        }
        .width(32)
        .height(32)
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          if (this.inputText.trim() || this.pendingAttachments.length > 0) {
            this.sendMessage()
          }
        })
      }
      .width('100%')
      .padding({ left: 8, right: 8 })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .constraintSize({ minHeight: 44, maxHeight: 120 })
    .backgroundColor(Theme.GlassBackground)
    .backgroundBlurStyle(BlurStyle.COMPONENT_REGULAR)
    .borderRadius(22)
    .border({ width: 0.5, color: 'rgba(255, 255, 255, 0.2)' })
    .shadow({ radius: 20, color: 'rgba(0, 0, 0, 0.3)', offsetX: 0, offsetY: 5 })
    // 静态边框发光（与 SearchBar 一致）
    .visualEffect(
      new hdsEffect.HdsEffectBuilder()
        .pointLight({
          illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER_CONTENT,
        })
        .buildEffect()
    )
    .clip(true)
    // 手指追光 —— onTouch 直接在外层 Stack（不阻止子组件触控）
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        animateTo({ duration: 100, curve: Curve.EaseIn }, () => {
          this.lightIntensity = 2.5
        })
        this.lightFingerX = event.touches[0].x
        this.lightFingerY = event.touches[0].y
      } else if (event.type === TouchType.Move) {
        animateTo({
          curve: curves.responsiveSpringMotion(0.5, 0.5)
        }, () => {
          this.lightFingerX = event.touches[0].x
          this.lightFingerY = event.touches[0].y
        })
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        animateTo({ duration: 200, curve: Curve.EaseOut }, () => {
          this.lightIntensity = 0
        })
      }
    })
  }
}
