/**
 * 工作区页面 - 文件树浏览器
 */

import { Theme } from '../common/Theme'
import { sessionStore } from '../stores/SessionStore'
import { apiService, FsEntry } from '../services/APIService'
import router from '@ohos.router'

@Entry
@Component
struct WorkspacePage {
  @State sessionId: string = ''
  @State rootPath: string = ''
  @State rootEntries: FsEntry[] = []
  @State isLoading: boolean = true

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
    this.isLoading = false // trigger refresh
  }

  build() {
    Column() {
      Column() {
        // 标题栏
        Row() {
          SymbolGlyph($r('sys.symbol.chevron_left'))
            .fontSize(20).fontColor([Theme.PrimaryColor])

          Text(this.rootPath ? this.rootPath.split('/').pop() || '工作区' : '工作区')
            .fontSize(18).fontWeight(FontWeight.Bold).fontColor(Theme.TextPrimary)
            .layoutWeight(1).textAlign(TextAlign.Center)

          Blank().width(20)
        }
        .width('100%').padding(Theme.SpacingMD)
        .onClick(() => { router.back() })

        // 文件树
        if (this.isLoading) {
          LoadingProgress().width(30).height(30).color(Theme.PrimaryColor).margin({ top: 40 })
        } else if (this.rootPath) {
          Text(this.rootPath).fontSize(11).fontColor(Theme.TextTertiary)
            .width('100%').padding({ left: Theme.SpacingMD, bottom: Theme.SpacingSM })
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })

          Scroll() {
            Column() {
              ForEach(this.rootEntries, (entry: FsEntry) => {
                this.FileTreeItem(entry, 0)
              }, (entry: FsEntry) => entry.fullPath)
            }
            .width('100%')
          }
          .width('100%').layoutWeight(1)
        } else {
          Text('暂无工作区信息').fontSize(14).fontColor(Theme.TextTertiary).margin({ top: 40 })
        }
      }
      .width('100%').height('100%')
      .linearGradient({
        angle: 180,
        colors: [
          [Theme.BackgroundGradientStart, 0.0],
          [Theme.BackgroundGradientMiddle, 0.5],
          [Theme.BackgroundGradientEnd, 1.0]
        ]
      })
    }
    .width('100%').height('100%')
  }

  @Builder
  FileTreeItem(entry: FsEntry, depth: number) {
    Column() {
      Row({ space: 6 }) {
        // 缩进
        if (depth > 0) {
          Row().width(depth * 16)
        }

        // 展开箭头 (仅目录)
        if (entry.isDir) {
          SymbolGlyph(entry.isExpanded ? $r('sys.symbol.chevron_down') : $r('sys.symbol.chevron_right'))
            .fontSize(10).fontColor([Theme.TextTertiary])
        } else {
          Row().width(10)
        }

        // 图标
        SymbolGlyph(entry.isDir ? $r('sys.symbol.folder') : $r('sys.symbol.doc_text'))
          .fontSize(14)
          .fontColor([entry.isDir ? Theme.AccentBlue : Theme.TextSecondary])

        // 文件名
        Text(entry.name)
          .fontSize(13).fontColor(Theme.TextPrimary).layoutWeight(1).maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%').padding({ left: 12, right: 12, top: 6, bottom: 6 })
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
