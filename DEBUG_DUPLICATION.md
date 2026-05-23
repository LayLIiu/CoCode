# 消息重复问题调试指南

## 已应用的修复

1. ✅ `messageContentKey` 方法已增强（第 994 行）
2. ✅ `getDedupedMessages` 方法已修复（第 1105 行）
3. ✅ `ChatDetailPage` 的 `ForEach` key 已优化（第 1592 行）

## 如果还有重复，请检查以下日志

在 DevEco Studio 的 Log 窗口中过滤 `[SessionStore]` 和 `[ChatDetailPage]` 标签：

### 1. 检查去重日志

```
[SessionStore] getDedupedMessages: removed X dups from Y msgs
```

如果看到这个日志，说明去重机制在工作，但可能有新的重复消息不断产生。

### 2. 检查 WS 消息去重日志

```
[SessionStore] Dedup: skipping duplicate msg ...
```

如果看到这个日志，说明 WebSocket 双通道重复被拦截。

### 3. 检查同步日志

```
[SessionStore] syncMessagesFromServer: already syncing ...
[SessionStore] Removing dup after sync (by ID): ...
[SessionStore] Removing dup after sync (by content): ...
```

### 4. 检查 Head/Tail 刷新日志

```
[SessionStore] flushHeadToTail: ...
```

## 常见重复场景

### 场景 1：用户消息重复
- **原因**：本地发送后，`user_message_echo` 又推送一次
- **检查**：查看 `user_message_echo` 处理日志
- **解决**：已修复，`addMessage` 会检查重复

### 场景 2：AI 回复重复
- **原因**：`content_delta` 消息重复推送
- **检查**：查看 `content_delta` 的 `dedupKey` 日志
- **解决**：已修复，WS 层有 30 秒去重窗口

### 场景 3：工具调用重复
- **原因**：`tool_use_complete` 消息重复，或 `toolUseId` 不一致
- **检查**：查看 `tool_use_complete` 的日志
- **解决**：已修复，`messageContentKey` 现在使用 `toolName + toolInput`

### 场景 4：页面切换后重复
- **原因**：`onPageShow` 加载本地消息 + WS 推送消息
- **检查**：查看 `onPageShow` 和 `loadMessages` 日志
- **解决**：已修复，`getDedupedMessages` 作为展示层安全网

## 如果还有重复，请提供以下信息

1. **重复的消息类型**：用户消息、AI 回复、工具调用、还是其他？
2. **重复的时机**：发送后立即重复、页面切换后重复、还是后台切换后重复？
3. **日志输出**：过滤 `[SessionStore]` 后的相关日志
4. **消息内容**：重复消息的具体内容（可脱敏）

## 临时解决方案

如果急需解决，可以在 `ChatDetailPage` 的 `getVisibleMessages()` 方法中添加更强的去重：

```typescript
private getVisibleMessages(): Message[] {
  const allMessages = sessionStore.getDedupedMessages(this.sessionId)
  
  // 临时增强去重：按内容完全去重
  const uniqueMessages: Message[] = []
  const seenContent = new Set<string>()
  
  for (const msg of allMessages) {
    const contentKey = msg.type + '|' + (msg.content || msg.toolResult || '')
    if (!seenContent.has(contentKey)) {
      seenContent.add(contentKey)
      uniqueMessages.push(msg)
    }
  }
  
  // 过滤 Agent 子工具
  const filtered = uniqueMessages.filter(m => !(m.type === 'tool_use' && m.parentToolUseId))
  
  // ... 原有分页逻辑
  return filtered
}
```

## 联系支持

如果以上方法都无法解决问题，请提供：
1. 完整的日志文件（过滤 `[SessionStore]` 和 `[ChatDetailPage]`）
2. 复现步骤
3. 消息列表截图（脱敏）
