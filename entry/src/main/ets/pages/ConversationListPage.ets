/**
 * 会话列表页面 - 根据 Tab 类型过滤显示会话
 */

import { HdsNavigation, ScrollEffectType, HdsNavigationBadgeIconOptions, HdsNavigationTitleMode } from '@hms.hds.hdsBaseComponent'
import { hdsMaterial } from '@hms.hds.hdsMaterial'
import { Theme } from '../common/Theme'
import { Constants, TabIndex } from '../common/Constants'
import { TabType, DateGroup } from '../viewmodel/ConversationModel'
import { Session, SessionStatus } from '../models/Models'
import { sessionStore } from '../stores/SessionStore'
import { storageService } from '../services/StorageService'
import { SearchBar } from '../components/SearchBar'
import { PixelMascot, MascotStatus, getMascotColorForSession, getMascotTypeForProvider } from '../components/PixelMascot'
import { ConversationListSkeleton } from '../components/SkeletonLoading'
import { toastManager } from '../services/ToastManager'
import router from '@ohos.router'
import pasteboard from '@ohos.pasteboard'
import { KeyboardAvoidMode } from '@kit.ArkUI'

// 分组数据结构
class SessionGroup {
  groupName: DateGroup = DateGroup.TODAY
  sessions: Session[] = []
}

// 会话项组件
@Component
struct SessionItemView {
  @Prop session: Session
  @Prop @Watch('onRefresh') refreshTrigger: number = 0
  @State currentStatus: SessionStatus = 'idle'

  aboutToAppear(): void {
    this.refreshStatus()
  }

  onRefresh(): void {
    this.refreshStatus()
  }

  private refreshStatus(): void {
    this.currentStatus = sessionStore.getSessionStatus(this.session.id)
  }

  private getSessionStatusText(): string {
    if (this.currentStatus !== 'idle' && this.currentStatus !== 'completed') {
      return this.getStatusText(this.currentStatus)
    }
    if (this.currentStatus === 'completed') {
      return '已完成'
    }
    return '空闲'
  }

  private getStatusText(status: SessionStatus): string {
    switch (status) {
      case 'thinking': return '思考中'
      case 'streaming': return '工作中'
      case 'tool_executing': return '执行中'
      case 'permission_pending': return '等待权限'
      case 'question_pending': return '等待回答'
      default: return ''
    }
  }

  private getStatusColor(): string {
    switch (this.currentStatus) {
      case 'thinking':
      case 'streaming':
      case 'tool_executing':
        return Theme.AccentBlue
      case 'permission_pending':
      case 'question_pending':
        return Theme.AccentOrange
      case 'completed':
        return Theme.AccentGreen
      default:
        return Theme.TextTertiary
    }
  }

  private getStatusBackground(): string {
    switch (this.currentStatus) {
      case 'thinking':
      case 'streaming':
      case 'tool_executing':
        return 'rgba(10, 132, 255, 0.14)'
      case 'permission_pending':
      case 'question_pending':
        return 'rgba(255, 159, 10, 0.16)'
      case 'completed':
        return 'rgba(48, 209, 88, 0.13)'
      default:
        return 'rgba(255, 255, 255, 0.06)'
    }
  }

  private getStatusBorderColor(): string {
    switch (this.currentStatus) {
      case 'thinking':
      case 'streaming':
      case 'tool_executing':
        return 'rgba(10, 132, 255, 0.32)'
      case 'permission_pending':
      case 'question_pending':
        return 'rgba(255, 159, 10, 0.34)'
      case 'completed':
        return 'rgba(48, 209, 88, 0.30)'
      default:
        return 'rgba(255, 255, 255, 0.07)'
    }
  }

  private getRelativeTime(): string {
    const modified = new Date(this.session.modifiedAt)
    const modifiedTime = modified.getTime()
    if (modifiedTime !== modifiedTime) return ''
    const diff = Date.now() - modifiedTime
    if (diff < 60 * 1000) return '刚刚'
    if (diff < 60 * 60 * 1000) return `${Math.floor(diff / 60000)}分钟前`
    if (diff < 24 * 60 * 60 * 1000) return `${Math.floor(diff / 3600000)}小时前`
    if (diff < 7 * 24 * 60 * 60 * 1000) return `${Math.floor(diff / 86400000)}天前`
    return `${modified.getMonth() + 1}/${modified.getDate()}`
  }

  private getMascotStatus(): MascotStatus {
    if (this.currentStatus === 'thinking' || this.currentStatus === 'streaming' || this.currentStatus === 'tool_executing') {
      return MascotStatus.PROCESSING
    } else if (this.currentStatus === 'permission_pending' || this.currentStatus === 'question_pending') {
      return MascotStatus.WAITING_APPROVAL
    } else if (this.currentStatus === 'completed') {
      return MascotStatus.COMPLETED
    }
    return MascotStatus.IDLE
  }

  private openSession(): void {
    sessionStore.setCurrentSession(this.session.id)
    sessionStore.subscribeToSession(this.session.id)

    router.pushUrl({
      url: 'pages/ChatDetailPage',
      params: {
        sessionId: this.session.id,
        title: this.session.title
      }
    })
  }

  build() {
    Column() {
      Row() {
        Row()
          .width(3)
          .height(46)
          .borderRadius(2)
          .backgroundColor(this.getStatusColor())
          .opacity(this.currentStatus === 'idle' ? 0.28 : 1)
          .margin({ right: Theme.SpacingMD })

        PixelMascot({
          mascotSize: 38,
          status: this.getMascotStatus(),
          bodyColor: getMascotColorForSession(this.session.id),
          mascotType: getMascotTypeForProvider(this.session.aiTool || '')
        })

        Column({ space: 6 }) {
          Text(this.session.title)
            .fontSize(Theme.FontBody)
            .fontColor(Theme.TextPrimary)
            .fontWeight(FontWeight.Medium)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          Row({ space: 6 }) {
            SymbolGlyph($r('sys.symbol.folder'))
              .fontSize(12)
              .fontColor([this.session.workDirExists ? Theme.TextTertiary : Theme.AccentOrange])

            Text(this.session.projectPath || this.session.workDir || '未设置工作目录')
              .fontSize(Theme.FontTiny)
              .fontColor(this.session.workDirExists ? Theme.TextSecondary : Theme.AccentOrange)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
          }
          .width('100%')
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        .margin({ left: Theme.SpacingMD })

        Column({ space: 8 }) {
          Text(this.getSessionStatusText())
            .fontSize(11)
            .fontColor(this.getStatusColor())
            .padding({ left: 8, right: 8, top: 3, bottom: 3 })
            .backgroundColor(this.getStatusBackground())
            .borderRadius(8)

          Row({ space: 6 }) {
            Text(`${this.session.messageCount}`)
              .fontSize(Theme.FontTiny)
              .fontColor(Theme.TextTertiary)

            Text(this.getRelativeTime())
              .fontSize(Theme.FontTiny)
              .fontColor(Theme.TextTertiary)
          }
        }
        .alignItems(HorizontalAlign.End)
      }
      .width('100%')
      .padding({ left: Theme.SpacingMD, right: Theme.SpacingMD, top: 14, bottom: 14 })
    }
    .width('100%')
    .backgroundColor('rgba(28, 28, 30, 0.82)')
    .border({ width: 0.5, color: this.getStatusBorderColor() })
    .borderRadius(Theme.RadiusMedium)
    .margin({ bottom: Theme.SpacingSM })
    .onClick(() => {
      this.openSession()
    })
  }
}

@Component
export struct ConversationListPage {
  @Prop tabType: TabType = TabType.CLAUDE
  @Prop pageTitle: string = Constants.TITLE_CLAUDE
  @State searchText: string = ''
  @State sessions: Session[] = []
  @State isLoading: boolean = false
  @State isSyncingOfficialCodex: boolean = false
  @State refreshTrigger: number = 0
  @State showNewSessionDialog: boolean = false

  // 新建对话表单
  @State sessionWorkDir: string = ''
  @State sessionLoading: boolean = false
  @State sessionRecentDirs: string[] = []

  private scroller: Scroller = new Scroller()
  private sessionsChangedListener: () => void = () => {}
  private statusChangedListener: (sessionId: string, status: SessionStatus) => void = () => {}
  private lastOfficialCodexSyncAt: number = 0

  private subIcon: HdsNavigationBadgeIconOptions = {
    content: {
      icon: $r('sys.symbol.arrow_down_circle'),
      action: () => { this.importSessions() }
    }
  }

  private menus: Array<HdsNavigationBadgeIconOptions> = [
    {
      content: {
        icon: $r('sys.symbol.plus'),
        action: () => { this.showNewSessionDialog = true }
      }
    }
  ]

  aboutToAppear(): void {
    if (!this.sessions) {
      this.sessions = []
    }

    // 键盘避让：使用 OFFSET 模式，让 Tab Bar 保持固定
    try {
      this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.OFFSET)
    } catch (e) {}

    this.sessionsChangedListener = () => {
      // 创建新数组引用，确保 @State 响应式更新
      this.sessions = [...(sessionStore.sessions || [])]
      this.isLoading = sessionStore.isLoading
      this.refreshTrigger = Date.now()
    }
    sessionStore.addSessionsChangedListener(this.sessionsChangedListener)

    this.statusChangedListener = (sessionId: string, status: SessionStatus) => {
      console.info(`[ConversationListPage] Status changed: ${sessionId} -> ${status}`)
      this.refreshTrigger = Date.now()
    }
    sessionStore.addStatusChangedListener(this.statusChangedListener)

    if (sessionStore.sessions && sessionStore.sessions.length > 0) {
      this.refreshSessionsFromStore()
      this.isLoading = false
      // 每次出现时同步 stale 状态（WS 断开的工作状态重置为 idle）
      sessionStore.syncSessionStatuses()
    } else {
      this.loadSessions()
    }

    this.loadRecentDirs()
    this.syncOfficialCodexThreadsIfNeeded()
  }

  onPageShow(): void {
    this.refreshSessionsFromStore()
    this.syncOfficialCodexThreadsIfNeeded()
    // 每次页面显示时重新设置键盘避让模式
    try {
      this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.OFFSET)
    } catch (e) {}
  }

  private refreshSessionsFromStore(): void {
    this.sessions = [...(sessionStore.sessions || [])]
    this.isLoading = sessionStore.isLoading
    this.refreshTrigger = Date.now()
  }

  private syncOfficialCodexThreadsIfNeeded(): void {
    if (this.tabType !== TabType.CODEX) return
    if (this.isSyncingOfficialCodex) return

    const now = Date.now()
    if (now - this.lastOfficialCodexSyncAt < 8 * 1000) return

    this.lastOfficialCodexSyncAt = now
    this.isSyncingOfficialCodex = true
    sessionStore.warmOfficialCodexControllerIfNeeded()
    void sessionStore.syncOfficialCodexThreadsToLocal(20).then(() => {
      this.refreshSessionsFromStore()
    }).catch((e: Error) => {
      console.error(`[ConversationListPage] Sync Official Codex threads error: ${e.message}`)
    }).finally(() => {
      this.isSyncingOfficialCodex = false
    })
  }

  aboutToDisappear(): void {
    sessionStore.removeSessionsChangedListener(this.sessionsChangedListener)
    sessionStore.removeStatusChangedListener(this.statusChangedListener)
  }

  // MARK: - 新建对话

  private async loadRecentDirs(): Promise<void> {
    this.sessionRecentDirs = await storageService.loadRecentWorkDirs()
  }

  private async createSessionFromSheet(): Promise<void> {
    if (!this.sessionWorkDir.trim()) return
    this.sessionLoading = true

    const providerId = this.getProviderId()
    const sessionId = await sessionStore.createSessionWithProvider(this.sessionWorkDir.trim(), providerId)
    this.sessionLoading = false

    if (sessionId) {
      this.showNewSessionDialog = false
      this.sessionWorkDir = ''
      sessionStore.setCurrentSession(sessionId)
      sessionStore.subscribeToSession(sessionId)
      router.pushUrl({
        url: 'pages/ChatDetailPage',
        params: { sessionId: sessionId, title: '新对话' }
      })
    }
  }

  private getProviderId(): string {
    if (this.tabType === TabType.CLAUDE) return 'claude'
    if (this.tabType === TabType.CODEX) return 'codex'
    if (this.tabType === TabType.OPEN_CODE) return 'opencode'
    return ''
  }

  private async loadSessions(): Promise<void> {
    this.isLoading = true

    try {
      await sessionStore.fetchSessions()
    } catch (e) {
      console.error(`[ConversationListPage] Load error: ${e}`)
    }

    this.isLoading = false
  }

  // 导入会话 - 跳转到导入页面
  private importSessions(): void {
    router.pushUrl({
      url: 'pages/ImportSessionPage',
      params: {
        tabType: this.tabType
      }
    })
  }

  // 根据 Tab 类型判断会话是否属于该 Tab
  private isSessionForTab(session: Session): boolean {
    const providerId = session.aiTool || ''

    if (this.tabType === TabType.CLAUDE) {
      return providerId === '' ||
        providerId === 'claude' ||
        providerId === 'anthropic' ||
        providerId.toLowerCase().includes('claude')
    } else if (this.tabType === TabType.CODEX) {
      return !!session.officialCodexThreadId
    } else if (this.tabType === TabType.OPEN_CODE) {
      return providerId === 'opencode' ||
        providerId === 'local' ||
        providerId.toLowerCase().includes('opencode') ||
        providerId.toLowerCase().includes('local')
    }

    return false
  }

  private getFilteredSessions(): Session[] {
    if (!this.sessions) {
      return []
    }

    let filtered: Session[] = []
    for (let i = 0; i < this.sessions.length; i++) {
      if (this.isSessionForTab(this.sessions[i])) {
        filtered.push(this.sessions[i])
      }
    }

    if (!this.searchText) {
      return filtered
    }

    const lowerSearch = this.searchText.toLowerCase()
    const result: Session[] = []
    for (let i = 0; i < filtered.length; i++) {
      const s = filtered[i]
      // 匹配标题、项目路径、工作目录
      if (s.title.toLowerCase().includes(lowerSearch) ||
        s.projectPath.toLowerCase().includes(lowerSearch) ||
        (s.workDir && s.workDir.toLowerCase().includes(lowerSearch))) {
        result.push(s)
        continue
      }
      // 匹配消息内容
      const messages = sessionStore.messages.get(s.id)
      if (messages) {
        for (let j = 0; j < messages.length; j++) {
          const msg = messages[j]
          if (msg.content && msg.content.toLowerCase().includes(lowerSearch)) {
            result.push(s)
            break
          }
        }
      }
    }
    return result
  }

  private hasFilteredSessions(): boolean {
    return this.getFilteredSessions().length > 0
  }

  private getDateGroup(timestamp: string): DateGroup {
    const date = new Date(timestamp)
    const now = new Date()
    const today = new Date(now.getFullYear(), now.getMonth(), now.getDate())
    const yesterday = new Date(today.getTime() - 24 * 60 * 60 * 1000)
    const sevenDaysAgo = new Date(today.getTime() - 7 * 24 * 60 * 60 * 1000)

    const targetDate = new Date(date.getFullYear(), date.getMonth(), date.getDate())

    if (targetDate.getTime() >= today.getTime()) {
      return DateGroup.TODAY
    } else if (targetDate.getTime() >= yesterday.getTime()) {
      return DateGroup.YESTERDAY
    } else if (targetDate.getTime() >= sevenDaysAgo.getTime()) {
      return DateGroup.LAST_SEVEN_DAYS
    } else {
      return DateGroup.EARLIER
    }
  }

  private getGroupedSessionArray(): SessionGroup[] {
    const result: SessionGroup[] = []

    const todayGroup = new SessionGroup()
    todayGroup.groupName = DateGroup.TODAY
    todayGroup.sessions = []

    const yesterdayGroup = new SessionGroup()
    yesterdayGroup.groupName = DateGroup.YESTERDAY
    yesterdayGroup.sessions = []

    const weekGroup = new SessionGroup()
    weekGroup.groupName = DateGroup.LAST_SEVEN_DAYS
    weekGroup.sessions = []

    const earlierGroup = new SessionGroup()
    earlierGroup.groupName = DateGroup.EARLIER
    earlierGroup.sessions = []

    const filtered = this.getFilteredSessions()
    if (!filtered || filtered.length === 0) {
      return result
    }

    const sorted: Session[] = []
    for (let i = 0; i < filtered.length; i++) {
      sorted.push(filtered[i])
    }

    sorted.sort((a, b) => {
      return new Date(b.modifiedAt).getTime() - new Date(a.modifiedAt).getTime()
    })

    for (let i = 0; i < sorted.length; i++) {
      const session = sorted[i]
      const group = this.getDateGroup(session.modifiedAt)
      if (group === DateGroup.TODAY) {
        todayGroup.sessions.push(session)
      } else if (group === DateGroup.YESTERDAY) {
        yesterdayGroup.sessions.push(session)
      } else if (group === DateGroup.LAST_SEVEN_DAYS) {
        weekGroup.sessions.push(session)
      } else {
        earlierGroup.sessions.push(session)
      }
    }

    if (todayGroup.sessions.length > 0) {
      result.push(todayGroup)
    }
    if (yesterdayGroup.sessions.length > 0) {
      result.push(yesterdayGroup)
    }
    if (weekGroup.sessions.length > 0) {
      result.push(weekGroup)
    }
    if (earlierGroup.sessions.length > 0) {
      result.push(earlierGroup)
    }

    return result
  }

  private getCopyableConversationId(session: Session): string {
    return session.officialCodexThreadId || session.id
  }

  private copyConversationId(session: Session): void {
    const id = this.getCopyableConversationId(session)
    try {
      const systemPasteboard = pasteboard.getSystemPasteboard()
      const pasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, id)
      systemPasteboard.setData(pasteData)
      toastManager.success('已复制对话 ID')
    } catch (e) {
      console.error(`[ConversationListPage] copy conversation id error: ${e}`)
      toastManager.error('复制失败')
    }
  }

  // 侧滑操作按钮
  @Builder
  SwipeActions(session: Session) {
    Row({ space: 8 }) {
      Button() {
        SymbolGlyph($r('sys.symbol.doc_text'))
          .fontSize(19)
          .fontColor([Color.White])
      }
      .width(50)
      .height(50)
      .borderRadius(25)
      .backgroundColor(Theme.AccentBlue)
      .onClick(() => {
        this.copyConversationId(session)
      })

      Button() {
        SymbolGlyph($r('sys.symbol.trash'))
          .fontSize(20)
          .fontColor([Color.White])
      }
      .width(50)
      .height(50)
      .borderRadius(25)
      .backgroundColor('#FF3B30')
      .onClick(async () => {
        // 本地隐藏，服务端保留，可通过导入恢复
        await sessionStore.deleteLocalSession(session.id)
      })
    }
    .margin({ right: 8 })
  }

  build() {
    Stack() {
      HdsNavigation() {
        // 会话列表（延伸到屏幕最顶部，向上滑时内容可延伸到标题栏后面）
        List({ space: 0, scroller: this.scroller }) {
          // 顶部占位：让列表内容默认从搜索框下方开始
          ListItem() {
            Column().width('100%').height(146)
          }

          if (this.isLoading && !this.hasFilteredSessions()) {
            ListItem() {
              this.LoadingState()
            }
          } else if (this.hasFilteredSessions()) {
            ForEach(this.getGroupedSessionArray(), (group: SessionGroup) => {
              ListItemGroup({
                header: this.GroupHeader(group.groupName)
              }) {
                ForEach(group.sessions, (session: Session) => {
                  ListItem() {
                    SessionItemView({
                      session: session,
                      refreshTrigger: this.refreshTrigger
                    })
                  }
                  .swipeAction({
                    end: this.SwipeActions(session),
                    edgeEffect: SwipeEdgeEffect.Spring
                  })
                }, (session: Session) => session.id)
              }
            }, (group: SessionGroup) => group.groupName)
          } else {
            ListItem() {
              this.EmptyState()
            }
          }
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: Theme.SpacingLG, right: Theme.SpacingLG })
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      }
      .titleBar({
        content: {
          title: {
            mainTitle: this.pageTitle,
          },
          subIcon: this.subIcon,
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
      .hideBackButton(true)
      .backgroundColor(Color.Transparent)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

      // 浮动搜索框（在导航栏下方，不随列表滚动）
      SearchBar({
        searchText: $searchText,
        onSearchChange: () => {
        }
      })
        .width('100%')
        .padding({ left: Theme.SpacingLG, right: Theme.SpacingLG })
        .position({ x: 0, y: 96 })

      // 新建对话弹窗改为 bindSheet
    }
    .bindSheet($$this.showNewSessionDialog, this.NewSessionSheet(), {
      height: 400, backgroundColor: '#1C1C1E', dragBar: true, showClose: false, blurStyle: BlurStyle.NONE
    })
    .width('100%')
    .height('100%')
    .backgroundColor('#121214')
  }

  @Builder
  GroupHeader(groupName: DateGroup) {
    Row() {
      Text(groupName)
        .fontSize(Theme.FontCaption)
        .fontColor(Theme.TextSecondary)
        .fontWeight(FontWeight.Medium)

      Row()
        .height(1)
        .layoutWeight(1)
        .backgroundColor('rgba(255, 255, 255, 0.06)')
        .margin({ left: Theme.SpacingMD })
    }
    .width('100%')
    .padding({ top: Theme.SpacingLG, bottom: Theme.SpacingSM })
  }

  @Builder
  LoadingState() {
    ConversationListSkeleton()
  }

  @Builder
  EmptyState() {
    Column() {
      SymbolGlyph($r('sys.symbol.inbox'))
        .fontSize(60)
        .fontColor([Theme.PrimaryColor])
        .margin({ bottom: Theme.SpacingLG })

      Text(this.getEmptyTitle())
        .fontSize(Theme.FontHeading)
        .fontColor(Theme.TextPrimary)
        .margin({ bottom: Theme.SpacingSM })

      Text(this.getEmptySubtitle())
        .fontSize(Theme.FontCaption)
        .fontColor(Theme.TextSecondary)
    }
    .width('100%')
    .height(300)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  private getEmptyTitle(): string {
    if (this.tabType === TabType.CODEX) return '暂无 Codex Desktop 对话'
    return '暂无会话'
  }

  private getEmptySubtitle(): string {
    if (this.tabType === TabType.CODEX) return '点击左上角导入，或等待后台同步 Codex Desktop 对话'
    return '点击右上角 + 开始新对话'
  }

  @Builder
  NewSessionSheet() {
    Column({ space: 4 }) {
      Row() {
        Text('新建对话')
          .fontSize(18).fontWeight(FontWeight.Bold).fontColor(Theme.TextPrimary)
          .layoutWeight(1).textAlign(TextAlign.Center)
      }
      .width('100%').padding({ bottom: 12 })

      Text('工作目录').fontSize(14).fontColor(Theme.TextSecondary).width('100%')

      TextInput({ placeholder: '请输入项目路径', text: this.sessionWorkDir })
        .width('100%').height(44)
        .backgroundColor(Theme.BackgroundTertiary).borderRadius(8)
        .fontColor(Theme.TextPrimary).fontSize(15)
        .onChange((value: string) => { this.sessionWorkDir = value })

      // 最近使用目录
      if (this.sessionRecentDirs.length > 0) {
        Text('最近使用')
          .fontSize(14).fontColor(Theme.TextSecondary).width('100%').margin({ top: 12, bottom: 8 })

        Column({ space: 8 }) {
          ForEach(this.sessionRecentDirs, (dir: string) => {
            Row() {
              SymbolGlyph($r('sys.symbol.folder')).fontSize(16).fontColor([Theme.TextSecondary])
              Text(dir).fontSize(14).fontColor(Theme.TextPrimary)
                .margin({ left: 8 }).layoutWeight(1).maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            .width('100%').padding(12)
            .backgroundColor(Theme.BackgroundTertiary).borderRadius(8)
            .onClick(() => { this.sessionWorkDir = dir })
          }, (dir: string) => `dir-${dir}`)
        }
        .width('100%').constraintSize({ maxHeight: 140 })
      }

      Row({ space: 12 }) {
        Button('取消').width('40%').height(44).fontSize(16)
          .fontColor(Theme.TextPrimary).backgroundColor(Theme.BackgroundTertiary).borderRadius(8)
          .onClick(() => { this.showNewSessionDialog = false })

        Button(this.sessionLoading ? '创建中...' : '创建').width('40%').height(44).fontSize(16)
          .fontColor(Theme.TextOnPrimary)
          .backgroundColor(this.sessionWorkDir.trim() ? Theme.PrimaryColor : Theme.BackgroundTertiary)
          .borderRadius(8)
          .enabled(!this.sessionLoading && this.sessionWorkDir.trim().length > 0)
          .onClick(() => { this.createSessionFromSheet() })
      }
      .width('100%').justifyContent(FlexAlign.Center)
    }
    .width('100%').padding(Theme.SpacingLG)
  }
}
