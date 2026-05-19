/**
 * 入口页面 - 检查登录状态 & 生物识别锁屏
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
  @State isLocked: boolean = false
  @State authFailed: boolean = false
  private authTimer: number = -1
  private subscribeTimer: number = -1
  private appStateTimer: number = -1

  async aboutToAppear(): Promise<void> {
    // 等待 authStore 初始化
    await authStore.setContext(getContext(this) as Context)
    this.isLoggedIn = authStore.isLoggedIn
    this.isLocked = authStore.isLocked
    this.isInitialized = true

    if (this.isLoggedIn && !this.isLocked) {
      this.initData()
    }

    // 如果已锁定，自动触发生物识别
    if (this.isLocked) {
      this.authTimer = setTimeout(() => {
        this.authenticate()
        this.authTimer = -1
      }, 500)
    }
  }

  aboutToDisappear(): void {
    if (this.authTimer >= 0) {
      clearTimeout(this.authTimer)
      this.authTimer = -1
    }
    if (this.subscribeTimer >= 0) {
      clearTimeout(this.subscribeTimer)
      this.subscribeTimer = -1
    }
    if (this.appStateTimer >= 0) {
      clearTimeout(this.appStateTimer)
      this.appStateTimer = -1
    }
  }

  private authenticate(): void {
    // 生物识别功能待后续适配，当前直接解锁
    this.isLocked = false
    authStore.unlock()
    this.initData()
  }

  private initData(): void {
    // 获取会话列表
    sessionStore.fetchSessions().then(() => {
      console.info('[Index] Sessions loaded')
    }).catch((e: Error) => {
      console.error(`[Index] Load sessions error: ${e.message}`)
    })

    // 延迟订阅 WebSocket
    this.subscribeTimer = setTimeout(() => {
      try {
        sessionStore.subscribeToAllSessions()
      } catch (e) {
        console.error(`[Index] Subscribe error: ${e}`)
      }
    }, 300)

    // 延迟初始化应用状态
    this.appStateTimer = setTimeout(() => {
      appState.initialize().catch((e: Error) => {
        console.error(`[Index] Init app state error: ${e.message}`)
      })
    }, 500)
  }

  build() {
    Column() {
      if (!this.isInitialized) {
        this.SplashScreen()
      } else if (this.isLocked) {
        this.LockScreen()
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

  @Builder
  LockScreen() {
    Column({ space: 24 }) {
      SymbolGlyph($r('sys.symbol.message_fill'))
        .fontSize(72)
        .fontColor(['#0A84FF'])

      Text('Claude Code')
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor('#FFFFFF')

      if (this.authFailed) {
        Text('验证失败，请重试')
          .fontSize(14)
          .fontColor('#FF3B30')
      } else {
        Text('请验证身份以解锁')
          .fontSize(14)
          .fontColor('#8E8E93')
      }

      LoadingProgress()
        .width(32)
        .height(32)
        .color('#0A84FF')
        .opacity(this.authFailed ? 0.3 : 1.0)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor('#000000')
  }
}
