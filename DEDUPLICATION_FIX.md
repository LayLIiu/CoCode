# 消息去重问题修复指南

## 问题描述

聊天界面出现重复消息，主要原因：
1. WebSocket 双通道（会话 WS + 全局广播）推送重复消息
2. 本地缓存与服务器同步时数据冲突
3. 流式消息 Head/Tail 缓冲机制导致重复
4. 用户消息回声（本地添加 + WS 推送）

## 修复步骤

### 步骤 1：替换 `messageContentKey` 方法

**文件**：`entry/src/main/ets/stores/SessionStore.ets`

找到 `messageContentKey` 方法，替换为：

```typescript
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
  const timePart = msg.timestamp ? ':' + msg.timestamp.substring(0, 16) : ''
  return msg.type + ':content:' + content.substring(0, 2000) + timePart
}
```

### 步骤 2：添加同步锁属性

在 `SessionStore` 类属性中添加：

```typescript
private syncLocks: Map<string, boolean> = new Map()
```

### 步骤 3：修改 `syncMessagesFromServer` 方法

替换为带锁的版本：

```typescript
private async syncMessagesFromServer(sessionId: string): Promise<void> {
  if (this.syncingSessions.has(sessionId) || this.syncLocks.get(sessionId)) {
    console.info(`[SessionStore] syncMessagesFromServer: already syncing ${sessionId}, skip`)
    return
  }
  this.syncingSessions.add(sessionId)
  this.syncLocks.set(sessionId, true)
  
  try {
    const serverMessages = await apiService.getMessages(sessionId, 200)
    const currentLocal = this.messages.get(sessionId) || []
    let merged = this.mergeMessages(currentLocal, serverMessages)
    
    // 检查 merge 期间是否有新 WS 消息
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
    
    // 最终去重
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
    this.enqueueSave(sessionId, () => storageService.saveMessages(sessionId, finalDeduped))
  } catch (e) {
    console.error(`[SessionStore] Sync messages error: ${e}`)
  } finally {
    this.syncingSessions.delete(sessionId)
    this.syncLocks.set(sessionId, false)
  }
}
```

### 步骤 4：修改 `flushHeadToTail` 方法

替换为增强去重版本：

```typescript
flushHeadToTail(sessionId: string): void {
  const head = this.streamHeads.get(sessionId)
  if (!head || head.length === 0) return

  const tail = this.messages.get(sessionId) || []
  let changed = false

  for (const headMsg of head) {
    headMsg.isStreaming = false
    
    const headKey = this.messageContentKey(headMsg)
    const headContentNorm = (headMsg.content || '').trim().replace(/\s+/g, ' ')
    
    let exists = false
    for (const tailMsg of tail) {
      if (tailMsg.id === headMsg.id) {
        exists = true
        break
      }
      if (this.messageContentKey(tailMsg) === headKey) {
        exists = true
        break
      }
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
```

### 步骤 5：修改 `addMessage` 方法

替换为增强去重版本：

```typescript
addMessage(sessionId: string, message: Message): void {
  let sessionMessages = this.messages.get(sessionId)
  if (!sessionMessages) {
    sessionMessages = []
  }

  const newKey = this.messageContentKey(message)
  
  let exists = false
  for (const existing of sessionMessages) {
    if (existing.id === message.id && message.id) {
      exists = true
      break
    }
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
```

### 步骤 6：修改 `handleWSMessage` 的去重逻辑

在方法开头替换：

```typescript
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

if (this.recentMessageIds.has(dedupKey)) {
  console.info(`[SessionStore] Dedup: skipping duplicate msg ${msg.id || '(no-id)'} (${msg.type})`)
  return
}
this.recentMessageIds.add(dedupKey)
setTimeout(() => {
  this.recentMessageIds.delete(dedupKey)
}, SessionStore.DEDUP_CACHE_TTL_MS)
```

### 步骤 7：优化 ChatDetailPage 的 ForEach key

在 `ChatDetailPage.ets` 中，修改 ForEach 的 key 生成：

```typescript
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
```

## 验证修复

1. 重新编译并运行应用
2. 发送消息，观察是否还有重复
3. 检查日志中 `[SessionStore] Dedup: skipping duplicate` 的输出去重情况
4. 测试断网重连、后台切换等场景

## 额外建议

1. **定期清理**：已有的重复消息可通过清除应用数据或调用 `cleanupDuplicateMessages()` 清理
2. **监控**：在发布版本中保留去重日志，便于排查问题
3. **服务端优化**：建议服务端也增加消息去重机制，减少客户端压力
