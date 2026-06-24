/**
 * 会话列表页面 - 根据 Tab 类型过滤显示会话
 * 参考项目分组+简洁对话列表风格
 */

import { HdsNavigation, ScrollEffectType, HdsNavigationBadgeIconOptions, HdsNavigationTitleMode } from '@hms.hds.hdsBaseComponent'
import { hdsMaterial } from '@hms.hds.hdsMaterial'
import { Theme } from '../common/Theme'
import { Constants } from '../common/Constants'
import { DateGroup } from '../viewmodel/ConversationModel'
import { Session, SessionStatus } from '../models/Models'
import { sessionStore } from '../stores/SessionStore'
import { storageService } from '../services/StorageService'
import { SearchBar } from '../components/SearchBar'
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

class ProjectSessionGroup {
  projectName: string = ''
  projectPath: string = ''
  sessions: Session[] = []
  latestModifiedAt: number = 0
  latestSessionTitle: string = ''
}

// 会话项组件 - 简洁风格：标题 + 时间 + 状态指示器
@Component
struct SessionItemView {
  @Prop session: Session
  @Prop hasUnreadCompletion: boolean = false
  onOpen?: (session: Session) => void
  @State currentStatus: SessionStatus = 'idle'
  private statusListener: ((sessionId: string, status: SessionStatus) => void) | null = null

  aboutToAppear(): void {
    this.refreshStatus()
    this.statusListener = (sessionId: string, status: SessionStatus) => {
      if (sessionId === this.session.id) {
        this.currentStatus = status
      }
    }
    sessionStore.addStatusChangedListener(this.statusListener)
  }

  aboutToDisappear(): void {
    if (this.statusListener) {
      sessionStore.removeStatusChangedListener(this.statusListener)
      this.statusListener = null
    }
  }

  private refreshStatus(): void {
    this.currentStatus = sessionStore.getSessionStatus(this.session.id)
  }

  private getRelativeTime(): string {
    // 优先使用 modifiedAt，回退到 createdAt
    const modified = new Date(this.session.modifiedAt)
    let modifiedTime = modified.getTime()
    if (Number.isNaN(modifiedTime) || modifiedTime <= 0) {
      const created = new Date(this.session.createdAt)
      modifiedTime = created.getTime()
    }
    if (Number.isNaN(modifiedTime) || modifiedTime <= 0) return ''
    const diff = Math.max(0, Date.now() - modifiedTime)
    const minute = 60 * 1000
    const hour = 60 * minute
    const day = 24 * hour
    const week = 7 * day
    const month = 30 * day
    const year = 365 * day
    if (diff >= year) return `${Math.floor(diff / year)}年前`
    if (diff >= month) return `${Math.floor(diff / month)}个月前`
    if (diff >= week) return `${Math.floor(diff / week)}周前`
    if (diff >= day) return `${Math.floor(diff / day)}天前`
    if (diff >= hour) return `${Math.floor(diff / hour)}小时前`
    if (diff >= minute) return `${Math.floor(diff / minute)}分钟前`
    return '刚刚'
  }

  private isWorking(): boolean {
    return this.currentStatus === 'thinking' ||
      this.currentStatus === 'streaming' ||
      this.currentStatus === 'tool_executing' ||
      this.currentStatus === 'permission_pending' ||
      this.currentStatus === 'question_pending'
  }

  private isHighlighted(): boolean {
    if (sessionStore.currentSessionId === this.session.id) {
      return true
    }
    return this.isWorking()
  }

  private openSession(): void {
    if (this.onOpen) {
      this.onOpen(this.session)
      return
    }
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
    Row() {
      Text(this.session.title)
        .fontSize(Theme.FontBody)
        .fontColor(Theme.TextPrimary)
        .fontWeight(this.isHighlighted() ? FontWeight.Medium : FontWeight.Regular)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)

      // 工作状态指示器
      Row() {
        if (this.isWorking()) {
          LoadingProgress()
            .width(16)
            .height(16)
            .color(Theme.AccentBlue)
        } else if (this.hasUnreadCompletion) {
          Circle()
            .width(8)
            .height(8)
            .fill(Theme.AccentBlue)
        }
      }
      .width(24)
      .height(24)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .margin({ left: 10 })

      Text(this.getRelativeTime())
        .fontSize(Theme.FontCaption)
        .fontColor(Theme.TextTertiary)
        .margin({ left: 6 })
        .flexShrink(0)
    }
    .width('100%')
    .height(44)
    .padding({ left: Theme.SpacingMD, right: Theme.SpacingMD })
    .onClick(() => {
      this.openSession()
    })
  }
}

@Component
export struct ConversationListPage {
  private static readonly PROJECT_EXPANDED_KEY: string = 'project_expanded_groups'

  @Prop pageTitle: string = Constants.TITLE_CLAUDE
  @State searchText: string = ''
  @State sessions: Session[] = []
  @State expandedProjects: Set<string> = new Set<string>()
  @State expandedStateReady: boolean = false
  @State expandedStateHasSavedValue: boolean = false
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

    // 键盘避让：使用 OFFSET 模式
    try {
      this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.OFFSET)
    } catch (e) {}

    this.sessionsChangedListener = () => {
      this.sessions = [...(sessionStore.sessions || [])]
      this.isLoading = sessionStore.isLoading
      this.refreshTrigger = Date.now()
    }
    sessionStore.addSessionsChangedListener(this.sessionsChangedListener)

    this.statusChangedListener = (sessionId: string, status: SessionStatus) => {
      console.info(`[ConversationListPage] Status changed: ${sessionId} -> ${status}`)
      this.sessions = [...(sessionStore.sessions || [])]
      this.refreshTrigger = Date.now()
    }
    sessionStore.addStatusChangedListener(this.statusChangedListener)

    if (sessionStore.sessions && sessionStore.sessions.length > 0) {
      this.refreshSessionsFromStore()
      this.isLoading = false
      sessionStore.syncSessionStatuses()
    } else {
      this.loadSessions()
    }

    this.loadRecentDirs()
    void this.loadProjectExpandState()
  }

  onPageShow(): void {
    this.refreshSessionsFromStore()
    try {
      this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.OFFSET)
    } catch (e) {}
  }

  private refreshSessionsFromStore(): void {
    this.sessions = [...(sessionStore.sessions || [])]
    this.isLoading = sessionStore.isLoading
    this.ensureExpandedProjects()
    this.refreshTrigger = Date.now()
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
      this.openSessionById(sessionId, '新对话')
    }
  }

  private async createSessionForProject(projectPath: string): Promise<void> {
    const path = projectPath.trim()
    if (path.length <= 0 || path === '未知项目') {
      this.showNewSessionDialog = true
      return
    }

    this.sessionLoading = true
    const sessionId = await sessionStore.createSessionWithProvider(path, this.getProviderId())
    this.sessionLoading = false
    if (!sessionId) {
      toastManager.error('新建对话失败')
      return
    }

    this.openSessionById(sessionId, '新对话')
  }

  private getProviderId(): string {
    return 'claude'
  }

  private openSession(session: Session): void {
    sessionStore.setCurrentSession(session.id)
    sessionStore.subscribeToSession(session.id)
    router.pushUrl({
      url: 'pages/ChatDetailPage',
      params: {
        sessionId: session.id,
        title: session.title
      }
    })
  }

  private openSessionById(sessionId: string, title: string): void {
    sessionStore.setCurrentSession(sessionId)
    sessionStore.subscribeToSession(sessionId)
    router.pushUrl({
      url: 'pages/ChatDetailPage',
      params: {
        sessionId: sessionId,
        title: title
      }
    })
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

  // 导入会话
  private importSessions(): void {
    router.pushUrl({
      url: 'pages/ImportSessionPage'
    })
  }

  private getSubIcon(): HdsNavigationBadgeIconOptions {
    return {
      content: {
        icon: $r('sys.symbol.arrow_down_circle'),
        action: () => { this.importSessions() }
      }
    }
  }

  // MARK: - 会话过滤

  private isSessionForTab(session: Session): boolean {
    const providerId = (session.aiTool || '').toLowerCase()
    return providerId === '' ||
      providerId === 'claude' ||
      providerId === 'anthropic' ||
      providerId.includes('claude')
  }

  private getFilteredSessions(): Session[] {
    if (!this.sessions) {
      return []
    }

    let filtered: Session[] = []
    for (let i = 0; i < this.sessions.length; i++) {
      if (sessionStore.isSessionArchived(this.sessions[i].id) ||
        (!!this.sessions[i].officialCodexThreadId &&
          sessionStore.isOfficialCodexThreadArchived(this.sessions[i].officialCodexThreadId || ''))) {
        continue
      }
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
        s.projectPath.toLowerCase().includes(lowerSearch) ||
        (s.workDir && s.workDir.toLowerCase().includes(lowerSearch))) {
        result.push(s)
      }
    }
    return result
  }

  private hasFilteredSessions(): boolean {
    return this.getFilteredSessions().length > 0
  }

  // MARK: - 排序

  private getSessionSortTimestamp(session: Session): number {
    const modifiedAt = new Date(session.modifiedAt).getTime()
    if (!Number.isNaN(modifiedAt) && modifiedAt > 0) {
      return modifiedAt
    }
    const createdAt = new Date(session.createdAt).getTime()
    if (!Number.isNaN(createdAt) && createdAt > 0) {
      return createdAt
    }
    return 0
  }

  private getSessionSortPriority(session: Session): number {
    const status = sessionStore.getSessionStatus(session.id)
    if (status === 'thinking' || status === 'streaming' || status === 'tool_executing') {
      return 4
    }
    if (status === 'permission_pending' || status === 'question_pending') {
      return 3
    }
    if (status === 'completed') {
      return 2
    }
    return 1
  }

  private compareSessionsForList(a: Session, b: Session): number {
    const priorityDiff = this.getSessionSortPriority(b) - this.getSessionSortPriority(a)
    if (priorityDiff !== 0) {
      return priorityDiff
    }
    return this.getSessionSortTimestamp(b) - this.getSessionSortTimestamp(a)
  }

  // MARK: - 项目分组

  private getSessionProjectName(session: Session): string {
    const rawProject = (session.workDir && session.workDir.length > 0) ? session.workDir : session.projectPath
    if (!rawProject || rawProject.length === 0 || rawProject === 'Codex Desktop') {
      return '未知项目'
    }
    const parts = rawProject.split('/').filter((part: string) => part.length > 0)
    if (parts.length === 0) {
      return rawProject
    }
    return parts[parts.length - 1]
  }

  private getSessionProjectPath(session: Session): string {
    return (session.workDir && session.workDir.length > 0) ? session.workDir : (session.projectPath || '')
  }

  private getProjectGroupPriority(group: ProjectSessionGroup): number {
    for (let i = 0; i < group.sessions.length; i++) {
      const status = sessionStore.getSessionStatus(group.sessions[i].id)
      if (status === 'thinking' || status === 'streaming' || status === 'tool_executing') {
        return 4
      }
      if (status === 'permission_pending' || status === 'question_pending') {
        return 3
      }
      if (status === 'completed') {
        return 2
      }
    }
    return 1
  }

  private getProjectGroups(): ProjectSessionGroup[] {
    const groups = new Map<string, ProjectSessionGroup>()
    const sessions = this.getFilteredSessions()

    for (let i = 0; i < sessions.length; i++) {
      const session = sessions[i]
      const projectName = this.getSessionProjectName(session)
      let group = groups.get(projectName)
      if (!group) {
        group = new ProjectSessionGroup()
        group.projectName = projectName
        group.projectPath = this.getSessionProjectPath(session)
        groups.set(projectName, group)
      } else if (group.projectPath.length <= 0) {
        group.projectPath = this.getSessionProjectPath(session)
      }
      group.sessions.push(session)

      const modifiedAt = this.getSessionSortTimestamp(session)
      if (modifiedAt > group.latestModifiedAt) {
        group.latestModifiedAt = modifiedAt
        group.latestSessionTitle = session.title
      }
    }

    const result = Array.from(groups.values())
    result.sort((a: ProjectSessionGroup, b: ProjectSessionGroup) => {
      if (a.projectName === '未知项目') return 1
      if (b.projectName === '未知项目') return -1
      const priorityDiff = this.getProjectGroupPriority(b) - this.getProjectGroupPriority(a)
      if (priorityDiff !== 0) {
        return priorityDiff
      }
      return b.latestModifiedAt - a.latestModifiedAt
    })

    for (let i = 0; i < result.length; i++) {
      result[i].sessions.sort((a: Session, b: Session) => {
        return this.compareSessionsForList(a, b)
      })
      if (result[i].sessions.length > 0) {
        result[i].latestSessionTitle = result[i].sessions[0].title
        result[i].latestModifiedAt = this.getSessionSortTimestamp(result[i].sessions[0])
      }
    }

    return result
  }

  // MARK: - 项目展开/折叠状态

  private ensureExpandedProjects(): void {
    if (!this.expandedStateReady) {
      return
    }
    if (this.expandedProjects.size > 0 || this.expandedStateHasSavedValue) {
      return
    }
    const groups = this.getProjectGroups()
    if (groups.length <= 0) {
      return
    }
    const nextExpanded = new Set<string>()
    for (let i = 0; i < groups.length; i++) {
      nextExpanded.add(groups[i].projectName)
    }
    this.expandedProjects = nextExpanded
    void this.saveProjectExpandState()
  }

  private isProjectExpanded(projectName: string): boolean {
    return this.expandedProjects.has(projectName)
  }

  private toggleProjectExpanded(projectName: string): void {
    animateTo({ duration: 200, curve: Curve.Friction }, () => {
      const nextExpanded = new Set<string>(this.expandedProjects)
      if (nextExpanded.has(projectName)) {
        nextExpanded.delete(projectName)
      } else {
        nextExpanded.add(projectName)
      }
      this.expandedProjects = nextExpanded
    })
    void this.saveProjectExpandState()
  }

  private async loadProjectExpandState(): Promise<void> {
    try {
      const raw = await storageService.loadString(ConversationListPage.PROJECT_EXPANDED_KEY, '')
      const groups = this.getProjectGroups()
      this.expandedStateHasSavedValue = raw.trim().length > 0
      if (raw.trim().length <= 0) {
        const expanded = new Set<string>()
        for (let i = 0; i < groups.length; i++) {
          expanded.add(groups[i].projectName)
        }
        this.expandedProjects = expanded
      } else {
        const parsed = JSON.parse(raw) as string[]
        const expanded = new Set<string>()
        for (let i = 0; i < parsed.length; i++) {
          const name = (parsed[i] || '').trim()
          if (name.length > 0) {
            expanded.add(name)
          }
        }
        for (let i = 0; i < groups.length; i++) {
          const projectName = groups[i].projectName
          if (!expanded.has(projectName) && raw.trim().length <= 0) {
            expanded.add(projectName)
          }
        }
        this.expandedProjects = expanded
      }
    } catch (e) {
      console.error(`[ConversationListPage] loadProjectExpandState error: ${e}`)
      const groups = this.getProjectGroups()
      const expanded = new Set<string>()
      for (let i = 0; i < groups.length; i++) {
        expanded.add(groups[i].projectName)
      }
      this.expandedProjects = expanded
    } finally {
      this.expandedStateReady = true
      this.ensureExpandedProjects()
      this.refreshTrigger = Date.now()
    }
  }

  private async saveProjectExpandState(): Promise<void> {
    try {
      const values = Array.from(this.expandedProjects.values())
      await storageService.saveString(ConversationListPage.PROJECT_EXPANDED_KEY, JSON.stringify(values))
      this.expandedStateHasSavedValue = true
    } catch (e) {
      console.error(`[ConversationListPage] saveProjectExpandState error: ${e}`)
    }
  }

  // MARK: - 复制对话 ID

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
        SymbolGlyph($r('sys.symbol.archivebox'))
          .fontSize(19)
          .fontColor([Color.White])
      }
      .width(50)
      .height(50)
      .borderRadius(25)
      .backgroundColor(Theme.AccentOrange)
      .onClick(async () => {
        await sessionStore.archiveSession(session.id)
        toastManager.success('已归档')
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
        await sessionStore.deleteLocalSession(session.id)
      })
    }
    .margin({ right: 8 })
  }

  // MARK: - 页面构建

  build() {
    Stack() {
      HdsNavigation() {
        List({ space: 0, scroller: this.scroller }) {
          // 顶部占位
          ListItem() {
            Column().width('100%').height(156)
          }

          if (this.isLoading && !this.hasFilteredSessions()) {
            ListItem() {
              this.LoadingState()
            }
          } else if (this.hasFilteredSessions()) {
            ForEach(this.getProjectGroups(), (group: ProjectSessionGroup) => {
              ListItemGroup({
                header: this.ProjectHeader(group, this.isProjectExpanded(group.projectName))
              }) {
                if (this.isProjectExpanded(group.projectName)) {
                  ForEach(group.sessions, (session: Session) => {
                    ListItem() {
                      SessionItemView({
                        session: session,
                        hasUnreadCompletion: false,
                        onOpen: (target: Session) => this.openSession(target)
                      })
                    }
                    .swipeAction({
                      end: this.SwipeActions(session),
                      edgeEffect: SwipeEdgeEffect.Spring
                    })
                  }, (session: Session) => session.id)
                }
              }
            }, (group: ProjectSessionGroup) => group.projectName)
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
          subIcon: this.getSubIcon(),
          menu: { value: this.menus },
        },
        style: {
          scrollEffectOpts: {
            enableScrollEffect: false,
            scrollEffectType: ScrollEffectType.GRADIENT_BLUR,
          },
          systemMaterialEffect: {
            materialType: hdsMaterial.MaterialType.ADAPTIVE,
            materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
          },
        },
        avoidLayoutSafeArea: true,
        enableComponentSafeArea: false,
      })
      .titleMode(HdsNavigationTitleMode.MINI)
      .hideBackButton(true)
      .backgroundColor(Color.Transparent)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

      // 浮动搜索框
      SearchBar({
        searchText: $searchText,
        onSearchChange: () => {
        }
      })
        .width('100%')
        .padding({ left: Theme.SpacingLG, right: Theme.SpacingLG })
        .position({ x: 0, y: 96 })
    }
    .bindSheet($$this.showNewSessionDialog, this.NewSessionSheet(), {
      height: 400, backgroundColor: '#0E0E10', dragBar: true, showClose: false, blurStyle: BlurStyle.NONE
    })
    .width('100%')
    .height('100%')
    .backgroundColor('#000000')
  }

  @Builder
  ProjectHeader(group: ProjectSessionGroup, expanded: boolean) {
    Row() {
      Row({ space: 10 }) {
        SymbolGlyph($r('sys.symbol.folder'))
          .fontSize(21)
          .fontColor(['#8E8E93'])

        Text(group.projectName)
          .fontSize(18)
          .fontColor('#8E8E93')
          .fontWeight(FontWeight.Medium)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        SymbolGlyph(expanded ? $r('sys.symbol.chevron_down') : $r('sys.symbol.chevron_right'))
          .fontSize(14)
          .fontColor(['#8E8E93'])
      }
      .layoutWeight(1)
      .height(44)
      .onClick(() => {
        this.toggleProjectExpanded(group.projectName)
      })

      Button() {
        SymbolGlyph($r('sys.symbol.square_and_pencil'))
          .fontSize(20)
          .fontColor(['#8E8E93'])
      }
      .width(44)
      .height(44)
      .backgroundColor(Color.Transparent)
      .onClick(() => {
        void this.createSessionForProject(group.projectPath)
      })
    }
    .width('100%')
    .height(56)
    .padding({ top: 12, bottom: 0, left: 4, right: 0 })
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
