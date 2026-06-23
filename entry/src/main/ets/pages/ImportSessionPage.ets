/**
 * 导入会话页面 - 从服务器选择会话导入
 * 使用鸿蒙液态玻璃效果
 */

import { Theme } from '../common/Theme'
import { Session } from '../models/Models'
import { sessionStore } from '../stores/SessionStore'
import { apiService } from '../services/APIService'
import { HdsNavigation, ScrollEffectType, HdsNavigationBadgeIconOptions, HdsNavigationTitleMode } from '@hms.hds.hdsBaseComponent'
import { hdsMaterial } from '@hms.hds.hdsMaterial'
import router from '@ohos.router'

@Entry
@Component
struct ImportSessionPage {
  @State sessions: Session[] = []
  @State selectedIds: string[] = []
  @State expandedProjects: Set<string> = new Set<string>()  // 展开的项目
  @State isLoading: boolean = true
  @State isImporting: boolean = false
  private importMenus: Array<HdsNavigationBadgeIconOptions> = [
    {
      content: {
        icon: $r('sys.symbol.checkmark_circle'),
        action: () => { this.selectAll() }
      }
    }
  ]

  aboutToAppear(): void {
    this.loadServerSessions()
  }

  private async loadServerSessions(): Promise<void> {
    this.isLoading = true

    try {
      const allSessions = await apiService.getSessions()
      this.sessions = allSessions.filter((s: Session) => this.isSessionForTab(s))
    } catch (e) {
      console.error(`[ImportSessionPage] Load error: ${e}`)
    }

    this.isLoading = false
  }

  private isSessionForTab(session: Session): boolean {
    const providerId = session.aiTool || ''
    return providerId === '' ||
      providerId === 'claude' ||
      providerId === 'anthropic' ||
      providerId.toLowerCase().includes('claude')
  }

  // 过滤掉已存在的会话（已删除/归档的会话可以重新导入恢复）
  private getNotImportedSessions(): Session[] {
    const existingIds = new Set<string>()
    sessionStore.sessions.forEach((s: Session) => existingIds.add(s.id))
    const existingOfficialThreadIds = new Set<string>()
    sessionStore.sessions.forEach((s: Session) => {
      if (s.officialCodexThreadId) existingOfficialThreadIds.add(s.officialCodexThreadId)
    })

    return this.sessions.filter((s: Session) => {
      const isArchived = sessionStore.isSessionArchived(s.id)
      const isDeleted = sessionStore.isSessionLocallyDeleted(s.id)
      if (existingIds.has(s.id) && !isArchived && !isDeleted) return false
      if (s.officialCodexThreadId && existingOfficialThreadIds.has(s.officialCodexThreadId) && !isArchived && !isDeleted) return false
      return true
    })
  }

  // 按项目分组
  private getSessionsGroupedByProject(): Map<string, Session[]> {
    const groups = new Map<string, Session[]>()
    const sessions = this.getNotImportedSessions()
    
    for (let i = 0; i < sessions.length; i++) {
      const session = sessions[i]
      const project = session.workDir || session.projectPath || '未知项目'
      const projectName = project.split('/').pop() || project
      
      if (!groups.has(projectName)) {
        groups.set(projectName, [])
      }
      const arr = groups.get(projectName)
      if (arr) {
        arr.push(session)
      }
    }
    
    return groups
  }

  // 获取排序后的项目列表
  private getSortedProjects(): string[] {
    const groups = this.getSessionsGroupedByProject()
    const projects = Array.from(groups.keys())
    return projects.sort((a: string, b: string): number => {
      if (a === '未知项目') return 1
      if (b === '未知项目') return -1
      return a.localeCompare(b)
    })
  }

  // 切换项目展开状态
  private toggleProjectExpand(projectName: string): void {
    if (this.expandedProjects.has(projectName)) {
      this.expandedProjects.delete(projectName)
    } else {
      this.expandedProjects.add(projectName)
    }
  }

  private toggleSelection(sessionId: string): void {
    if (this.selectedIds.includes(sessionId)) {
      this.selectedIds = this.selectedIds.filter(i => i !== sessionId)
    } else {
      this.selectedIds = [...this.selectedIds, sessionId]
    }
  }

  private selectAll(): void {
    const notImported = this.getNotImportedSessions()
    if (this.selectedIds.length === notImported.length) {
      // 已全选，取消全选
      this.selectedIds = []
    } else {
      // 全选
      this.selectedIds = notImported.map((s: Session) => s.id)
    }
  }

  private async importSelected(): Promise<void> {
    if (this.selectedIds.length === 0) return

    this.isImporting = true

    try {
      // 将选中的会话添加到本地列表
      const selectedSessions = this.sessions.filter((s: Session) => this.selectedIds.includes(s.id))

      for (let i = 0; i < selectedSessions.length; i++) {
        const session = selectedSessions[i]
        // 检查是否已存在
        let exists = false
        for (let j = 0; j < sessionStore.sessions.length; j++) {
          if (sessionStore.sessions[j].id === session.id) {
            exists = true
            break
          }
        }
        if (!exists) {
          sessionStore.sessions.push(session)
        }
        // 从已删除列表中移除（恢复会话）
        await sessionStore.restoreSessionFromDeleted(session.id)
        await sessionStore.unarchiveSession(session.id, session.officialCodexThreadId || '')
      }
      // 保存会话
      await sessionStore.saveSessionsToStorage()

      // 清空选择
      this.selectedIds = []
    } catch (e) {
      console.error(`[ImportSessionPage] Import error: ${e}`)
    } finally {
      this.isImporting = false
    }

    // 返回上一页
    router.back()
  }

  build() {
    Stack() {
      HdsNavigation() {
        Column() {
          // 提示
          Text(`共 ${this.getNotImportedSessions().length} 个会话可导入，已选择 ${this.selectedIds.length} 个`)
            .fontSize(14)
            .fontColor(Theme.TextSecondary)
            .width('100%')
            .padding({ left: Theme.SpacingLG, right: Theme.SpacingLG, top: Theme.SpacingMD, bottom: Theme.SpacingMD })

          if (this.isLoading) {
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
            .layoutWeight(1)
            .justifyContent(FlexAlign.Center)
          } else if (this.getNotImportedSessions().length === 0) {
            Column() {
              SymbolGlyph($r('sys.symbol.checkmark_circle'))
                .fontSize(60)
                .fontColor([Theme.SuccessColor])
                .margin({ bottom: Theme.SpacingLG })

              Text('所有会话已导入')
                .fontSize(Theme.FontHeading)
                .fontColor(Theme.TextPrimary)
            }
            .width('100%')
            .layoutWeight(1)
            .justifyContent(FlexAlign.Center)
          } else {
            List({ space: 0 }) {
              ForEach(this.getSortedProjects(), (projectName: string) => {
                ListItem() {
                  this.ProjectGroupView(projectName)
                }
              }, (projectName: string) => projectName)
            }
            .width('100%')
            .layoutWeight(1)
            .padding({ left: Theme.SpacingLG, right: Theme.SpacingLG })
            .scrollBar(BarState.Off)
            .edgeEffect(EdgeEffect.Spring)
          }

          // 底部导入按钮
          if (this.selectedIds.length > 0) {
            Column() {
              Button(`导入 ${this.selectedIds.length} 个会话`)
                .width('100%')
                .height(50)
                .fontSize(16)
                .fontColor(Theme.TextOnPrimary)
                .backgroundColor(Theme.PrimaryColor)
                .borderRadius(12)
                .backgroundBlurStyle(BlurStyle.COMPONENT_REGULAR)
                .enabled(!this.isImporting)
                .onClick(() => {
                  this.importSelected()
                })
            }
            .width('100%')
            .padding({ left: Theme.SpacingLG, right: Theme.SpacingLG, top: Theme.SpacingMD, bottom: Theme.SpacingXL })
            .backgroundColor(Theme.BackgroundPrimary)
          }
        }
        .width('100%')
        .height('100%')
        .padding({ top: 100 })
      }
      .titleBar({
        content: {
          title: { mainTitle: '导入会话' },
          menu: { value: this.importMenus },
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
      .backgroundColor(Theme.BackgroundPrimary)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    }
    .width('100%')
    .height('100%')
  }

  private getProjectSessionCount(projectName: string): number {
    const sessions = this.getSessionsGroupedByProject().get(projectName)
    return sessions ? sessions.length : 0
  }

  private isProjectAllSelected(projectName: string): boolean {
    const sessions = this.getSessionsGroupedByProject().get(projectName)
    if (!sessions || sessions.length === 0) return false
    return sessions.every((s: Session) => this.selectedIds.includes(s.id))
  }

  private toggleProjectSelection(projectName: string): void {
    const sessions = this.getSessionsGroupedByProject().get(projectName)
    if (!sessions) return
    
    const projectIds: string[] = []
    for (let i = 0; i < sessions.length; i++) {
      projectIds.push(sessions[i].id)
    }
    
    const allSelected = this.isProjectAllSelected(projectName)
    if (allSelected) {
      // 取消选择
      this.selectedIds = this.selectedIds.filter((id: string) => !projectIds.includes(id))
    } else {
      // 全选
      const newIds: string[] = [...this.selectedIds]
      for (let i = 0; i < projectIds.length; i++) {
        if (!newIds.includes(projectIds[i])) {
          newIds.push(projectIds[i])
        }
      }
      this.selectedIds = newIds
    }
  }

  @Builder
  ProjectGroupView(projectName: string) {
    Column() {
      // 项目标题（可折叠）
      Row() {
        SymbolGlyph(this.expandedProjects.has(projectName) ? 
          $r('sys.symbol.chevron_down') : $r('sys.symbol.chevron_right'))
          .fontSize(16)
          .fontColor([Theme.TextSecondary])

        Text(projectName)
          .fontSize(Theme.FontBody)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.TextPrimary)
          .margin({ left: Theme.SpacingSM })

        Text(`(${this.getProjectSessionCount(projectName)})`)
          .fontSize(Theme.FontTiny)
          .fontColor(Theme.TextSecondary)
          .margin({ left: Theme.SpacingXS })

        Blank()

        Text(this.isProjectAllSelected(projectName) ? '取消' : '全选')
          .fontSize(Theme.FontTiny)
          .fontColor(Theme.PrimaryColor)
          .onClick(() => {
            this.toggleProjectSelection(projectName)
          })
      }
      .width('100%')
      .padding({ top: Theme.SpacingMD, bottom: Theme.SpacingSM })
      .onClick(() => {
        this.toggleProjectExpand(projectName)
      })

      // 展开的会话列表
      if (this.expandedProjects.has(projectName)) {
        Column({ space: Theme.SpacingSM }) {
          ForEach(this.getSessionsGroupedByProject().get(projectName) || [], (session: Session) => {
            this.SessionItemView(session)
          }, (session: Session) => session.id)
        }
        .width('100%')
        .padding({ left: Theme.SpacingLG })
      }
    }
    .width('100%')
  }

  @Builder
  SessionItemView(session: Session) {
    Row() {
      // 选择框
      Column() {
        if (this.selectedIds.includes(session.id)) {
          SymbolGlyph($r('sys.symbol.checkmark_circle_fill'))
            .fontSize(24)
            .fontColor([Theme.PrimaryColor])
        } else {
          SymbolGlyph($r('sys.symbol.circle'))
            .fontSize(24)
            .fontColor([Theme.TextTertiary])
        }
      }
      .width(36)
      .height(36)
      .justifyContent(FlexAlign.Center)

      // 会话信息
      Column({ space: 4 }) {
        Text(session.title)
          .fontSize(Theme.FontBody)
          .fontColor(Theme.TextPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(session.projectPath)
          .fontSize(Theme.FontTiny)
          .fontColor(Theme.TextSecondary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(session.officialCodexThreadId ? 'Codex Desktop' : `${session.messageCount} 条消息`)
          .fontSize(Theme.FontTiny)
          .fontColor(session.officialCodexThreadId ? Theme.PrimaryColor : Theme.TextTertiary)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .margin({ left: Theme.SpacingSM })
    }
    .width('100%')
    .padding(Theme.SpacingMD)
    .backgroundColor(Theme.GlassBackground)
    .borderRadius(Theme.RadiusMedium)
    .margin({ bottom: Theme.SpacingSM })
    .onClick(() => {
      this.toggleSelection(session.id)
    })
  }
}
