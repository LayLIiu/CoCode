/**
 * SessionStore 修复版 - 解决消息重复问题
 * 主要改进：
 * 1. 增强 messageContentKey 对 tool_use/tool_result 的处理
 * 2. 添加同步锁防止并发竞态
 * 3. 优化 WS 消息去重逻辑
 * 4. 改进 mergeMessages 的冲突解决
 */

// 将以下方法替换到 SessionStore.ets 中对应的方法

// ========== 1. 替换 messageContentKey 方法 ==========
/*
private messageContentKey(msg: Message): string {
  // 1. 有有效 ID 的消息直接用 ID（排除临时 ID）
  if (msg.id && 
      !msg.id.startsWith('stream-') && 
      !msg.id.startsWith('thinking-') && 
      !msg.id.startsWith('user-') &&
      !msg.id.startsWith('permission-') &&
      !msg.id.startsWith('question-') &&
      !msg.id.startsWith('err-') &&
      !msg.id.startsWith('sys-')) {
    return msg.type + ':id:' + msg.id
  }
  
  // 2. tool_use 消息：用 toolName + 稳定化的 toolInput 作为键
  // 这是关键修复：tool_use 的 content 为空，不能靠内容去重
  if (msg.type === 'tool_use' && msg.toolName) {
    const inputStr = msg.toolInput ? this.stableStringify(msg.toolInput) : ''
    // 加入 parentToolUseId 区分不同 Agent 调用的同名工具
    const parentId = msg.parentToolUseId ? ':parent:' + msg.parentToolUseId : ''
    return msg.type + ':tool:' + msg.toolName + ':' + inputStr.substring(0, 500) + parentId
  }
  
  // 3. tool_result 消息：关联到对应的 tool_use
  if (msg.type === 'tool_result' && msg.toolUseId) {
    return msg.type + ':result:' + msg.toolUseId
  }
  
  // 4. permission_request 用 requestId
  if (msg.type === 'permission_request' && msg.permissionId) {
    return msg.type + ':perm:' + msg.permissionId
  }
  
  // 5. question 用 questionId
  if (msg.type === 'question' && msg.questionId) {
    return msg.type + ':q:' + msg.questionId
  }
  
  // 6. 普通消息：用规整化内容 + 时间戳（防止完全不同消息被合并）
  const content = (msg.content || msg.toolResult || '').trim().replace(/\s+/g, ' ')
  const timePart = msg.timestamp ? ':' + msg.timestamp.substring(0, 16) : '' // 精确到分钟
  return msg.type + ':content:' + content.substring(0, 2000) + timePart
}
*/

// ========== 2. 添加同步锁（在类属性中添加） ==========
/*
private syncLocks: Map<string, boolean> = new Map()
*/

// ========== 3. 修改 syncMessagesFromServer 添加锁 ==========
/*
private async syncMessagesFromServer(sessionId: string): Promise<void> {
  // 并发保护：已有同步进行中则跳过
  if (this.syncingSessions.has(sessionId) || this.syncLocks.get(sessionId)) {
    console.info(`[SessionStore] syncMessagesFromServer: already syncing ${sessionId}, skip`)
    return
  }
  this.syncingSessions.add(sessionId)
  this.syncLocks.set(sessionId, true)
  
  try {
    const serverMessages = await apiService.getMessages(sessionId, 200)
    
    // 同步期间暂停 WS 消息处理，防止竞态
    const currentLocal = this.messages.get(sessionId) || []
    let merged = this.mergeMessages(currentLocal, serverMessages)
    
    // 检查 merge 期间是否有新 WS 消息（使用新的去重键）
    const afterMerge = this.messages.get(sessionId) || []
    if (afterMerge.length > currentLocal.length) {
      for (let i = currentLocal.length; i < afterMerge.length; i++) {
        const newMsg = afterMerge[i]
        const newKey = this.messageContentKey(newMsg)
        const exists = merged.some(m => this.messageContentKey(m) === newKey)
        if (!exists) {
          merged.push(newMsg)
        }
      }
      merged.sort((a, b) =>
        new Date(a.timestamp).getTime() - new Date(b.timestamp).getTime()
      )
    }
    
    // 最终去重（使用增强的 messageContentKey）
    const finalDeduped: Message[] = []
    const seenKeys = new Set<string>()
    for (const m of merged) {
      const key = this.messageContentKey(m)
      if (!seenKeys.has(key)) {
        seenKeys.add(key)
        finalDeduped.push(m)
      }
    }
    
    this.messages.set(sessionId, finalDeduped)
    this.notifyMessagesChanged(sessionId)
    
    // 保存到本地
    this.enqueueSave(sessionId, () => storageService.saveMessages(sessionId, finalDeduped))
  } catch (e) {
    console.error(`[SessionStore] Sync messages error: ${e}`)
  } finally {
    this.syncingSessions.delete(sessionId)
    this.syncLocks.set(sessionId, false)
  }
}
*/

// ========== 4. 修改 handleWSMessage 的去重逻辑 ==========
/*
// 在 handleWSMessage 开头，替换现有的 dedup 逻辑：

// 生成更精确的去重键
let dedupKey: string
if (msg.id && !msg.id.startsWith('tool-')) {
  dedupKey = sessionId + ':msg:' + msg.id + ':' + msg.type
} else if (msg.toolUseId) {
  // 必须包含 msg.type，防止 tool_use_complete 和 tool_result 互相去重
  dedupKey = sessionId + ':tool:' + msg.type + ':' + msg.toolUseId
} else if (msg.toolName) {
  // tool_use_complete 没有 toolUseId 时，用 toolName + input 摘要
  const inputSummary = msg.input ? JSON.stringify(msg.input).substring(0, 200) : ''
  dedupKey = sessionId + ':toolname:' + msg.type + ':' + msg.toolName + ':' + inputSummary
} else {
  const textPart = typeof msg.text === 'string' ? msg.text.substring(0, 200) : ''
  const contentPart = typeof msg.content === 'string' ? (msg.content as string).substring(0, 200) : ''
  dedupKey = sessionId + ':content:' + msg.type + ':' + textPart + ':' + contentPart
}

if (this.recentMessageIds.has(dedupKey)) {
  console.info(`[SessionStore] Dedup: skipping duplicate msg ${msg.id || '(no-id)'} (${msg.type})`)
  return
}
this.recentMessageIds.add(dedupKey)
setTimeout(() => {
  this.recentMessageIds.delete(dedupKey)
}, SessionStore.DEDUP_CACHE_TTL_MS)
*/

// ========== 5. 修改 flushHeadToTail 增强去重 ==========
/*
flushHeadToTail(sessionId: string): void {
  const head = this.streamHeads.get(sessionId)
  if (!head || head.length === 0) return

  const tail = this.messages.get(sessionId) || []
  let changed = false

  for (const headMsg of head) {
    headMsg.isStreaming = false
    
    // 使用增强的去重键检查
    const headKey = this.messageContentKey(headMsg)
    const headContentNorm = (headMsg.content || '').trim().replace(/\s+/g, ' ')
    
    let exists = false
    for (const tailMsg of tail) {
      // ID 匹配
      if (tailMsg.id === headMsg.id) {
        exists = true
        break
      }
      // 去重键匹配
      if (this.messageContentKey(tailMsg) === headKey) {
        exists = true
        break
      }
      // 内容匹配（针对 assistant/thinking 消息）
      if (tailMsg.type === headMsg.type && tailMsg.type !== 'tool_use') {
        const tailContentNorm = (tailMsg.content || '').trim().replace(/\s+/g, ' ')
        if (tailContentNorm === headContentNorm && tailContentNorm.length > 0) {
          exists = true
          break
        }
      }
    }
    
    if (!exists) {
      tail.push(headMsg)
      changed = true
    }
  }

  if (changed) {
    this.messages.set(sessionId, tail)
    this.enqueueSave(sessionId, () => storageService.saveMessages(sessionId, tail))
    this.notifyMessagesChanged(sessionId)
  }
  this.streamHeads.set(sessionId, [])
}
*/

// ========== 6. 修改 addMessage 增强去重 ==========
/*
addMessage(sessionId: string, message: Message): void {
  let sessionMessages = this.messages.get(sessionId)
  if (!sessionMessages) {
    sessionMessages = []
  }

  // 使用增强的去重键
  const newKey = this.messageContentKey(message)
  
  let exists = false
  for (const existing of sessionMessages) {
    // ID 匹配
    if (existing.id === message.id && message.id) {
      exists = true
      break
    }
    // 去重键匹配
    if (this.messageContentKey(existing) === newKey) {
      exists = true
      break
    }
  }

  if (!exists) {
    sessionMessages.push(message)
    this.messages.set(sessionId, sessionMessages)
    this.notifyMessagesChanged(sessionId)
    this.enqueueSave(sessionId, () => storageService.saveMessages(sessionId, sessionMessages || []))
  } else {
    console.info(`[SessionStore] addMessage: dedup skipped type=${message.type} key=${newKey.substring(0, 80)}`)
  }
}
*/

// ========== 7. ChatDetailPage 的 ForEach key 优化 ==========
/*
// 在 ChatDetailPage.ets 中，修改 ForEach 的 key 生成：

ForEach([...this.getVisibleMessages()].reverse(), (message: Message) => {
  // ... 渲染逻辑不变
}, (message: Message) => {
  // 生成稳定且唯一的 key
  if (message.toolUseId && message.type === 'tool_use') {
    return 'tool_' + message.toolUseId
  }
  if (message.toolUseId && message.type === 'tool_result') {
    return 'result_' + message.toolUseId
  }
  if (message.permissionId) {
    return 'perm_' + message.permissionId
  }
  if (message.questionId) {
    return 'q_' + message.questionId
  }
  if (message.id && !message.id.startsWith('stream-') && !message.id.startsWith('thinking-')) {
    return message.id
  }
  // 回退到内容摘要
  return message.type + '_' + (message.content || message.toolResult || '').substring(0, 30)
})
*/
