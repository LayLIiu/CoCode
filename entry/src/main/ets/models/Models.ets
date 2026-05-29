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
  aiTool?: string  // 'claude' | 'codex' | 'opencode'
  officialCodexThreadId?: string
}

// MARK: - 消息

export type MessageType = 'user' | 'assistant' | 'thinking' | 'tool_use' | 'tool_result' | 'permission_request' | 'question' | 'task_list' | 'error' | 'system_notification' | 'system'

export type ToolStatus = 'pending' | 'running' | 'completed' | 'failed'

export interface Message {
  id: string
  type: MessageType
  content: string
  toolUseId?: string  // 用于匹配 tool_result
  timestamp: string
  toolName?: string
  toolInput?: Record<string, Object>
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
  questions?: QuestionItem[]

  // Agent 派遣
  parentToolUseId?: string  // 父级工具 ID，用于 Agent 子工具嵌套
  agentTaskStatus?: 'starting' | 'running' | 'done' | 'failed' | 'stopped'  // Agent 任务状态
  agentSummary?: string     // Agent 任务摘要

  // 任务列表
  tasks?: TaskItem[]

  // 工具结果中的图片内容（Claude 通过 image_generation 等工具生成的图片）
  images?: MessageImage[]

  // 工具结果是否为错误
  isError?: boolean
}

// MARK: - 图片内容

export interface MessageImage {
  data: string
  mediaType: string
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
  | 'system_notification'
  | 'sessions_updated'
  | 'session_activated'
  | 'session_status_changed'
  | 'session_broadcast'
  | 'unknown'
  | 'pong'
  | "official_codex_update"


export interface WSMessage {
  type?: WSMessageType
  text?: string
  message?: string | object
  blockType?: string
  toolName?: string
  toolUseId?: string
  input?: Record<string, Object>
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
  threadId?: string

  title?: string
  questions?: QuestionItem[]
  tasks?: TaskItem[]

  // Agent 派遣
  subtype?: string           // system_notification 子类型（如 task_notification）
  data?: Record<string, Object>  // 附加数据（如 task_notification 负载）
  summary?: string           // Agent 任务摘要
  parentToolUseId?: string   // 父级工具 UseID（用于 Agent 子工具追踪）
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

// MARK: - 待审批权限请求

export interface PendingPermission {
  requestId: string
  toolName?: string
  toolUseId?: string
  input?: Record<string, Object>
  description?: string
}

// MARK: - 附件

export interface AttachmentRef {
  type: 'file' | 'image'
  name?: string
  path?: string
  data?: string  // base64 编码的图片数据
  mimeType?: string
  size?: number  // 文件大小（字节）
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
  answers?: Record<string, string>
  input?: Record<string, string>  // AskUserQuestion 响应
  response?: Record<string, string>  // AskUserQuestion 响应备用字段
  mode?: string
  attachments?: AttachmentRef[]
}

// MARK: - 会话状态

export type SessionStatus = 'idle' | 'thinking' | 'tool_executing' | 'streaming' | 'permission_pending' | 'question_pending' | 'completed'

// MARK: - 网络信息

export interface NetworkInfo {
  recommendedType?: string
  lanUrl?: string
  tailscaleUrl?: string
  tunnelUrl?: string
  cloudRelayUrl?: string
  tunnelEnabled: boolean
  serverPort: number
}

export function getBestUrl(info: NetworkInfo): string | undefined {
  if (info.recommendedType) {
    switch (info.recommendedType) {
      case 'lan':
        return info.lanUrl
      case 'tailscale':
        return info.tailscaleUrl
      case 'tunnel':
        return info.tunnelUrl
    }
  }
  return info.lanUrl || info.tunnelUrl
}

export function getConnectionTypeName(info: NetworkInfo): string {
  switch (info.recommendedType) {
    case 'lan':
      return '局域网直连'
    case 'tailscale':
      return 'Tailscale'
    case 'tunnel':
      return 'Cloudflare 隧道'
    default:
      return '未知'
  }
}

// MARK: - 服务器模式

export type ServerMode = 'lan' | 'tunnel'

export interface ServerProfile {
  id: string
  name: string        // "家里", "办公室" 等
  url: string
  type: 'lan' | 'pgy' | 'tunnel' | 'cloud_relay'
  lastUsed: number    // 时间戳
}

// MARK: - 最近项目

export interface RecentProject {
  projectName: string
  projectPath: string
  realPath: string
  isGit: boolean
  repoName?: string
  branch?: string
  modifiedAt: string
  sessionCount: number
}

// MARK: - 任务列表 API 响应

export interface TasksListResponse {
  tasks: CLITaskResponse[]
}

export interface CLITaskResponse {
  id: string
  subject: string
  description?: string
  activeForm?: string
  owner?: string
  status: string
  taskListId?: string
}

// MARK: - Effort 响应

export interface EffortResponse {
  level: string
  available: string[]
}

// MARK: - 服务商预设

export interface ProviderPreset {
  id: string
  name: string
  baseUrl: string
  apiFormat: ApiFormat
  defaultModels: ModelMapping
}

export const PROVIDER_PRESETS: ProviderPreset[] = [
  {
    id: 'openai',
    name: 'OpenAI',
    baseUrl: 'https://api.openai.com/v1',
    apiFormat: 'openai_chat',
    defaultModels: {
      main: 'gpt-4o',
      haiku: 'gpt-4o-mini',
      sonnet: 'gpt-4o',
      opus: 'gpt-4o'
    }
  },
  {
    id: 'anthropic',
    name: 'Anthropic',
    baseUrl: 'https://api.anthropic.com',
    apiFormat: 'anthropic',
    defaultModels: {
      main: 'claude-sonnet-4-20250514',
      haiku: 'claude-haiku-4-5-20250219',
      sonnet: 'claude-sonnet-4-20250514',
      opus: 'claude-opus-4-20250514'
    }
  },
  {
    id: 'deepseek',
    name: 'DeepSeek',
    baseUrl: 'https://api.deepseek.com',
    apiFormat: 'openai_chat',
    defaultModels: {
      main: 'deepseek-chat',
      haiku: 'deepseek-chat',
      sonnet: 'deepseek-reasoner',
      opus: 'deepseek-reasoner'
    }
  },
  {
    id: 'gemini',
    name: 'Google Gemini',
    baseUrl: 'https://generativelanguage.googleapis.com/v1beta',
    apiFormat: 'openai_chat',
    defaultModels: {
      main: 'gemini-2.5-pro',
      haiku: 'gemini-2.5-flash',
      sonnet: 'gemini-2.5-pro',
      opus: 'gemini-2.5-pro'
    }
  },
  {
    id: 'custom',
    name: '自定义',
    baseUrl: '',
    apiFormat: 'openai_chat',
    defaultModels: {
      main: '',
      haiku: '',
      sonnet: '',
      opus: ''
    }
  }
]

// MARK: - 服务商输入/测试

export class ProviderInput {
  presetId: string = ''
  name: string = ''
  apiKey: string = ''
  baseUrl: string = ''
  apiFormat?: ApiFormat
  models: ModelMapping = { main: '', haiku: '', sonnet: '', opus: '' }
  notes?: string
}

export class ProviderTestOverrides {
  baseUrl?: string
  modelId?: string
  apiFormat?: string
}

// MARK: - 服务商测试结果

export interface ConnectivityResult {
  success: boolean
  latencyMs?: number
  error?: string
}

export interface ProviderTestResult {
  connectivity: ConnectivityResult
}

export interface ProviderTestResultResponse {
  result: ProviderTestResult
}

export interface ProviderResponse {
  provider: Provider
}

// MARK: - 权限/问题请求

export interface PermissionRequest {
  requestId: string
  toolName: string
  input: Record<string, Object>
  description?: string
}

export interface QuestionRequest {
  questionId: string
  questionText: string
  options: string[]
}

// MARK: - 最近项目响应

export interface RecentProjectsResponse {
  projects: RecentProject[]
}

// MARK: - 隧道响应

export interface TunnelResponse {
  ok: boolean
  tunnelUrl?: string
  error?: string
}

// MARK: - mDNS 发现

export interface DiscoveredServer {
  id: string
  name: string
  ip: string
  port: number
  url: string
  host: string
}

export interface ServerDiscoverListener {
  onServerFound: (server: DiscoveredServer) => void
  onServerLost: (serverId: string) => void
  onSearchStateChange: (isSearching: boolean) => void
}
