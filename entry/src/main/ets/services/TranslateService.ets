/**
 * 翻译服务
 * 使用 HTTP 调用免费翻译 API 获取真实翻译文本
 * 如果网络请求失败，回退到复制到剪贴板
 */

import { http } from '@kit.NetworkKit'
import { BusinessError } from '@kit.BasicServicesKit'

export interface TranslateResult {
  success: boolean
  text?: string
  error?: string
}

class TranslateService {
  private static instance: TranslateService

  static getInstance(): TranslateService {
    if (!TranslateService.instance) {
      TranslateService.instance = new TranslateService()
    }
    return TranslateService.instance
  }

  /**
   * 翻译文本 - 使用免费在线翻译 API
   * 返回翻译结果文本
   */
  async translate(text: string): Promise<TranslateResult> {
    if (!text || text.trim() === '') {
      return { success: false, error: '无内容可翻译' }
    }

    const trimmed = text.trim().substring(0, 2000) // 限制长度

    try {
      const httpRequest = http.createHttp()

      // 使用 MyMemory 免费翻译 API（无需 API key，有每日限额但足够个人使用）
      const url = 'https://api.mymemory.translated.net/get?q=' +
        encodeURIComponent(trimmed) +
        '&langpair=en%7Czh-CN'

      const response = await httpRequest.request(url, {
        method: http.RequestMethod.GET,
        header: {
          'User-Agent': 'CC-Haha/1.0',
          'Accept': 'application/json'
        },
        expectDataType: http.HttpDataType.OBJECT,
        connectTimeout: 10000,
        readTimeout: 10000
      })

      httpRequest.destroy()

      if (response.responseCode === 200 && response.result) {
        const data = response.result as Record<string, Object>
        const responseData = data['responseData'] as Record<string, Object> | undefined
        if (responseData) {
          const translatedText = responseData['translatedText'] as string
          if (translatedText && translatedText.trim()) {
            return { success: true, text: translatedText }
          }
        }
      }

      // API 请求成功但解析失败，返回错误
      return { success: false, error: '翻译解析失败' }
    } catch (e) {
      const err = e as BusinessError
      console.error(`[TranslateService] HTTP request failed: ${err.code} ${err.message}`)

      // 尝试使用 MyMemory 备用接口
      try {
        return await this.tryBackendApi(trimmed)
      } catch (_) {
        return { success: false, error: '翻译服务不可用，内容已复制到剪贴板' }
      }
    }
  }

  /**
   * 备用翻译接口 - 使用 LibreTranslate 公开实例
   */
  private async tryBackendApi(text: string): Promise<TranslateResult> {
    const httpRequest = http.createHttp()

    const response = await httpRequest.request(
      'https://libretranslate.com/translate',
      {
        method: http.RequestMethod.POST,
        extraData: JSON.stringify({
          q: text,
          source: 'en',
          target: 'zh',
          format: 'text'
        }),
        header: {
          'Content-Type': 'application/json',
          'User-Agent': 'CC-Haha/1.0'
        },
        expectDataType: http.HttpDataType.OBJECT,
        connectTimeout: 8000,
        readTimeout: 8000
      }
    )

    httpRequest.destroy()

    if (response.responseCode === 200 && response.result) {
      const data = response.result as Record<string, Object>
      const translatedText = data['translatedText'] as string
      if (translatedText && translatedText.trim()) {
        return { success: true, text: translatedText }
      }
    }

    return { success: false, error: '翻译服务不可用' }
  }
}

export const translateService = TranslateService.getInstance()