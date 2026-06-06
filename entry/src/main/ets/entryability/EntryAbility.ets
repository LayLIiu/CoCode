import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { window, router } from '@kit.ArkUI'
import { backgroundTaskManager } from '@kit.BackgroundTasksKit'
import { pushService } from '@kit.PushKit'
import { BusinessError } from '@kit.BasicServicesKit'
import { authStore } from '../stores/AuthStore'
import { apiService } from '../services/APIService'
import { appState } from '../stores/AppState'
import { sessionStore } from '../stores/SessionStore'
import { wsService } from '../services/WebSocketService'
import { storageService } from '../services/StorageService'
import { notificationHelper } from '../services/NotificationHelper'
import { liveViewService } from '../services/LiveViewService'
import { initScanService } from '../services/ScanService'
import { connectionManager } from '../services/ConnectionManager'

const DOMAIN = 0x0000

export default class EntryAbility extends UIAbility {
  private isBackgroundTaskRunning: boolean = false
  private foregroundLockTimer: number = -1
  private foregroundReconnectTimer: number = -1
  private foregroundRefreshTimer: number = -1

  async onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): Promise<void> {
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET)
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err))
    }
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate')

    // 初始化 Store
    await authStore.setContext(this.context)
    initScanService(this.context)
    notificationHelper.setContext(this.context)
    liveViewService.setBundleName(this.context.applicationInfo.name)

    // 初始化本地存储
    await storageService.init(this.context)
    hilog.info(DOMAIN, 'testTag', 'StorageService initialized')

    // 请求通知授权 & 同步 NotificationHelper 内部状态
    try {
      await notificationHelper.requestNotificationPermission()
      hilog.info(DOMAIN, 'testTag', 'Notification permission granted')
    } catch (e) {
      hilog.error(DOMAIN, 'testTag', 'Notification permission error: %{public}s', JSON.stringify(e))
    }
    hilog.info(DOMAIN, 'testTag', 'Notification helper initialized')

    // 处理通知点击跳转
    this.handleNotificationWant(want)

    // 获取华为推送 Token（非阻塞，不阻碍 App 启动）
    // 注意：调试签名下会报 1000900010 (Illegal application identity)，
    // 这是正常现象，需使用 AGC 正式签名才能获取成功
    this.initPushToken()
  }

  onNewWant(want: Want): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onNewWant')
    this.handleNotificationWant(want)
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy')
    this.clearForegroundTimers()
    // 断开所有 WebSocket 连接
    wsService.disconnectAll()
  }

  private clearForegroundTimers(): void {
    if (this.foregroundLockTimer >= 0) {
      clearTimeout(this.foregroundLockTimer)
      this.foregroundLockTimer = -1
    }
    if (this.foregroundReconnectTimer >= 0) {
      clearTimeout(this.foregroundReconnectTimer)
      this.foregroundReconnectTimer = -1
    }
    if (this.foregroundRefreshTimer >= 0) {
      clearTimeout(this.foregroundRefreshTimer)
      this.foregroundRefreshTimer = -1
    }
  }

  /**
   * 初始化推送 Token
   * 调试签名下会报 1000900010 (Illegal application identity)，属正常现象
   * 仅在使用 AGC 正式签名时才能成功获取
   */
  private initPushToken(): void {
    hilog.info(DOMAIN, 'testTag', 'Requesting push token...')
    pushService.getToken().then((token: string) => {
      hilog.info(DOMAIN, 'testTag', 'Succeeded in getting push token: %{public}s', token)
      if (token) {
        apiService.uploadPushToken(token).then(() => {
          hilog.info(DOMAIN, 'testTag', 'Push token uploaded to server')
        }).catch((err: Error) => {
          hilog.error(DOMAIN, 'testTag', 'Failed to upload push token: %{public}s', err.message)
        })
      }
    }).catch((err: Error) => {
      const code = (err as BusinessError).code
      if (code === 1000900010) {
        // 调试签名下的预期错误，降级为 info 级别避免日志刷屏
        hilog.info(DOMAIN, 'testTag',
          'Push token unavailable (debug signing). Use AGC release signing for push notifications.')
      } else {
        hilog.error(DOMAIN, 'testTag', 'Failed to get push token: %{public}d %{public}s',
          code, (err as BusinessError).message)
      }
    })
  }

  private handleNotificationWant(want: Want): void {
    if (!want.parameters) return
    const fromNotification = want.parameters['fromNotification']
    const sessionId = want.parameters['sessionId']
    if (fromNotification === 'true' && typeof sessionId === 'string' && sessionId) {
      appState.pendingSessionId = sessionId
      hilog.info(DOMAIN, 'testTag', 'Notification deep link: sessionId=%{public}s', sessionId)
      // 延迟跳转等 Index 页加载完成
      setTimeout(() => {
        try {
          sessionStore.setCurrentSession(sessionId)
          router.pushUrl({
            url: 'pages/ChatDetailPage',
            params: { sessionId: sessionId }
          })
        } catch (e) {
          hilog.error(DOMAIN, 'testTag', 'Notification navigation error: %{public}s', JSON.stringify(e))
        }
      }, 500)
    }
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate')

    windowStage.getMainWindow((err, mainWindow) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to get main window. Cause: %{public}s', JSON.stringify(err))
        return
      }

      // 设置窗口全屏
      mainWindow.setWindowLayoutFullScreen(true).then(() => {
        hilog.info(DOMAIN, 'testTag', 'Succeeded in setting window layout full screen.')
      }).catch((err: Error) => {
        hilog.error(DOMAIN, 'testTag', 'Failed to set window layout full screen. Cause: %{public}s', JSON.stringify(err))
      })

      // 设置状态栏透明，实现全面屏沉浸式效果
      mainWindow.setWindowSystemBarProperties({
        statusBarColor: '#00000000',
        statusBarContentColor: '#FFFFFF',
        navigationBarColor: '#00000000',
        navigationBarContentColor: '#FFFFFF'
      }).then(() => {
        hilog.info(DOMAIN, 'testTag', 'Succeeded in setting system bar properties.')
      }).catch((err: Error) => {
        hilog.error(DOMAIN, 'testTag', 'Failed to set system bar properties. Cause: %{public}s', JSON.stringify(err))
      })
    })

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err))
        return
      }
      hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.')
    })
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy')
  }

  async onForeground(): Promise<void> {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground')
    appState.isInForeground = true
    this.clearForegroundTimers()

    // 已登录且开启生物识别 → 锁定应用（异步执行，不阻塞 UI）
    if (authStore.isLoggedIn && authStore.biometricEnabled) {
      // 使用 setTimeout 延后执行，避免阻塞 UI 渲染
      this.foregroundLockTimer = setTimeout(() => {
        this.foregroundLockTimer = -1
        authStore.lock()
      }, 100)
    }

    // 异步执行所有清理操作，不阻塞 UI
    // 1. 取消通知
    notificationHelper.cancelAll().catch((e: Error) => {
      hilog.error(DOMAIN, 'testTag', 'Cancel notifications error: %{public}s', e.message)
    })

    // 2. 请求通知权限（异步，不等待）
    notificationHelper.requestNotificationPermission().catch((e: Error) => {
      hilog.error(DOMAIN, 'testTag', 'Notification permission request error: %{public}s', e.message)
    })

    // 3. 停止后台任务（异步，不等待）
    backgroundTaskManager.stopBackgroundRunning(this.context).then(() => {
      hilog.info(DOMAIN, 'testTag', 'Background task stopped')
      this.isBackgroundTaskRunning = false
    }).catch(() => {
      // 可能本来就没有在运行后台任务，忽略错误
      this.isBackgroundTaskRunning = false
    })

    // 4. 连接恢复（延后执行，避开窗口恢复和后台任务停止的高峰）
    if (authStore.serverUrl) {
      // 回前台后先让首帧稳定，再恢复网络探测和 WebSocket。
      this.foregroundReconnectTimer = setTimeout(() => {
        this.foregroundReconnectTimer = -1
        connectionManager.quickStart()
        wsService.resumeFromForeground(authStore.serverUrl)
        hilog.info(DOMAIN, 'testTag', 'WebSocket resumed on foreground')
      }, 1200)
    }

    // 5. 数据加载（放在连接恢复之后，避免回前台瞬间同时触发大量任务）
    this.foregroundRefreshTimer = setTimeout(() => {
      this.foregroundRefreshTimer = -1
      sessionStore.syncOfficialCodexThreadsToLocal(80).catch((e: Error) => {
        hilog.error(DOMAIN, 'testTag', 'Official Codex thread sync on foreground error: %{public}s', e.message)
      })
      if (sessionStore.currentSessionId) {
        sessionStore.syncCurrentOfficialCodexSession().catch((e: Error) => {
          hilog.error(DOMAIN, 'testTag', 'Official Codex foreground sync error: %{public}s', e.message)
        })
      }
      const dataAgeMs = Date.now() - sessionStore.lastFetchedAt
      if (dataAgeMs < 30_000) {
        hilog.info(DOMAIN, 'testTag', 'Data fetched %{public}dms ago, skipping refresh', dataAgeMs)
      } else {
        sessionStore.fetchSessions().then(() => {
          hilog.info(DOMAIN, 'testTag', 'Sessions loaded')
          if (sessionStore.currentSessionId) {
            sessionStore.loadMessages(sessionStore.currentSessionId)
          }
        }).catch((e: Error) => {
          hilog.error(DOMAIN, 'testTag', 'Data refresh error: %{public}s', e.message)
        })
      }
    }, 2500)
  }

  async onBackground(): Promise<void> {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground')
    appState.isInForeground = false
    this.clearForegroundTimers()

    // 记录进入后台的时间戳，前台回来时检测后台期间的新消息
    appState.lastBackgroundTimestamp = Date.now()

    // 后台期间不再保持 WebSocket 心跳/重连/连接探测。
    // HarmonyOS 长时间冻结后，这些定时器会在回前台集中补跑，容易造成卡死和崩溃。
    wsService.pauseForBackground()
    connectionManager.stopPeriodicCheck()
    this.isBackgroundTaskRunning = false
  }
}
