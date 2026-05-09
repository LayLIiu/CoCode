/**
 * 会话列表页面 - 根据 Tab 类型过滤显示会话
 */

import { Theme } from '../common/Theme'
import { Constants, TabIndex } from '../common/Constants'
import { TabType, DateGroup } from '../viewmodel/ConversationModel'
import { Session, SessionStatus } from '../models/Models'
import { sessionStore } from '../stores/SessionStore'
import { storageService } from '../services/StorageService'
import { SearchBar } from '../components/SearchBar'
import { PixelMascot, MascotStatus, getMascotColorForSession } from '../components/PixelMascot'
import router from '@ohos.router'

// 分组数据结构
class SessionGroup {
  groupName: DateGroup = DateGroup.TODAY
  sessions: Session[] = []
}

// 新建对话弹窗组件
@Component
struct NewSessionDialog {
  @Link isVisible: boolean
  @Prop tabType: TabType = TabType.CLAUDE
  @State workDir: string = ''
  @State recentDirs: string[] = []
  @State isLoading: boolean = false

  aboutToAppear(): void {
    this.loadRecentDirs()
  }

  private async loadRecentDirs(): Promise<void> {
    this.recentDirs = await storageService.loadRecentWorkDirs()
  }

  private async createSession(): Promise<void> {
    if (!this.workDir.trim()) {
      return
    }

    this.isLoading = true

    const providerId = this.getProviderId()
    const sessionId = await sessionStore.createSessionWithProvider(this.workDir.trim(), providerId)

    this.isLoading = false

    if (sessionId) {
      this.isVisible = false
      sessionStore.setCurrentSession(sessionId)
      sessionStore.subscribeToSession(sessionId)

      router.pushUrl({
        url: 'pages/ChatDetailPage',
        params: {
          sessionId: sessionId,
          title: '新对话'
        }
      })
    }
  }

  private getProviderId(): string {
    if (this.tabType === TabType.CLAUDE) {
      return 'claude'
    } else if (this.tabType === TabType.CODEX) {
      return 'codex'
    } else if (this.tabType === TabType.OPEN_CODE) {
      return 'opencode'
    }
    return ''
  }

  private selectRecentDir(dir: string): void {
    this.workDir = dir
  }

  build() {
    if (this.isVisible) {
      Column() {
        Column() {
          // 标题
          Text('新建对话')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(Theme.TextPrimary)
            .width('100%')
            .textAlign(TextAlign.Center)
            .margin({ bottom: 20 })

          // 工作目录输入
          Text('工作目录')
            .fontSize(14)
            .fontColor(Theme.TextSecondary)
            .width('100%')
            .margin({ bottom: 8 })

          TextInput({ placeholder: '请输入项目路径', text: this.workDir })
            .width('100%')
            .height(44)
            .backgroundColor(Theme.BackgroundTertiary)
            .borderRadius(8)
            .fontColor(Theme.TextPrimary)
            .onChange((value: string) => {
              this.workDir = value
            })

          // 最近使用
          if (this.recentDirs.length > 0) {
            Text('最近使用')
              .fontSize(14)
              .fontColor(Theme.TextSecondary)
              .width('100%')
              .margin({ top: 16, bottom: 8 })

            Column({ space: 8 }) {
              ForEach(this.recentDirs, (dir: string, index: number) => {
                Row() {
                  SymbolGlyph($r('sys.symbol.folder'))
                    .fontSize(16)
                    .fontColor([Theme.TextSecondary])

                  Text(dir)
                    .fontSize(14)
                    .fontColor(Theme.TextPrimary)
                    .margin({ left: 8 })
                    .layoutWeight(1)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                .width('100%')
                .padding(12)
                .backgroundColor(Theme.BackgroundTertiary)
                .borderRadius(8)
                .onClick(() => {
                  this.selectRecentDir(dir)
                })
              }, (dir: string, index: number) => `dir-${index}`)
            }
            .width('100%')
            .height(this.recentDirs.length > 3 ? 150 : this.recentDirs.length * 52)
          }

          // 按钮
          Row({ space: 12 }) {
            Button('取消')
              .width('40%')
              .height(44)
              .fontSize(16)
              .fontColor(Theme.TextPrimary)
              .backgroundColor(Theme.BackgroundTertiary)
              .borderRadius(8)
              .onClick(() => {
                this.isVisible = false
              })

            Button(this.isLoading ? '创建中...' : '创建')
              .width('40%')
              .height(44)
              .fontSize(16)
              .fontColor(Theme.TextOnPrimary)
              .backgroundColor(this.workDir.trim() ? Theme.PrimaryColor : Theme.BackgroundTertiary)
              .borderRadius(8)
              .enabled(!this.isLoading && this.workDir.trim().length > 0)
              .onClick(() => {
                this.createSession()
              })
          }
          .width('100%')
          .justifyContent(FlexAlign.Center)
          .margin({ top: 24 })
        }
        .width('85%')
        .padding(24)
        .backgroundColor(Theme.BackgroundSecondary)
        .borderRadius(16)
      }
      .width('100%')
      .height('100%')
      .backgroundColor('rgba(0,0,0,0.5)')
      .justifyContent(FlexAlign.Center)
      .onClick(() => {
        this.isVisible = false
      })
    }
  }
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
          bodyColor: getMascotColorForSession(this.session.id)
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
    .backgroundColor(Theme.BackgroundSecondary)
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

  private scroller: Scroller = new Scroller()

  aboutToAppear(): void {
    if (!this.sessions) {
      this.sessions = []
    }

    sessionStore.onSessionsChanged = () => {
      this.sessions = sessionStore.sessions || []
      this.isLoading = sessionStore.isLoading
      this.refreshTrigger = Date.now()
    }

    sessionStore.onStatusChanged = (sessionId: string, status: SessionStatus) => {
      console.info(`[ConversationListPage] Status changed: ${sessionId} -> ${status}`)
      this.refreshTrigger = Date.now()
    }

    if (sessionStore.sessions && sessionStore.sessions.length > 0) {
      this.sessions = sessionStore.sessions
      this.isLoading = false
    } else {
      this.loadSessions()
    }
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
    const providerId = session.providerId || ''

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
      if (s.title.toLowerCase().includes(lowerSearch) ||
        s.projectPath.toLowerCase().includes(lowerSearch)) {
        result.push(s)
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

  build() {
    Stack() {
      // 底层：会话列表（延伸到屏幕最顶部）
      List({ space: 0, scroller: this.scroller }) {
        if (this.isLoading && (!this.sessions || this.sessions.length === 0)) {
          ListItem() {
            this.LoadingState()
          }
        } else if (this.sessions && this.sessions.length > 0) {
          // 顶部占位：让列表内容默认从搜索框下方开始，向上滑时可延伸到最顶部
          ListItem() {
            Column().width('100%').height(158)
          }
          ForEach(this.getGroupedSessionArray(), (group: SessionGroup) => {
            ListItemGroup({
              header: this.GroupHeader(group.groupName)
            }) {
              ForEach(group.sessions, (session: Session) => {
                ListItem() {
                  SessionItemView({ session: session, refreshTrigger: this.refreshTrigger })
                }
              }, (session: Session) => `${session.id}-${this.refreshTrigger}`)
            }
          }, (group: SessionGroup) => group.groupName)
        } else {
          ListItem() {
            this.EmptyState()
          }
        }
      }
      .width('100%')
      .height('100%')
      .padding({ left: Theme.SpacingLG, right: Theme.SpacingLG })
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })

      // 上层：浮动标题栏 + 搜索框（透明背景，内容可透到下方）
      Column() {
        // 导航栏按钮行
        Row() {
          // 导入会话按钮 - 液态玻璃
          Column() {
            SymbolGlyph($r('sys.symbol.arrow_down_circle'))
              .fontSize(20)
              .fontColor([Theme.TextPrimary])
          }
          .width(36)
          .height(36)
          .backgroundColor('#40FFFFFF')
          .backgroundBlurStyle(BlurStyle.COMPONENT_REGULAR)
          .shadow({ radius: 20, color: '#33000000', offsetX: 0, offsetY: 2 })
          .borderRadius(18)
          .borderWidth(1)
          .borderColor('#80FFFFFF')
          .outline({ width: 1, color: '#1A000000', radius: 18 })
          .linearGradient({ angle: 180, colors: [['#10FFFFFF', 0.0], ['#00FFFFFF', 0.3]] })
          .justifyContent(FlexAlign.Center)
          .onClick(() => {
            this.importSessions()
          })

          Text(this.pageTitle)
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor(Theme.TextPrimary)
            .layoutWeight(1)
            .textAlign(TextAlign.Center)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          // 新建对话按钮 - 液态玻璃
          Column() {
            SymbolGlyph($r('sys.symbol.plus'))
              .fontSize(20)
              .fontColor([Theme.TextPrimary])
          }
          .width(36)
          .height(36)
          .backgroundColor('#40FFFFFF')
          .backgroundBlurStyle(BlurStyle.COMPONENT_REGULAR)
          .shadow({ radius: 20, color: '#33000000', offsetX: 0, offsetY: 2 })
          .borderRadius(18)
          .borderWidth(1)
          .borderColor('#80FFFFFF')
          .outline({ width: 1, color: '#1A000000', radius: 18 })
          .linearGradient({ angle: 180, colors: [['#10FFFFFF', 0.0], ['#00FFFFFF', 0.3]] })
          .justifyContent(FlexAlign.Center)
          .onClick(() => {
            this.showNewSessionDialog = true
          })
        }
        .width('100%')
        .padding({ left: Theme.SpacingLG, right: Theme.SpacingLG })

        // 搜索框
        SearchBar({
          searchText: $searchText,
          onSearchChange: () => {
          }
        })
          .width('100%')
          .padding({ left: Theme.SpacingLG, right: Theme.SpacingLG, top: Theme.SpacingMD, bottom: Theme.SpacingMD })
      }
      .width('100%')
      .backgroundColor(Color.Transparent)
      .padding({ top: 50 })

      // 新建对话弹窗
      NewSessionDialog({
        isVisible: $showNewSessionDialog,
        tabType: this.tabType
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#121214')
    .alignContent(Alignment.Top)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
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
}
