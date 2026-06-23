import { HdsTabs, HdsTabsController, HdsBarStyle } from '@kit.UIDesignKit'
import { hdsMaterial } from '@hms.hds.hdsMaterial'
import { SymbolGlyphModifier } from '@kit.ArkUI'
import { router } from '@kit.ArkUI'
import { Theme } from '../common/Theme'
import { Constants } from '../common/Constants'
import { ConversationListPage } from './ConversationListPage'
import { SettingsPage } from './SettingsPage'
import { sessionStore } from '../stores/SessionStore'
import { Session, SessionStatus } from '../models/Models'
import { PixelMascot, MascotStatus, getMascotColorForSession, getMascotTypeForProvider } from '../components/PixelMascot'

/**
 * 主页面 - 使用 HdsTabs 实现原生液态玻璃Tab栏
 * 所有 Tab 都使用真实服务器数据
 */
@Component
export struct MainPage {
  private tabsController: HdsTabsController = new HdsTabsController()
  @State currentIndex: number = 0
  @State miniBarCurrentStyle: HdsBarStyle = HdsBarStyle.COLLAPSE
  @State activeSessionList: Session[] = []
  @State refreshTrigger: number = 0

  private statusListener: (sessionId: string, status: SessionStatus) => void = () => {}
  private sessionsListener: () => void = () => {}
  // 防抖：避免 activeSessionList 频繁变化导致 TabBar 结构闪烁
  private activeSessionsDebounceTimer: number = -1
  private pendingActiveSessions: Session[] = []

  aboutToAppear(): void {
    this.updateActiveSessions()
    this.statusListener = (sessionId: string, status: SessionStatus) => {
      this.scheduleUpdateActiveSessions()
    }
    this.sessionsListener = () => {
      this.scheduleUpdateActiveSessions()
    }
    sessionStore.addStatusChangedListener(this.statusListener)
    sessionStore.addSessionsChangedListener(this.sessionsListener)
  }

  aboutToDisappear(): void {
    sessionStore.removeStatusChangedListener(this.statusListener)
    sessionStore.removeSessionsChangedListener(this.sessionsListener)
    if (this.activeSessionsDebounceTimer >= 0) {
      clearTimeout(this.activeSessionsDebounceTimer)
      this.activeSessionsDebounceTimer = -1
    }
  }

  private scheduleUpdateActiveSessions(): void {
    this.pendingActiveSessions = sessionStore.getActiveSessions()
    if (this.activeSessionsDebounceTimer >= 0) {
      return
    }
    this.activeSessionsDebounceTimer = setTimeout(() => {
      this.activeSessionsDebounceTimer = -1
      this.activeSessionList = this.pendingActiveSessions
      this.refreshTrigger = Date.now()
    }, 500)
  }

  private updateActiveSessions(): void {
    this.activeSessionList = sessionStore.getActiveSessions()
    this.refreshTrigger = Date.now()
  }

  // 获取优先显示的活跃会话
  private getPriorityActiveSession(): Session | null {
    if (this.activeSessionList.length === 0) return null

    // 优先找 Claude 会话
    for (const session of this.activeSessionList) {
      if (!session.aiTool || session.aiTool === 'claude') {
        return session
      }
    }
    // 最后返回第一个
    return this.activeSessionList[0]
  }

  private navigateToSession(session: Session): void {
    router.pushUrl({
      url: 'pages/ChatDetailPage',
      params: {
        sessionId: session.id,
        title: session.title
      }
    })
  }

  build() {
    // 根据是否有活跃对话，使用不同的配置
    if (this.activeSessionList.length > 0) {
      HdsTabs({ controller: this.tabsController }) {
        this.TabContents()
      }
      .barOverlap(true)
      .barPosition(BarPosition.End)
      .barFloatingStyle({
        barBottomMargin: 28,
        systemMaterialEffect: {
          materialType: hdsMaterial.MaterialType.ADAPTIVE,
          materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
        },
        miniBar: {
          miniBarBuilder: (): void => {
            this.buildActiveSessionMiniBar()
          },
          enableMiniBarBackground: true,
          enableMiniBarClip: true,
          onBarStyleChange: (miniBarStyle: HdsBarStyle, _tabBarStyle: HdsBarStyle, _miniBarWidth: number, _tabBarWidth: number, _mode: number) => {
            this.miniBarCurrentStyle = miniBarStyle
          }
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
    } else {
      // 无活跃对话：不配置 miniBar，Tab 栏居中显示
      HdsTabs({ controller: this.tabsController }) {
        this.TabContents()
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

  // Tab 内容 - 提取为公共方法避免重复
  @Builder TabContents() {
    // Claude Tab - 真实服务器数据
    TabContent() {
      ConversationListPage({
        pageTitle: Constants.TITLE_CLAUDE
      })
    }
    .tabBar(new BottomTabBarStyle({
      normal: new SymbolGlyphModifier($r('sys.symbol.message'))
        .fontColor([$r('sys.color.ohos_id_color_bottom_tab_icon_off')]),
      selected: new SymbolGlyphModifier($r('sys.symbol.message_fill'))
        .fontColor([$r('sys.color.ohos_id_color_activated')])
    }, 'Claude'))

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

  // MiniBar Builder - 活跃会话吉祥物图标
  @Builder buildActiveSessionMiniBar() {
    if (this.miniBarCurrentStyle === HdsBarStyle.EXPAND) {
      // 展开态：显示所有活跃会话，点击跳转
      Row({ space: 8 }) {
        ForEach(this.activeSessionList, (session: Session) => {
          PixelMascot({
            mascotSize: 32,
            status: MascotStatus.PROCESSING,
            bodyColor: getMascotColorForSession(session.id),
            mascotType: getMascotTypeForProvider(session.aiTool || '')
          })
          .onClick(() => {
            this.navigateToSession(session)
          })
        })
      }
      .padding({ left: 16, right: 16, top: 10, bottom: 10 })
    } else {
      // 收缩态：只显示一个图标（优先 Claude）
      if (this.getPriorityActiveSession()) {
        PixelMascot({
          mascotSize: 28,
          status: MascotStatus.PROCESSING,
          bodyColor: getMascotColorForSession(this.getPriorityActiveSession()!.id),
          mascotType: getMascotTypeForProvider(this.getPriorityActiveSession()!.aiTool || '')
        })
        .padding({ left: 12, right: 12, top: 8, bottom: 8 })
      }
    }
  }
}
