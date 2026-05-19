/**
 * URL 工具类
 * 统一的 URL 规范化逻辑
 */

export class UrlUtils {
  /**
   * 规范化 URL，处理协议、host:port:token 格式等
   */
  static normalizeUrl(url: string): string {
    if (!url) return url

    let processed = url.trim()
    let isSecure = false

    // 移除协议前缀
    if (processed.startsWith('https://')) {
      isSecure = true
      processed = processed.substring(8)
    } else if (processed.startsWith('http://')) {
      processed = processed.substring(7)
    }

    // IPv6 地址（带括号）直接返回原始 URL
    if (processed.startsWith('[')) {
      return (isSecure ? 'https://' : 'http://') + processed
    }

    // 处理 host:port:token 格式（仅对非 IPv6 URL）
    const colonCount = UrlUtils.countChar(processed, ':')
    if (colonCount >= 2) {
      const parts = processed.split(':')
      if (parts.length >= 2) {
        const host = parts[0]
        const port = parts[1]
        const isTunnel = host.includes('.tunnel.') ||
          host.includes('trycloudflare') ||
          host.includes('loca.lt')
        processed = isTunnel ? `https://${host}:${port}` : `http://${host}:${port}`
        return processed
      }
    }

    // 判断是否需要 HTTPS
    const isTunnel = processed.includes('.tunnel.') ||
      processed.includes('trycloudflare') ||
      processed.includes('loca.lt')

    if (isSecure || isTunnel) {
      processed = 'https://' + processed
    } else {
      processed = 'http://' + processed
    }

    return processed
  }

  static countChar(str: string, char: string): number {
    let count = 0
    for (let i = 0; i < str.length; i++) {
      if (str[i] === char) {
        count++
      }
    }
    return count
  }
}
