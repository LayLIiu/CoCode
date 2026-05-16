/**
 * 文件查看页面 - 阅读文件内容并支持添加到对话
 */

import { Theme } from '../common/Theme'
import { apiService } from '../services/APIService'
import { HdsNavigation, HdsNavigationTitleMode, ScrollEffectType } from '@hms.hds.hdsBaseComponent'
import { hdsMaterial } from '@hms.hds.hdsMaterial'
import router from '@ohos.router'

@Entry
@Component
struct FileViewPage {
  @State filePath: string = ''
  @State fileName: string = ''
  @State fileContent: string = ''
  @State isLoading: boolean = true
  @State sessionId: string = ''
  @State readError: string = ''

  async aboutToAppear(): Promise<void> {
    const params = router.getParams() as Record<string, Object>
    if (params) {
      const fp = params['filePath']
      if (typeof fp === 'string') this.filePath = fp
      const fn = params['fileName']
      if (typeof fn === 'string') this.fileName = fn
      const sid = params['sessionId']
      if (typeof sid === 'string') this.sessionId = sid
    }
    if (this.filePath) {
      this.fileContent = await apiService.readFileText(this.filePath)
      if (!this.fileContent) {
        this.readError = '无法读取该文件（二进制文件或不支持的文件类型）'
      }
    }
    this.isLoading = false
  }

  private addToChat(): void {
    router.pushUrl({
      url: 'pages/ChatDetailPage',
      params: {
        sessionId: this.sessionId,
        title: '对话',
        attachFile: this.filePath,
        attachFileName: this.fileName
      }
    })
  }

  build() {
    Stack() {
      HdsNavigation() {
        List() {
          ListItem() { Row().width('100%').height(80) }

          ListItem() {
            if (this.isLoading) {
              Column() { LoadingProgress().width(30).height(30).color(Theme.PrimaryColor) }
                .width('100%').height(300).justifyContent(FlexAlign.Center)
            } else if (this.readError) {
              Column({ space: 12 }) {
                SymbolGlyph($r('sys.symbol.exclamationmark_triangle_fill'))
                  .fontSize(32).fontColor([Theme.WarningColor])
                Text(this.readError)
                  .fontSize(14).fontColor(Theme.TextSecondary).textAlign(TextAlign.Center)
              }.width('100%').height(200).justifyContent(FlexAlign.Center)
            } else if (this.fileContent) {
              Text() {
                Span(this.fileContent).fontSize(14).fontColor(Theme.TextPrimary).fontFamily('monospace')
              }
              .width('100%')
            }
          }
        }
        .width('100%').layoutWeight(1)
        .padding({ left: Theme.SpacingLG, right: Theme.SpacingLG })
        .scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring)
      }
      .titleBar({
        content: {
          title: { mainTitle: this.fileName || '文件' },
          menu: {
            value: [{
              content: {
                icon: $r('sys.symbol.plus'),
                action: () => { this.addToChat() }
              }
            }]
          }
        },
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
}
