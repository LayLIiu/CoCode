/**
 * 工作区页面 - 文件树浏览器（设置页风格）
 */

import { Theme } from '../common/Theme'
import { sessionStore } from '../stores/SessionStore'
import { apiService, FsEntry } from '../services/APIService'
import { HdsNavigation, HdsNavigationTitleMode, ScrollEffectType } from '@hms.hds.hdsBaseComponent'
import { hdsMaterial } from '@hms.hds.hdsMaterial'
import router from '@ohos.router'

@Entry
@Component
struct WorkspacePage {
  @State sessionId: string = ''
  @State rootPath: string = ''
  @State rootEntries: FsEntry[] = []
  @State isLoading: boolean = true
  @State refreshKey: number = 0

  aboutToAppear(): void {
    const params = router.getParams() as Record<string, string>
    if (params && params['sessionId']) {
      this.sessionId = params['sessionId']
      this.loadRoot()
    }
  }

  private async loadRoot(): Promise<void> {
    const session = sessionStore.sessions.find(s => s.id === this.sessionId)
    if (session?.workDir) {
      this.rootPath = session.workDir
    } else if (session?.projectPath) {
      this.rootPath = session.projectPath
    }
    if (this.rootPath) {
      this.rootEntries = await apiService.browseDirectory(this.rootPath)
    }
    this.isLoading = false
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
    // 复制数组引用触发 ForEach 重渲染
    this.rootEntries = [...this.rootEntries]
  }

  build() {
    Stack() {
      HdsNavigation() {
        List() {
          // 顶部留白
          ListItem() { Row().width('100%').height(80) }

          // 路径
          ListItem() {
            Column({ space: 4 }) {
              Row({ space: 8 }) {
                SymbolGlyph($r('sys.symbol.folder')).fontSize(16).fontColor([Theme.AccentBlue])
                Text('项目目录').fontSize(14).fontColor(Theme.TextSecondary)
              }
              if (this.rootPath) {
                Text(this.rootPath)
                  .fontSize(13).fontColor(Theme.TextTertiary).maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
              }
            }
            .width('100%').padding(Theme.SpacingMD)
            .backgroundColor(Theme.GlassBackground)
            .borderRadius(Theme.RadiusMedium)
            .border({ width: 0.5, color: Theme.GlassBorder })
          }

          // 文件树
          ListItem() {
            if (this.isLoading) {
              Column() {
                LoadingProgress().width(30).height(30).color(Theme.PrimaryColor)
              }.width('100%').height(200).justifyContent(FlexAlign.Center)
            } else if (this.rootEntries.length > 0) {
              Column({ space: 2 }) {
                ForEach(this.rootEntries, (entry: FsEntry) => {
                  this.FileTreeItem(entry, 0)
                }, (entry: FsEntry) => entry.fullPath + this.refreshKey)
              }
              .width('100%')
              .key('tree-' + this.refreshKey)
            } else {
              Text('暂无文件').fontSize(14).fontColor(Theme.TextTertiary)
                .width('100%').textAlign(TextAlign.Center).margin({ top: 40 })
            }
          }
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: Theme.SpacingLG, right: Theme.SpacingLG })
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
      }
      .titleBar({
        content: { title: { mainTitle: '工作区' } },
        style: {
          scrollEffectOpts: { enableScrollEffect: true, scrollEffectType: ScrollEffectType.GRADIENT_BLUR },
          systemMaterialEffect: { materialType: hdsMaterial.MaterialType.ADAPTIVE, materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE },
        },
        avoidLayoutSafeArea: true,
        enableComponentSafeArea: false,
      })
      .titleMode(HdsNavigationTitleMode.MINI)
      .hideBackButton(false)
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
  }

  @Builder
  FileTreeItem(entry: FsEntry, depth: number) {
    Column() {
      Row({ space: 6 }) {
        // 缩进
        if (depth > 0) {
          Row().width(depth * 20)
        }

        // 展开箭头
        if (entry.isDir) {
          SymbolGlyph(entry.isExpanded ? $r('sys.symbol.chevron_down') : $r('sys.symbol.chevron_right'))
            .fontSize(10).fontColor([Theme.TextTertiary])
        } else {
          Row().width(10)
        }

        // 图标
        SymbolGlyph(entry.isDir ? $r('sys.symbol.folder') : $r('sys.symbol.doc_text'))
          .fontSize(16).fontColor([entry.isDir ? Theme.AccentBlue : Theme.TextSecondary])

        Text(entry.name)
          .fontSize(14).fontColor(Theme.TextPrimary).layoutWeight(1).maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%').padding({ left: 12, right: 12, top: 8, bottom: 8 })
      .onClick(() => { this.toggleDir(entry) })

      // 子项
      if (entry.isDir && entry.isExpanded && entry.children) {
        ForEach(entry.children, (child: FsEntry) => {
          this.FileTreeItem(child, depth + 1)
        }, (child: FsEntry) => child.fullPath)
      }
    }
  }
}
