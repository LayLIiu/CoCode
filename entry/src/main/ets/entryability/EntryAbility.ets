import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { window } from '@kit.ArkUI'
import { backgroundTaskManager } from '@kit.BackgroundTasksKit'
import { wantAgent } from '@kit.AbilityKit'
import { authStore } from '../stores/AuthStore'
import { appState } from '../stores/AppState'
import { sessionStore } from '../stores/SessionStore'
import { wsService } from '../services/WebSocketService'
import { storageService } from '../services/StorageService'
import { notificationHelper } from '../services/NotificationHelper'

const DOMAIN = 0x0000

export default class EntryAbility extends UIAbility {
  async onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): Promise<void> {
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET)
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err))
    }
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate')

    // 初始化 Store
    authStore.setContext(this.context)
    notificationHelper.setContext(this.context)

    // 初始化本地存储
    await storageService.init(this.context)
    hilog.info(DOMAIN, 'testTag', 'StorageService initialized')
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy')
    // 断开所有 WebSocket 连接
    wsService.disconnectAll()
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

    // 取消所有通知（用户已回到应用）
    await notificationHelper.cancelAll()

    // 停止后台任务
    try {
      await backgroundTaskManager.stopBackgroundRunning(this.context)
      hilog.info(DOMAIN, 'testTag', 'Background task stopped')
    } catch (e) {
      // 可能本来就没有在运行后台任务
    }

    // 重连 WebSocket
    if (authStore.serverUrl) {
      wsService.setServerUrl(authStore.serverUrl)
      wsService.forceReconnectAll()
      hilog.info(DOMAIN, 'testTag', 'WebSocket reconnected on foreground')
    }

    // 刷新数据
    try {
      await sessionStore.fetchSessions()
      if (sessionStore.currentSessionId) {
        await sessionStore.loadMessages(sessionStore.currentSessionId)
      }
      hilog.info(DOMAIN, 'testTag', 'Data refreshed on foreground')
    } catch (e) {
      hilog.error(DOMAIN, 'testTag', 'Data refresh error: %{public}s', JSON.stringify(e))
    }
  }

  async onBackground(): Promise<void> {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground')
    appState.isInForeground = false

    // 申请后台长时任务，保持 WebSocket 连接
    try {
      const wantAgentInfo: wantAgent.WantAgentInfo = {
        wants: [{
          bundleName: this.context.applicationInfo.name,
          abilityName: 'EntryAbility'
        }],
        operationType: wantAgent.OperationType.START_ABILITY,
        requestCode: 0,
        wantAgentFlags: [wantAgent.WantAgentFlags.CONSTANT_FLAG]
      }

      const agent = await wantAgent.getWantAgent(wantAgentInfo)
      await backgroundTaskManager.startBackgroundRunning(this.context,
        backgroundTaskManager.BackgroundMode.DATA_TRANSFER, agent)
      hilog.info(DOMAIN, 'testTag', 'Background task started for WebSocket keepalive')
    } catch (e) {
      hilog.error(DOMAIN, 'testTag', 'Background task start error: %{public}s', JSON.stringify(e))
    }
  }
}
