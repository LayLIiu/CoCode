/**
 * 工作区页面 - 显示项目目录和文件信息
 */

import { Theme } from '../common/Theme'
import { sessionStore } from '../stores/SessionStore'
import { apiService } from '../services/APIService'
import router from '@ohos.router'

@Entry
@Component
struct WorkspacePage {
  @State sessionId: string = ''
  @State workDir: string = ''
  @State projectPath: string = ''

  aboutToAppear(): void {
    const params = router.getParams() as Record<string, string>
    if (params && params['sessionId']) {
      this.sessionId = params['sessionId']
      this.loadWorkspace()
    }
  }

  private loadWorkspace(): void {
    const session = sessionStore.sessions.find(s => s.id === this.sessionId)
    if (session) {
      this.workDir = session.workDir || ''
      this.projectPath = session.projectPath
    }
  }

  build() {
    Column() {
      Column() {
        // 标题栏
        Row() {
          SymbolGlyph($r('sys.symbol.chevron_left'))
            .fontSize(20).fontColor([Theme.PrimaryColor])

          Text('工作区')
            .fontSize(20).fontWeight(FontWeight.Bold).fontColor(Theme.TextPrimary)
            .layoutWeight(1).textAlign(TextAlign.Center)

          Blank().width(20)
        }
        .width('100%').padding(Theme.SpacingMD)
        .onClick(() => {
          router.back()
        })

        // 项目路径
        if (this.projectPath) {
          Column({ space: 8 }) {
            Row({ space: 8 }) {
              SymbolGlyph($r('sys.symbol.folder')).fontSize(16).fontColor([Theme.AccentBlue])
              Text('项目目录').fontSize(14).fontColor(Theme.TextSecondary)
            }
            Text(this.projectPath)
              .fontSize(14).fontColor(Theme.TextPrimary)
              .width('100%').padding(12)
              .backgroundColor(Theme.BackgroundTertiary).borderRadius(8)
          }
          .width('100%').padding(Theme.SpacingMD)
        }

        if (this.workDir) {
          Column({ space: 8 }) {
            Row({ space: 8 }) {
              SymbolGlyph($r('sys.symbol.gearshape')).fontSize(16).fontColor([Theme.TextTertiary])
              Text('工作目录').fontSize(14).fontColor(Theme.TextSecondary)
            }
            Text(this.workDir)
              .fontSize(14).fontColor(Theme.TextPrimary)
              .width('100%').padding(12)
              .backgroundColor(Theme.BackgroundTertiary).borderRadius(8)
          }
          .width('100%').padding(Theme.SpacingMD)
        }

        if (!this.projectPath && !this.workDir) {
          Text('暂无工作区信息')
            .fontSize(14).fontColor(Theme.TextTertiary)
            .margin({ top: 40 })
        }
      }
      .width('100%')
      .linearGradient({
        angle: 180,
        colors: [
          [Theme.BackgroundGradientStart, 0.0],
          [Theme.BackgroundGradientMiddle, 0.5],
          [Theme.BackgroundGradientEnd, 1.0]
        ]
      })
    }
    .width('100%')
    .height('100%')
  }
}
