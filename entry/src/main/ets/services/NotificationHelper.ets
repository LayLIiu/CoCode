/**
 * 通知辅助工具
 * 在后台收到新消息时发送系统通知
 */

import { notificationManager } from '@kit.NotificationKit'
import { wantAgent, WantAgent, common } from '@kit.AbilityKit'
import { appState } from '../stores/AppState'

class NotificationParams {
  id: number = 0
  title: string = ''
  text: string = ''
  label: string = ''
  sessionId: string = ''
}

export class NotificationHelper {
  private static instance: NotificationHelper
  private context: Context | null = null
  private isNotificationEnabled: boolean = false
  private isSlotCreated: boolean = false
  private bundleName: string = ''

  static getInstance(): NotificationHelper {
    if (!NotificationHelper.instance) {
      NotificationHelper.instance = new NotificationHelper()
    }
    return NotificationHelper.instance
  }

  setContext(context: Context): void {
    this.context = context
    this.bundleName = context.applicationInfo.name
  }

  async requestNotificationPermission(): Promise<void> {
    if (!this.context) return
    try {
      const enabled = await notificationManager.isNotificationEnabled()
      if (enabled) {
        this.isNotificationEnabled = true
        await this.ensureSlotCreated()
      } else {
        // 尝试请求权限，UI 未就绪时可能失败——不设 false，保持默认 false
        // publishNotification 中会兜底重试
        try {
          await notificationManager.requestEnableNotification(this.context as common.UIAbilityContext)
          this.isNotificationEnabled = true
          await this.ensureSlotCreated()
        } catch (innerErr) {
          console.warn('[NotificationHelper] requestEnableNotification failed (UI not ready?), will retry later')
          // 保持 this.isNotificationEnabled 为 false，publish 时会再试
        }
      }
    } catch (e) {
      console.warn('[NotificationHelper] isNotificationEnabled check failed: ' + JSON.stringify(e))
      // 保持 this.isNotificationEnabled 为 false
    }
  }

  private async ensureSlotCreated(): Promise<void> {
    if (this.isSlotCreated) return
    try {
      await notificationManager.addSlot(notificationManager.SlotType.SOCIAL_COMMUNICATION)
      this.isSlotCreated = true
    } catch (e) {
      // addSlot 在槽位已存在时也会报错，标记已创建避免重复尝试
      this.isSlotCreated = true
    }
  }

  async notifyNewMessage(aiName: string, sessionTitle: string, content: string, sessionId: string): Promise<void> {
    if (!this.shouldNotify()) return
    const displayTitle = sessionTitle || '新消息'
    let displayText = content
    if (displayText.length > 200) {
      displayText = displayText.substring(0, 197) + '...'
    }
    const p = new NotificationParams()
    p.id = this.hashSessionId(sessionId)
    p.title = aiName + ' 新回复 - ' + displayTitle
    p.text = displayText
    p.label = 'ChatMessage'
    p.sessionId = sessionId
    await this.publishNotification(p)
  }

  async notifyPermissionRequest(aiName: string, sessionTitle: string, toolName: string, sessionId: string): Promise<void> {
    if (!this.shouldNotify(true)) return
    const p = new NotificationParams()
    p.id = this.hashSessionId(sessionId) + 10000
    p.title = aiName + ' 权限请求 - ' + sessionTitle
    p.text = '工具 "' + toolName + '" 需要您的授权'
    p.label = 'PermissionRequest'
    p.sessionId = sessionId
    await this.publishNotification(p)
  }

  async notifyQuestion(aiName: string, sessionTitle: string, text: string, sessionId: string): Promise<void> {
    if (!this.shouldNotify(true)) return
    const p = new NotificationParams()
    p.id = this.hashSessionId(sessionId) + 20000
    p.title = aiName + ' 问题 - ' + sessionTitle
    p.text = text.length > 100 ? text.substring(0, 97) + '...' : text
    p.label = 'Question'
    p.sessionId = sessionId
    await this.publishNotification(p)
  }

  private shouldNotify(allowInForeground: boolean = false): boolean {
    if (appState.isInForeground && !allowInForeground) {
      return false
    }
    return true
  }

  private async publishNotification(params: NotificationParams): Promise<void> {
    if (!this.context) return
    // 权限未确认时检查（不请求——requestEnableNotification 必须在前台调用）
    // 权限请求已在 EntryAbility.onForeground 中处理
    if (!this.isNotificationEnabled) {
      try {
        const enabled = await notificationManager.isNotificationEnabled()
        if (enabled) {
          this.isNotificationEnabled = true
        } else {
          // 权限未授予，跳过（前台时 requestNotificationPermission 已尝试过）
          return
        }
      } catch (e) {
        console.warn('[NotificationHelper] publish: permission check failed: ' + JSON.stringify(e))
        return
      }
    }
    if (!this.isSlotCreated) {
      await this.ensureSlotCreated()
    }
    try {
      const agent = await this.createWantAgent(params.sessionId)

      const titleStr = params.title
      const textStr = params.text
      const labelStr = params.label
      const idNum = params.id

      const request: notificationManager.NotificationRequest = {
        id: idNum,
        notificationSlotType: notificationManager.SlotType.SOCIAL_COMMUNICATION,
        content: {
          notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
          normal: {
            title: titleStr,
            text: textStr
          }
        },
        wantAgent: agent,
        isAlertOnce: true,
        showDeliveryTime: true,
        label: labelStr
      }

      await notificationManager.publish(request)
      console.info('[NotificationHelper] notification published: id=' + idNum + ' title=' + titleStr)
    } catch (e) {
      console.warn('[NotificationHelper] publish error: ' + JSON.stringify(e))
    }
  }

  async cancelNotification(sessionId: string): Promise<void> {
    try {
      await notificationManager.cancel(this.hashSessionId(sessionId))
    } catch (e) {
      // ignore
    }
  }

  async cancelAll(): Promise<void> {
    try {
      await notificationManager.cancelAll()
    } catch (e) {
      // ignore
    }
  }

  private async createWantAgent(sessionId: string): Promise<WantAgent> {
    const bundleNameStr = this.bundleName || 'com.cocode.app'
    const reqCode = this.hashSessionId(sessionId)

    const wantInfo = wantAgent.getWantAgent({
      wants: [{
        bundleName: bundleNameStr,
        abilityName: 'EntryAbility',
        parameters: {
          'sessionId': sessionId,
          'fromNotification': 'true'
        }
      }],
      operationType: wantAgent.OperationType.START_ABILITY,
      requestCode: reqCode,
      wantAgentFlags: [wantAgent.WantAgentFlags.CONSTANT_FLAG]
    })
    return await wantInfo
  }

  private hashSessionId(sessionId: string): number {
    let hash = 0
    for (let i = 0; i < sessionId.length; i++) {
      hash = ((hash << 5) - hash) + sessionId.charCodeAt(i)
      hash = hash & hash
    }
    return Math.abs(hash) % 2147483647
  }
}

export const notificationHelper = NotificationHelper.getInstance()
