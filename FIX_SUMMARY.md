# 消息重复问题修复总结

## 📋 问题分析

你的 HarmonyOS ArkTS 聊天应用存在消息重复显示问题，经过代码分析，发现以下根本原因：

### 根本原因

1. **`messageContentKey` 方法缺陷**：对 `tool_use` 类型消息只使用 `toolUseId` 作为去重键，但不同消息可能共享相同的 `toolUseId`（如 `tool_use_complete` 和 `tool_result`）

2. **`getDedupedMessages` 逻辑错误**：
   - 第一道去重后，如果 `dupCount === 0`，不会执行第二道去重
   - `tool_use` 消息永远不会被第一道去重命中
   - 第二道去重中 `result` 数组和 `normResult` 数组混用

3. **WebSocket 双通道**：会话级 WS + 全局广播 WS 同时推送相同消息

4. **流式消息缓冲**：`streamHeads` 和 `messages` 可能包含重复内容

## 🔧 修复方案

### 修复 1：增强 `messageContentKey` 方法

**文件**：`entry/src/main/ets/stores/SessionStore.ets`（第 994 行）

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
```

### 修复 2：重写 `getDedupedMessages` 方法

**文件**：`entry/src/main/ets/stores/SessionStore.ets`（第 1105 行）

```typescript
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
  
  // 第二道去重：用规整化内容去重
  const normalizedSeen = new Set<string>()
  const finalResult: Message[] = []
  let normDupCount = 0
  
  for (let i = 0; i < result.length; i++) {
    const msg = result[i]
    let normKey: string
    
    if (msg.type === 'tool_use' && msg.toolName) {
      const inputStr = msg.toolInput ? this.stableStringify(msg.toolInput) : ''
      normKey = msg.type + ':tool:' + msg.toolName + ':' + inputStr.substring(0, 500)
    } else {
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
```

### 修复 3：优化 WS 消息去重键

**文件**：`entry/src/main/ets/stores/SessionStore.ets`（第 1411 行）

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
```

### 修复 4：优化 ChatDetailPage 的 ForEach key

**文件**：`entry/src/main/ets/pages/ChatDetailPage.ets`

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

## 📁 生成的文件

我已经为你生成了以下文件：

1. **`SessionStore.fixed.ets`** - 完整的修复代码（注释形式）
2. **`SessionStore.patch.ets`** - 关键修复补丁（注释形式）
3. **`DEDUPLICATION_FIX.md`** - 详细修复指南
4. **`ARCHITECTURE_IMPROVEMENT.md`** - 架构改进建议

## 🚀 实施步骤

1. **备份原文件**：
   ```bash
   cp entry/src/main/ets/stores/SessionStore.ets entry/src/main/ets/stores/SessionStore.ets.backup
   cp entry/src/main/ets/pages/ChatDetailPage.ets entry/src/main/ets/pages/ChatDetailPage.ets.backup
   ```

2. **应用修复**：
   - 打开 `entry/src/main/ets/stores/SessionStore.ets`
   - 找到对应的方法（按行号）
   - 替换为修复后的代码

3. **编译测试**：
   ```bash
   # 在 DevEco Studio 中构建项目
   # 或命令行：
   hvigorw assembleDebug
   ```

4. **验证修复**：
   - 发送消息，检查是否还有重复
   - 查看日志中 `[SessionStore] getDedupedMessages: removed X dups` 的输出去重情况
   - 测试断网重连、后台切换等场景

## 📝 额外建议

1. **定期清理**：已有的重复消息可通过清除应用数据或调用清理方法解决
2. **监控**：在发布版本中保留去重日志，便于排查问题
3. **服务端优化**：建议服务端也增加消息去重机制

## 🎯 预期效果

应用修复后，消息重复问题应该得到显著改善。如果仍有少量重复，请检查日志中的去重信息，可能需要进一步调整 `messageContentKey` 的逻辑。
