/**
 * 推送审批服务
 *
 * 当 AI 请求权限时，立即推送系统通知。
 * 用户点击通知即可跳转到对应会话页面处理审批。
 *
 * 功能：
 * 1. 权限请求推送 —— 显示工具名称和简短描述
 * 2. 问题推送 —— AI 提问时通知用户
 * 3. 会话完成推送 —— AI 完成任务后通知
 * 4. 批量审批 —— 同一会话多个权限请求时合并为一条通知
 * 5. 通知点击跳转 —— 自动导航到对应会话
 */

import { notificationManager, NotificationRequest, NotificationSlot } from '@kit.NotificationKit'
import { wantAgent, WantAgent, common } from '@kit.AbilityKit'
import { appState } from '../stores/AppState'
import { Theme } from '../common/Theme'

// 通知类型
export type PushApprovalType = 'permission' | 'question' | 'completed' | 'error'

// 推送审批参数
interface PushApprovalParams {
  sessionId: string
  sessionTitle: string
  aiName: string
  type: PushApprovalType
  toolName?: string
  description?: string
  requestId?: string
}

// 批量权限请求聚合
interface PendingPermissionBatch {
  sessionId: string
  count: number
  firstToolName: string
  firstDescription: string
  requestId: string
  timestamp: number
}

// 通知渠道 ID
const CHANNEL_PERMISSION = 'permission_requests'
const CHANNEL_QUESTION = 'ai_questions'
const CHANNEL_STATUS = 'ai_status'

class PushApprovalService {
  private static instance: PushApprovalService
  private context: Context | null = null
  private isInitialized: boolean = false
  private bundleName: string = ''

  // 批量聚合：同一会话的权限请求
  private pendingBatches: Map<string, PendingPermissionBatch> = new Map()
  private batchFlushTimer: number = -1
  private readonly BATCH_FLUSH_INTERVAL = 2000  // 2秒内聚合同一会话的权限请求

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
      // 创建通知渠道
      await this.ensureChannelsCreated()
      this.isInitialized = true
    } catch (e) {
      console.warn('[PushApproval] initialize failed: ' + JSON.stringify(e))
    }
  }

  /**
   * 推送权限请求通知
   *
   * 支持批量聚合：2秒内同一会话的多个权限请求合并为一条通知
   * "3个权限请求待审批 - 第一个: 编辑 main.ts"
   */
  pushPermissionRequest(params: PushApprovalParams): void {
    if (!this.shouldPush(params.sessionId, true)) return

    // 聚合到批量
    const existing = this.pendingBatches.get(params.sessionId)
    if (existing) {
      existing.count++
      existing.timestamp = Date.now()
    } else {
      const batch: PendingPermissionBatch = {
        sessionId: params.sessionId,
        count: 1,
        firstToolName: params.toolName || '操作',
        firstDescription: params.description || '',
        requestId: params.requestId || '',
        timestamp: Date.now()
      }
      this.pendingBatches.set(params.sessionId, batch)
    }

    // 延迟刷新（批量聚合）
    if (this.batchFlushTimer >= 0) {
      clearTimeout(this.batchFlushTimer)
    }
    this.batchFlushTimer = setTimeout(() => {
      this.flushBatchNotifications()
    }, this.BATCH_FLUSH_INTERVAL)
  }

  /**
   * 推送 AI 问题通知
   */
  pushQuestion(params: PushApprovalParams): void {
    if (!this.shouldPush(params.sessionId, true)) return
    this.sendNotification({
      id: this.hashSessionId(params.sessionId) + 20000,
      title: `${params.aiName} 提问 - ${params.sessionTitle}`,
      text: params.description || 'AI 需要您的回答',
      sessionId: params.sessionId,
      channel: CHANNEL_QUESTION
    })
  }

  /**
   * 推送 AI 完成通知
   */
  pushCompleted(params: PushApprovalParams): void {
    if (!this.shouldPush(params.sessionId, false)) return
    this.sendNotification({
      id: this.hashSessionId(params.sessionId) + 30000,
      title: `${params.aiName} 已完成 - ${params.sessionTitle}`,
      text: params.description || '任务已完成',
      sessionId: params.sessionId,
      channel: CHANNEL_STATUS
    })
  }

  /**
   * 推送 AI 出错通知
   */
  pushError(params: PushApprovalParams): void {
    if (!this.shouldPush(params.sessionId, true)) return
    this.sendNotification({
      id: this.hashSessionId(params.sessionId) + 40000,
      title: `${params.aiName} 出错 - ${params.sessionTitle}`,
      text: params.description || '执行过程中发生错误',
      sessionId: params.sessionId,
      channel: CHANNEL_STATUS
    })
  }

  /**
   * 取消指定会话的通知
   */
  async cancelSessionNotifications(sessionId: string): Promise<void> {
    const baseId = this.hashSessionId(sessionId)
    const ids = [baseId, baseId + 10000, baseId + 20000, baseId + 30000, baseId + 40000]
    for (const id of ids) {
      try {
        await notificationManager.cancel(id)
      } catch (e) {
        // ignore
      }
    }
  }

  /**
   * 取消所有通知
   */
  async cancelAll(): Promise<void> {
    try {
      await notificationManager.cancelAll()
    } catch (e) {
      // ignore
    }
  }

  // ── 内部方法 ──

  private shouldPush(sessionId: string, allowInForeground: boolean): boolean {
    // 当前正在查看该会话时，不推送（除非强制前台推送类型如权限请求）
    if (appState.isInForeground && !allowInForeground) {
      return false
    }
    return true
  }

  private async flushBatchNotifications(): Promise<void> {
    const batches = new Map(this.pendingBatches)
    this.pendingBatches.clear()
    this.batchFlushTimer = -1

    for (const [sessionId, batch] of batches) {
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

      await this.sendNotification({
        id: this.hashSessionId(sessionId) + 10000,
        title: title,
        text: text,
        sessionId: sessionId,
        channel: CHANNEL_PERMISSION
      })
    }
  }

  private async sendNotification(params: {
    id: number
    title: string
    text: string
    sessionId: string
    channel: string
  }): Promise<void> {
    if (!this.context) return

    // 确保初始化
    if (!this.isInitialized) {
      await this.initialize()
    }

    try {
      const agent = await this.createWantAgent(params.sessionId)

      const request: NotificationRequest = {
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
    // 鸿蒙使用 SlotType，这里用 addSlot 确保 SOCIAL_COMMUNICATION 槽存在
    try {
      await notificationManager.addSlot(notificationManager.SlotType.SOCIAL_COMMUNICATION)
    } catch (e) {
      // 槽已存在或其他错误，忽略
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
