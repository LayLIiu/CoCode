/**
 * 工作区页面 - 文件树浏览器（设置页风格）
 */

import { Theme } from '../common/Theme'
import { sessionStore } from '../stores/SessionStore'
import { apiService, FsEntry } from '../services/APIService'
import { HdsNavigation, HdsNavigationTitleMode, ScrollEffectType } from '@hms.hds.hdsBaseComponent'
import { hdsMaterial } from '@hms.hds.hdsMaterial'
import router from '@ohos.router'

class FlatItem {
  entry: FsEntry = new FsEntry('', '', false)
  depth: number = 0
  constructor(entry: FsEntry, depth: number) { this.entry = entry; this.depth = depth }
}

@Entry
@Component
struct WorkspacePage {
  @State sessionId: string = ''
  @State rootPath: string = ''
  @State rootEntries: FsEntry[] = []
  @State isLoading: boolean = true

  // 扁平化所有可见节点
  @State flatItems: FlatItem[] = []

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
      this.flattenEntries()
    }
    this.isLoading = false
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

  build() {
    Stack() {
      HdsNavigation() {
        List() {
          ListItem() { Row().width('100%').height(80) }

          ListItem() {
            Column({ space: 4 }) {
              Row({ space: 8 }) {
                SymbolGlyph($r('sys.symbol.folder')).fontSize(16).fontColor([Theme.AccentBlue])
                Text('项目目录').fontSize(14).fontColor(Theme.TextSecondary)
              }
              if (this.rootPath) {
                Text(this.rootPath).fontSize(13).fontColor(Theme.TextTertiary)
                  .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
              }
            }
            .width('100%').padding(Theme.SpacingMD)
            .backgroundColor(Theme.GlassBackground).borderRadius(Theme.RadiusMedium)
            .border({ width: 0.5, color: Theme.GlassBorder })
          }

          ListItem() {
            if (this.isLoading) {
              Column() { LoadingProgress().width(30).height(30).color(Theme.PrimaryColor) }
                .width('100%').height(200).justifyContent(FlexAlign.Center)
            } else if (this.flatItems.length > 0) {
              Column({ space: 2 }) {
                ForEach(this.flatItems, (item: FlatItem, idx: number) => {
                  this.FileTreeItem(item.entry, item.depth)
                }, (item: FlatItem) => item.entry.fullPath + '-' + item.depth)
              }
              .width('100%')
            } else {
              Text('暂无文件').fontSize(14).fontColor(Theme.TextTertiary)
                .width('100%').textAlign(TextAlign.Center).margin({ top: 40 })
            }
          }
        }
        .width('100%').layoutWeight(1)
        .padding({ left: Theme.SpacingLG, right: Theme.SpacingLG })
        .scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring)
      }
      .titleBar({
        content: { title: { mainTitle: '工作区' } },
        style: {
          scrollEffectOpts: { enableScrollEffect: true, scrollEffectType: ScrollEffectType.GRADIENT_BLUR },
          systemMaterialEffect: { materialType: hdsMaterial.MaterialType.ADAPTIVE, materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE },
        },
        avoidLayoutSafeArea: true, enableComponentSafeArea: false,
      })
      .titleMode(HdsNavigationTitleMode.MINI)
      .hideBackButton(false)
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
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  @Builder
  FileTreeItem(entry: FsEntry, depth: number) {
    Row({ space: 6 }) {
      Row().width(depth * 20)

      if (entry.isDir) {
        SymbolGlyph(entry.isExpanded ? $r('sys.symbol.chevron_down') : $r('sys.symbol.chevron_right'))
          .fontSize(10).fontColor([Theme.TextTertiary])
      } else {
        Row().width(10)
      }

      SymbolGlyph(entry.isDir ? $r('sys.symbol.folder') : $r('sys.symbol.doc_text'))
        .fontSize(16).fontColor([entry.isDir ? Theme.AccentBlue : Theme.TextSecondary])

      Text(entry.name).fontSize(14).fontColor(Theme.TextPrimary).layoutWeight(1)
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%').padding({ left: 12, right: 12, top: 8, bottom: 8 })
    .onClick(() => {
      if (entry.isDir) {
        this.toggleDir(entry)
      } else {
        router.pushUrl({
          url: 'pages/FileViewPage',
          params: { filePath: entry.fullPath, fileName: entry.name, sessionId: this.sessionId }
        })
      }
    })
  }
}
