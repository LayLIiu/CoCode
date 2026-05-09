/**
 * 通知辅助工具
 * 在后台收到新消息时发送系统通知
 */

import { notificationManager } from '@kit.NotificationKit'
import { wantAgent, WantAgent } from '@kit.AbilityKit'
import { appState } from '../stores/AppState'

export class NotificationHelper {
  private static instance: NotificationHelper
  private context: Context | null = null
  private isNotificationEnabled: boolean = false
  private isSlotCreated: boolean = false

  static getInstance(): NotificationHelper {
    if (!NotificationHelper.instance) {
      NotificationHelper.instance = new NotificationHelper()
    }
    return NotificationHelper.instance
  }

  setContext(context: Context): void {
    this.context = context
  }

  /**
   * 请求通知授权（应在应用启动时调用）
   */
  async requestNotificationPermission(): Promise<void> {
    if (!this.context) return

    try {
      // 先检查是否已授权
      const enabled = await notificationManager.isNotificationEnabled()
      if (enabled) {
        this.isNotificationEnabled = true
        console.info('[NotificationHelper] Notification already enabled')
      } else {
        // 请求用户授权（无参版本，由 EntryAbility 调用带 context 版本）
        await notificationManager.requestEnableNotification()
        this.isNotificationEnabled = true
        console.info('[NotificationHelper] Notification permission granted')
      }

      // 创建通知渠道
      await this.ensureSlotCreated()
    } catch (e) {
      console.error(`[NotificationHelper] Request permission error: ${e}`)
      this.isNotificationEnabled = false
    }
  }

  /**
   * 确保通知渠道已创建
   */
  private async ensureSlotCreated(): Promise<void> {
    if (this.isSlotCreated) return

    try {
      await notificationManager.addSlot(notificationManager.SlotType.SOCIAL_COMMUNICATION)
      this.isSlotCreated = true
      console.info('[NotificationHelper] Notification slot created')
    } catch (e) {
      console.error(`[NotificationHelper] Create slot error: ${e}`)
    }
  }

  /**
   * 发送新消息通知（仅在后台时发送）
   */
  async notifyNewMessage(sessionTitle: string, content: string, sessionId: string): Promise<void> {
    // 前台时不发通知
    if (appState.isInForeground) return
    if (!this.context) return

    // 确保已授权
    if (!this.isNotificationEnabled) {
      try {
        const enabled = await notificationManager.isNotificationEnabled()
        if (!enabled) {
          console.warn('[NotificationHelper] Notification not enabled, skip')
          return
        }
        this.isNotificationEnabled = true
      } catch (e) {
        return
      }
    }

    // 确保渠道存在
    if (!this.isSlotCreated) {
      await this.ensureSlotCreated()
    }

    try {
      const agent = await this.createWantAgent(sessionId)
      const notificationId = this.hashSessionId(sessionId)

      const request: notificationManager.NotificationRequest = {
        id: notificationId,
        notificationSlotType: notificationManager.SlotType.SOCIAL_COMMUNICATION,
        content: {
          notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
          normal: {
            title: sessionTitle || '新消息',
            text: content.length > 100 ? content.substring(0, 97) + '...' : content
          }
        },
        wantAgent: agent,
        isAlertOnce: false,
        isStopwatch: false,
        isCountDown: false,
        showDeliveryTime: true,
        isUnremovable: false,
        label: 'ChatMessage'
      }

      await notificationManager.publish(request)
      console.info(`[NotificationHelper] Published notification for ${sessionId}`)
    } catch (e) {
      console.error(`[NotificationHelper] Publish error: ${e}`)
    }
  }

  /**
   * 取消某个会话的通知
   */
  async cancelNotification(sessionId: string): Promise<void> {
    try {
      await notificationManager.cancel(this.hashSessionId(sessionId))
    } catch (e) {
      console.error(`[NotificationHelper] Cancel error: ${e}`)
    }
  }

  /**
   * 取消所有通知
   */
  async cancelAll(): Promise<void> {
    try {
      await notificationManager.cancelAll()
    } catch (e) {
      console.error(`[NotificationHelper] CancelAll error: ${e}`)
    }
  }

  private async createWantAgent(sessionId: string): Promise<WantAgent> {
    const wantAgentInfo: wantAgent.WantAgentInfo = {
      wants: [{
        bundleName: this.context!.applicationInfo.name,
        abilityName: 'EntryAbility',
        parameters: {
          sessionId: sessionId,
          fromNotification: 'true'
        }
      }],
      operationType: wantAgent.OperationType.START_ABILITY,
      requestCode: this.hashSessionId(sessionId),
      wantAgentFlags: [wantAgent.WantAgentFlags.CONSTANT_FLAG]
    }

    return await wantAgent.getWantAgent(wantAgentInfo)
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
