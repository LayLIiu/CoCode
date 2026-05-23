/**
 * SessionStore 关键修复补丁
 * 
 * 问题：消息重复显示
 * 原因：messageContentKey 对 tool_use 消息处理不完善，导致不同消息被误判为重复
 * 
 * 修复内容：
 * 1. 增强 messageContentKey 方法
 * 2. 修复 getDedupedMessages 的逻辑错误
 * 3. 优化 WS 消息去重
 */

// ============================================
// 修复 1：替换 messageContentKey 方法（第 994 行）
// ============================================

// 原代码：
/*
  private messageContentKey(msg: Message): string {
    if (msg.toolUseId) {
      return msg.type + ':toolUseId:' + msg.toolUseId
    }
    const content = (msg.content || '') || (msg.toolResult || '')
    const normalized = content.trim().replace(/\s+/g, ' ')
    return msg.type + ':' + normalized.substring(0, 2000)
  }
*/

// 修复后的代码：
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
    // 关键修复：tool_use 的 content 为空，不能靠内容去重
    if (msg.type === 'tool_use' && msg.toolName) {
      const inputStr = msg.toolInput ? this.stableStringify(msg.toolInput) : ''
      const parentId = msg.parentToolUseId ? ':parent:' + msg.parentToolUseId : ''
      return msg.type + ':tool:' + msg.toolName + ':' + inputStr.substring(0, 500) + parentId
    }
    
    // 3. tool_result 消息：关联到对应的 tool_use
    if (msg.type === 'tool_result' && msg.toolUseId) {
      return msg.type + ':result:' + msg.toolUseId
    }
    
    // 4. permission_request 用 permissionId
    if (msg.type === 'permission_request' && msg.permissionId) {
      return msg.type + ':perm:' + msg.permissionId
    }
    
    // 5. question 用 questionId
    if (msg.type === 'question' && msg.questionId) {
      return msg.type + ':q:' + msg.questionId
    }
    
    // 6. 普通消息：用规整化内容
    const content = (msg.content || msg.toolResult || '').trim().replace(/\s+/g, ' ')
    return msg.type + ':content:' + content.substring(0, 2000)
  }
*/

// ============================================
// 修复 2：修复 getDedupedMessages 方法（第 1105 行）
// ============================================

// 原代码问题：
// 1. 第一道去重后，如果 dupCount === 0，不会执行第二道去重
// 2. tool_use 消息永远不会被第一道去重命中（因为 key 包含 toolUseId）
// 3. 第二道去重的逻辑有 bug：result 数组和 normResult 数组混用

// 修复后的代码：
/*
  getDedupedMessages(sessionId: string): Message[] {
    const tail = this.messages.get(sessionId) || []
    if (tail.length < 2) return tail
    
    const result: Message[] = []
    const seen = new Set<string>()
    let dupCount = 0
    
    for (let i = 0; i < tail.length; i++) {
      const key = this.messageContentKey(tail[i])
      if (seen.has(key)) {
        dupCount++
        console.info(`[SessionStore] getDedupedMessages #${dupCount}: skip type=${tail[i].type} id=${tail[i].id} key=${key.substring(0, 80)}`)
        continue
      }
      seen.add(key)
      result.push(tail[i])
    }
    
    // 第二道去重：用规整化内容去重（处理流式 vs 服务端格式差异）
    const normalizedSeen = new Set<string>()
    const finalResult: Message[] = []
    let normDupCount = 0
    
    for (let i = 0; i < result.length; i++) {
      const msg = result[i]
      let normKey: string
      
      if (msg.type === 'tool_use' && msg.toolName) {
        // tool_use 用 type + toolName + toolInput 去重
        const inputStr = msg.toolInput ? this.stableStringify(msg.toolInput) : ''
        normKey = msg.type + ':tool:' + msg.toolName + ':' + inputStr.substring(0, 500)
      } else {
        // 其他消息用规整化内容
        const normContent = ((msg.content || '') || (msg.toolResult || '')).trim().replace(/\s+/g, ' ')
        normKey = msg.type + ':content:' + normContent.substring(0, 2000)
      }
      
      if (normalizedSeen.has(normKey)) {
        normDupCount++
        console.info(`[SessionStore] getDedupedMessages normDup #${normDupCount}: skip type=${msg.type} id=${msg.id}`)
        continue
      }
      normalizedSeen.add(normKey)
      finalResult.push(msg)
    }
    
    const totalRemoved = dupCount + normDupCount
    if (totalRemoved > 0) {
      console.info(`[SessionStore] getDedupedMessages: removed ${totalRemoved} dups from ${tail.length} msgs for ${sessionId}`)
    }
    
    return finalResult
  }
*/

// ============================================
// 修复 3：优化 handleWSMessage 的去重逻辑（第 1411 行）
// ============================================

// 修复后的去重键生成：
/*
    let dedupKey: string
    if (msg.id && !msg.id.startsWith('tool-')) {
      dedupKey = sessionId + ':msg:' + msg.id + ':' + msg.type
    } else if (msg.toolUseId) {
      dedupKey = sessionId + ':tool:' + msg.type + ':' + msg.toolUseId
    } else if (msg.toolName) {
      const inputSummary = msg.input ? JSON.stringify(msg.input).substring(0, 200) : ''
      dedupKey = sessionId + ':toolname:' + msg.type + ':' + msg.toolName + ':' + inputSummary
    } else {
      const textPart = typeof msg.text === 'string' ? msg.text.substring(0, 200) : ''
      const contentPart = typeof msg.content === 'string' ? (msg.content as string).substring(0, 200) : ''
      dedupKey = sessionId + ':content:' + msg.type + ':' + textPart + ':' + contentPart
    }
*/

// ============================================
// 修复 4：优化 ChatDetailPage 的 ForEach key（ChatDetailPage.ets）
// ============================================

// 在 ChatDetailPage.ets 中，找到 ForEach 的 key 生成部分，替换为：
/*
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
  return message.type + '_' + (message.content || message.toolResult || '').substring(0, 30)
})
*/
