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
import router from '@ohos.router'

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
  private statusCheckTimer: number = -1

  aboutToAppear(): void {
    this.refreshStatus()
    this.statusCheckTimer = setInterval(() => {
      const latestStatus = sessionStore.getSessionStatus(this.session.id)
      if (latestStatus !== this.currentStatus) {
        this.currentStatus = latestStatus
      }
    }, 500)
  }

  aboutToDisappear(): void {
    if (this.statusCheckTimer !== -1) {
      clearInterval(this.statusCheckTimer)
      this.statusCheckTimer = -1
    }
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
    return ''
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
        PixelMascot({
          mascotSize: 40,
          status: this.getMascotStatus(),
          bodyColor: getMascotColorForSession(this.session.id),
          mascotType: getMascotTypeForProvider(this.session.aiTool || '')
        })

        Column({ space: 4 }) {
          Text(this.session.title)
            .fontSize(Theme.FontBody)
            .fontColor(Theme.TextPrimary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          Text(this.session.projectPath)
            .fontSize(Theme.FontTiny)
            .fontColor(Theme.TextSecondary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        .margin({ left: Theme.SpacingMD })

        Column({ space: 4 }) {
          if (this.getSessionStatusText() !== '') {
            Text(this.getSessionStatusText())
              .fontSize(Theme.FontTiny)
              .fontColor(Theme.AccentGreen)
          }

          Text(`${this.session.messageCount}`)
            .fontSize(Theme.FontTiny)
            .fontColor(Theme.TextTertiary)
        }
        .alignItems(HorizontalAlign.End)
      }
      .width('100%')
      .padding(Theme.SpacingMD)
    }
    .width('100%')
    .backgroundColor('#1C1C1E')
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
  @State refreshTrigger: number = 0
  @State showNewSessionDialog: boolean = false

  // 新建对话表单
  @State sessionWorkDir: string = ''
  @State sessionLoading: boolean = false
  @State sessionRecentDirs: string[] = []

  private scroller: Scroller = new Scroller()
  private sessionsChangedListener: () => void = () => {}
  private statusChangedListener: (sessionId: string, status: SessionStatus) => void = () => {}

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

    this.sessionsChangedListener = () => {
      this.sessions = sessionStore.sessions || []
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
      this.sessions = sessionStore.sessions
      this.isLoading = false
    } else {
      this.loadSessions()
    }

    this.loadRecentDirs()
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
      return providerId === 'codex' ||
        providerId === 'openai' ||
        providerId.toLowerCase().includes('codex') ||
        providerId.toLowerCase().includes('openai')
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

  // 侧滑删除按钮
  @Builder
  SwipeDeleteButton(sessionId: string) {
    Button() {
      SymbolGlyph($r('sys.symbol.trash'))
        .fontSize(20)
        .fontColor([Color.White])
    }
    .width(50)
    .height(50)
    .borderRadius(25)
    .backgroundColor('#FF3B30')
    .margin({ right: 8 })
    .onClick(() => {
      // 直接调用删除
      sessionStore.deleteLocalSession(sessionId)
    })
  }

  build() {
    Stack() {
      HdsNavigation() {
        // 会话列表（延伸到屏幕最顶部，向上滑时内容可延伸到标题栏后面）
        List({ space: 0, scroller: this.scroller }) {
          // 顶部占位：让列表内容默认从搜索框下方开始
          ListItem() {
            Column().width('100%').height(135)
          }

          if (this.isLoading && (!this.sessions || this.sessions.length === 0)) {
            ListItem() {
              this.LoadingState()
            }
          } else if (this.sessions && this.sessions.length > 0) {
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
                    end: this.SwipeDeleteButton(session.id),
                    edgeEffect: SwipeEdgeEffect.Spring
                  })
                }, (session: Session) => `${session.id}_${this.refreshTrigger}`)
              }
            }, (group: SessionGroup) => `${group.groupName}_${this.refreshTrigger}`)
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
    Text(groupName)
      .fontSize(Theme.FontCaption)
      .fontColor(Theme.TextSecondary)
      .width('100%')
      .padding({ top: Theme.SpacingLG, bottom: Theme.SpacingSM })
  }

  @Builder
  LoadingState() {
    Column() {
      LoadingProgress()
        .width(40)
        .height(40)
        .color(Theme.PrimaryColor)

      Text('加载中...')
        .fontSize(Theme.FontBody)
        .fontColor(Theme.TextSecondary)
        .margin({ top: Theme.SpacingMD })
    }
    .width('100%')
    .height(300)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  EmptyState() {
    Column() {
      SymbolGlyph($r('sys.symbol.inbox'))
        .fontSize(60)
        .fontColor([Theme.PrimaryColor])
        .margin({ bottom: Theme.SpacingLG })

      Text('暂无会话')
        .fontSize(Theme.FontHeading)
        .fontColor(Theme.TextPrimary)
        .margin({ bottom: Theme.SpacingSM })

      Text('点击右上角 + 开始新对话')
        .fontSize(Theme.FontCaption)
        .fontColor(Theme.TextSecondary)
    }
    .width('100%')
    .height(300)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
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
