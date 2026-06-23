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
  cloudRelay: string | null
  e2eePub: string | null   // E2EE 桌面端公钥（云中继端到端加密用）
  h5Token: string | null   // cchaha H5 远程访问 token
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

/** 从查询字符串中提取指定参数的值（URL 编码安全） */
function getQueryParam(query: string, name: string): string | null {
  const pairs = query.split('&')
  for (let i = 0; i < pairs.length; i++) {
    const pair = pairs[i]
    const eqIndex = pair.indexOf('=')
    if (eqIndex < 0) continue
    const key = pair.substring(0, eqIndex)
    if (key === name) {
      const val = pair.substring(eqIndex + 1)
      return decodeURIComponent(val)
    }
  }
  return null
}

/** 解析二维码文本内容为标准地址格式 */
function parseQRContent(raw: string): ScannedAddresses | null {
  const normalize = (url: string | null): string | null => {
    if (!url) return null
    if (url.startsWith('http://') || url.startsWith('https://')) return url
    return 'http://' + url
  }

  // 优先尝试解析 cchaha 桌面端 H5 二维码格式:
  // http://host:port/?serverUrl=http://host:port&h5Token=h5_xxx
  // 或 http://host:port/?h5Token=h5_xxx (无 serverUrl 参数，直接用 host 作为地址)
  if (raw.startsWith('http://') || raw.startsWith('https://')) {
    const queryIndex = raw.indexOf('?')
    if (queryIndex >= 0) {
      const queryString = raw.substring(queryIndex + 1)
      const hostPart = raw.substring(0, queryIndex)
      // 手动解析查询参数（ArkTS 不支持 URL 构造函数）
      const h5Token = getQueryParam(queryString, 'h5Token') || getQueryParam(queryString, 'h5_token')
      if (h5Token) {
        const serverUrlParam = getQueryParam(queryString, 'serverUrl')
        const serverUrl = serverUrlParam || hostPart
        const normalized = normalize(serverUrl)
        return {
          bestUrl: normalized,
          lan: normalized,
          pgy: null,
          tunnel: null,
          cloudRelay: null,
          e2eePub: null,
          h5Token: h5Token
        }
      }
    }
  }

  try {
    const data = JSON.parse(raw) as Record<string, string>
    if (typeof data !== 'object' || data === null) {
      // 不是 JSON，直接当文本 URL 使用
      const url = normalize(raw)
      return { bestUrl: url, lan: null, pgy: null, tunnel: null, cloudRelay: null, e2eePub: null, h5Token: null }
    }

    const lan = normalize(typeof data.lan === 'string' ? data.lan : null)
    const pgy = normalize(typeof data.pgy === 'string' ? data.pgy : null)
    const tunnel = normalize(typeof data.tunnel === 'string' ? data.tunnel : null)
    const cloudRelay = normalize(typeof data.cloud_relay === 'string' ? data.cloud_relay : null)
    const e2eePub = typeof data.e2ee_pub === 'string' ? data.e2ee_pub : null
    const h5Token = typeof data.h5_token === 'string' ? data.h5_token : (typeof data.h5Token === 'string' ? data.h5Token : null)
    const bestUrl = tunnel || pgy || lan || cloudRelay

    return { bestUrl, lan, pgy, tunnel, cloudRelay, e2eePub, h5Token }
  } catch (_) {
    // 不是 JSON，直接当文本 URL 使用
    const url = normalize(raw)
    return { bestUrl: url, lan: null, pgy: null, tunnel: null, cloudRelay: null, e2eePub: null, h5Token: null }
  }
}