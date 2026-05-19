/**
 * 扫码服务
 *
 * 使用 @kit.ScanKit（HMS Scan Kit）打开系统扫码界面，直接解析二维码
 * 二维码格式: {"v":1,"lan":"192.168.1.100:3456","pgy":"172.16.0.1:3456","tunnel":"https://xxx.trycloudflare.com"}
 */

import { BusinessError } from '@kit.BasicServicesKit'
import { common } from '@kit.AbilityKit'
import { scanBarcode, scanCore } from '@kit.ScanKit'

export interface ScannedAddresses {
  bestUrl: string | null
  lan: string | null
  pgy: string | null
  tunnel: string | null
}

let abilityContext: common.UIAbilityContext | null = null

/** 在 EntryAbility.onCreate 中调用，注入 UIAbilityContext */
export function initScanService(context: common.UIAbilityContext): void {
  abilityContext = context
}

/** 打开系统扫码界面，扫码并解析二维码内容 */
export async function openScanner(): Promise<ScannedAddresses | null> {
  if (!abilityContext) {
    console.error('[Scan] abilityContext not set, call initScanService first')
    return null
  }

  try {
    // 使用 HMS Scan Kit 打开系统扫码界面，限制只扫 QR 码
    const result = await scanBarcode.startScanForResult(
      abilityContext,
      {
        scanTypes: [scanCore.ScanType.QR_CODE],
        enableAlbum: false
      }
    )

    if (!result || !result.originalValue) {
      console.info('[Scan] no result from scanner')
      return null
    }

    console.info(`[Scan] decoded: ${result.originalValue}`)
    return parseQRContent(result.originalValue)
  } catch (e) {
    const err = e as BusinessError
    if (err.code === 1000500002) {
      console.info('[Scan] user cancelled scanning')
    } else if (err.code === 201) {
      console.info('[Scan] camera permission denied')
    } else {
      console.error(`[Scan] error: ${err.code} ${err.message}`)
    }
    return null
  }
}

/** 解析二维码文本内容为标准地址格式 */
function parseQRContent(raw: string): ScannedAddresses | null {
  const normalize = (url: string | null): string | null => {
    if (!url) return null
    if (url.startsWith('http://') || url.startsWith('https://')) return url
    return 'http://' + url
  }

  try {
    const data = JSON.parse(raw) as Record<string, string>
    if (typeof data !== 'object' || data === null) {
      // 不是 JSON，直接当文本 URL 使用
      const url = normalize(raw)
      return { bestUrl: url, lan: null, pgy: null, tunnel: null }
    }

    const lan = normalize(typeof data.lan === 'string' ? data.lan : null)
    const pgy = normalize(typeof data.pgy === 'string' ? data.pgy : null)
    const tunnel = normalize(typeof data.tunnel === 'string' ? data.tunnel : null)
    const bestUrl = tunnel || pgy || lan

    return { bestUrl, lan, pgy, tunnel }
  } catch (_) {
    // 不是 JSON，直接当文本 URL 使用
    const url = normalize(raw)
    return { bestUrl: url, lan: null, pgy: null, tunnel: null }
  }
}