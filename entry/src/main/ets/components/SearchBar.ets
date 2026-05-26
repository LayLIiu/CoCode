import { Theme } from '../common/Theme'
import { hdsMaterial, HdsTabs } from '@kit.UIDesignKit'

/**
 * 搜索栏组件 - 沉浸光感液态玻璃效果
 * 使用 HdsTabs 的 barFloatingStyle 承载搜索输入内容
 */
@Component
export struct SearchBar {
  @Link searchText: string
  placeholder: string = '搜索对话...'
  onSearchChange: () => void = () => {}
  @State searchBarWidth: number = 1

  private readonly barHeight: number = 48
  private readonly containerHeight: number = 72
  private readonly barBottomMargin: number = 12
  private readonly horizontalOverflow: number = 32
  private readonly visualInset: number = 7.5

  private getSearchBarWidth(): number {
    return this.searchBarWidth > 1 ? this.searchBarWidth : 1
  }

  private getVisibleBarWidth(): number {
    const visibleWidth = this.getSearchBarWidth() - this.visualInset * 2
    return visibleWidth > 1 ? visibleWidth : 1
  }

  private getHostWidth(): number {
    return this.getVisibleBarWidth() + this.horizontalOverflow * 2
  }

  @Builder
  searchContent() {
    Row() {
      Image($r('app.media.ic_search'))
        .width(20)
        .height(20)
        .fillColor(Theme.TextSecondary)
        .margin({ right: Theme.SpacingSM })
        .translate({ y: -3 })

      TextInput({ placeholder: this.placeholder, text: this.searchText })
        .layoutWeight(1)
        .height(36)
        .padding({ top: 0, bottom: 0 })
        .backgroundColor(Color.Transparent)
        .placeholderColor(Theme.TextSecondary)
        .placeholderFont({ size: Theme.FontBody })
        .fontColor(Theme.TextPrimary)
        .fontSize(Theme.FontBody)
        .caretColor(Theme.AccentBlue)
        .translate({ y: -3 })
        .onChange((value: string) => {
          this.searchText = value
          this.onSearchChange()
        })

      if (this.searchText.length > 0) {
        Image($r('app.media.ic_clear'))
          .width(18)
          .height(18)
          .fillColor(Theme.TextSecondary)
          .translate({ y: -3 })
          .onClick(() => {
            this.searchText = ''
            this.onSearchChange()
          })
      }
    }
      .width(this.getVisibleBarWidth())
      .height(this.barHeight)
      .padding({ left: Theme.SpacingMD, right: Theme.SpacingMD })
      .alignItems(VerticalAlign.Center)
      .backgroundColor(Color.Transparent)
  }

  build() {
    Stack() {
      HdsTabs() {
        TabContent()
          .tabBar(this.searchContent())
      }
      .width(this.getHostWidth())
      .height(this.containerHeight)
      .padding({ left: this.horizontalOverflow, right: this.horizontalOverflow })
      .barWidth(this.getVisibleBarWidth())
      .barHeight(this.barHeight)
      .barOverlap(true)
      .barPosition(BarPosition.End)
      .scrollable(false)
      .animationDuration(0)
      .barFloatingStyle({
        gradientMask: {
          maskColor: 'rgba(0,0,0,0)'
        },
        barBottomMargin: this.barBottomMargin,
        systemMaterialEffect: {
          materialType: hdsMaterial.MaterialType.IMMERSIVE,
          materialLevel: hdsMaterial.MaterialLevel.EXQUISITE
        }
      })
      .backgroundColor(Color.Transparent)
      .border({ width: 0 })
      .shadow({ radius: 0 })
    }
    .width('100%')
    .height(this.containerHeight)
    .alignContent(Alignment.Center)
    .clip(false)
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      this.searchBarWidth = newArea.width as number
    })
  }
}
