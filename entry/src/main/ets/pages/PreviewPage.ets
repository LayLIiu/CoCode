/**
 * Preview 页面 - 参考 codex-relay WorkspacePreviewSurface
 * 包含 Git、文件树、Markdown、Web、终端 SSH 等标签页
 * 所有功能接入真实 API
 */

import { Theme } from '../common/Theme'
import { sessionStore } from '../stores/SessionStore'
import {
  apiService, FsEntry,
  GitStatusResponse, GitStatusFile, GitCommitItem, GitBranchItem,
  GitCommitResponse, GitPushResponse, GitCreatePRRequest
} from '../services/APIService'
import { HdsNavigation, HdsNavigationTitleMode, ScrollEffectType } from '@hms.hds.hdsBaseComponent'
import { hdsMaterial } from '@hms.hds.hdsMaterial'
import { curves } from '@kit.ArkUI'
import router from '@ohos.router'

// 标签页类型
type TabType = 'git' | 'files' | 'markdown' | 'web' | 'ssh'

// 标签页定义
interface TabDefinition {
  type: TabType
  icon: Resource
  label: string
  subtitle: string
}

const TAB_DEFINITIONS: TabDefinition[] = [
  { type: 'git', icon: $r('sys.symbol.arrow_counterclockwise'), label: 'Git', subtitle: '查看和发布代码变更' },
  { type: 'files', icon: $r('sys.symbol.folder'), label: '文件', subtitle: '浏览项目文件' },
  { type: 'markdown', icon: $r('sys.symbol.doc_text'), label: 'Markdown', subtitle: '预览 Markdown 文档' },
  { type: 'web', icon: $r('sys.symbol.magnifyingglass'), label: 'Web', subtitle: '打开本地 Web 预览' },
  { type: 'ssh', icon: $r('sys.symbol.gearshape'), label: '终端', subtitle: 'SSH 终端连接' }
]

// 文件树项
class FlatItem {
  entry: FsEntry = new FsEntry('', '', false)
  depth: number = 0
  constructor(entry: FsEntry, depth: number) { this.entry = entry; this.depth = depth }
}

@Entry
@Component
struct PreviewPage {
  @State sessionId: string = ''
  @State workspacePath: string = ''
  @State activeTab: TabType = 'files'

  // Git 状态
  @State gitStatus: GitStatusResponse | null = null
  @State isLoadingGit: boolean = false
  @State gitError: string = ''
  @State gitSuccess: string = ''

  // Git 提交
  @State commitMessage: string = ''
  @State showCommitSheet: boolean = false
  @State isCommitting: boolean = false

  // Git 分支
  @State branches: GitBranchItem[] = []
  @State showBranchSheet: boolean = false
  @State currentBranch: string = ''

  // Git 日志
  @State gitCommits: GitCommitItem[] = []
  @State showGitLog: boolean = false

  // 创建 PR
  @State showPRSheet: boolean = false
  @State prTitle: string = ''
  @State prBody: string = ''
  @State prHead: string = ''
  @State prBase: string = 'main'
  @State isCreatingPR: boolean = false

  // 文件树
  @State rootEntries: FsEntry[] = []
  @State flatItems: FlatItem[] = []
  @State isLoadingFiles: boolean = false
  @State currentDirectory: string = ''

  // Markdown 预览
  @State markdownPath: string = ''
  @State markdownHtml: string = ''
  @State isLoadingMarkdown: boolean = false
  @State markdownError: string = ''

  // Web 预览
  @State webUrl: string = ''
  @State webInputUrl: string = ''
  @State webPreviewPort: number = 0
  @State isWebPreviewRunning: boolean = false

  // SSH
  @State sshHost: string = ''
  @State sshPort: string = '22'
  @State sshUser: string = ''
  @State sshPassword: string = ''
  @State sshSessionId: string = ''
  @State sshConnected: boolean = false
  @State sshOutput: string = ''
  @State sshCommand: string = ''
  @State sshError: string = ''

  aboutToAppear(): void {
    const params = router.getParams() as Record<string, string>
    if (params) {
      if (params['sessionId']) {
        this.sessionId = params['sessionId']
      }
      if (params['tab']) {
        this.activeTab = params['tab'] as TabType
      }
    }
    this.loadWorkspace()
  }

  private async loadWorkspace(): Promise<void> {
    const session = sessionStore.sessions.find(s => s.id === this.sessionId)
    if (session?.workDir) {
      this.workspacePath = session.workDir
    } else if (session?.projectPath) {
      this.workspacePath = session.projectPath
    }
    // 加载文件树
    await this.loadFiles()
  }

  // MARK: - 文件树

  private async loadFiles(): Promise<void> {
    this.isLoadingFiles = true
    const dir = this.currentDirectory || this.workspacePath
    if (dir) {
      this.rootEntries = await apiService.browseDirectory(dir)
      this.flattenEntries()
    }
    this.isLoadingFiles = false
  }

  private flattenEntries(): void {
    const result: FlatItem[] = []
    this.doFlatten(this.rootEntries, 0, result)
    this.flatItems = result
  }

  private doFlatten(list: FsEntry[], depth: number, out: FlatItem[]): void {
    for (let i = 0; i < list.length; i++) {
      const e = list[i]
      out.push(new FlatItem(e, depth))
      if (e.isDir && e.isExpanded && e.children) {
        this.doFlatten(e.children, depth + 1, out)
      }
    }
  }

  private async toggleDir(entry: FsEntry): Promise<void> {
    if (!entry.isDir) return
    if (entry.isExpanded) {
      entry.isExpanded = false
      entry.children = null
    } else {
      entry.isExpanded = true
      entry.children = await apiService.browseDirectory(entry.fullPath)
    }
    this.flattenEntries()
  }

  // MARK: - Git

  private async loadGitStatus(): Promise<void> {
    if (!this.workspacePath) return

    this.isLoadingGit = true
    this.gitError = ''
    this.gitSuccess = ''

    try {
      this.gitStatus = await apiService.getGitStatus(this.workspacePath)
      this.currentBranch = this.gitStatus.branch
    } catch (e) {
      this.gitError = `加载 Git 状态失败: ${(e as Error).message}`
    }

    this.isLoadingGit = false
  }

  private async loadGitBranches(): Promise<void> {
    if (!this.workspacePath) return

    try {
      const response = await apiService.gitBranch(this.workspacePath)
      this.branches = response.branches
      this.currentBranch = response.current
    } catch (e) {
      console.error(`加载分支失败: ${e}`)
    }
  }

  private async loadGitLog(): Promise<void> {
    if (!this.workspacePath) return

    try {
      const response = await apiService.gitLog(this.workspacePath, 30)
      this.gitCommits = response.commits
      this.showGitLog = true
    } catch (e) {
      this.gitError = `加载提交历史失败: ${(e as Error).message}`
    }
  }

  private async gitAddAll(): Promise<void> {
    if (!this.workspacePath || !this.gitStatus) return

    try {
      const allFiles: string[] = []
      this.gitStatus.unstaged.forEach(f => allFiles.push(f.path))
      this.gitStatus.untracked.forEach(f => allFiles.push(f.path))

      if (allFiles.length === 0) return

      await apiService.gitAdd(this.workspacePath, allFiles)
      await this.loadGitStatus()
      this.gitSuccess = '已添加所有文件到暂存区'
    } catch (e) {
      this.gitError = `添加文件失败: ${(e as Error).message}`
    }
  }

  private async doCommit(): Promise<void> {
    if (!this.workspacePath || !this.commitMessage.trim()) return

    this.isCommitting = true
    try {
      const response = await apiService.gitCommit(this.workspacePath, this.commitMessage.trim())
      this.commitMessage = ''
      this.showCommitSheet = false
      await this.loadGitStatus()
      this.gitSuccess = `提交成功: ${response.sha.substring(0, 7)}`
    } catch (e) {
      this.gitError = `提交失败: ${(e as Error).message}`
    }
    this.isCommitting = false
  }

  private async doPush(): Promise<void> {
    if (!this.workspacePath) return

    this.isLoadingGit = true
    try {
      const response = await apiService.gitPush(this.workspacePath)
      if (response.success) {
        this.gitSuccess = `推送成功: ${response.remote}/${response.branch}`
        await this.loadGitStatus()
      } else {
        this.gitError = `推送失败: ${response.message}`
      }
    } catch (e) {
      this.gitError = `推送失败: ${(e as Error).message}`
    }
    this.isLoadingGit = false
  }

  private async doPull(): Promise<void> {
    if (!this.workspacePath) return

    this.isLoadingGit = true
    try {
      const response = await apiService.gitPull(this.workspacePath)
      if (response.success) {
        this.gitSuccess = `拉取成功: ${response.message || '已完成'}`
        await this.loadGitStatus()
      } else {
        this.gitError = `拉取失败: ${response.message}`
      }
    } catch (e) {
      this.gitError = `拉取失败: ${(e as Error).message}`
    }
    this.isLoadingGit = false
  }

  private async doCommitAndPush(): Promise<void> {
    // 如果有未暂存的文件，先添加
    if (this.gitStatus && (this.gitStatus.unstaged.length > 0 || this.gitStatus.untracked.length > 0)) {
      await this.gitAddAll()
    }
    // 打开提交对话框
    this.showCommitSheet = true
  }

  private async checkoutBranch(branch: string): Promise<void> {
    if (!this.workspacePath) return

    try {
      await apiService.gitCheckout(this.workspacePath, branch)
      this.currentBranch = branch
      await this.loadGitStatus()
      this.showBranchSheet = false
      this.gitSuccess = `已切换到分支: ${branch}`
    } catch (e) {
      this.gitError = `切换分支失败: ${(e as Error).message}`
    }
  }

  private async doCreatePR(): Promise<void> {
    if (!this.workspacePath || !this.prTitle.trim()) return

    this.isCreatingPR = true
    try {
      const request: GitCreatePRRequest = {
        title: this.prTitle.trim(),
        body: this.prBody.trim(),
        head: this.prHead || this.currentBranch,
        base: this.prBase
      }
      const response = await apiService.createPullRequest(this.workspacePath, request)
      if (response.success) {
        this.gitSuccess = `PR #${response.number} 创建成功: ${response.url}`
        this.showPRSheet = false
        this.prTitle = ''
        this.prBody = ''
      } else {
        this.gitError = `创建 PR 失败: ${response.message}`
      }
    } catch (e) {
      this.gitError = `创建 PR 失败: ${(e as Error).message}`
    }
    this.isCreatingPR = false
  }

  private getAllChangedFiles(): GitStatusFile[] {
    if (!this.gitStatus) return []
    return [
      ...this.gitStatus.staged,
      ...this.gitStatus.unstaged,
      ...this.gitStatus.untracked
    ]
  }

  private getStatusColor(status: string): string {
    switch (status) {
      case 'modified': return Theme.WarningColor
      case 'added': return Theme.SuccessColor
      case 'deleted': return Theme.ErrorColor
      case 'renamed': return Theme.AccentBlue
      default: return Theme.TextTertiary
    }
  }

  private getStatusLabel(status: string): string {
    switch (status) {
      case 'modified': return 'M'
      case 'added': return 'A'
      case 'deleted': return 'D'
      case 'renamed': return 'R'
      case 'untracked': return '?'
      default: return '?'
    }
  }

  // MARK: - Markdown

  private async loadMarkdown(path: string): Promise<void> {
    this.markdownPath = path
    this.isLoadingMarkdown = true
    this.markdownError = ''

    try {
      const response = await apiService.renderMarkdown(path)
      this.markdownHtml = response.html
    } catch (e) {
      this.markdownError = `渲染失败: ${(e as Error).message}`
    }

    this.isLoadingMarkdown = false
  }

  // MARK: - Web Preview

  private async startWebPreview(): Promise<void> {
    if (!this.workspacePath) return

    try {
      const response = await apiService.startWebPreview(this.workspacePath, 0, this.webInputUrl || '/')
      this.webUrl = response.url
      this.webPreviewPort = response.port
      this.isWebPreviewRunning = true
    } catch (e) {
      console.error(`启动 Web 预览失败: ${e}`)
    }
  }

  private async stopWebPreview(): Promise<void> {
    if (!this.workspacePath || !this.webPreviewPort) return

    try {
      await apiService.stopWebPreview(this.workspacePath, this.webPreviewPort)
      this.isWebPreviewRunning = false
      this.webUrl = ''
      this.webPreviewPort = 0
    } catch (e) {
      console.error(`停止 Web 预览失败: ${e}`)
    }
  }

  // MARK: - SSH

  private async sshConnect(): Promise<void> {
    if (!this.sshHost || !this.sshUser) return

    this.sshError = ''

    try {
      const response = await apiService.sshConnect({
        host: this.sshHost,
        port: parseInt(this.sshPort) || 22,
        user: this.sshUser,
        password: this.sshPassword
      })

      if (response.success) {
        this.sshSessionId = response.sessionId
        this.sshConnected = true
        this.sshOutput = `已连接到 ${this.sshUser}@${this.sshHost}\n`
      } else {
        this.sshError = `连接失败: ${response.message}`
      }
    } catch (e) {
      this.sshError = `连接失败: ${(e as Error).message}`
    }
  }

  private async sshDisconnect(): Promise<void> {
    if (!this.sshSessionId) return

    try {
      await apiService.sshDisconnect(this.sshSessionId)
      this.sshConnected = false
      this.sshSessionId = ''
      this.sshOutput += '\n已断开连接\n'
    } catch (e) {
      this.sshError = `断开失败: ${(e as Error).message}`
    }
  }

  private async sshExecute(): Promise<void> {
    if (!this.sshSessionId || !this.sshCommand.trim()) return

    try {
      const response = await apiService.sshExecute(this.sshSessionId, this.sshCommand.trim())
      this.sshOutput += `$ ${this.sshCommand}\n${response.output}\n`
      this.sshCommand = ''
    } catch (e) {
      this.sshError = `执行失败: ${(e as Error).message}`
    }
  }

  build() {
    Column() {
      // 标题栏
      this.HeaderBar()

      // 标签页栏
      this.TabStrip()

      // 内容区域
      Column() {
        if (this.activeTab === 'git') {
          this.GitTabContent()
        } else if (this.activeTab === 'files') {
          this.FilesTabContent()
        } else if (this.activeTab === 'markdown') {
          this.MarkdownTabContent()
        } else if (this.activeTab === 'web') {
          this.WebTabContent()
        } else if (this.activeTab === 'ssh') {
          this.SshTabContent()
        }
      }
      .layoutWeight(1)
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .linearGradient({
      angle: 180,
      colors: [
        [Theme.BackgroundGradientStart, 0.0],
        [Theme.BackgroundGradientMiddle, 0.5],
        [Theme.BackgroundGradientEnd, 1.0]
      ]
    })
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .bindSheet($$this.showCommitSheet, this.CommitSheet(), {
      height: 320,
      backgroundColor: Theme.BackgroundPrimary,
      dragBar: true
    })
    .bindSheet($$this.showBranchSheet, this.BranchSheet(), {
      height: 400,
      backgroundColor: Theme.BackgroundPrimary,
      dragBar: true
    })
    .bindSheet($$this.showPRSheet, this.PRSheet(), {
      height: 450,
      backgroundColor: Theme.BackgroundPrimary,
      dragBar: true
    })
  }

  @Builder
  HeaderBar() {
    Row() {
      // 返回按钮
      Row() {
        SymbolGlyph($r('sys.symbol.chevron_left'))
          .fontSize(18)
          .fontColor([Theme.TextPrimary])
      }
      .width(36)
      .height(36)
      .backgroundColor('rgba(255, 255, 255, 0.08)')
      .borderRadius(18)
      .justifyContent(FlexAlign.Center)
      .onClick(() => {
        router.back()
      })

      // 标题
      Column({ space: 2 }) {
        Text('Preview')
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.TextPrimary)

        if (this.workspacePath) {
          Text(this.workspacePath.split('/').pop() || this.workspacePath)
            .fontSize(10)
            .fontColor(Theme.TextTertiary)
            .maxLines(1)
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Center)

      // 占位
      Row().width(36).height(36)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 56, bottom: 8 })
  }

  @Builder
  TabStrip() {
    Scroll() {
      Row({ space: 4 }) {
        ForEach(TAB_DEFINITIONS, (tabDef: TabDefinition) => {
          Row({ space: 4 }) {
            SymbolGlyph(tabDef.icon)
              .fontSize(12)
              .fontColor([this.activeTab === tabDef.type ? Theme.TextPrimary : Theme.TextSecondary])

            Text(tabDef.label)
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.activeTab === tabDef.type ? Theme.TextPrimary : Theme.TextSecondary)
          }
          .padding({ left: 10, right: 10, top: 6, bottom: 6 })
          .backgroundColor(this.activeTab === tabDef.type ? 'rgba(255, 255, 255, 0.1)' : 'transparent')
          .borderRadius(8)
          .onClick(() => {
            this.activeTab = tabDef.type
          })
        }, (tabDef: TabDefinition) => tabDef.type)
      }
      .padding({ left: 4, right: 4 })
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
    .padding({ left: 12, right: 12, top: 6, bottom: 6 })
    .backgroundColor('rgba(255, 255, 255, 0.03)')
    .borderRadius(10)
    .margin({ left: 12, right: 12, bottom: 8 })
  }

  // MARK: - Git 标签页内容

  @Builder
  GitTabContent() {
    Column({ space: 12 }) {
      // 成功/错误提示
      if (this.gitSuccess) {
        Row({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.checkmark_circle_fill'))
            .fontSize(14)
            .fontColor([Theme.SuccessColor])
          Text(this.gitSuccess)
            .fontSize(12)
            .fontColor(Theme.SuccessColor)
            .layoutWeight(1)
        }
        .width('100%')
        .padding(10)
        .backgroundColor('rgba(34, 197, 94, 0.1)')
        .borderRadius(8)
      }

      if (this.gitError) {
        Row({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.exclamationmark_triangle_fill'))
            .fontSize(14)
            .fontColor([Theme.ErrorColor])
          Text(this.gitError)
            .fontSize(12)
            .fontColor(Theme.ErrorColor)
            .layoutWeight(1)
        }
        .width('100%')
        .padding(10)
        .backgroundColor('rgba(239, 68, 68, 0.1)')
        .borderRadius(8)
      }

      if (this.isLoadingGit) {
        Column() {
          LoadingProgress()
            .width(30)
            .height(30)
            .color(Theme.PrimaryColor)
        }
        .width('100%')
        .height(200)
        .justifyContent(FlexAlign.Center)
      } else if (this.gitStatus) {
        // 分支信息
        Row({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.arrow_counterclockwise'))
            .fontSize(14)
            .fontColor([Theme.AccentBlue])

          Text(this.gitStatus.branch)
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(Theme.TextPrimary)

          Blank()

          if (this.gitStatus.ahead > 0) {
            Text(`↑${this.gitStatus.ahead}`)
              .fontSize(11)
              .fontColor(Theme.SuccessColor)
          }
          if (this.gitStatus.behind > 0) {
            Text(`↓${this.gitStatus.behind}`)
              .fontSize(11)
              .fontColor(Theme.WarningColor)
          }

          // 切换分支按钮
          Row() {
            SymbolGlyph($r('sys.symbol.chevron_down'))
              .fontSize(10)
              .fontColor([Theme.TextTertiary])
          }
          .padding(4)
          .backgroundColor('rgba(255, 255, 255, 0.06)')
          .borderRadius(4)
          .onClick(async () => {
            await this.loadGitBranches()
            this.showBranchSheet = true
          })
        }
        .width('100%')
        .padding(12)
        .backgroundColor('rgba(255, 255, 255, 0.04)')
        .borderRadius(10)

        // 操作按钮
        Row({ space: 8 }) {
          Button('提交并推送')
            .fontSize(12)
            .fontColor(Theme.TextOnPrimary)
            .backgroundColor(Theme.SuccessColor)
            .borderRadius(8)
            .layoutWeight(1)
            .height(36)
            .enabled(this.gitStatus.hasChanges)
            .opacity(this.gitStatus.hasChanges ? 1 : 0.5)
            .onClick(() => {
              this.doCommitAndPush()
            })

          Button('创建 PR')
            .fontSize(12)
            .fontColor(Theme.AccentBlue)
            .backgroundColor('rgba(10, 132, 255, 0.1)')
            .borderRadius(8)
            .layoutWeight(1)
            .height(36)
            .onClick(() => {
              if (this.gitStatus) {
                this.prHead = this.gitStatus.branch
              }
              this.showPRSheet = true
            })
        }
        .width('100%')

        // 拉取按钮
        Row({ space: 8 }) {
          Button('拉取')
            .fontSize(12)
            .fontColor(Theme.TextPrimary)
            .backgroundColor('rgba(255, 255, 255, 0.08)')
            .borderRadius(8)
            .layoutWeight(1)
            .height(36)
            .onClick(() => {
              this.doPull()
            })

          Button('查看日志')
            .fontSize(12)
            .fontColor(Theme.TextPrimary)
            .backgroundColor('rgba(255, 255, 255, 0.08)')
            .borderRadius(8)
            .layoutWeight(1)
            .height(36)
            .onClick(() => {
              this.loadGitLog()
            })
        }
        .width('100%')

        // 变更文件列表
        if (this.getAllChangedFiles().length > 0) {
          Row() {
            Text('变更文件')
              .fontSize(13)
              .fontWeight(FontWeight.Bold)
              .fontColor(Theme.TextSecondary)

            Blank()

            Text(`${this.getAllChangedFiles().length} 个文件`)
              .fontSize(11)
              .fontColor(Theme.TextTertiary)
          }
          .width('100%')
          .margin({ top: 8 })

          Column({ space: 4 }) {
            ForEach(this.getAllChangedFiles(), (file: GitStatusFile) => {
              this.GitFileRow(file)
            }, (file: GitStatusFile) => file.path + '-' + file.status)
          }
          .width('100%')
        } else {
          Column({ space: 8 }) {
            SymbolGlyph($r('sys.symbol.checkmark_circle_fill'))
              .fontSize(24)
              .fontColor([Theme.SuccessColor])
            Text('工作区干净，没有待提交的变更')
              .fontSize(14)
              .fontColor(Theme.TextSecondary)
          }
          .width('100%')
          .height(150)
          .justifyContent(FlexAlign.Center)
        }
      } else {
        // 初始状态 - 加载 Git
        Column({ space: 12 }) {
          SymbolGlyph($r('sys.symbol.arrow_counterclockwise'))
            .fontSize(40)
            .fontColor([Theme.TextTertiary])

          Text('Git 状态')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor(Theme.TextPrimary)

          Text('点击下方按钮加载 Git 状态')
            .fontSize(13)
            .fontColor(Theme.TextSecondary)

          Button('加载 Git 状态')
            .fontSize(14)
            .fontColor(Theme.TextOnPrimary)
            .backgroundColor(Theme.PrimaryColor)
            .borderRadius(10)
            .width(160)
            .height(40)
            .onClick(() => {
              this.loadGitStatus()
            })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      }
    }
    .width('100%')
    .padding(16)
    .layoutWeight(1)
  }

  @Builder
  GitFileRow(file: GitStatusFile) {
    Row({ space: 8 }) {
      // 状态指示器
      Row() {
        Text(this.getStatusLabel(file.status))
          .fontSize(9)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.TextOnPrimary)
      }
      .width(18)
      .height(18)
      .borderRadius(4)
      .backgroundColor(this.getStatusColor(file.status))
      .justifyContent(FlexAlign.Center)

      // 文件路径
      Text(file.path)
        .fontSize(12)
        .fontColor(Theme.TextPrimary)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
    }
    .width('100%')
    .padding({ top: 6, bottom: 6, left: 8, right: 8 })
    .backgroundColor('rgba(255, 255, 255, 0.02)')
    .borderRadius(6)
  }

  @Builder
  CommitSheet() {
    Column({ space: 16 }) {
      Text('提交更改')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(Theme.TextPrimary)

      TextArea({ placeholder: '输入提交信息...', text: this.commitMessage })
        .width('100%')
        .height(100)
        .backgroundColor('rgba(255, 255, 255, 0.04)')
        .borderRadius(8)
        .fontSize(14)
        .fontColor(Theme.TextPrimary)
        .placeholderColor(Theme.TextTertiary)
        .onChange((value: string) => {
          this.commitMessage = value
        })

      Row({ space: 12 }) {
        Button('取消')
          .fontSize(14)
          .fontColor(Theme.TextPrimary)
          .backgroundColor('rgba(255, 255, 255, 0.08)')
          .borderRadius(10)
          .layoutWeight(1)
          .height(44)
          .onClick(() => {
            this.showCommitSheet = false
          })

        Button(this.isCommitting ? '提交中...' : '提交并推送')
          .fontSize(14)
          .fontColor(Theme.TextOnPrimary)
          .backgroundColor(Theme.SuccessColor)
          .borderRadius(10)
          .layoutWeight(1)
          .height(44)
          .enabled(!this.isCommitting && this.commitMessage.trim().length > 0)
          .onClick(async () => {
            await this.doCommit()
            if (!this.gitError) {
              await this.doPush()
            }
            this.showCommitSheet = false
          })
      }
      .width('100%')
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 16, bottom: 32 })
  }

  @Builder
  BranchSheet() {
    Column({ space: 12 }) {
      Row() {
        Text('切换分支')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.TextPrimary)
      }
      .width('100%')
      .padding({ bottom: 8 })

      if (this.branches.length > 0) {
        List() {
          ForEach(this.branches, (branch: GitBranchItem) => {
            ListItem() {
              Row({ space: 12 }) {
                SymbolGlyph($r('sys.symbol.arrow_counterclockwise'))
                  .fontSize(14)
                  .fontColor([branch.isCurrent ? Theme.AccentBlue : Theme.TextTertiary])

                Text(branch.name)
                  .fontSize(14)
                  .fontColor(branch.isCurrent ? Theme.AccentBlue : Theme.TextPrimary)
                  .layoutWeight(1)

                if (branch.isCurrent) {
                  SymbolGlyph($r('sys.symbol.checkmark'))
                    .fontSize(12)
                    .fontColor([Theme.AccentBlue])
                }
              }
              .width('100%')
              .padding(12)
              .backgroundColor(branch.isCurrent ? 'rgba(10, 132, 255, 0.1)' : 'transparent')
              .borderRadius(8)
              .onClick(() => {
                if (!branch.isCurrent) {
                  this.checkoutBranch(branch.name)
                }
              })
            }
          }, (branch: GitBranchItem) => branch.name)
        }
        .width('100%')
        .layoutWeight(1)
      } else {
        Text('没有找到分支')
          .fontSize(14)
          .fontColor(Theme.TextTertiary)
          .padding(20)
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, bottom: 32 })
    .height(350)
  }

  @Builder
  PRSheet() {
    Column({ space: 16 }) {
      Text('创建 Pull Request')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(Theme.TextPrimary)

      Column({ space: 8 }) {
        Text('标题')
          .fontSize(12)
          .fontColor(Theme.TextSecondary)
          .width('100%')

        TextInput({ placeholder: 'PR 标题', text: this.prTitle })
          .width('100%')
          .height(40)
          .backgroundColor('rgba(255, 255, 255, 0.04)')
          .borderRadius(8)
          .fontSize(14)
          .fontColor(Theme.TextPrimary)
          .onChange((value: string) => {
            this.prTitle = value
          })
      }
      .width('100%')

      Column({ space: 8 }) {
        Text('描述（可选）')
          .fontSize(12)
          .fontColor(Theme.TextSecondary)
          .width('100%')

        TextArea({ placeholder: 'PR 描述...', text: this.prBody })
          .width('100%')
          .height(80)
          .backgroundColor('rgba(255, 255, 255, 0.04)')
          .borderRadius(8)
          .fontSize(14)
          .fontColor(Theme.TextPrimary)
          .onChange((value: string) => {
            this.prBody = value
          })
      }
      .width('100%')

      Row({ space: 12 }) {
        Column({ space: 4 }) {
          Text('源分支')
            .fontSize(11)
            .fontColor(Theme.TextTertiary)
          TextInput({ text: this.prHead })
            .width('100%')
            .height(36)
            .backgroundColor('rgba(255, 255, 255, 0.04)')
            .borderRadius(6)
            .fontSize(13)
            .fontColor(Theme.TextPrimary)
            .onChange((value: string) => {
              this.prHead = value
            })
        }
        .layoutWeight(1)

        Column({ space: 4 }) {
          Text('目标分支')
            .fontSize(11)
            .fontColor(Theme.TextTertiary)
          TextInput({ text: this.prBase })
            .width('100%')
            .height(36)
            .backgroundColor('rgba(255, 255, 255, 0.04)')
            .borderRadius(6)
            .fontSize(13)
            .fontColor(Theme.TextPrimary)
            .onChange((value: string) => {
              this.prBase = value
            })
        }
        .layoutWeight(1)
      }
      .width('100%')

      Row({ space: 12 }) {
        Button('取消')
          .fontSize(14)
          .fontColor(Theme.TextPrimary)
          .backgroundColor('rgba(255, 255, 255, 0.08)')
          .borderRadius(10)
          .layoutWeight(1)
          .height(44)
          .onClick(() => {
            this.showPRSheet = false
          })

        Button(this.isCreatingPR ? '创建中...' : '创建 PR')
          .fontSize(14)
          .fontColor(Theme.TextOnPrimary)
          .backgroundColor(Theme.AccentBlue)
          .borderRadius(10)
          .layoutWeight(1)
          .height(44)
          .enabled(!this.isCreatingPR && this.prTitle.trim().length > 0)
          .onClick(() => {
            this.doCreatePR()
          })
      }
      .width('100%')
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 16, bottom: 32 })
  }

  // MARK: - 文件树标签页内容

  @Builder
  FilesTabContent() {
    Column({ space: 8 }) {
      // 搜索栏
      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.magnifyingglass'))
          .fontSize(14)
          .fontColor([Theme.TextTertiary])

        TextInput({ placeholder: '搜索文件...', text: '' })
          .layoutWeight(1)
          .height(32)
          .backgroundColor('transparent')
          .fontSize(13)
          .fontColor(Theme.TextPrimary)
          .placeholderColor(Theme.TextTertiary)
      }
      .width('100%')
      .padding({ left: 12, right: 12 })
      .backgroundColor('rgba(255, 255, 255, 0.04)')
      .borderRadius(8)

      // 文件列表
      if (this.isLoadingFiles) {
        Column() {
          LoadingProgress()
            .width(30)
            .height(30)
            .color(Theme.PrimaryColor)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.flatItems.length > 0) {
        List() {
          ForEach(this.flatItems, (item: FlatItem) => {
            ListItem() {
              this.FileTreeItem(item.entry, item.depth)
            }
          }, (item: FlatItem) => item.entry.fullPath + '-' + item.depth)
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Auto)
      } else {
        Column({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.folder'))
            .fontSize(40)
            .fontColor([Theme.TextTertiary])
          Text('暂无文件')
            .fontSize(14)
            .fontColor(Theme.TextSecondary)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      }
    }
    .width('100%')
    .padding(12)
    .layoutWeight(1)
  }

  @Builder
  FileTreeItem(entry: FsEntry, depth: number) {
    Row({ space: 6 }) {
      Row().width(depth * 16)

      if (entry.isDir) {
        SymbolGlyph(entry.isExpanded ? $r('sys.symbol.chevron_down') : $r('sys.symbol.chevron_right'))
          .fontSize(10)
          .fontColor([Theme.TextTertiary])
      } else {
        Row().width(10)
      }

      SymbolGlyph(entry.isDir ? $r('sys.symbol.folder') : $r('sys.symbol.doc_text'))
        .fontSize(14)
        .fontColor([entry.isDir ? Theme.AccentBlue : Theme.TextSecondary])

      Text(entry.name)
        .fontSize(13)
        .fontColor(Theme.TextPrimary)
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .padding({ left: 8, right: 8, top: 8, bottom: 8 })
    .backgroundColor('rgba(255, 255, 255, 0.01)')
    .borderRadius(6)
    .onClick(() => {
      if (entry.isDir) {
        this.toggleDir(entry)
      } else {
        // 检查是否为 Markdown 文件
        if (entry.name.endsWith('.md') || entry.name.endsWith('.markdown')) {
          this.loadMarkdown(entry.fullPath)
          this.activeTab = 'markdown'
        } else {
          router.pushUrl({
            url: 'pages/FileViewPage',
            params: { filePath: entry.fullPath, fileName: entry.name, sessionId: this.sessionId }
          })
        }
      }
    })
  }

  // MARK: - Markdown 标签页内容

  @Builder
  MarkdownTabContent() {
    Column({ space: 12 }) {
      if (this.isLoadingMarkdown) {
        Column() {
          LoadingProgress()
            .width(30)
            .height(30)
            .color(Theme.PrimaryColor)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.markdownError) {
        Column({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.exclamationmark_triangle_fill'))
            .fontSize(24)
            .fontColor([Theme.ErrorColor])
          Text(this.markdownError)
            .fontSize(14)
            .fontColor(Theme.TextSecondary)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.markdownHtml) {
        // 显示 Markdown 文件路径
        Row({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.doc_text'))
            .fontSize(12)
            .fontColor([Theme.TextTertiary])
          Text(this.markdownPath.split('/').pop() || this.markdownPath)
            .fontSize(12)
            .fontColor(Theme.TextTertiary)
            .maxLines(1)
            .layoutWeight(1)
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 8, bottom: 8 })
        .backgroundColor('rgba(255, 255, 255, 0.03)')
        .borderRadius(8)
        .margin({ bottom: 8 })

        // 使用 RichText 显示 HTML
        Scroll() {
          Column() {
            Text(this.markdownHtml)
              .fontSize(14)
              .fontColor(Theme.TextPrimary)
          }
          .width('100%')
          .padding(16)
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Auto)
      } else {
        Column({ space: 12 }) {
          SymbolGlyph($r('sys.symbol.doc_text'))
            .fontSize(40)
            .fontColor([Theme.TextTertiary])

          Text('Markdown 预览')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor(Theme.TextPrimary)

          Text('从文件树中选择 .md 文件进行预览')
            .fontSize(13)
            .fontColor(Theme.TextSecondary)
            .textAlign(TextAlign.Center)

          Button('浏览文件')
            .fontSize(14)
            .fontColor(Theme.TextOnPrimary)
            .backgroundColor(Theme.PrimaryColor)
            .borderRadius(10)
            .width(120)
            .height(36)
            .onClick(() => {
              this.activeTab = 'files'
            })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .padding(16)
      }
    }
    .width('100%')
    .padding(16)
    .layoutWeight(1)
  }

  // MARK: - Web 预览标签页内容

  @Builder
  WebTabContent() {
    Column({ space: 12 }) {
      // URL 输入栏
      Row({ space: 8 }) {
        TextInput({ placeholder: '输入 URL 或路径...', text: this.webInputUrl })
          .layoutWeight(1)
          .height(36)
          .backgroundColor('rgba(255, 255, 255, 0.04)')
          .borderRadius(8)
          .fontSize(13)
          .fontColor(Theme.TextPrimary)
          .placeholderColor(Theme.TextTertiary)
          .onChange((value: string) => {
            this.webInputUrl = value
          })

        if (this.isWebPreviewRunning) {
          Button('停止')
            .fontSize(12)
            .fontColor(Theme.ErrorColor)
            .backgroundColor('rgba(239, 68, 68, 0.1)')
            .borderRadius(8)
            .height(36)
            .onClick(() => {
              this.stopWebPreview()
            })
        } else {
          Button('打开')
            .fontSize(12)
            .fontColor(Theme.TextOnPrimary)
            .backgroundColor(Theme.PrimaryColor)
            .borderRadius(8)
            .height(36)
            .onClick(() => {
              this.startWebPreview()
            })
        }
      }
      .width('100%')

      // Web 内容
      if (this.isWebPreviewRunning && this.webUrl) {
        Column({ space: 8 }) {
          Row({ space: 8 }) {
            SymbolGlyph($r('sys.symbol.checkmark_circle_fill'))
              .fontSize(12)
              .fontColor([Theme.SuccessColor])
            Text(`预览运行中 - 端口 ${this.webPreviewPort}`)
              .fontSize(11)
              .fontColor(Theme.TextTertiary)
          }
          .width('100%')

          Text(this.webUrl)
            .fontSize(14)
            .fontColor(Theme.AccentBlue)
            .maxLines(1)

          Text('Web 预览需要在浏览器中打开上述地址')
            .fontSize(12)
            .fontColor(Theme.TextTertiary)
            .margin({ top: 8 })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .backgroundColor('rgba(255, 255, 255, 0.02)')
        .borderRadius(10)
        .padding(16)
      } else {
        Column({ space: 12 }) {
          SymbolGlyph($r('sys.symbol.magnifyingglass'))
            .fontSize(40)
            .fontColor([Theme.TextTertiary])

          Text('Web 预览')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor(Theme.TextPrimary)

          Text('输入路径启动本地开发服务器预览')
            .fontSize(13)
            .fontColor(Theme.TextSecondary)

          Text('例如: / 或 /index.html')
            .fontSize(11)
            .fontColor(Theme.TextTertiary)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      }
    }
    .width('100%')
    .padding(16)
    .layoutWeight(1)
  }

  // MARK: - SSH 终端标签页内容

  @Builder
  SshTabContent() {
    Column({ space: 16 }) {
      // 错误提示
      if (this.sshError) {
        Row({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.exclamationmark_triangle_fill'))
            .fontSize(12)
            .fontColor([Theme.ErrorColor])
          Text(this.sshError)
            .fontSize(11)
            .fontColor(Theme.ErrorColor)
            .layoutWeight(1)
        }
        .width('100%')
        .padding(8)
        .backgroundColor('rgba(239, 68, 68, 0.1)')
        .borderRadius(6)
      }

      if (!this.sshConnected) {
        // 连接信息输入
        Column({ space: 12 }) {
          Row({ space: 8 }) {
            Text('主机:')
              .fontSize(13)
              .fontColor(Theme.TextSecondary)
              .width(50)

            TextInput({ placeholder: 'IP 或域名', text: this.sshHost })
              .layoutWeight(1)
              .height(36)
              .backgroundColor('rgba(255, 255, 255, 0.04)')
              .borderRadius(8)
              .fontSize(13)
              .fontColor(Theme.TextPrimary)
              .onChange((value: string) => {
                this.sshHost = value
              })
          }
          .width('100%')

          Row({ space: 8 }) {
            Text('端口:')
              .fontSize(13)
              .fontColor(Theme.TextSecondary)
              .width(50)

            TextInput({ placeholder: '22', text: this.sshPort })
              .layoutWeight(1)
              .height(36)
              .backgroundColor('rgba(255, 255, 255, 0.04)')
              .borderRadius(8)
              .fontSize(13)
              .fontColor(Theme.TextPrimary)
              .onChange((value: string) => {
                this.sshPort = value
              })
          }
          .width('100%')

          Row({ space: 8 }) {
            Text('用户:')
              .fontSize(13)
              .fontColor(Theme.TextSecondary)
              .width(50)

            TextInput({ placeholder: '用户名', text: this.sshUser })
              .layoutWeight(1)
              .height(36)
              .backgroundColor('rgba(255, 255, 255, 0.04)')
              .borderRadius(8)
              .fontSize(13)
              .fontColor(Theme.TextPrimary)
              .onChange((value: string) => {
                this.sshUser = value
              })
          }
          .width('100%')

          Row({ space: 8 }) {
            Text('密码:')
              .fontSize(13)
              .fontColor(Theme.TextSecondary)
              .width(50)

            TextInput({ placeholder: '密码（可选）', text: this.sshPassword })
              .layoutWeight(1)
              .height(36)
              .backgroundColor('rgba(255, 255, 255, 0.04)')
              .borderRadius(8)
              .fontSize(13)
              .fontColor(Theme.TextPrimary)
              .type(InputType.Password)
              .onChange((value: string) => {
                this.sshPassword = value
              })
          }
          .width('100%')

          Button('连接')
            .fontSize(14)
            .fontColor(Theme.TextOnPrimary)
            .backgroundColor(Theme.PrimaryColor)
            .borderRadius(10)
            .width(160)
            .height(40)
            .margin({ top: 8 })
            .onClick(() => {
              this.sshConnect()
            })
        }
        .width('100%')
        .padding(16)
        .backgroundColor('rgba(255, 255, 255, 0.02)')
        .borderRadius(12)
      } else {
        // 已连接 - 显示终端
        Column({ space: 8 }) {
          // 状态栏
          Row({ space: 8 }) {
            SymbolGlyph($r('sys.symbol.checkmark_circle_fill'))
              .fontSize(12)
              .fontColor([Theme.SuccessColor])
            Text(`${this.sshUser}@${this.sshHost}`)
              .fontSize(12)
              .fontColor(Theme.TextSecondary)
            Blank()
            Button('断开')
              .fontSize(11)
              .fontColor(Theme.ErrorColor)
              .backgroundColor('rgba(239, 68, 68, 0.1)')
              .borderRadius(6)
              .height(28)
              .onClick(() => {
                this.sshDisconnect()
              })
          }
          .width('100%')
          .padding(8)
          .backgroundColor('rgba(255, 255, 255, 0.03)')
          .borderRadius(6)

          // 输出区域
          Scroll() {
            Text(this.sshOutput)
              .width('100%')
              .fontSize(12)
              .fontColor(Theme.TextPrimary)
              .fontFamily('monospace')
          }
          .width('100%')
          .layoutWeight(1)
          .backgroundColor('rgba(0, 0, 0, 0.3)')
          .borderRadius(8)
          .padding(12)

          // 命令输入
          Row({ space: 8 }) {
            Text('$')
              .fontSize(13)
              .fontColor(Theme.TextTertiary)

            TextInput({ placeholder: '输入命令...', text: this.sshCommand })
              .layoutWeight(1)
              .height(36)
              .backgroundColor('rgba(255, 255, 255, 0.04)')
              .borderRadius(6)
              .fontSize(13)
              .fontColor(Theme.TextPrimary)
              .fontFamily('monospace')
              .onChange((value: string) => {
                this.sshCommand = value
              })
              .onSubmit(() => {
                this.sshExecute()
              })

            Button('执行')
              .fontSize(12)
              .fontColor(Theme.TextOnPrimary)
              .backgroundColor(Theme.PrimaryColor)
              .borderRadius(6)
              .height(36)
              .onClick(() => {
                this.sshExecute()
              })
          }
          .width('100%')
        }
        .width('100%')
        .layoutWeight(1)
      }
    }
    .width('100%')
    .padding(16)
    .layoutWeight(1)
  }
}

export default PreviewPage
