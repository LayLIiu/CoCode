/**
 * E2EE 加密传输层 (手机端)
 *
 * 基于 @ohos.security.cryptoFramework：
 *   - X25519 ECDH 密钥交换
 *   - AES-256-GCM 对称加密
 *
 * 与桌面端 (tweetnacl + Web Crypto API) 互通。
 *
 * 密文格式: base64(12字节 IV + AES-GCM 加密数据 + 认证标签)
 */

import { cryptoFramework } from '@kit.CryptoKit'
import { util } from '@kit.ArkTS'

const base64 = new util.Base64Helper()
const textEncoder = new util.TextEncoder()
const textDecoder = new util.TextDecoder('utf-8', { ignoreBOM: true })

// ── 工具 ──────────────────────────────────────────────

/** Uint8Array → base64 字符串 */
function uint8ArrayToB64(arr: Uint8Array): string {
  return base64.encodeToStringSync(arr)
}

/** base64 字符串 → Uint8Array */
function b64ToUint8Array(b64: string): Uint8Array {
  return base64.decodeSync(b64)
}

/** 字符串 → UTF-8 bytes */
function strToBytes(str: string): Uint8Array {
  return textEncoder.encodeInto(str)
}

/** UTF-8 bytes → 字符串 */
function bytesToStr(bytes: Uint8Array): string {
  const ret = textDecoder.decodeWithStream(bytes, { off: 0, len: bytes.length })
  return ret
}

/** X25519 原始 32 字节公钥 → SPKI DER 编码 */
function rawPubKeyToSPKI(rawKey: Uint8Array): Uint8Array {
  if (rawKey.length !== 32) {
    throw new Error(`X25519 公钥长度必须为 32 字节, 实际 ${rawKey.length}`)
  }
  // SPKI for X25519: SEQUENCE { SEQUENCE { OID 1.3.101.110 }, BIT STRING (32 bytes) }
  // 30 2A 30 05 06 03 2B 65 6E 03 21 00 <32 bytes>
  const spki = new Uint8Array(12 + 32)
  spki[0] = 0x30
  spki[1] = 42      // SEQUENCE length
  spki[2] = 0x30
  spki[3] = 5       // inner SEQUENCE length
  spki[4] = 0x06
  spki[5] = 3       // OID length
  spki[6] = 0x2B    // 1.3.101.110
  spki[7] = 0x65
  spki[8] = 0x6E
  spki[9] = 0x03
  spki[10] = 33     // BIT STRING length (1 byte padding + 32 bytes)
  spki[11] = 0x00   // no unused bits
  spki.set(rawKey, 12)
  return spki
}

// ── 密钥对 ────────────────────────────────────────────

export interface E2EEKeyPair {
  publicKey: string  // base64 编码的原始 32 字节公钥
  secretKey: string  // base64 编码的 PKCS#8 私钥
}

/** 生成 X25519 密钥对 */
export async function generateKeyPair(): Promise<E2EEKeyPair> {
  const generator = cryptoFramework.createAsyKeyGenerator('X25519')
  const keyPair = await generator.generateKeyPair()

  const pubKeyBlob = keyPair.pubKey.getEncoded()
  const priKeyBlob = keyPair.priKey.getEncoded()

  return {
    publicKey: uint8ArrayToB64(pubKeyBlob.data),
    secretKey: uint8ArrayToB64(priKeyBlob.data),
  }
}

/** 从 base64 原始公钥重建 PubKey 对象 */
async function importRawPubKey(rawB64: string): Promise<cryptoFramework.PubKey> {
  const rawKey = b64ToUint8Array(rawB64)
  const spki = rawPubKeyToSPKI(rawKey)

  // 先用 'X25519' 创建生成器备用，纯转换用
  const generator = cryptoFramework.createAsyKeyGenerator('X25519')
  const keyPair = await generator.convertKey({ data: spki }, null)
  return keyPair.pubKey
}

// ── 共享密钥派生 ──────────────────────────────────────

/** 用 ECDH (X25519) + SHA-256 导出 AES-256-GCM 密钥材料 */
export async function deriveSharedKey(
  theirPublicKeyB64: string,
  ourSecretKeyB64: string,
): Promise<string> {
  const generator = cryptoFramework.createAsyKeyGenerator('X25519')
  const ourSecretEncoded = b64ToUint8Array(ourSecretKeyB64)
  const ourKeyPair = await generator.convertKey(null, { data: ourSecretEncoded })
  const theirPub = await importRawPubKey(theirPublicKeyB64)

  const keyAgreement = cryptoFramework.createKeyAgreement('X25519')
  const sharedSecret = await keyAgreement.generateSecret(ourKeyPair.priKey, theirPub)

  // SHA-256 散列得到 AES-256 密钥材料
  const md = cryptoFramework.createHash('SHA256')
  await md.update({ data: sharedSecret.data })
  const hash = await md.digest()

  return uint8ArrayToB64(hash.data)
}

// ── 加密 / 解密 ───────────────────────────────────────

const IV_LENGTH = 12
const TAG_LENGTH = 16 // AES-GCM 128-bit 认证标签

/** 使用 AES-256-GCM 加密，返回 base64(IV + 密文 + 认证标签) */
export async function encrypt(
  plaintext: string,
  sharedKeyB64: string,
): Promise<string> {
  const keyBytes = b64ToUint8Array(sharedKeyB64)

  // 生成随机 IV (12 字节)
  const rand = cryptoFramework.createRandom()
  const randData = await rand.generateRandom(IV_LENGTH)
  const ivBytes = randData.data

  // 创建 AES 密钥
  const symKeyGenerator = cryptoFramework.createSymKeyGenerator('AES256')
  const symKey = await symKeyGenerator.convertKey({ data: keyBytes })

  // 创建加密器
  const cipher = cryptoFramework.createCipher('AES256|GCM|PKCS7')
  await cipher.init(
    cryptoFramework.CryptoMode.ENCRYPT_MODE,
    symKey,
    {
      iv: { data: ivBytes },
      aad: { data: new Uint8Array(0) },
      tagLen: TAG_LENGTH,
    },
  )

  // 加密
  const plainBytes = strToBytes(plaintext)
  const encResult = await cipher.doFinal({ data: plainBytes })
  const authTag = cipher.getAuthTag()

  // 组合: IV + 密文 + 认证标签
  const combined = new Uint8Array(IV_LENGTH + encResult.data.length + authTag.data.length)
  combined.set(ivBytes)
  combined.set(encResult.data, IV_LENGTH)
  combined.set(authTag.data, IV_LENGTH + encResult.data.length)

  return uint8ArrayToB64(combined)
}

/** 解密 base64(IV + 密文 + 认证标签) → 原文 */
export async function decrypt(
  ciphertextB64: string,
  sharedKeyB64: string,
): Promise<string> {
  const combined = b64ToUint8Array(ciphertextB64)
  const keyBytes = b64ToUint8Array(sharedKeyB64)

  // 分解: IV (12) + 密文 + 认证标签 (16)
  const iv = combined.slice(0, IV_LENGTH)
  const ciphertext = combined.slice(IV_LENGTH, combined.length - TAG_LENGTH)
  const tag = combined.slice(combined.length - TAG_LENGTH)

  // 创建 AES 密钥
  const symKeyGenerator = cryptoFramework.createSymKeyGenerator('AES256')
  const symKey = await symKeyGenerator.convertKey({ data: keyBytes })

  // 创建解密器
  const cipher = cryptoFramework.createCipher('AES256|GCM|PKCS7')
  await cipher.init(
    cryptoFramework.CryptoMode.DECRYPT_MODE,
    symKey,
    {
      iv: { data: iv },
      aad: { data: new Uint8Array(0) },
      tagLen: TAG_LENGTH,
    },
  )

  // 设置认证标签
  cipher.setAuthTag({ data: tag })

  // 解密
  const decResult = await cipher.doFinal({ data: ciphertext })
  return bytesToStr(decResult.data)
}

// ── 会话密钥管理 ──────────────────────────────────────

/**
 * 每个 WS 隧道的 E2EE 会话状态
 * 用于在手机端 WebSocket 连接中追踪 E2EE 握手
 */
export interface E2EESessionState {
  /** 手机端自己的密钥对 */
  localKeyPair: E2EEKeyPair | null
  /** 桌面端 E2EE 公钥（从 QR 码获取） */
  desktopPubKey: string | null
  /** 派生出的共享 AES 密钥 (base64) */
  sharedKey: string | null
  /** 握手状态 */
  handshakeStatus: 'idle' | 'waiting_ack' | 'established' | 'failed'
}

/** 创建 E2EE 会话（手机端发起） */
export async function startE2EESession(
  desktopPubKey: string,
): Promise<E2EESessionState> {
  const keyPair = await generateKeyPair()
  return {
    localKeyPair: keyPair,
    desktopPubKey,
    sharedKey: null,
    handshakeStatus: 'idle',
  }
}

/**
 * 构建 E2EE 握手消息（手机端 -> 桌面端）
 * 返回 JSON 字符串，应作为 WS tunnel 的第一条消息发送
 */
export function buildHandshakeMessage(state: E2EESessionState): string {
  if (!state.localKeyPair) return ''
  return JSON.stringify({
    type: 'e2ee_key_exchange',
    publicKey: state.localKeyPair.publicKey,
  })
}

/**
 * 收到桌面端 ACK 后，完成握手，派生共享密钥
 */
export async function completeHandshake(state: E2EESessionState): Promise<E2EESessionState> {
  if (!state.localKeyPair || !state.desktopPubKey) {
    throw new Error('E2EE: 缺少密钥对或桌面端公钥')
  }
  const sharedKey = await deriveSharedKey(
    state.desktopPubKey,
    state.localKeyPair.secretKey,
  )
  return {
    ...state,
    sharedKey,
    handshakeStatus: 'established',
  }
}

/**
 * 使用会话密钥加密消息
 */
export async function encryptMessage(
  plaintext: string,
  state: E2EESessionState,
): Promise<string> {
  if (!state.sharedKey) {
    throw new Error('E2EE: 会话密钥未就绪')
  }
  return encrypt(plaintext, state.sharedKey)
}

/**
 * 使用会话密钥解密消息
 */
export async function decryptMessage(
  ciphertextB64: string,
  state: E2EESessionState,
): Promise<string> {
  if (!state.sharedKey) {
    throw new Error('E2EE: 会话密钥未就绪')
  }
  return decrypt(ciphertextB64, state.sharedKey)
}