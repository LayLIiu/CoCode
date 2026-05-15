/**
 * HTTP API 服务
 * 负责与服务器的所有 HTTP 通信
 */

import http from '@ohos.net.http'
import {
  Session, Message, Provider, NetworkInfo, ModelInfo,
  RecentProject, EffortResponse, ProviderInput, ProviderTestOverrides,
  ProviderTestResultResponse, ProviderResponse, TunnelResponse, RecentProjectsResponse
} from '../models/Models'

// 请求体类型定义
export class WorkDirRequest {
  workDir: string = ''
}

export class CreateSessionRequest {
  workDir: string = ''
  providerId?: string
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
  type: string = ''
  text: string = ''
  name: string = ''
  input: Record<string, Object> = {}
}

export class RawMessage {
  id: string = ''
  type: string = ''
  content: ContentBlock[] | string | null = null
  timestamp: string = ''
  isError: boolean = false
  thinking: string = ''
}

export class APIError extends Error {
  code: number = 0

  constructor(message: string, code: number = 0) {
    super(message)
    this.code = code
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
    let processedUrl = url.trim()
    let isSecure = false

    // 移除协议前缀
    if (processedUrl.startsWith('https://')) {
      isSecure = true
      processedUrl = processedUrl.substring(8)
    } else if (processedUrl.startsWith('http://')) {
      processedUrl = processedUrl.substring(7)
    }

    // 处理 host:port:token 格式
    const colonCount = this.countChar(processedUrl, ':')
    if (colonCount >= 2) {
      const parts = processedUrl.split(':')
      if (parts.length >= 2) {
        processedUrl = parts[0] + ':' + parts[1]
      }
    }

    // 判断是否需要 HTTPS
    const isTunnel = processedUrl.includes('.tunnel.') ||
      processedUrl.includes('trycloudflare') ||
      processedUrl.includes('loca.lt')

    if (isSecure || isTunnel) {
      processedUrl = 'https://' + processedUrl
    } else {
      processedUrl = 'http://' + processedUrl
    }

    this.baseUrl = processedUrl
    console.info(`[APIService] baseUrl: ${this.baseUrl}`)
  }

  private countChar(str: string, char: string): number {
    let count = 0
    for (let i = 0; i < str.length; i++) {
      if (str[i] === char) {
        count++
      }
    }
    return count
  }

  getBaseUrl(): string {
    return this.baseUrl
  }

  // MARK: - 会话 API

  async getSessions(providerId?: string): Promise<Session[]> {
    let path = '/api/sessions'
    if (providerId) {
      path += '?providerId=' + providerId
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

  async createSessionWithProvider(workDir: string, providerId: string): Promise<CreateSessionResponse> {
    const req = new CreateSessionRequest()
    req.workDir = workDir
    req.providerId = providerId
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

  async getMessages(sessionId: string): Promise<Message[]> {
    const response = await this.request<MessagesResponse>('/api/sessions/' + sessionId + '/messages', 'GET', '')
    return this.transformMessages(response.messages)
  }

  // MARK: - 网络 API

  async getNetworkInfo(): Promise<NetworkInfo> {
    const paths = ['/api/mobile/network-info', '/api/mobile/networkInfo']
    for (let i = 0; i < paths.length; i++) {
      try {
        const response = await this.request<NetworkInfoResponse>(paths[i], 'GET', '')
        const info: NetworkInfo = {
          recommendedType: response.recommendedType,
          lanUrl: response.lanUrl,
          tailscaleUrl: response.tailscaleUrl,
          tunnelUrl: response.tunnelUrl,
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
    await this.request<Object>('/api/effort', 'PUT', JSON.stringify({ level: level }))
  }

  // MARK: - 隧道 API

  async enableTunnel(enabled: boolean): Promise<TunnelResponse> {
    const paths = ['/api/mobile/tunnel', '/api/mobile/tunnel/enable']
    let lastError: Error | null = null
    for (let i = 0; i < paths.length; i++) {
      try {
        return await this.request<TunnelResponse>(paths[i], 'POST', JSON.stringify({ enabled: enabled }))
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

  async getModels(): Promise<ModelsResponse> {
    return await this.request<ModelsResponse>('/api/models', 'GET', '')
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

  // MARK: - 私有方法

  private async request<T>(path: string, method: string, body: string): Promise<T> {
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
      httpMethod = http.RequestMethod.PUT // 鸿蒙 http.RequestMethod 不包含 PATCH，用 PUT + X-HTTP-Method-Override
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
      connectTimeout: 30000,
      readTimeout: 30000
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
      } else if (response.responseCode === 401) {
        throw new APIError('未授权，请检查配对码', 401)
      } else if (response.responseCode === 404) {
        throw new APIError('接口不存在，请检查服务器地址', 404)
      } else if (response.responseCode === 500) {
        throw new APIError('服务器内部错误', 500)
      } else {
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
                const toolMsg: Message = {
                  id: msgId + '-tool-' + blockIdx,
                  type: 'tool_use',
                  content: '',
                  timestamp: timestamp,
                  toolName: block.name || 'Unknown',
                  toolInput: block.input,
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
        if (msg.content) {
          if (typeof msg.content === 'string') {
            resultContent = msg.content as string
          } else if (Array.isArray(msg.content)) {
            const arr = msg.content as ContentBlock[]
            const texts: string[] = []
            for (let i = 0; i < arr.length; i++) {
              if (arr[i].text) {
                texts.push(arr[i].text)
              }
            }
            resultContent = texts.join('')
          }
        }

        if (!resultContent.startsWith('[{')) {
          const resultMsg: Message = {
            id: msgId,
            type: 'tool_result',
            content: '',
            timestamp: timestamp,
            toolResult: resultContent,
            toolStatus: msg.isError ? 'failed' : 'completed'
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
        // 找到对应的 tool_use 并合并
        for (let j = i - 1; j >= 0; j--) {
          if (messages[j].type === 'tool_use' && !messages[j].toolResult) {
            messages[j].toolResult = messages[i].toolResult
            messages[j].toolStatus = messages[i].toolStatus
            break
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
}

export const apiService = APIService.getInstance()
