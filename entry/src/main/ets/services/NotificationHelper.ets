/**
 * 通知辅助工具
 * 在后台收到新消息时发送系统通知
 */

import { notificationManager } from '@kit.NotificationKit'
import { wantAgent, WantAgent } from '@kit.AbilityKit'
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
      } else {
        await notificationManager.requestEnableNotification()
        this.isNotificationEnabled = true
      }
      await this.ensureSlotCreated()
    } catch (e) {
      this.isNotificationEnabled = false
    }
  }

  private async ensureSlotCreated(): Promise<void> {
    if (this.isSlotCreated) return
    try {
      await notificationManager.addSlot(notificationManager.SlotType.SOCIAL_COMMUNICATION)
      this.isSlotCreated = true
    } catch (e) {
      // ignore slot creation error
    }
  }

  async notifyNewMessage(sessionTitle: string, content: string, sessionId: string): Promise<void> {
    if (!this.shouldNotify()) return
    const p = new NotificationParams()
    p.id = this.hashSessionId(sessionId)
    p.title = sessionTitle || '新消息'
    p.text = content.length > 100 ? content.substring(0, 97) + '...' : content
    p.label = 'ChatMessage'
    p.sessionId = sessionId
    await this.publishNotification(p)
  }

  async notifyPermissionRequest(sessionTitle: string, toolName: string, sessionId: string): Promise<void> {
    if (!this.shouldNotify()) return
    const p = new NotificationParams()
    p.id = this.hashSessionId(sessionId) + 10000
    p.title = '权限请求 - ' + sessionTitle
    p.text = '工具 "' + toolName + '" 需要您的授权'
    p.label = 'PermissionRequest'
    p.sessionId = sessionId
    await this.publishNotification(p)
  }

  async notifyQuestion(sessionTitle: string, text: string, sessionId: string): Promise<void> {
    if (!this.shouldNotify()) return
    const p = new NotificationParams()
    p.id = this.hashSessionId(sessionId) + 20000
    p.title = '问题 - ' + sessionTitle
    p.text = text.length > 100 ? text.substring(0, 97) + '...' : text
    p.label = 'Question'
    p.sessionId = sessionId
    await this.publishNotification(p)
  }

  private shouldNotify(): boolean {
    if (appState.isInForeground) {
      return false
    }
    return true
  }

  private async publishNotification(params: NotificationParams): Promise<void> {
    if (!this.context) return
    if (!this.isNotificationEnabled) {
      try {
        const enabled = await notificationManager.isNotificationEnabled()
        if (!enabled) return
        this.isNotificationEnabled = true
      } catch (e) {
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
    } catch (e) {
      // ignore
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
