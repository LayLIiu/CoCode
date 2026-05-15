import { HdsTabs, HdsTabsController } from '@kit.UIDesignKit'
import { hdsMaterial } from '@hms.hds.hdsMaterial'
import { SymbolGlyphModifier } from '@kit.ArkUI'
import { Theme } from '../common/Theme'
import { Constants, TabIndex } from '../common/Constants'
import { TabType } from '../viewmodel/ConversationModel'
import { ConversationListPage } from './ConversationListPage'
import { SettingsPage } from './SettingsPage'

/**
 * 主页面 - 使用 HdsTabs 实现原生液态玻璃Tab栏
 * 所有 Tab 都使用真实服务器数据
 */
@Component
export struct MainPage {
  private tabsController: HdsTabsController = new HdsTabsController()
  @State currentIndex: number = 0

  build() {
    HdsTabs({ controller: this.tabsController }) {
      // Claude Tab - 真实服务器数据
      TabContent() {
        ConversationListPage({
          tabType: TabType.CLAUDE,
          pageTitle: Constants.TITLE_CLAUDE
        })
      }
      .tabBar(new BottomTabBarStyle({
        normal: new SymbolGlyphModifier($r('sys.symbol.message'))
          .fontColor([$r('sys.color.ohos_id_color_bottom_tab_icon_off')]),
        selected: new SymbolGlyphModifier($r('sys.symbol.message_fill'))
          .fontColor([$r('sys.color.ohos_id_color_activated')])
      }, 'Claude'))

      // Codex Tab - 真实服务器数据
      TabContent() {
        ConversationListPage({
          tabType: TabType.CODEX,
          pageTitle: Constants.TITLE_CODEX
        })
      }
      .tabBar(new BottomTabBarStyle({
        normal: new SymbolGlyphModifier($r('sys.symbol.grid'))
          .fontColor([$r('sys.color.ohos_id_color_bottom_tab_icon_off')]),
        selected: new SymbolGlyphModifier($r('sys.symbol.grid'))
          .fontColor([$r('sys.color.ohos_id_color_activated')])
      }, 'Codex'))

      // Open Code Tab - 真实服务器数据
      TabContent() {
        ConversationListPage({
          tabType: TabType.OPEN_CODE,
          pageTitle: Constants.TITLE_OPEN_CODE
        })
      }
      .tabBar(new BottomTabBarStyle({
        normal: new SymbolGlyphModifier($r('sys.symbol.chevron_right'))
          .fontColor([$r('sys.color.ohos_id_color_bottom_tab_icon_off')]),
        selected: new SymbolGlyphModifier($r('sys.symbol.chevron_right'))
          .fontColor([$r('sys.color.ohos_id_color_activated')])
      }, 'Open Code'))

      // Settings Tab
      TabContent() {
        SettingsPage()
      }
      .tabBar(new BottomTabBarStyle({
        normal: new SymbolGlyphModifier($r('sys.symbol.gearshape'))
          .fontColor([$r('sys.color.ohos_id_color_bottom_tab_icon_off')]),
        selected: new SymbolGlyphModifier($r('sys.symbol.gearshape_fill'))
          .fontColor([$r('sys.color.ohos_id_color_activated')])
      }, '设置'))
    }
    .barOverlap(true)
    .barPosition(BarPosition.End)
    .barFloatingStyle({
      barBottomMargin: 28,
      systemMaterialEffect: {
        materialType: hdsMaterial.MaterialType.ADAPTIVE,
        materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
      }
    })
    .barMode(BarMode.Fixed)
    .scrollable(false)
    .backgroundColor(Color.Transparent)
    .width('100%')
    .height('100%')
    .onChange((index: number) => {
      this.currentIndex = index
    })
  }
}
