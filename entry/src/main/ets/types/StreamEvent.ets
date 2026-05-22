/**
 * 流事件类型定义
 *
 * Head/Tail 模型将消息流分为两个缓冲区:
 *   - Tail: 已提交消息列表（确定性历史）
 *   - Head: 活跃流式缓冲（增量更新中的消息）
 *
 * 流事件 (content_delta, thinking) → 直接更新 Head
 * 非流事件 (tool_use_complete, message_complete) → Head 提交到 Tail 后再追加到 Tail
 * message_complete → Head 最终化，刷新到 Tail
 *
 * Turn 生命周期: turn_started → (事件流) → turn_completed → Tail 最终化
 */

import { Message, TaskItem } from '../models/Models'

// MARK: - 流事件类型

export type StreamEventType =
  | 'content_start'       // 块开始
  | 'content_delta'       // 流式增量文本
  | 'thinking'            // 思考过程
  | 'tool_use_complete'   // 工具调用完成（非流式）
  | 'tool_result'         // 工具结果
  | 'message_complete'    // 消息完成
  | 'turn_started'        // Turn 开始（新的一轮对话）
  | 'turn_completed'      // Turn 完成
  | 'status'              // 会话状态更新
  | 'permission_request'  // 权限请求
  | 'question'            // 问题
  | 'task_list'           // 任务列表
  | 'task_update'         // 任务更新
  | 'error'               // 错误
  | 'system_notification' // 系统通知

/** 判断一个事件是否是流式事件（只影响 Head，不提交到 Tail） */
export function isStreamEvent(type: StreamEventType): boolean {
  return type === 'content_delta' || type === 'thinking'
}

/** 判断一个事件是否需要将 Head 刷新到 Tail */
export function shouldFlushBeforeApply(type: StreamEventType): boolean {
  return type === 'tool_use_complete' ||
    type === 'tool_result' ||
    type === 'permission_request' ||
    type === 'question' ||
    type === 'message_complete' ||
    type === 'turn_completed'
}

/** 判断一个事件是否是 Turn 结束事件 */
export function isTurnCompletionEvent(type: StreamEventType): boolean {
  return type === 'message_complete' || type === 'turn_completed'
}

// MARK: - Head/Tail 状态

export interface HeadTailState {
  /** 已提交消息列表 (Tail) */
  tail: Message[]
  /** 活跃流式缓冲 (Head) */
  head: Message[]
  /** 当前 Turn ID（可选，用于追踪） */
  currentTurnId: string | null
}

/** 创建空的 Head/Tail 状态 */
export function createHeadTailState(tail?: Message[]): HeadTailState {
  return {
    tail: tail || [],
    head: [],
    currentTurnId: null,
  }
}

/** 将 Head 中的所有消息刷新到 Tail */
export function flushHeadToTail(state: HeadTailState): HeadTailState {
  if (state.head.length === 0) return state
  const mergedTail = [...state.tail, ...state.head]
  return {
    ...state,
    tail: mergedTail,
    head: [],
  }
}

/**
 * 应用流式增量到 Head
 * 对于 content_delta: 追加或创建 assistant 消息
 * 对于 thinking: 追加或创建 thinking 消息
 */
export function applyStreamDelta(
  state: HeadTailState,
  deltaType: 'content_delta' | 'thinking',
  deltaText: string,
  blockType?: string,
): HeadTailState {
  const head = [...state.head]

  if (deltaType === 'content_delta') {
    // 追加文本到最后一个 assistant 消息
    if (head.length > 0 && head[head.length - 1].type === 'assistant') {
      const last = { ...head[head.length - 1] }
      last.content = (last.content || '') + deltaText
      head[head.length - 1] = last
    } else {
      // 创建新的 assistant 消息
      head.push({
        id: 'stream-' + Date.now(),
        type: 'assistant',
        content: deltaText,
        isStreaming: true,
        timestamp: new Date().toISOString(),
      })
    }
  } else if (deltaType === 'thinking') {
    // 追加到最后一个 thinking 消息
    if (head.length > 0 && head[head.length - 1].type === 'thinking') {
      const last = { ...head[head.length - 1] }
      last.content = (last.content || '') + deltaText
      head[head.length - 1] = last
    } else {
      // 创建新的 thinking 消息
      head.push({
        id: 'thinking-' + Date.now(),
        type: 'thinking',
        content: deltaText,
        isStreaming: true,
        timestamp: new Date().toISOString(),
      })
    }
  }

  return { ...state, head }
}

/**
 * 判断 Tail 中的任务列表是否和给定任务列表一致
 * 用于避免不必要的 task refresh
 */
export function hasTaskChanges(existing: TaskItem[] | undefined, incoming: TaskItem[]): boolean {
  if (!existing) return true
  if (existing.length !== incoming.length) return true
  for (let i = 0; i < existing.length; i++) {
    if (existing[i].status !== incoming[i].status) return true
  }
  return false
}