/**
 * 文件服务 — 处理从服务端获取文件、图片渲染、文件下载
 */

import { apiService } from './APIService'

// 文件类型信息
export class FileInfo {
  path: string = ''
  name: string = ''
  ext: string = ''
  mimeType: string = ''
  isImage: boolean = false
  isSvg: boolean = false
  isCode: boolean = false
  size: number = 0
  sizeLabel: string = ''
}

// 已知图片扩展名
const IMAGE_EXTS = new Set(['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'svg'])
// 已知代码/文本扩展名
const CODE_EXTS = new Set([
  'ts', 'tsx', 'js', 'jsx', 'json', 'py', 'rs', 'go', 'java', 'kt', 'swift',
  'css', 'scss', 'html', 'xml', 'yaml', 'yml', 'toml', 'md', 'txt', 'sh',
  'bash', 'zsh', 'c', 'cpp', 'h', 'hpp', 'sql', 'rb', 'php', 'pl', 'lua',
  'dart', 'vue', 'svelte', 'zig', 'nim', 'ex', 'exs'
])

function getExt(path: string): string {
  const parts = path.split('/')
  const name = parts[parts.length - 1] || ''
  const dot = name.lastIndexOf('.')
  return dot >= 0 ? name.substring(dot + 1).toLowerCase() : ''
}

function getFileName(path: string): string {
  const parts = path.split('/')
  return parts[parts.length - 1] || path
}

function formatSize(bytes: number): string {
  if (bytes <= 0) return ''
  if (bytes < 1024) return bytes + ' B'
  if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + ' KB'
  return (bytes / (1024 * 1024)).toFixed(1) + ' MB'
}

export class FileService {
  private static instance: FileService
  // 缓存已获取的文件内容 key=path, value=base64
  private imageCache: Map<string, string> = new Map()
  private textCache: Map<string, string> = new Map()

  static getInstance(): FileService {
    if (!FileService.instance) {
      FileService.instance = new FileService()
    }
    return FileService.instance
  }

  /**
   * 分析文件路径，返回文件类型信息
   */
  analyzeFilePath(path: string): FileInfo {
    const info = new FileInfo()
    info.path = path
    info.name = getFileName(path)
    info.ext = getExt(path)
    info.isImage = IMAGE_EXTS.has(info.ext)
    info.isSvg = info.ext === 'svg'
    info.isCode = CODE_EXTS.has(info.ext)

    const mimeMap: Record<string, string> = {
      'png': 'image/png', 'jpg': 'image/jpeg', 'jpeg': 'image/jpeg',
      'gif': 'image/gif', 'svg': 'image/svg+xml', 'webp': 'image/webp',
      'bmp': 'image/bmp', 'pdf': 'application/pdf'
    }
    info.mimeType = mimeMap[info.ext] || 'text/plain'
    return info
  }

  /**
   * 判断文件路径是否为远程 URL（http/https 开头）
   */
  isRemoteUrl(path: string): boolean {
    return path.startsWith('http://') || path.startsWith('https://')
  }

  /**
   * 判断路径是否为本地文件路径
   */
  isLocalPath(path: string): boolean {
    return !this.isRemoteUrl(path) && path.length > 0
  }

  /**
   * 获取图片的 base64 数据
   * 优先从缓存获取，缓存未命中则从服务端拉取
   */
  async fetchImageBase64(filePath: string): Promise<string> {
    if (this.isRemoteUrl(filePath)) {
      return filePath // 远程 URL 直接返回
    }

    // 检查缓存
    const cached = this.imageCache.get(filePath)
    if (cached) return cached

    // 从服务端拉取
    const ext = getExt(filePath)
    try {
      const content = await apiService.downloadFileAsBase64(filePath)
      const mime = ext === 'svg' ? 'image/svg+xml' : `image/${ext}`
      let dataUrl = content

      // 如果是文本内容（SVG 等），转为 data URI
      if (ext === 'svg' && !content.startsWith('data:')) {
        const encoded = encodeURIComponent(content)
        dataUrl = `data:image/svg+xml;charset=utf-8,${encoded}`
      } else if (!content.startsWith('data:')) {
        // 假设是纯 base64 数据
        dataUrl = `data:${mime};base64,${content}`
      }

      this.imageCache.set(filePath, dataUrl)
      return dataUrl
    } catch (e) {
      console.error(`[FileService] fetchImage failed: ${filePath}`, e)
      return ''
    }
  }

  /**
   * 获取文件的文本内容
   */
  async fetchTextContent(filePath: string): Promise<string> {
    const cached = this.textCache.get(filePath)
    if (cached) return cached

    try {
      const content = await apiService.readFileText(filePath)
      this.textCache.set(filePath, content)
      return content
    } catch (e) {
      console.error(`[FileService] fetchText failed: ${filePath}`, e)
      return ''
    }
  }

  /**
   * 清理文件缓存
   */
  clearCache(): void {
    this.imageCache.clear()
    this.textCache.clear()
  }

  /**
   * 获取代码文件的语言标识（用于语法高亮）
   */
  getCodeLanguage(ext: string): string {
    const langMap: Record<string, string> = {
      'ts': 'typescript', 'tsx': 'tsx', 'js': 'javascript', 'jsx': 'jsx',
      'py': 'python', 'rs': 'rust', 'go': 'go', 'java': 'java',
      'kt': 'kotlin', 'swift': 'swift', 'css': 'css', 'html': 'html',
      'json': 'json', 'xml': 'xml', 'yaml': 'yaml', 'yml': 'yaml',
      'md': 'markdown', 'sh': 'bash', 'bash': 'bash',
      'c': 'c', 'cpp': 'cpp', 'sql': 'sql', 'rb': 'ruby', 'php': 'php',
      'dart': 'dart', 'vue': 'vue', 'svelte': 'svelte'
    }
    return langMap[ext] || ''
  }
}

export const fileService = FileService.getInstance()