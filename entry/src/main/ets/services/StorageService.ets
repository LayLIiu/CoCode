/**
 * 本地存储服务
 * 用于持久化会话和消息数据
 */

import preferences from '@ohos.data.preferences'
import { Session, Message } from '../models/Models'

export class StorageService {
  private static instance: StorageService
  private context: Context | null = null
  private sessionStore: preferences.Preferences | null = null
  private messagesStore: preferences.Preferences | null = null

  static getInstance(): StorageService {
    if (!StorageService.instance) {
      StorageService.instance = new StorageService()
    }
    return StorageService.instance
  }

  async init(context: Context): Promise<void> {
    this.context = context

    try {
      // 初始化会话存储
      this.sessionStore = await preferences.getPreferences(context, 'sessions_store')

      // 初始化消息存储
      this.messagesStore = await preferences.getPreferences(context, 'messages_store')

      console.info('[StorageService] Initialized successfully')
    } catch (e) {
      console.error(`[StorageService] Init error: ${e}`)
    }
  }

  // MARK: - 会话存储

  async saveSessions(sessions: Session[]): Promise<void> {
    if (!this.sessionStore) return

    try {
      const jsonString = JSON.stringify(sessions)
      await this.sessionStore.put('sessions', jsonString)
      await this.sessionStore.flush()
      console.info(`[StorageService] Saved ${sessions.length} sessions`)
    } catch (e) {
      console.error(`[StorageService] Save sessions error: ${e}`)
    }
  }

  async loadSessions(): Promise<Session[]> {
    if (!this.sessionStore) return []

    try {
      const jsonString = await this.sessionStore.get('sessions', '[]') as string
      const sessions: Session[] = JSON.parse(jsonString)
      console.info(`[StorageService] Loaded ${sessions.length} sessions`)
      return sessions
    } catch (e) {
      console.error(`[StorageService] Load sessions error: ${e}`)
      return []
    }
  }

  // MARK: - 消息存储

  async saveMessages(sessionId: string, messages: Message[]): Promise<void> {
    if (!this.messagesStore) return

    try {
      const jsonString = JSON.stringify(messages)
      await this.messagesStore.put(`messages_${sessionId}`, jsonString)
      await this.messagesStore.flush()
      console.info(`[StorageService] Saved ${messages.length} messages for session ${sessionId}`)
    } catch (e) {
      console.error(`[StorageService] Save messages error: ${e}`)
    }
  }

  async loadMessages(sessionId: string): Promise<Message[]> {
    if (!this.messagesStore) return []

    try {
      const jsonString = await this.messagesStore.get(`messages_${sessionId}`, '[]') as string
      const messages: Message[] = JSON.parse(jsonString)
      console.info(`[StorageService] Loaded ${messages.length} messages for session ${sessionId}`)
      return messages
    } catch (e) {
      console.error(`[StorageService] Load messages error: ${e}`)
      return []
    }
  }

  async deleteMessages(sessionId: string): Promise<void> {
    if (!this.messagesStore) return

    try {
      await this.messagesStore.delete(`messages_${sessionId}`)
      await this.messagesStore.flush()
      console.info(`[StorageService] Deleted messages for session ${sessionId}`)
    } catch (e) {
      console.error(`[StorageService] Delete messages error: ${e}`)
    }
  }

  // MARK: - 通用数据存储

  async saveString(key: string, value: string): Promise<void> {
    if (!this.sessionStore) return

    try {
      await this.sessionStore.put(key, value)
      await this.sessionStore.flush()
    } catch (e) {
      console.error(`[StorageService] Save string error: ${e}`)
    }
  }

  async loadString(key: string, defaultValue: string = ''): Promise<string> {
    if (!this.sessionStore) return defaultValue

    try {
      return await this.sessionStore.get(key, defaultValue) as string
    } catch (e) {
      console.error(`[StorageService] Load string error: ${e}`)
      return defaultValue
    }
  }

  async saveNumber(key: string, value: number): Promise<void> {
    if (!this.sessionStore) return

    try {
      await this.sessionStore.put(key, value)
      await this.sessionStore.flush()
    } catch (e) {
      console.error(`[StorageService] Save number error: ${e}`)
    }
  }

  async loadNumber(key: string, defaultValue: number = 0): Promise<number> {
    if (!this.sessionStore) return defaultValue

    try {
      return await this.sessionStore.get(key, defaultValue) as number
    } catch (e) {
      console.error(`[StorageService] Load number error: ${e}`)
      return defaultValue
    }
  }

  async saveBoolean(key: string, value: boolean): Promise<void> {
    if (!this.sessionStore) return

    try {
      await this.sessionStore.put(key, value)
      await this.sessionStore.flush()
    } catch (e) {
      console.error(`[StorageService] Save boolean error: ${e}`)
    }
  }

  async loadBoolean(key: string, defaultValue: boolean = false): Promise<boolean> {
    if (!this.sessionStore) return defaultValue

    try {
      return await this.sessionStore.get(key, defaultValue) as boolean
    } catch (e) {
      console.error(`[StorageService] Load boolean error: ${e}`)
      return defaultValue
    }
  }

  // MARK: - 会话状态存储

  async saveSessionStatuses(statuses: Map<string, string>): Promise<void> {
    if (!this.sessionStore) return

    try {
      const statusObj: Record<string, string> = {}
      statuses.forEach((value, key) => {
        statusObj[key] = value
      })
      const jsonString = JSON.stringify(statusObj)
      await this.sessionStore.put('session_statuses', jsonString)
      await this.sessionStore.flush()
      console.info(`[StorageService] Saved ${statuses.size} session statuses`)
    } catch (e) {
      console.error(`[StorageService] Save session statuses error: ${e}`)
    }
  }

  async loadSessionStatuses(): Promise<Map<string, string>> {
    const result: Map<string, string> = new Map()
    if (!this.sessionStore) return result

    try {
      const jsonString = await this.sessionStore.get('session_statuses', '{}') as string
      const statusObj: Record<string, string> = JSON.parse(jsonString)
      const keys = Object.keys(statusObj)
      for (let i = 0; i < keys.length; i++) {
        const key = keys[i]
        result.set(key, statusObj[key])
      }
      console.info(`[StorageService] Loaded ${result.size} session statuses`)
    } catch (e) {
      console.error(`[StorageService] Load session statuses error: ${e}`)
    }
    return result
  }

  // MARK: - 最近使用的工作目录

  async saveRecentWorkDirs(dirs: string[]): Promise<void> {
    if (!this.sessionStore) return

    try {
      const jsonString = JSON.stringify(dirs)
      await this.sessionStore.put('recent_work_dirs', jsonString)
      await this.sessionStore.flush()
      console.info(`[StorageService] Saved ${dirs.length} recent work dirs`)
    } catch (e) {
      console.error(`[StorageService] Save recent work dirs error: ${e}`)
    }
  }

  async loadRecentWorkDirs(): Promise<string[]> {
    if (!this.sessionStore) return []

    try {
      const jsonString = await this.sessionStore.get('recent_work_dirs', '[]') as string
      const dirs: string[] = JSON.parse(jsonString)
      console.info(`[StorageService] Loaded ${dirs.length} recent work dirs`)
      return dirs
    } catch (e) {
      console.error(`[StorageService] Load recent work dirs error: ${e}`)
      return []
    }
  }

  // 添加最近使用的工作目录
  async addRecentWorkDir(dir: string): Promise<void> {
    if (!dir || dir.trim() === '') return

    const dirs = await this.loadRecentWorkDirs()

    // 移除已存在的相同目录
    const filtered: string[] = []
    for (let i = 0; i < dirs.length; i++) {
      if (dirs[i] !== dir) {
        filtered.push(dirs[i])
      }
    }

    // 添加到开头，最多保留 10 个
    filtered.unshift(dir)
    const toSave = filtered.slice(0, 10)

    await this.saveRecentWorkDirs(toSave)
  }

  // MARK: - 清理

  async clearAll(): Promise<void> {
    if (this.sessionStore) {
      await this.sessionStore.clear()
      await this.sessionStore.flush()
    }

    if (this.messagesStore) {
      await this.messagesStore.clear()
      await this.messagesStore.flush()
    }

    console.info('[StorageService] Cleared all data')
  }
}

export const storageService = StorageService.getInstance()
