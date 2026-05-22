/**
 * 下载服务 — 保存文件到设备存储
 *
 * 支持：
 * - 下载文件到应用沙箱
 * - 图片保存到相册
 * - 下载进度回调
 */

import http from '@ohos.net.http'
import fileIo from '@ohos.file.fs'
import { util } from '@kit.ArkTS'
import { apiService } from './APIService'
import { DownloadTokenResponse } from './APIService'

export class DownloadProgress {
  percent: number = 0
  bytesWritten: number = 0
  totalBytes: number = 0
}

export class DownloadService {
  private static instance: DownloadService

  static getInstance(): DownloadService {
    if (!DownloadService.instance) {
      DownloadService.instance = new DownloadService()
    }
    return DownloadService.instance
  }

  /**
   * 下载文件到应用沙箱缓存目录
   * @param filePath 服务器端的文件路径
   * @param fileName 保存的文件名
   * @param onProgress 进度回调
   * @returns 保存后的本地路径
   */
  async downloadToSandbox(
    filePath: string,
    fileName: string,
    onProgress?: (progress: DownloadProgress) => void
  ): Promise<string> {
    // 1. 先获取 download token
    const tokenInfo = await apiService.requestDownloadToken(filePath)

    // 2. 下载文件到沙箱
    const context = getContext(this)
    const cacheDir = context.cacheDir
    const destPath = cacheDir + '/' + this.sanitizeFileName(fileName)

    const httpRequest = http.createHttp()
    try {
      const downloadUrl = apiService.getBaseUrl() + tokenInfo.downloadUrl
      console.info(`[DownloadService] Downloading: ${downloadUrl}`)

      // 使用 expectDataType: Uint8Array 获取二进制数据
      const response = await httpRequest.request(downloadUrl, {
        method: http.RequestMethod.GET,
        connectTimeout: 60000,
        readTimeout: 60000,
        expectDataType: http.HttpDataType.UINT8_ARRAY,
      })

      if (response.responseCode >= 200 && response.responseCode < 300) {
        const data = response.result as Uint8Array
        // 写入文件
        const file = fileIo.openSync(destPath, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY)
        fileIo.writeSync(file.fd, data)
        fileIo.closeSync(file)

        if (onProgress) {
          const p = new DownloadProgress()
          p.percent = 1.0
          p.bytesWritten = data.length
          p.totalBytes = data.length
          onProgress(p)
        }

        console.info(`[DownloadService] Saved to: ${destPath} (${data.length} bytes)`)
        return destPath
      } else {
        throw new Error(`Download failed: ${response.responseCode}`)
      }
    } catch (e) {
      console.error(`[DownloadService] Error: ${e}`)
      throw e
    } finally {
      httpRequest.destroy()
    }
  }

  /**
   * 下载图片并尝试保存到相册
   */
  async downloadImage(imageSrc: string, fileName: string): Promise<string> {
    // 如果已经是 base64 data URI，直接保存
    if (imageSrc.startsWith('data:')) {
      return this.saveBase64Image(imageSrc, fileName)
    }

    // 否则按路径下载
    return this.downloadToSandbox(imageSrc, fileName)
  }

  /**
   * 保存 base64 图片到缓存
   */
  private async saveBase64Image(dataUri: string, fileName: string): Promise<string> {
    const context = getContext(this)
    const cacheDir = context.cacheDir
    const destPath = cacheDir + '/' + this.sanitizeFileName(fileName)

    // 解析 base64
    const matches = dataUri.match(/^data:.*;base64,(.+)$/)
    if (!matches) throw new Error('Invalid data URI')

    const base64Str = matches[1]
    // ArkTS 的 base64 解码
    const buffer = new Uint8Array(base64Str.length)
    // 使用内置 base64 解码
    const helper = new util.Base64Helper()
    const decoded = helper.decodeSync(base64Str)

    const file = fileIo.openSync(destPath, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY)
    fileIo.writeSync(file.fd, decoded)
    fileIo.closeSync(file)

    console.info(`[DownloadService] Saved base64 image to: ${destPath}`)
    return destPath
  }

  /**
   * 过滤文件名中的非法字符
   */
  private sanitizeFileName(name: string): string {
    return name.replace(/[\\/:*?"<>|]/g, '_').replace(/\s+/g, '_')
  }
}

export const downloadService = DownloadService.getInstance()