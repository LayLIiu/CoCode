/**
 * 入口页面 - 检查登录状态
 */

import { MainPage } from './MainPage'
import { LoginPage } from './LoginPage'
import { authStore } from '../stores/AuthStore'
import { appState } from '../stores/AppState'
import { sessionStore } from '../stores/SessionStore'

@Entry
@Component
struct Index {
  @State isLoggedIn: boolean = false
  @State isInitialized: boolean = false

  async aboutToAppear(): Promise<void> {
    // 等待 authStore 初始化完成后再判断登录状态
    await authStore.setContext(getContext(this) as Context)
    this.isLoggedIn = authStore.isLoggedIn
    this.isInitialized = true

    if (this.isLoggedIn) {
      // 异步初始化数据，不阻塞UI
      setTimeout(() => {
        this.initData()
      }, 500)
    }
  }

  private initData(): void {
    // 获取会话列表
    sessionStore.fetchSessions().then(() => {
      console.info('[Index] Sessions loaded')
    }).catch((e: Error) => {
      console.error(`[Index] Load sessions error: ${e.message}`)
    })

    // 延迟订阅 WebSocket
    setTimeout(() => {
      try {
        sessionStore.subscribeToAllSessions()
      } catch (e) {
        console.error(`[Index] Subscribe error: ${e}`)
      }
    }, 300)

    // 延迟初始化应用状态
    setTimeout(() => {
      appState.initialize().catch((e: Error) => {
        console.error(`[Index] Init app state error: ${e.message}`)
      })
    }, 500)
  }

  build() {
    Column() {
      if (!this.isInitialized) {
        this.SplashScreen()
      } else if (this.isLoggedIn) {
        MainPage()
      } else {
        LoginPage()
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  SplashScreen() {
    Column() {
      SymbolGlyph($r('sys.symbol.message_fill'))
        .fontSize(64)
        .fontColor(['#0A84FF'])

      LoadingProgress()
        .width(24)
        .height(24)
        .color('#0A84FF')
        .margin({ top: 24 })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor('#000000')
  }
}
