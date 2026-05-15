/**
 * 消息类型枚举
 */
export enum MessageType {
  TEXT = 'text',
  TOOL_EXECUTION = 'tool_execution',
  EXECUTING = 'executing'
}

/**
 * 工具执行状态
 */
export enum ToolStatus {
  SUCCESS = 'success',
  FAIL = 'fail',
  EXECUTING = 'executing'
}

/**
 * 工具类型枚举
 */
export enum ToolType {
  SHELL = 'SHELL',
  UPDATE_PLAN = 'UPDATE_PLAN',
  READ_FILE = 'READ_FILE',
  WRITE_FILE = 'WRITE_FILE',
  APPLY_PATCH = 'APPLY_PATCH'
}

/**
 * 消息数据模型
 */
export interface MessageModel {
  id: string
  type: MessageType
  content: string
  timestamp: string
  isUser: boolean
  toolInfo?: ToolInfo
  executingInfo?: ExecutingInfo
}

/**
 * 工具信息
 */
export interface ToolInfo {
  toolType: ToolType
  toolName: string
  status: ToolStatus
  icon: Resource
}

/**
 * 执行中信息
 */
export interface ExecutingInfo {
  command: string
  duration: number
}
