/**
 * 导入会话页面 - 从服务器选择会话导入
 * 使用鸿蒙液态玻璃效果
 */

import { Theme } from '../common/Theme'
import { Session } from '../models/Models'
import { sessionStore } from '../stores/SessionStore'
import { apiService } from '../services/APIService'
import { TabType } from '../viewmodel/ConversationModel'
import { HdsNavigation, ScrollEffectType, HdsNavigationBadgeIconOptions, HdsNavigationTitleMode } from '@hms.hds.hdsBaseComponent'
import { hdsMaterial } from '@hms.hds.hdsMaterial'
import router from '@ohos.router'

@Entry
@Component
struct ImportSessionPage {
  @State sessions: Session[] = []
  @State selectedIds: string[] = []
  @State isLoading: boolean = true
  @State isImporting: boolean = false
  @State tabType: TabType = TabType.CLAUDE

  private importMenus: Array<HdsNavigationBadgeIconOptions> = [
    {
      content: {
        icon: $r('sys.symbol.checkmark_circle'),
        action: () => { this.selectAll() }
      }
    }
  ]

  aboutToAppear(): void {
    // 从路由参数获取 tabType
    const params = router.getParams() as Record<string, Object>
    if (params && params['tabType']) {
      this.tabType = params['tabType'] as TabType
    }
    this.loadServerSessions()
  }

  private async loadServerSessions(): Promise<void> {
    this.isLoading = true

    try {
      const allSessions = await apiService.getSessions()
      // 根据Tab类型过滤
      this.sessions = allSessions.filter((s: Session) => this.isSessionForTab(s))
    } catch (e) {
      console.error(`[ImportSessionPage] Load error: ${e}`)
    }

    this.isLoading = false
  }

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

  // 过滤掉已存在的会话
  private getNotImportedSessions(): Session[] {
    const existingIds = new Set<string>()
    sessionStore.sessions.forEach((s: Session) => existingIds.add(s.id))

    return this.sessions.filter((s: Session) => !existingIds.has(s.id))
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

    // 将选中的会话添加到本地列表
    const selectedSessions = this.sessions.filter((s: Session) => this.selectedIds.includes(s.id))

    // 合并到本地
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
    }

    // 保存到本地
    await sessionStore.saveSessionsToStorage()

    this.isImporting = false

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
              ForEach(this.getNotImportedSessions(), (session: Session) => {
                ListItem() {
                  this.SessionItemView(session)
                }
              }, (session: Session) => session.id)
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

        Text(`${session.messageCount} 条消息`)
          .fontSize(Theme.FontTiny)
          .fontColor(Theme.TextTertiary)
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
