/**
 * 推送审批服务
 *
 * 当 AI 请求权限时，立即推送系统通知。
 * 用户点击通知即可跳转到对应会话页面处理审批。
 */

import { notificationManager } from '@kit.NotificationKit'
import { wantAgent, WantAgent, common } from '@kit.AbilityKit'
import { appState } from '../stores/AppState'

// 通知类型
export type PushApprovalType = 'permission' | 'question' | 'completed' | 'error'

// 推送审批参数 - 必须导出供 NotificationHelper 使用
export class PushApprovalParams {
  sessionId: string = ''
  sessionTitle: string = ''
  aiName: string = ''
  type: PushApprovalType = 'permission'
  toolName: string = ''
  description: string = ''
  requestId: string = ''
}

// 批量权限请求聚合
class PendingPermissionBatch {
  sessionId: string = ''
  count: number = 0
  firstToolName: string = ''
  firstDescription: string = ''
  requestId: string = ''
  timestamp: number = 0
}

// 通知发送参数
class NotificationSendParams {
  id: number = 0
  title: string = ''
  text: string = ''
  sessionId: string = ''
  channel: string = ''
}

class PushApprovalService {
  private static instance: PushApprovalService
  private context: Context | null = null
  private isInitialized: boolean = false
  private bundleName: string = ''

  // 批量聚合：同一会话的权限请求
  private pendingBatches: Map<string, PendingPermissionBatch> = new Map()
  private batchFlushTimer: number = -1
  private readonly BATCH_FLUSH_INTERVAL: number = 2000

  static getInstance(): PushApprovalService {
    if (!PushApprovalService.instance) {
      PushApprovalService.instance = new PushApprovalService()
    }
    return PushApprovalService.instance
  }

  setContext(context: Context): void {
    this.context = context
    this.bundleName = context.applicationInfo.name
  }

  async initialize(): Promise<void> {
    if (this.isInitialized) return
    try {
      const enabled = await notificationManager.isNotificationEnabled()
      if (!enabled) {
        try {
          await notificationManager.requestEnableNotification(this.context as common.UIAbilityContext)
        } catch (e) {
          console.warn('[PushApproval] requestEnableNotification failed, will retry later')
        }
      }
      await this.ensureChannelsCreated()
      this.isInitialized = true
    } catch (e) {
      console.warn('[PushApproval] initialize failed: ' + JSON.stringify(e))
    }
  }

  pushPermissionRequest(params: PushApprovalParams): void {
    if (!this.shouldPush(params.sessionId, true)) return

    const existing = this.pendingBatches.get(params.sessionId)
    if (existing) {
      existing.count++
      existing.timestamp = Date.now()
    } else {
      const batch = new PendingPermissionBatch()
      batch.sessionId = params.sessionId
      batch.count = 1
      batch.firstToolName = params.toolName || '操作'
      batch.firstDescription = params.description || ''
      batch.requestId = params.requestId || ''
      batch.timestamp = Date.now()
      this.pendingBatches.set(params.sessionId, batch)
    }

    if (this.batchFlushTimer >= 0) {
      clearTimeout(this.batchFlushTimer)
    }
    this.batchFlushTimer = setTimeout(() => {
      this.flushBatchNotifications()
    }, this.BATCH_FLUSH_INTERVAL)
  }

  pushQuestion(params: PushApprovalParams): void {
    if (!this.shouldPush(params.sessionId, true)) return
    const sendParams = new NotificationSendParams()
    sendParams.id = this.hashSessionId(params.sessionId) + 20000
    sendParams.title = `${params.aiName} 提问 - ${params.sessionTitle}`
    sendParams.text = params.description || 'AI 需要您的回答'
    sendParams.sessionId = params.sessionId
    sendParams.channel = 'ai_questions'
    this.sendNotification(sendParams)
  }

  pushCompleted(params: PushApprovalParams): void {
    if (!this.shouldPush(params.sessionId, false)) return
    const sendParams = new NotificationSendParams()
    sendParams.id = this.hashSessionId(params.sessionId) + 30000
    sendParams.title = `${params.aiName} 已完成 - ${params.sessionTitle}`
    sendParams.text = params.description || '任务已完成'
    sendParams.sessionId = params.sessionId
    sendParams.channel = 'ai_status'
    this.sendNotification(sendParams)
  }

  pushError(params: PushApprovalParams): void {
    if (!this.shouldPush(params.sessionId, true)) return
    const sendParams = new NotificationSendParams()
    sendParams.id = this.hashSessionId(params.sessionId) + 40000
    sendParams.title = `${params.aiName} 出错 - ${params.sessionTitle}`
    sendParams.text = params.description || '执行过程中发生错误'
    sendParams.sessionId = params.sessionId
    sendParams.channel = 'ai_status'
    this.sendNotification(sendParams)
  }

  async cancelSessionNotifications(sessionId: string): Promise<void> {
    const baseId = this.hashSessionId(sessionId)
    const ids = [baseId, baseId + 10000, baseId + 20000, baseId + 30000, baseId + 40000]
    for (let i = 0; i < ids.length; i++) {
      try {
        await notificationManager.cancel(ids[i])
      } catch (e) {
        // ignore
      }
    }
  }

  async cancelAll(): Promise<void> {
    try {
      await notificationManager.cancelAll()
    } catch (e) {
      // ignore
    }
  }

  private shouldPush(sessionId: string, allowInForeground: boolean): boolean {
    if (appState.isInForeground && !allowInForeground) {
      return false
    }
    return true
  }

  private async flushBatchNotifications(): Promise<void> {
    const batchKeys = Array.from(this.pendingBatches.keys())
    const batches = new Map<string, PendingPermissionBatch>()
    for (let i = 0; i < batchKeys.length; i++) {
      const key = batchKeys[i]
      const batch = this.pendingBatches.get(key)
      if (batch) {
        batches.set(key, batch)
      }
    }
    this.pendingBatches.clear()
    this.batchFlushTimer = -1

    const keys = Array.from(batches.keys())
    for (let i = 0; i < keys.length; i++) {
      const sessionId = keys[i]
      const batch = batches.get(sessionId)
      if (!batch) continue

      let title = ''
      let text = ''

      if (batch.count === 1) {
        title = `权限请求 - ${batch.firstToolName}`
        text = batch.firstDescription || `${batch.firstToolName} 需要您的授权`
      } else {
        title = `${batch.count} 个权限请求待审批`
        text = `第一个: ${batch.firstToolName}` +
          (batch.firstDescription ? ` - ${batch.firstDescription}` : '')
      }

      const sendParams = new NotificationSendParams()
      sendParams.id = this.hashSessionId(sessionId) + 10000
      sendParams.title = title
      sendParams.text = text
      sendParams.sessionId = sessionId
      sendParams.channel = 'permission_requests'
      await this.sendNotification(sendParams)
    }
  }

  private async sendNotification(params: NotificationSendParams): Promise<void> {
    if (!this.context) return

    if (!this.isInitialized) {
      await this.initialize()
    }

    try {
      const agent = await this.createWantAgent(params.sessionId)

      const request: notificationManager.NotificationRequest = {
        id: params.id,
        notificationSlotType: notificationManager.SlotType.SOCIAL_COMMUNICATION,
        content: {
          notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
          normal: {
            title: params.title,
            text: params.text
          }
        },
        wantAgent: agent,
        isAlertOnce: false,
        showDeliveryTime: true,
        label: params.channel
      }

      await notificationManager.publish(request)
      console.info(`[PushApproval] notification sent: id=${params.id} title=${params.title}`)
    } catch (e) {
      console.warn('[PushApproval] publish error: ' + JSON.stringify(e))
    }
  }

  private async ensureChannelsCreated(): Promise<void> {
    try {
      await notificationManager.addSlot(notificationManager.SlotType.SOCIAL_COMMUNICATION)
    } catch (e) {
      // ignore
    }
  }

  private async createWantAgent(sessionId: string): Promise<WantAgent> {
    const bundleNameStr = this.bundleName || 'com.cocode.app'
    const reqCode = this.hashSessionId(sessionId)

    return await wantAgent.getWantAgent({
      wants: [{
        bundleName: bundleNameStr,
        abilityName: 'EntryAbility',
        parameters: {
          'sessionId': sessionId,
          'fromNotification': 'true',
          'action': 'open_chat'
        }
      }],
      operationType: wantAgent.OperationType.START_ABILITY,
      requestCode: reqCode,
      wantAgentFlags: [wantAgent.WantAgentFlags.CONSTANT_FLAG]
    })
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

export const pushApprovalService = PushApprovalService.getInstance()
