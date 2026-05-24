/**
 * 入口页面 - 检查登录状态 & 生物识别锁屏
 */

import { MainPage } from './MainPage'
import { LoginPage } from './LoginPage'
import { authStore } from '../stores/AuthStore'
import { appState } from '../stores/AppState'
import { sessionStore } from '../stores/SessionStore'
import { GlobalToast } from '../components/GlobalToast'
import { connectionManager } from '../services/ConnectionManager'
import type { Context } from '@kit.AbilityKit'
import { Theme } from '../common/Theme'

@Entry
@Component
struct Index {
  @State isLoggedIn: boolean = false
  @State isInitialized: boolean = false
  @State isLocked: boolean = false
  @State authFailed: boolean = false
  private authTimer: number = -1

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
  }

  private authenticate(): void {
    // 生物识别功能待后续适配，当前直接解锁
    this.isLocked = false
    authStore.unlock()
    this.initData()
  }

  private initData(): void {
    // 快速启动连接：立即使用已配置的 URL，不等待网络检测
    if (authStore.serverUrl) {
      connectionManager.quickStart()
    }

    // 并发执行所有初始化任务，无需延迟等待
    sessionStore.fetchSessions().then(() => {
      console.info('[Index] Sessions loaded')
    }).catch((e: Error) => {
      console.error(`[Index] Load sessions error: ${e.message}`)
    })

    // 立即订阅 WebSocket
    try {
      sessionStore.subscribeToAllSessions()
    } catch (e) {
      console.error(`[Index] Subscribe error: ${e}`)
    }

    // 立即初始化应用状态
    appState.initialize().catch((e: Error) => {
      console.error(`[Index] Init app state error: ${e.message}`)
    })
  }

  build() {
    Stack() {
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

      // 全局 Toast 覆盖层
      GlobalToast()
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  SplashScreen() {
    Column({ space: 18 }) {
      Stack() {
        Circle()
          .width(76)
          .height(76)
          .fill('rgba(10, 132, 255, 0.14)')

        SymbolGlyph($r('sys.symbol.message_fill'))
          .fontSize(38)
          .fontColor([Theme.AccentBlue])
      }
      .width(76)
      .height(76)

      Text('正在进入工作台')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(Theme.TextPrimary)

      LoadingProgress()
        .width(24)
        .height(24)
        .color(Theme.AccentBlue)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor('#101114')
  }

  @Builder
  LockScreen() {
    Column({ space: 20 }) {
      Stack() {
        Circle()
          .width(84)
          .height(84)
          .fill('rgba(10, 132, 255, 0.14)')

        SymbolGlyph($r('sys.symbol.message_fill'))
          .fontSize(42)
          .fontColor([Theme.AccentBlue])
      }
      .width(84)
      .height(84)

      Text('Claude Code')
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor(Theme.TextPrimary)

      if (this.authFailed) {
        Text('验证失败，请重试')
          .fontSize(14)
          .fontColor(Theme.ErrorColor)
      } else {
        Text('请验证身份以解锁')
          .fontSize(14)
          .fontColor(Theme.TextSecondary)
      }

      LoadingProgress()
        .width(32)
        .height(32)
        .color(Theme.AccentBlue)
        .opacity(this.authFailed ? 0.3 : 1.0)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor('#101114')
  }
}
