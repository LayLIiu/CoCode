/**
 * HTTP API 服务
 * 负责与服务器的所有 HTTP 通信
 */

import http from '@ohos.net.http'
import { UrlUtils } from '../common/UrlUtils'
import {
  Session, Message, Provider, NetworkInfo, ModelInfo, TaskItem,
  RecentProject, EffortResponse, ProviderInput, ProviderTestOverrides,
  ProviderTestResultResponse, ProviderResponse, TunnelResponse, RecentProjectsResponse, MessageImage
} from '../models/Models'

// 请求体类型定义
export class WorkDirRequest {
  workDir: string = ''
}

export class FsEntry {
  name: string = ''
  fullPath: string = ''
  isDir: boolean = false
  isExpanded: boolean = false
  children: FsEntry[] | null = null

  constructor(name: string, fullPath: string, isDir: boolean) {
    this.name = name
    this.fullPath = fullPath
    this.isDir = isDir
  }
}

export class InspectResult {
  percentage: number = 0
  model: string = ''
  totalTokens: number = 0
  maxTokens: number = 0
}

export class CreateSessionRequest {
  workDir: string = ''
  aiTool?: string
}

export class TitleRequest {
  title: string = ''
}

export class CodeRequest {
  code: string = ''
}

export class ModelIdRequest {
  modelId: string = ''
}

export class DownloadTokenResponse {
  token: string = ''
  fileName: string = ''
  mimeType: string = ''
  size: number = 0
  downloadUrl: string = ''
}

export class TtlRequest {
  ttlHours: number = 1
}

// 响应类型定义
export class SessionsResponse {
  sessions: Session[] = []
}

export class MessagesResponse {
  messages: RawMessage[] = []
}

export class CreateSessionResponse {
  sessionId: string = ''
}

export class NetworkInfoResponse {
  recommendedType: string = ''
  lanUrl: string = ''
  tailscaleUrl: string = ''
  tunnelUrl: string = ''
  cloudRelayUrl: string = ''
  tunnelEnabled: boolean = false
  serverPort: number = 0
}

export class PairingCodeResponse {
  pairingCode: string = ''
  expiresAt: number = 0
  createdAt: number = 0
}

export class ProvidersResponse {
  providers: Provider[] = []
  activeId: string = ''
}

export class ModelsResponse {
  models: ModelInfo[] = []
  provider: ProviderInfo = new ProviderInfo()
}

export class ProviderInfo {
  id: string = ''
  name: string = ''
}

// 内容块类型
export class ContentBlock {
  id?: string
  type: string = ''
  text: string = ''
  name: string = ''
  input: Record<string, Object> = {}
  tool_use_id?: string
  toolUseId?: string
  source?: Record<string, Object>
}

export class RawMessage {
  id: string = ''
  type: string = ''
  content: ContentBlock[] | string | null = null
  timestamp: string = ''
  isError: boolean = false
  thinking: string = ''
  tool_use_id?: string
  toolUseId?: string
}

// 文件信息响应
export class FileInfoResult {
  type: string = ''
  size: number = 0
  name: string = ''
}

// MARK: - Status API 响应类型

export class ServerStatusResponse {
  status: string = ''
  version: string = ''
  uptime: number = 0
}

export class UsageResponse {
  totalInputTokens: number = 0
  totalOutputTokens: number = 0
  totalCost: number = 0
}

export class UserStatusResponse {
  configDir: string = ''
  projects: string[] = []
}

export class ActivityStatsResponse {
  stats: Record<string, Object> = {}
  range: string = ''
  generatedAt: string = ''
}

export class DiagnosticsStatusResponse {
  logDir: string = ''
  retention: number = 0
  counters: Record<string, number> = {}
}

export class DiagnosticsEventsResponse {
  events: DiagnosticsEventItem[] = []
}

export class DiagnosticsEventItem {
  type: string = ''
  severity: string = ''
  summary: string = ''
  timestamp: string = ''
}

// MARK: - Skills API 响应类型

export class SkillsListResponse {
  skills: SkillMeta[] = []
}

export class SkillMeta {
  name: string = ''
  displayName: string = ''
  description: string = ''
  source: string = ''
  userInvocable: boolean = false
  version: string = ''
  contentLength: number = 0
}

// MARK: - Agents API 响应类型

export class AgentListItem {
  agentType: string = ''
  description: string = ''
  model: string = ''
  modelDisplay: string = ''
  tools: string[] = []
  systemPrompt: string = ''
  color: string = ''
  source: string = ''
  baseDir: string = ''
  isActive: boolean = false
}

export class ResolvedAgentItem extends AgentListItem {
  overriddenBy: string = ''
}

export class AgentsListResponse {
  activeAgents: AgentListItem[] = []
  allAgents: ResolvedAgentItem[] = []
}

export class AgentDefinition {
  name: string = ''
  description: string = ''
  model: string = ''
  tools: string[] = []
  systemPrompt: string = ''
  color: string = ''
}

export class AgentDetailResponse {
  agent: AgentDefinition = new AgentDefinition()
}

// MARK: - Scheduled Tasks API 响应类型

export class TaskNotificationConfig {
  enabled: boolean = false
  channels: string[] = []
}

export class CronTask {
  id: string = ''
  name: string = ''
  description: string = ''
  cron: string = ''
  prompt: string = ''
  createdAt: number = 0
  lastFiredAt: string = ''
  enabled: boolean = true
  recurring: boolean = true
  permanent: boolean = false
  permissionMode: string = ''
  model: string = ''
  providerId: string = ''
  folderPath: string = ''
  useWorktree: boolean = false
  notification: TaskNotificationConfig = new TaskNotificationConfig()
}

export class ScheduledTasksListResponse {
  tasks: CronTask[] = []
}

export class ScheduledTaskResponse {
  task: CronTask = new CronTask()
}

export class TaskRunItem {
  id: string = ''
  taskId: string = ''
  taskName: string = ''
  startedAt: string = ''
  completedAt: string = ''
  status: string = ''
  prompt: string = ''
  output: string = ''
  error: string = ''
  exitCode: number = 0
  durationMs: number = 0
  sessionId: string = ''
}

export class TaskRunsResponse {
  runs: TaskRunItem[] = []
}

// MARK: - Git API 响应类型

export class GitStatusFile {
  path: string = ''
  status: string = ''  // 'modified', 'added', 'deleted', 'renamed', 'untracked'
  oldPath?: string = ''  // 用于 renamed 类型
}

export class GitStatusResponse {
  branch: string = ''
  ahead: number = 0
  behind: number = 0
  staged: GitStatusFile[] = []
  unstaged: GitStatusFile[] = []
  untracked: GitStatusFile[] = []
  hasChanges: boolean = false
}

export class GitDiffResponse {
  files: GitDiffFile[] = []
}

export class GitDiffFile {
  path: string = ''
  oldPath?: string = ''
  hunks: GitDiffHunk[] = []
}

export class GitDiffHunk {
  oldStart: number = 0
  oldLines: number = 0
  newStart: number = 0
  newLines: number = 0
  lines: string[] = []
}

export class GitCommitRequest {
  message: string = ''
  files?: string[]  // 要提交的文件列表，不指定则提交所有
}

export class GitCommitResponse {
  sha: string = ''
  message: string = ''
  files: string[] = []
}

export class GitPushResponse {
  success: boolean = false
  message: string = ''
  remote: string = ''
  branch: string = ''
}

export class GitPullResponse {
  success: boolean = false
  message: string = ''
  files: string[] = []
  ahead: number = 0
  behind: number = 0
}

export class GitBranchResponse {
  current: string = ''
  branches: GitBranchItem[] = []
}

export class GitBranchItem {
  name: string = ''
  isRemote: boolean = false
  isCurrent: boolean = false
  upstream?: string = ''
  ahead: number = 0
  behind: number = 0
}

export class GitLogResponse {
  commits: GitCommitItem[] = []
}

export class GitCommitItem {
  sha: string = ''
  shortSha: string = ''
  message: string = ''
  author: string = ''
  email: string = ''
  date: string = ''
  parents: string[] = []
}

export class GitRemoteResponse {
  remotes: GitRemoteItem[] = []
}

export class GitRemoteItem {
  name: string = ''
  fetchUrl: string = ''
  pushUrl: string = ''
}

export class GitCreatePRRequest {
  title: string = ''
  body?: string = ''
  head: string = ''  // 源分支
  base: string = ''  // 目标分支
  draft?: boolean = false
}

export class GitCreatePRResponse {
  success: boolean = false
  url: string = ''
  number: number = 0
  message: string = ''
}

export class GitStashResponse {
  success: boolean = false
  message: string = ''
  stashName?: string = ''
}

// MARK: - Web Preview API 响应类型

export class WebPreviewResponse {
  url: string = ''
  port: number = 0
  status: string = ''
}

export class WebPreviewStartRequest {
  port?: number = 0
  path?: string = ''
}

// MARK: - SSH API 响应类型

export class SSHConnectionRequest {
  host: string = ''
  port: number = 22
  user: string = ''
  password?: string = ''
  privateKey?: string = ''
}

export class SSHConnectionResponse {
  success: boolean = false
  sessionId: string = ''
  message: string = ''
}

export class SSHCommandRequest {
  sessionId: string = ''
  command: string = ''
}

export class SSHCommandResponse {
  success: boolean = false
  output: string = ''
  exitCode: number = 0
}

export class DesktopCapabilityItem {
  key: string = ''
  title: string = ''
  description: string = ''
  path: string = ''
  available: boolean = false
  required: boolean = false
  latency: number = -1
  statusCode: number = 0
  message: string = ''
}

export class DesktopCapabilityReport {
  ok: boolean = false
  checkedAt: number = 0
  items: DesktopCapabilityItem[] = []
}

// MARK: - Markdown API 响应类型

export class MarkdownRenderResponse {
  html: string = ''
  toc: MarkdownTocItem[] = []
}

export class MarkdownTocItem {
  level: number = 0
  text: string = ''
  anchor: string = ''
}

// MARK: - 其他请求类型

export class GitAddRequest {
  files: string[] = []
}

export class EffortRequest {
  level: string = ''
}

export class TunnelRequest {
  enabled: boolean = false
}

export class PushTokenRequest {
  token: string = ''
}

export class OkResponse {
  ok: boolean = false
}

export class APIError extends Error {
  code: number = 0
  serverCode: string = ''

  constructor(message: string, code: number = 0, serverCode: string = '') {
    super(message)
    this.code = code
    this.serverCode = serverCode
  }
}

export class APIService {
  private static instance: APIService
  private baseUrl: string = ''

  static getInstance(): APIService {
    if (!APIService.instance) {
      APIService.instance = new APIService()
    }
    return APIService.instance
  }

  setBaseUrl(url: string): void {
    this.baseUrl = UrlUtils.normalizeUrl(url)
    console.info(`[APIService] baseUrl: ${this.baseUrl}`)
  }

  getBaseUrl(): string {
    return this.baseUrl
  }

  /**
   * 请求文件下载令牌（安全下载）
   * 返回 { token, fileName, mimeType, size, downloadUrl }
   */
  async requestDownloadToken(filePath: string): Promise<DownloadTokenResponse> {
    const res = await this.request<Record<string, Object>>(
      '/api/filesystem/token?path=' + encodeURIComponent(filePath), 'GET', ''
    )
    return {
      token: res['token'] as string,
      fileName: res['fileName'] as string,
      mimeType: res['mimeType'] as string,
      size: res['size'] as number,
      downloadUrl: res['downloadUrl'] as string,
    }
  }

  // MARK: - 会话 API

  async getSessions(providerId?: string, limit?: number): Promise<Session[]> {
    let path = '/api/sessions'
    let sep = '?'
    if (providerId) {
      path += '?providerId=' + providerId
      sep = '&'
    }
    if (limit !== undefined && limit > 0) {
      path += sep + 'limit=' + limit
    }
    const response = await this.request<SessionsResponse>(path, 'GET', '')
    return response.sessions
  }

  async createSession(workDir?: string): Promise<CreateSessionResponse> {
    let body = ''
    if (workDir) {
      const req = new WorkDirRequest()
      req.workDir = workDir
      body = JSON.stringify(req)
    }
    return await this.request<CreateSessionResponse>('/api/sessions', 'POST', body)
  }

  async createSessionWithProvider(workDir: string, aiTool: string): Promise<CreateSessionResponse> {
    const req = new CreateSessionRequest()
    req.workDir = workDir
    req.aiTool = aiTool
    return await this.request<CreateSessionResponse>('/api/sessions', 'POST', JSON.stringify(req))
  }

  async deleteSession(sessionId: string): Promise<void> {
    await this.request<Object>('/api/sessions/' + sessionId, 'DELETE', '')
  }

  async renameSession(sessionId: string, title: string): Promise<void> {
    const req = new TitleRequest()
    req.title = title
    await this.request<Object>('/api/sessions/' + sessionId, 'PATCH', JSON.stringify(req))
  }

  async getMessages(sessionId: string, limit?: number): Promise<Message[]> {
    let path = '/api/sessions/' + sessionId + '/messages'
    if (limit !== undefined && limit > 0) {
      path += '?limit=' + limit
    }
    const response = await this.request<MessagesResponse>(path, 'GET', '')
    return this.transformMessages(response.messages)
  }

  // 从服务器获取任务列表
  async getTasks(sessionId: string): Promise<TaskItem[]> {
    try {
      const response = await this.request<Record<string, Object>>('/api/sessions/' + sessionId + '/tasks', 'GET', '')
      if (response['tasks'] && Array.isArray(response['tasks'])) {
        return response['tasks'] as TaskItem[]
      }
    } catch (e) {
      console.info(`[APIService] Tasks endpoint not available: ${e}`)
    }
    return []
  }

  // MARK: - 网络 API

  async getNetworkInfo(): Promise<NetworkInfo> {
    const paths = ['/api/mobile/network-info', '/api/mobile/networkInfo']
    for (let i = 0; i < paths.length; i++) {
      try {
        const response = await this.request<NetworkInfoResponse>(paths[i], 'GET', '')
        const info: NetworkInfo = {
          recommendedType: response.recommendedType,
          lanUrl: response.lanUrl ? UrlUtils.normalizeUrl(response.lanUrl) : '',
          tailscaleUrl: response.tailscaleUrl ? UrlUtils.normalizeUrl(response.tailscaleUrl) : '',
          tunnelUrl: response.tunnelUrl ? UrlUtils.normalizeUrl(response.tunnelUrl) : '',
          cloudRelayUrl: response.cloudRelayUrl ? UrlUtils.normalizeUrl(response.cloudRelayUrl) : '',
          tunnelEnabled: response.tunnelEnabled,
          serverPort: response.serverPort
        }
        return info
      } catch (e) {
        continue
      }
    }
    const defaultInfo: NetworkInfo = {
      tunnelEnabled: false,
      serverPort: 0
    }
    return defaultInfo
  }

  async getPairingCode(): Promise<PairingCodeResponse> {
    const paths = ['/api/mobile/pairing-code', '/api/mobile/pairingCode']
    let lastError: Error | null = null
    for (let i = 0; i < paths.length; i++) {
      try {
        const req = new TtlRequest()
        req.ttlHours = 1
        return await this.request<PairingCodeResponse>(paths[i], 'POST', JSON.stringify(req))
      } catch (e) {
        lastError = e as Error
        continue
      }
    }
    throw lastError || new Error('获取配对码失败')
  }

  async pair(code: string): Promise<boolean> {
    const req = new CodeRequest()
    req.code = code
    const response = await this.request<Object>('/api/mobile/pair', 'POST', JSON.stringify(req))
    return response !== null
  }

  // MARK: - 最近项目 API

  async getRecentProjects(): Promise<RecentProject[]> {
    const response = await this.request<RecentProjectsResponse>('/api/sessions/recent-projects', 'GET', '')
    return response.projects
  }

  // MARK: - Effort API

  async getEffort(): Promise<EffortResponse> {
    return await this.request<EffortResponse>('/api/effort', 'GET', '')
  }

  async setEffort(level: string): Promise<void> {
    const req = new EffortRequest()
    req.level = level
    await this.request<Object>('/api/effort', 'PUT', JSON.stringify(req))
  }

  // MARK: - 隧道 API

  async enableTunnel(enabled: boolean): Promise<TunnelResponse> {
    const paths = ['/api/mobile/tunnel', '/api/mobile/tunnel/enable']
    let lastError: Error | null = null
    for (let i = 0; i < paths.length; i++) {
      try {
        const req = new TunnelRequest()
        req.enabled = enabled
        return await this.request<TunnelResponse>(paths[i], 'POST', JSON.stringify(req))
      } catch (e) {
        lastError = e as Error
        continue
      }
    }
    throw lastError || new Error('隧道操作失败')
  }

  // MARK: - 服务商 API

  async getProviders(): Promise<ProvidersResponse> {
    return await this.request<ProvidersResponse>('/api/providers', 'GET', '')
  }

  async createProvider(input: ProviderInput): Promise<ProviderResponse> {
    return await this.request<ProviderResponse>('/api/providers', 'POST', JSON.stringify(input))
  }

  async updateProvider(id: string, input: ProviderInput): Promise<ProviderResponse> {
    return await this.request<ProviderResponse>('/api/providers/' + id, 'PUT', JSON.stringify(input))
  }

  async deleteProvider(id: string): Promise<void> {
    await this.request<Object>('/api/providers/' + id, 'DELETE', '')
  }

  async testProvider(id: string, overrides?: ProviderTestOverrides): Promise<ProviderTestResultResponse> {
    return await this.request<ProviderTestResultResponse>('/api/providers/' + id + '/test', 'POST',
      JSON.stringify(overrides || {}))
  }

  async activateProvider(id: string): Promise<void> {
    await this.request<Object>('/api/providers/' + id + '/activate', 'POST', '')
  }

  async activateOfficialProvider(): Promise<void> {
    await this.request<Object>('/api/providers/official', 'POST', '')
  }

  // MARK: - 模型 API

  async getModels(providerId?: string): Promise<ModelsResponse> {
    let path = '/api/models'
    if (providerId) {
      path += '?providerId=' + encodeURIComponent(providerId)
    }
    return await this.request<ModelsResponse>(path, 'GET', '')
  }

  async getCurrentModel(): Promise<ModelInfo> {
    const response = await this.request<ModelInfo>('/api/models/current', 'GET', '')
    return response
  }

  async setCurrentModel(modelId: string): Promise<void> {
    const req = new ModelIdRequest()
    req.modelId = modelId
    await this.request<Object>('/api/models/current', 'PUT', JSON.stringify(req))
  }

  // MARK: - 上下文容量 API

  async getInspection(sessionId: string): Promise<InspectResult> {
    const result = new InspectResult()
    const res = await this.request<Record<string, Object>>('/api/sessions/' + sessionId + '/inspection?contextOnly=1', 'GET', '')
    const estimate = res['contextEstimate']
    if (estimate) {
      const estMap = estimate as Record<string, Object>
      if (typeof estMap['percentage'] === 'number') result.percentage = estMap['percentage'] as number
      if (typeof estMap['totalTokens'] === 'number') result.totalTokens = estMap['totalTokens'] as number
      if (typeof estMap['maxTokens'] === 'number') result.maxTokens = estMap['maxTokens'] as number
      if (typeof estMap['model'] === 'string') result.model = estMap['model'] as string
    }
    return result
  }

  // MARK: - 文件系统 API

  async browseDirectory(dirPath: string): Promise<FsEntry[]> {
    try {
      const res = await this.request<Record<string, Object>>('/api/filesystem/browse?includeFiles=true&path=' + encodeURIComponent(dirPath), 'GET', '')
      const entries = res['entries']
      if (Array.isArray(entries)) {
        const result: FsEntry[] = []
        for (let i = 0; i < entries.length; i++) {
          const e = entries[i] as Record<string, Object>
          result.push(new FsEntry(
            String(e['name'] || ''),
            String(e['path'] || ''),
            e['isDirectory'] === true
          ))
        }
        return result
      }
    } catch (e) { /* ignore */ }
    return []
  }

  // MARK: - 文件读取 API

  async readFileText(filePath: string): Promise<string> {
    try {
      const res = await this.request<Record<string, Object>>('/api/filesystem/read?path=' + encodeURIComponent(filePath), 'GET', '')
      const content = res['content']
      if (typeof content === 'string') return content
    } catch (e) { /* ignore */ }
    return ''
  }

  /**
   * 下载文件为 Base64 编码
   * 用于获取图片等二进制文件，返回 data:image/...;base64,... 格式
   */
  async downloadFileAsBase64(filePath: string): Promise<string> {
    if (!this.baseUrl) {
      throw new APIError('服务器地址未设置', -1)
    }

    const url = this.baseUrl + '/api/filesystem/read?path=' + encodeURIComponent(filePath)
    console.info(`[APIService] Download file: ${url}`)

    const httpRequest = http.createHttp()
    try {
      // 使用二进制模式读取文件
      const response = await httpRequest.request(url, {
        method: http.RequestMethod.GET,
        connectTimeout: 30000,
        readTimeout: 30000,
        header: {
          'Accept': 'image/png,image/jpeg,image/svg+xml,image/*,*/*'
        },
        // 让 http 响应返回字符串（对于小文件足够）
        expectDataType: http.HttpDataType.STRING
      })

      if (response.responseCode >= 200 && response.responseCode < 300) {
        const result = response.result as string
        // 判断是否为 JSON（文本文件）或二进制
        if (typeof result === 'string') {
          try {
            const parsed: Record<string, Object> = JSON.parse(result)
            if (parsed && parsed['content']) {
              // 文本文件内容
              return parsed['content'] as string
            }
          } catch (e) {
            // 不是 JSON，尝试 base64
            return result
          }
        }
      }
      throw new APIError('文件下载失败', response.responseCode)
    } catch (e) {
      if (e instanceof APIError) throw e
      console.error(`[APIService] Download error: ${e}`)
      throw new APIError('文件下载失败: 网络错误', -3)
    } finally {
      httpRequest.destroy()
    }
  }

  /**
   * 获取文件信息（MIME 类型、大小等）
   */
  async getFileInfo(filePath: string): Promise<FileInfoResult> {
    try {
      const res = await this.request<Record<string, Object>>('/api/filesystem/info?path=' + encodeURIComponent(filePath), 'GET', '')
      const result = new FileInfoResult()
      result.type = (res['mimeType'] as string) || ''
      result.size = (res['size'] as number) || 0
      result.name = (res['name'] as string) || filePath.split('/').pop() || filePath
      return result
    } catch (e) {
      // 从文件路径推断
      const name = filePath.split('/').pop() || filePath
      const ext = name.split('.').pop()?.toLowerCase() || ''
      const mimeMap: Record<string, string> = {
        'png': 'image/png', 'jpg': 'image/jpeg', 'jpeg': 'image/jpeg',
        'gif': 'image/gif', 'svg': 'image/svg+xml', 'webp': 'image/webp',
        'pdf': 'application/pdf', 'txt': 'text/plain'
      }
      const result = new FileInfoResult()
      result.type = mimeMap[ext] || 'application/octet-stream'
      result.size = 0
      result.name = name
      return result
    }
  }

  // MARK: - Status API

  async getServerStatus(): Promise<ServerStatusResponse> {
    return await this.request<ServerStatusResponse>('/api/status', 'GET', '')
  }

  async getUsage(): Promise<UsageResponse> {
    return await this.request<UsageResponse>('/api/status/usage', 'GET', '')
  }

  async getUserStatus(): Promise<UserStatusResponse> {
    return await this.request<UserStatusResponse>('/api/status/user', 'GET', '')
  }

  // MARK: - Activity Stats API

  async getActivityStats(range?: string): Promise<ActivityStatsResponse> {
    const path = range ? `/api/activity-stats/${range}` : '/api/activity-stats'
    return await this.request<ActivityStatsResponse>(path, 'GET', '')
  }

  // MARK: - Diagnostics API

  async getDiagnosticsStatus(): Promise<DiagnosticsStatusResponse> {
    return await this.request<DiagnosticsStatusResponse>('/api/diagnostics/status', 'GET', '')
  }

  async getDiagnosticsEvents(limit?: number): Promise<DiagnosticsEventsResponse> {
    const path = limit ? `/api/diagnostics/events?limit=${limit}` : '/api/diagnostics/events'
    return await this.request<DiagnosticsEventsResponse>(path, 'GET', '')
  }

  // MARK: - Skills API

  async getSkills(): Promise<SkillsListResponse> {
    return await this.request<SkillsListResponse>('/api/skills', 'GET', '')
  }

  // MARK: - Agents API

  async getAgents(): Promise<AgentsListResponse> {
    return await this.request<AgentsListResponse>('/api/agents', 'GET', '')
  }

  async getAgentDetail(name: string): Promise<AgentDetailResponse> {
    return await this.request<AgentDetailResponse>('/api/agents/' + encodeURIComponent(name), 'GET', '')
  }

  // MARK: - Scheduled Tasks API

  async getScheduledTasks(): Promise<ScheduledTasksListResponse> {
    return await this.request<ScheduledTasksListResponse>('/api/scheduled-tasks', 'GET', '')
  }

  async createScheduledTask(data: Record<string, Object>): Promise<ScheduledTaskResponse> {
    return await this.request<ScheduledTaskResponse>('/api/scheduled-tasks', 'POST', JSON.stringify(data))
  }

  async updateScheduledTask(id: string, data: Record<string, Object>): Promise<ScheduledTaskResponse> {
    return await this.request<ScheduledTaskResponse>('/api/scheduled-tasks/' + encodeURIComponent(id), 'PUT',
      JSON.stringify(data))
  }

  async deleteScheduledTask(id: string): Promise<OkResponse> {
    return await this.request<OkResponse>('/api/scheduled-tasks/' + encodeURIComponent(id), 'DELETE', '')
  }

  async executeScheduledTask(id: string): Promise<OkResponse> {
    return await this.request<OkResponse>('/api/scheduled-tasks/' + encodeURIComponent(id) + '/run', 'POST', '')
  }

  async getScheduledTaskRuns(id: string): Promise<TaskRunsResponse> {
    return await this.request<TaskRunsResponse>('/api/scheduled-tasks/' + encodeURIComponent(id) + '/runs', 'GET', '')
  }

  // MARK: - Settings API

  async getUserSettings(): Promise<Record<string, Object>> {
    return await this.request<Record<string, Object>>('/api/settings/user', 'GET', '')
  }

  async updateUserSettings(settings: Record<string, Object>): Promise<void> {
    await this.request<Record<string, Object>>('/api/settings/user', 'PUT', JSON.stringify(settings))
  }

  // MARK: - Git API

  async getGitStatus(workDir: string): Promise<GitStatusResponse> {
    const res = await this.request<Record<string, Object>>(
      '/api/git/status?path=' + encodeURIComponent(workDir), 'GET', ''
    )
    const response = new GitStatusResponse()
    response.branch = (res['branch'] as string) || ''
    response.ahead = (res['ahead'] as number) || 0
    response.behind = (res['behind'] as number) || 0
    response.hasChanges = (res['hasChanges'] as boolean) || false

    const parseFiles = (arr: Object[] | undefined): GitStatusFile[] => {
      if (!arr) return []
      return arr.map((item: Object) => {
        const f = item as Record<string, Object>
        const file = new GitStatusFile()
        file.path = (f['path'] as string) || ''
        file.status = (f['status'] as string) || ''
        file.oldPath = (f['oldPath'] as string) || ''
        return file
      })
    }

    response.staged = parseFiles(res['staged'] as Object[])
    response.unstaged = parseFiles(res['unstaged'] as Object[])
    response.untracked = parseFiles(res['untracked'] as Object[])
    return response
  }

  async getGitDiff(workDir: string, staged: boolean = false): Promise<GitDiffResponse> {
    const path = '/api/git/diff?path=' + encodeURIComponent(workDir) + '&staged=' + staged
    const res = await this.request<Record<string, Object>>(path, 'GET', '')
    const response = new GitDiffResponse()
    if (res['files'] && Array.isArray(res['files'])) {
      response.files = (res['files'] as Object[]).map((f: Object) => {
        const file = f as Record<string, Object>
        const df = new GitDiffFile()
        df.path = (file['path'] as string) || ''
        df.oldPath = (file['oldPath'] as string) || ''
        if (file['hunks'] && Array.isArray(file['hunks'])) {
          df.hunks = (file['hunks'] as Object[]).map((h: Object) => {
            const hunk = h as Record<string, Object>
            const dh = new GitDiffHunk()
            dh.oldStart = (hunk['oldStart'] as number) || 0
            dh.oldLines = (hunk['oldLines'] as number) || 0
            dh.newStart = (hunk['newStart'] as number) || 0
            dh.newLines = (hunk['newLines'] as number) || 0
            dh.lines = (hunk['lines'] as string[]) || []
            return dh
          })
        }
        return df
      })
    }
    return response
  }

  async gitCommit(workDir: string, message: string, files?: string[]): Promise<GitCommitResponse> {
    const req = new GitCommitRequest()
    req.message = message
    if (files && files.length > 0) {
      req.files = files
    }
    const res = await this.request<Record<string, Object>>(
      '/api/git/commit?path=' + encodeURIComponent(workDir), 'POST', JSON.stringify(req)
    )
    const response = new GitCommitResponse()
    response.sha = (res['sha'] as string) || ''
    response.message = (res['message'] as string) || ''
    response.files = (res['files'] as string[]) || []
    return response
  }

  async gitPush(workDir: string, remote?: string, branch?: string): Promise<GitPushResponse> {
    let path = '/api/git/push?path=' + encodeURIComponent(workDir)
    if (remote) path += '&remote=' + encodeURIComponent(remote)
    if (branch) path += '&branch=' + encodeURIComponent(branch)

    const res = await this.request<Record<string, Object>>(path, 'POST', '')
    const response = new GitPushResponse()
    response.success = (res['success'] as boolean) || false
    response.message = (res['message'] as string) || ''
    response.remote = (res['remote'] as string) || ''
    response.branch = (res['branch'] as string) || ''
    return response
  }

  async gitPull(workDir: string, remote?: string, branch?: string): Promise<GitPullResponse> {
    let path = '/api/git/pull?path=' + encodeURIComponent(workDir)
    if (remote) path += '&remote=' + encodeURIComponent(remote)
    if (branch) path += '&branch=' + encodeURIComponent(branch)

    const res = await this.request<Record<string, Object>>(path, 'POST', '')
    const response = new GitPullResponse()
    response.success = (res['success'] as boolean) || false
    response.message = (res['message'] as string) || ''
    response.files = (res['files'] as string[]) || []
    response.ahead = (res['ahead'] as number) || 0
    response.behind = (res['behind'] as number) || 0
    return response
  }

  async gitAdd(workDir: string, files: string[]): Promise<OkResponse> {
    const req = new GitAddRequest()
    req.files = files
    const res = await this.request<Record<string, Object>>(
      '/api/git/add?path=' + encodeURIComponent(workDir), 'POST', JSON.stringify(req)
    )
    return { ok: (res['ok'] as boolean) || false }
  }

  async gitCheckout(workDir: string, branch: string, createNew: boolean = false): Promise<OkResponse> {
    let path = '/api/git/checkout?path=' + encodeURIComponent(workDir) + '&branch=' + encodeURIComponent(branch)
    if (createNew) path += '&createNew=true'

    const res = await this.request<Record<string, Object>>(path, 'POST', '')
    return { ok: (res['ok'] as boolean) || false }
  }

  async gitBranch(workDir: string): Promise<GitBranchResponse> {
    const res = await this.request<Record<string, Object>>(
      '/api/git/branch?path=' + encodeURIComponent(workDir), 'GET', ''
    )
    const response = new GitBranchResponse()
    response.current = (res['current'] as string) || ''
    if (res['branches'] && Array.isArray(res['branches'])) {
      response.branches = (res['branches'] as Object[]).map((b: Object) => {
        const branch = b as Record<string, Object>
        const item = new GitBranchItem()
        item.name = (branch['name'] as string) || ''
        item.isRemote = (branch['isRemote'] as boolean) || false
        item.isCurrent = (branch['isCurrent'] as boolean) || false
        item.upstream = (branch['upstream'] as string) || ''
        item.ahead = (branch['ahead'] as number) || 0
        item.behind = (branch['behind'] as number) || 0
        return item
      })
    }
    return response
  }

  async gitLog(workDir: string, limit: number = 20): Promise<GitLogResponse> {
    const res = await this.request<Record<string, Object>>(
      '/api/git/log?path=' + encodeURIComponent(workDir) + '&limit=' + limit, 'GET', ''
    )
    const response = new GitLogResponse()
    if (res['commits'] && Array.isArray(res['commits'])) {
      response.commits = (res['commits'] as Object[]).map((c: Object) => {
        const commit = c as Record<string, Object>
        const item = new GitCommitItem()
        item.sha = (commit['sha'] as string) || ''
        item.shortSha = (commit['shortSha'] as string) || ''
        item.message = (commit['message'] as string) || ''
        item.author = (commit['author'] as string) || ''
        item.email = (commit['email'] as string) || ''
        item.date = (commit['date'] as string) || ''
        item.parents = (commit['parents'] as string[]) || []
        return item
      })
    }
    return response
  }

  async gitRemotes(workDir: string): Promise<GitRemoteResponse> {
    const res = await this.request<Record<string, Object>>(
      '/api/git/remotes?path=' + encodeURIComponent(workDir), 'GET', ''
    )
    const response = new GitRemoteResponse()
    if (res['remotes'] && Array.isArray(res['remotes'])) {
      response.remotes = (res['remotes'] as Object[]).map((r: Object) => {
        const remote = r as Record<string, Object>
        const item = new GitRemoteItem()
        item.name = (remote['name'] as string) || ''
        item.fetchUrl = (remote['fetchUrl'] as string) || ''
        item.pushUrl = (remote['pushUrl'] as string) || ''
        return item
      })
    }
    return response
  }

  async gitStash(workDir: string, message?: string): Promise<GitStashResponse> {
    let path = '/api/git/stash?path=' + encodeURIComponent(workDir)
    if (message) path += '&message=' + encodeURIComponent(message)

    const res = await this.request<Record<string, Object>>(path, 'POST', '')
    const response = new GitStashResponse()
    response.success = (res['success'] as boolean) || false
    response.message = (res['message'] as string) || ''
    response.stashName = (res['stashName'] as string) || ''
    return response
  }

  async gitStashPop(workDir: string): Promise<GitStashResponse> {
    const res = await this.request<Record<string, Object>>(
      '/api/git/stash/pop?path=' + encodeURIComponent(workDir), 'POST', ''
    )
    const response = new GitStashResponse()
    response.success = (res['success'] as boolean) || false
    response.message = (res['message'] as string) || ''
    return response
  }

  async createPullRequest(workDir: string, request: GitCreatePRRequest): Promise<GitCreatePRResponse> {
    const res = await this.request<Record<string, Object>>(
      '/api/git/pr?path=' + encodeURIComponent(workDir), 'POST', JSON.stringify(request)
    )
    const response = new GitCreatePRResponse()
    response.success = (res['success'] as boolean) || false
    response.url = (res['url'] as string) || ''
    response.number = (res['number'] as number) || 0
    response.message = (res['message'] as string) || ''
    return response
  }

  // MARK: - Markdown API

  async renderMarkdown(filePath: string): Promise<MarkdownRenderResponse> {
    const res = await this.request<Record<string, Object>>(
      '/api/filesystem/markdown?path=' + encodeURIComponent(filePath), 'GET', ''
    )
    const response = new MarkdownRenderResponse()
    response.html = (res['html'] as string) || ''
    if (res['toc'] && Array.isArray(res['toc'])) {
      response.toc = (res['toc'] as Object[]).map((t: Object) => {
        const item = t as Record<string, Object>
        const tocItem = new MarkdownTocItem()
        tocItem.level = (item['level'] as number) || 0
        tocItem.text = (item['text'] as string) || ''
        tocItem.anchor = (item['anchor'] as string) || ''
        return tocItem
      })
    }
    return response
  }

  // MARK: - Web Preview API

  async startWebPreview(workDir: string, port?: number, path?: string): Promise<WebPreviewResponse> {
    const body: Record<string, Object> = {}
    if (port) body['port'] = port
    if (path) body['path'] = path

    const res = await this.request<Record<string, Object>>(
      '/api/preview/start?workDir=' + encodeURIComponent(workDir), 'POST', JSON.stringify(body)
    )
    const response = new WebPreviewResponse()
    response.url = (res['url'] as string) || ''
    response.port = (res['port'] as number) || 0
    response.status = (res['status'] as string) || ''
    return response
  }

  async stopWebPreview(workDir: string, port: number): Promise<OkResponse> {
    const res = await this.request<Record<string, Object>>(
      '/api/preview/stop?workDir=' + encodeURIComponent(workDir) + '&port=' + port, 'POST', ''
    )
    return { ok: (res['ok'] as boolean) || false }
  }

  // MARK: - SSH API

  async sshConnect(request: SSHConnectionRequest): Promise<SSHConnectionResponse> {
    const res = await this.request<Record<string, Object>>(
      '/api/ssh/connect', 'POST', JSON.stringify(request)
    )
    const response = new SSHConnectionResponse()
    response.success = (res['success'] as boolean) || false
    response.sessionId = (res['sessionId'] as string) || ''
    response.message = (res['message'] as string) || ''
    return response
  }

  async sshDisconnect(sessionId: string): Promise<OkResponse> {
    const res = await this.request<Record<string, Object>>(
      '/api/ssh/disconnect?sessionId=' + encodeURIComponent(sessionId), 'POST', ''
    )
    return { ok: (res['ok'] as boolean) || false }
  }

  async sshExecute(sessionId: string, command: string): Promise<SSHCommandResponse> {
    const req = new SSHCommandRequest()
    req.sessionId = sessionId
    req.command = command
    const res = await this.request<Record<string, Object>>(
      '/api/ssh/execute', 'POST', JSON.stringify(req)
    )
    const response = new SSHCommandResponse()
    response.success = (res['success'] as boolean) || false
    response.output = (res['output'] as string) || ''
    response.exitCode = (res['exitCode'] as number) || 0
    return response
  }

  // MARK: - 桌面端能力自检

  async checkDesktopCapabilities(): Promise<DesktopCapabilityReport> {
    const checks: DesktopCapabilityItem[] = [
      this.makeCapability('status', '服务状态', '桌面端 server 基础健康检查', '/api/status', true),
      this.makeCapability('sessions', '会话控制', '读取和创建桌面端会话', '/api/sessions', true),
      this.makeCapability('filesystem', '文件访问', '浏览桌面端工作目录与文件', '/api/filesystem/browse?includeFiles=true', true),
      this.makeCapability('providers', '模型服务商', '读取和切换桌面端 Provider', '/api/providers', true),
      this.makeCapability('models', '模型列表', '读取桌面端可用模型', '/api/models', true),
      this.makeCapability('agents', 'Agent 管理', '读取桌面端 Agent 能力', '/api/agents', false),
      this.makeCapability('skills', '技能管理', '读取桌面端技能列表', '/api/skills', false),
      this.makeCapability('git', 'Git 能力', '检测桌面端 Git API 是否存在', '/api/git/status', false),
      this.makeCapability('preview', '网页预览', '启动桌面端项目预览服务', '/api/preview/start', false),
      this.makeCapability('ssh', 'SSH/终端', '通过桌面端执行远程命令', '/api/ssh/connect', false)
    ]

    const report = new DesktopCapabilityReport()
    report.checkedAt = Date.now()

    for (let i = 0; i < checks.length; i++) {
      report.items.push(await this.probeCapability(checks[i]))
    }

    report.ok = report.items.filter((item: DesktopCapabilityItem) => item.required && !item.available).length === 0
    return report
  }

  // MARK: - 私有方法

  private makeCapability(key: string, title: string, description: string, path: string, required: boolean): DesktopCapabilityItem {
    const item = new DesktopCapabilityItem()
    item.key = key
    item.title = title
    item.description = description
    item.path = path
    item.required = required
    item.message = '未检测'
    item.statusCode = 0
    item.latency = -1
    return item
  }

  private async probeCapability(item: DesktopCapabilityItem): Promise<DesktopCapabilityItem> {
    if (!this.baseUrl) {
      item.available = false
      item.message = '服务器地址未设置'
      return item
    }

    const startTime = Date.now()
    const httpRequest = http.createHttp()

    try {
      const response = await httpRequest.request(this.baseUrl + item.path, {
        method: http.RequestMethod.GET,
        connectTimeout: 5000,
        readTimeout: 5000,
        header: {
          'Accept': 'application/json'
        }
      })

      item.latency = Date.now() - startTime
      item.statusCode = response.responseCode
      item.available = response.responseCode >= 200 && response.responseCode < 500 && response.responseCode !== 404
      if (item.available) {
        item.message = item.latency + 'ms'
      } else if (response.responseCode === 404) {
        item.message = '桌面端未实现'
      } else {
        item.message = 'HTTP ' + response.responseCode
      }
    } catch (e) {
      const err = e as Error
      item.available = false
      item.latency = -1
      item.message = err.message || '请求失败'
    } finally {
      httpRequest.destroy()
    }

    return item
  }

  private async request<T>(path: string, method: string, body: string, timeoutMs: number = 30000): Promise<T> {
    if (!this.baseUrl) {
      throw new APIError('服务器地址未设置', -1)
    }

    const url = this.baseUrl + path
    console.info(`[APIService] Request: ${method} ${url}`)

    const httpRequest = http.createHttp()

    let httpMethod: http.RequestMethod = http.RequestMethod.GET
    if (method === 'POST') {
      httpMethod = http.RequestMethod.POST
    } else if (method === 'PUT') {
      httpMethod = http.RequestMethod.PUT
    } else if (method === 'PATCH') {
      httpMethod = http.RequestMethod.PUT
      // 鸿蒙 http.RequestMethod 不包含 PATCH 枚举值，服务端使用 X-HTTP-Method-Override 头识别 PATCH
      // 若服务端不支持此方式，需改用 POST 或添加原生 PATCH 支持
    } else if (method === 'DELETE') {
      httpMethod = http.RequestMethod.DELETE
    }

    const headers: Record<string, string> = {
      'Content-Type': 'application/json'
    }
    if (method === 'PATCH') {
      headers['X-HTTP-Method-Override'] = 'PATCH'
    }

    const options: http.HttpRequestOptions = {
      method: httpMethod,
      header: headers,
      connectTimeout: timeoutMs,
      readTimeout: timeoutMs
    }

    if (body) {
      options.extraData = body
    }

    try {
      const response = await httpRequest.request(url, options)
      console.info(`[APIService] Response code: ${response.responseCode}`)

      if (response.responseCode >= 200 && response.responseCode < 300) {
        const result = response.result as string
        return JSON.parse(result) as T
      } else {
        const errorBody = this.parseErrorBody(response.result as string)
        const serverMessage = errorBody['userMessage'] || errorBody['message'] || errorBody['error']
        const serverCode = errorBody['error'] || ''
        if (serverMessage && String(serverMessage).length > 0) {
          throw new APIError(String(serverMessage), response.responseCode, String(serverCode))
        }
        if (response.responseCode === 401) {
          throw new APIError('未授权，请检查配对码', 401)
        } else if (response.responseCode === 404) {
          throw new APIError('接口不存在，请检查服务器地址', 404)
        } else if (response.responseCode === 500) {
          throw new APIError('服务器内部错误', 500)
        }
        throw new APIError(`请求失败 (${response.responseCode})`, response.responseCode)
      }
    } catch (e) {
      if (e instanceof APIError) {
        throw e
      }
      // 处理网络错误
      const err = e as Error
      console.error(`[APIService] Error: ${err.message}`)
      if (err.message.includes('timeout')) {
        throw new APIError('连接超时，请检查网络', -2)
      } else if (err.message.includes('network')) {
        throw new APIError('网络错误，请检查连接', -3)
      } else if (err.message.includes('ECONNREFUSED')) {
        throw new APIError('无法连接到服务器', -4)
      }
      throw new APIError(err.message || '未知错误', 0)
    } finally {
      httpRequest.destroy()
    }
  }

  private parseErrorBody(raw: string): Record<string, string> {
    if (!raw || raw.length === 0) return {}
    try {
      const parsed = JSON.parse(raw) as Record<string, Object>
      const result: Record<string, string> = {}
      if (parsed['userMessage']) result['userMessage'] = String(parsed['userMessage'])
      if (parsed['message']) result['message'] = String(parsed['message'])
      if (parsed['error']) result['error'] = String(parsed['error'])
      return result
    } catch (e) {
      return {}
    }
  }

  /**
   * 通过官方 Codex Remote Control 向 Codex Desktop 发送消息
   */
  async sendCodexRemotePrompt(
    prompt: string,
    cwd?: string,
    threadId?: string,
    clientSessionId?: string,
    model?: string,
    reasoningEffort?: string,
    serviceTier?: string,
    transportMode?: 'auto' | 'remote_control' | 'script_fallback'
  ): Promise<Record<string, Object>> {
    const body = JSON.stringify({
      prompt,
      cwd: cwd || null,
      threadId: threadId || null,
      clientSessionId: clientSessionId || null,
      model: model || null,
      reasoningEffort: reasoningEffort || null,
      serviceTier: serviceTier || null,
      transportMode: transportMode || 'auto'
    })
    return await this.request<Record<string, Object>>('/api/official-codex-remote/send', 'POST', body, 70000)
  }
  // MARK: - Official Codex Remote Control API

  /**
   * 获取 Official Codex Remote Control 状态
   */
  async getCodexRemoteStatus(): Promise<Record<string, Object>> {
    return await this.request<Record<string, Object>>('/api/official-codex-remote/status', 'GET', '')
  }

  /**
   * 获取 controller session 信息
   */
  async getCodexControllerSession(): Promise<Record<string, Object>> {
    return await this.request<Record<string, Object>>('/api/official-codex-remote/controller-session', 'GET', '')
  }

  /**
   * 恢复持久化的 controller session
   */
  async restoreCodexControllerSession(autoConnect: boolean = false): Promise<Record<string, Object>> {
    const body = JSON.stringify({ autoConnect })
    return await this.request<Record<string, Object>>('/api/official-codex-remote/restore', 'POST', body, 25000)
  }

  /**
   * 刷新 controller token
   */
  async refreshCodexControllerToken(): Promise<Record<string, Object>> {
    return await this.request<Record<string, Object>>('/api/official-codex-remote/refresh', 'POST', '')
  }

  /**
   * 连接 controller WebSocket
   */
  async connectCodexController(): Promise<Record<string, Object>> {
    return await this.request<Record<string, Object>>('/api/official-codex-remote/connect', 'POST', '', 25000)
  }

  /**
   * 获取 controller WebSocket 状态
   */
  async getCodexControllerWsStatus(): Promise<Record<string, Object>> {
    return await this.request<Record<string, Object>>('/api/official-codex-remote/ws-status', 'GET', '', 4000)
  }

  /**
   * 断开 controller WebSocket
   */
  async disconnectCodexController(): Promise<Record<string, Object>> {
    return await this.request<Record<string, Object>>('/api/official-codex-remote/ws-disconnect', 'POST', '')
  }

  /**
   * 拉取官方 Codex Desktop 线程 turns，用于手机端同步 AI 回复
   */
  async getCodexRemoteThreadTurns(threadId: string): Promise<Record<string, Object>> {
    const encoded = encodeURIComponent(threadId)
    return await this.request<Record<string, Object>>(
      `/api/official-codex-remote/thread/${encoded}/turns?itemsView=full&sortDirection=desc&limit=20`,
      'GET',
      '',
      90000
    )
  }

  /**
   * 从本地 Codex session 文件读取线程历史，作为 Official turns API 的兜底
   */
  async getLocalCodexThreadMessages(threadId: string, limit: number = 400): Promise<Record<string, Object>> {
    const encoded = encodeURIComponent(threadId)
    return await this.request<Record<string, Object>>(
      `/api/official-codex-remote/thread/${encoded}/local-messages?limit=${limit}`,
      'GET',
      '',
      12000
    )
  }

  /**
   * 拉取官方 Codex Desktop 最新 turns，用于正在进行的回复轮询
   */
  async getCodexRemoteLatestThreadTurns(
    threadId: string,
    limit: number = 8,
    timeoutMs: number = 6000
  ): Promise<Record<string, Object>> {
    const encoded = encodeURIComponent(threadId)
    return await this.request<Record<string, Object>>(
      `/api/official-codex-remote/thread/${encoded}/turns?itemsView=full&sortDirection=desc&limit=${limit}`,
      'GET',
      '',
      timeoutMs
    )
  }

  /**
   * 拉取官方 Codex Desktop 线程列表
   */
  async listCodexRemoteThreads(limit: number = 50, cursor?: string): Promise<Record<string, Object>> {
    let path = `/api/official-codex-remote/threads?limit=${limit}&sortDirection=desc`
    if (cursor && cursor.length > 0) {
      path += `&cursor=${encodeURIComponent(cursor)}`
    }
    return await this.request<Record<string, Object>>(path, 'GET', '', 12000)
  }

  /**
   * 读取官方 Codex Desktop 单个线程元信息
   */
  async readCodexRemoteThread(threadId: string): Promise<Record<string, Object>> {
    const encoded = encodeURIComponent(threadId)
    return await this.request<Record<string, Object>>(`/api/official-codex-remote/thread/${encoded}`, 'GET', '')
  }

  /**
   * 回复官方 Codex Desktop Remote Control 权限审批
   */
  async sendCodexRemotePermissionResponse(requestId: string, allowed: boolean): Promise<Record<string, Object>> {
    const body = JSON.stringify({
      requestId,
      allowed
    })
    return await this.request<Record<string, Object>>('/api/official-codex-remote/permission-response', 'POST', body)
  }

  async getCodexRemotePendingPermissions(clientSessionId: string, threadId: string): Promise<Record<string, Object>> {
    let path = '/api/official-codex-remote/pending-permissions'
    const params: string[] = []
    if (clientSessionId.length > 0) params.push('clientSessionId=' + encodeURIComponent(clientSessionId))
    if (threadId.length > 0) params.push('threadId=' + encodeURIComponent(threadId))
    if (params.length > 0) path += '?' + params.join('&')
    return await this.request<Record<string, Object>>(path, 'GET', '')
  }

  // MARK: - Push Token 上报

  async uploadPushToken(token: string): Promise<void> {
    const req = new PushTokenRequest()
    req.token = token
    await this.request<Object>('/api/push/token', 'POST', JSON.stringify(req))
  }

  // MARK: - 消息转换

  private transformMessages(rawMessages: RawMessage[]): Message[] {
    const result: Message[] = []

    for (let idx = 0; idx < rawMessages.length; idx++) {
      const msg = rawMessages[idx]
      const msgId = msg.id || msg.type + '-' + msg.timestamp + '-' + result.length
      const timestamp = msg.timestamp || ''

      // 用户消息
      if (msg.type === 'user') {
        const text = this.extractText(msg.content)
        if (text.trim()) {
          const userMsg: Message = {
            id: msgId,
            type: 'user',
            content: text.trim(),
            timestamp: timestamp
          }
          result.push(userMsg)
        }
        continue
      }

      // 助手消息
      if (msg.type === 'assistant') {
        // 先处理 thinking 内容
        if (msg.thinking && msg.thinking.trim()) {
          const thinkingMsg: Message = {
            id: msgId + '-thinking',
            type: 'thinking',
            content: msg.thinking.trim(),
            timestamp: timestamp
          }
          result.push(thinkingMsg)
        }

        if (msg.content) {
          if (typeof msg.content === 'object' && Array.isArray(msg.content)) {
            const blocks = msg.content as ContentBlock[]
            // 先遍历 thinking 块（确保思考过程在回复文本之前）
            for (let blockIdx = 0; blockIdx < blocks.length; blockIdx++) {
              const block = blocks[blockIdx]
              if (block.type === 'thinking') {
                const thinkingText = (block.text || '').trim()
                if (thinkingText) {
                  const thinkingMsg: Message = {
                    id: msgId + '-thinking-' + blockIdx,
                    type: 'thinking',
                    content: thinkingText,
                    timestamp: timestamp
                  }
                  result.push(thinkingMsg)
                }
              }
            }
            // 再遍历 text 和 tool_use 块
            for (let blockIdx = 0; blockIdx < blocks.length; blockIdx++) {
              const block = blocks[blockIdx]

              if (block.type === 'text') {
                const text = (block.text || '').trim()
                if (text) {
                  const textMsg: Message = {
                    id: msgId + '-text-' + blockIdx,
                    type: 'assistant',
                    content: text,
                    timestamp: timestamp
                  }
                  result.push(textMsg)
                }
              } else if (block.type === 'tool_use') {
                const toolUseId = block.id || block.tool_use_id || block.toolUseId || ''
                const toolMsg: Message = {
                  id: toolUseId || msgId + '-tool-' + blockIdx,
                  type: 'tool_use',
                  content: '',
                  timestamp: timestamp,
                  toolName: block.name || 'Unknown',
                  toolInput: block.input,
                  toolUseId: toolUseId || undefined,
                  toolStatus: 'completed'
                }
                result.push(toolMsg)
              }
            }
          } else if (typeof msg.content === 'string') {
            const text = (msg.content as string).trim()
            if (text && !text.startsWith('[{')) {
              const textMsg: Message = {
                id: msgId,
                type: 'assistant',
                content: text,
                timestamp: timestamp
              }
              result.push(textMsg)
            }
          }
        }
        continue
      }

      // tool_result 消息
      if (msg.type === 'tool_result') {
        let resultContent = ''
        const extractedImages: MessageImage[] = []
        if (msg.content) {
          if (typeof msg.content === 'string') {
            resultContent = msg.content as string
          } else if (Array.isArray(msg.content)) {
            const blocks = msg.content as ContentBlock[]
            const texts: string[] = []
            for (let i = 0; i < blocks.length; i++) {
              const block = blocks[i]
              if (block.type === 'text' && block.text) {
                texts.push(block.text)
              } else if (block.type === 'image' && block.source) {
                const source = block.source
                if (source['data'] && source['media_type']) {
                  const img: MessageImage = {
                    data: String(source['data']),
                    mediaType: String(source['media_type'])
                  }
                  extractedImages.push(img)
                }
              }
            }
            resultContent = texts.join('')
          }
        }

        if (!resultContent.startsWith('[{')) {
          const rawMsg = msg as RawMessage
          const toolUseId = rawMsg.tool_use_id || rawMsg.toolUseId || ''
          const resultMsg: Message = {
            id: msgId,
            type: 'tool_result',
            content: '',
            timestamp: timestamp,
            toolUseId: toolUseId || undefined,
            toolResult: resultContent,
            toolStatus: msg.isError ? 'failed' : 'completed',
            images: extractedImages.length > 0 ? extractedImages : undefined
          }
          result.push(resultMsg)
        }
      }
    }

    return this.pairToolResults(result)
  }

  private extractText(content: ContentBlock[] | string | null): string {
    if (!content) return ''
    if (typeof content === 'string') return content as string
    if (Array.isArray(content)) {
      const texts: string[] = []
      for (let i = 0; i < content.length; i++) {
        if (content[i].type === 'text' && content[i].text) {
          texts.push(content[i].text)
        }
      }
      return texts.join('')
    }
    return ''
  }

  private pairToolResults(messages: Message[]): Message[] {
    const result: Message[] = []

    for (let i = 0; i < messages.length; i++) {
      if (messages[i].type === 'tool_result') {
        let paired = false
        if (messages[i].toolUseId) {
          for (let j = i - 1; j >= 0; j--) {
            if (messages[j].type === 'tool_use' &&
              messages[j].toolUseId === messages[i].toolUseId &&
              !messages[j].toolResult) {
              messages[j].toolResult = messages[i].toolResult
              messages[j].toolStatus = messages[i].toolStatus
              if (messages[i].images && messages[i].images!.length > 0) {
                messages[j].images = messages[i].images
              }
              paired = true
              break
            }
          }
        }

        // 找不到 toolUseId 或历史数据缺字段时，回退到最近的未配对 tool_use。
        if (!paired) {
          for (let j = i - 1; j >= 0; j--) {
            if (messages[j].type === 'tool_use' && !messages[j].toolResult) {
              messages[j].toolResult = messages[i].toolResult
              messages[j].toolStatus = messages[i].toolStatus
              if (messages[i].images && messages[i].images!.length > 0) {
                messages[j].images = messages[i].images
              }
              break
            }
          }
        }
      }
    }

    // 过滤掉 tool_result
    for (let i = 0; i < messages.length; i++) {
      if (messages[i].type !== 'tool_result') {
        result.push(messages[i])
      }
    }

    return result
  }

  // 获取 Codex 线程上下文容量信息
  async getCodexThreadContext(threadId: string): Promise<Record<string, Object>> {
    const encoded = encodeURIComponent(threadId)
    return await this.request<Record<string, Object>>(
      `/api/official-codex-remote/thread/${encoded}/context`,
      'GET',
      '',
      8000
    )
  }

  // 快速获取本地线程列表（从 ~/.codex/sessions 读取）
  async getLocalCodexThreads(limit: number = 120, maxAgeDays: number = 15): Promise<Record<string, Object>> {
    return await this.request<Record<string, Object>>(
      `/api/official-codex-remote/local-threads?limit=${limit}&maxAgeDays=${maxAgeDays}`,
      'GET',
      ''
    )
  }


}

// 单例导出
export const apiService = new APIService()
