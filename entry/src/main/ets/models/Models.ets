/**
 * 数据模型定义
 */

// MARK: - 权限模式

export enum PermissionMode {
  DEFAULT = 'default',
  ACCEPT_EDITS = 'acceptEdits',
  PLAN = 'plan',
  BYPASS_PERMISSIONS = 'bypassPermissions'
}

export function getPermissionModeDisplayName(mode: PermissionMode): string {
  switch (mode) {
    case PermissionMode.DEFAULT: return '询问权限'
    case PermissionMode.ACCEPT_EDITS: return '自动接受编辑'
    case PermissionMode.PLAN: return '计划模式'
    case PermissionMode.BYPASS_PERMISSIONS: return '跳过权限'
  }
}

export function getPermissionModeDescription(mode: PermissionMode): string {
  switch (mode) {
    case PermissionMode.DEFAULT: return 'CLR请求时，确定文件编辑和高风险命令'
    case PermissionMode.ACCEPT_EDITS: return 'Cloud无需询问即可写入磁盘'
    case PermissionMode.PLAN: return '仅架构和推理，不操作文件'
    case PermissionMode.BYPASS_PERMISSIONS: return '对shell和文件系统完全工具访问'
  }
}

// MARK: - 会话

export interface Session {
  id: string
  title: string
  projectPath: string
  workDir?: string
  workDirExists: boolean
  createdAt: string
  modifiedAt: string
  messageCount: number
  providerId?: string
}

// MARK: - 消息

export type MessageType = 'user' | 'assistant' | 'thinking' | 'tool_use' | 'tool_result' | 'permission_request' | 'question' | 'task_list'

export type ToolStatus = 'pending' | 'running' | 'completed' | 'failed'

export interface Message {
  id: string
  type: MessageType
  content: string
  timestamp: string
  toolName?: string
  toolInput?: Record<string, object>
  toolResult?: string
  toolStatus?: ToolStatus
  isStreaming?: boolean

  // 权限请求
  permissionId?: string
  permissionDescription?: string
  isPermissionHandled?: boolean
  permissionResult?: boolean

  // 问题选项
  questionId?: string
  options?: string[]
  selectedAnswer?: string
  isQuestionAnswered?: boolean

  // 任务列表
  tasks?: TaskItem[]
}

// MARK: - 任务

export type TaskStatus = 'pending' | 'in_progress' | 'completed' | 'failed'

export interface TaskItem {
  id: string
  content: string
  status: TaskStatus
  activeForm?: string
  owner?: string
}

// MARK: - 服务商

export type ApiFormat = 'anthropic' | 'openai_chat' | 'openai_responses'

export interface ModelMapping {
  main: string
  haiku: string
  sonnet: string
  opus: string
}

export interface Provider {
  id: string
  presetId: string
  name: string
  apiKey: string
  baseUrl: string
  apiFormat: ApiFormat
  models: ModelMapping
  notes?: string
}

export interface ModelInfo {
  id: string
  name: string
  description?: string
}

// MARK: - 用户

export interface User {
  id: string
  name: string
  email?: string
}

// MARK: - WebSocket 消息类型

export type WSMessageType =
  | 'connected'
  | 'content_start'
  | 'content_delta'
  | 'thinking'
  | 'tool_use_complete'
  | 'tool_result'
  | 'message_complete'
  | 'status'
  | 'user_message_echo'
  | 'permission_request'
  | 'question'
  | 'questions'
  | 'error'
  | 'token_usage'
  | 'session_title_updated'
  | 'task_list'
  | 'task_update'
  | 'unknown'

export interface WSMessage {
  type?: WSMessageType
  text?: string
  blockType?: string
  toolName?: string
  toolUseId?: string
  input?: Record<string, object>
  content?: object | string
  isError?: boolean
  requestId?: string
  description?: string
  questionId?: string
  questionText?: string
  options?: string[]
  sessionId?: string
  state?: string
  verb?: string
  timestamp?: string
  id?: string
  percentage?: number
  used?: number
  total?: number
  title?: string
  questions?: QuestionItem[]
  tasks?: TaskItem[]
}

export interface QuestionItem {
  question?: string
  header?: string
  options?: QuestionOption[]
  multiSelect?: boolean
}

export interface QuestionOption {
  label?: string
  description?: string
}

// MARK: - 发送消息类型

export interface OutgoingMessage {
  type: string
  content?: string
  requestId?: string
  allowed?: boolean
  rule?: string
  questionId?: string
  answer?: string
  mode?: string
}

// MARK: - 会话状态

export type SessionStatus = 'idle' | 'thinking' | 'tool_executing' | 'streaming' | 'permission_pending' | 'question_pending' | 'completed'

// MARK: - 网络信息

export interface NetworkInfo {
  recommendedType?: string
  lanUrl?: string
  tailscaleUrl?: string
  tunnelUrl?: string
  tunnelEnabled: boolean
  serverPort: number
}

// MARK: - 服务器模式

export type ServerMode = 'lan' | 'tunnel'
