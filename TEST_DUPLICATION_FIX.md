# 消息重复问题修复测试指南

## 修复内容总结

### 1. 增强去重键生成（SessionStore.ets）
- `tool_use` 消息现在使用 `toolName + toolInput` 作为去重键
- `tool_result` 使用 `toolUseId`
- 普通消息使用规整化内容

### 2. 修复 `getDedupedMessages`（SessionStore.ets）
- 修复了两道去重的逻辑错误
- 确保所有消息类型都能被正确去重

### 3. 优化 UI 层更新（ChatDetailPage.ets）
- `messagesChangedListener` 现在会检查消息是否真的变化了
- `onPageShow` 只在消息数量变化时更新 UI
- `ForEach` key 生成使用更稳定的标识

### 4. 防止重复同步（SessionStore.ets）
- `loadMessages` 检查是否已经在同步中
- `syncMessagesFromServer` 确保去重后再通知 UI
- `addMessagesChangedListener` 防止重复添加监听器

## 测试步骤

### 测试 1：页面切换后是否还有重复
1. 打开一个对话，发送一条消息
2. 等待 AI 回复完成
3. 切换到其他页面（如对话列表）
4. 切换回该对话
5. **预期结果**：AI 回复不重复

### 测试 2：快速切换页面
1. 在 AI 回复过程中快速切换页面
2. **预期结果**：不会出现重复消息

### 测试 3：后台恢复
1. 将应用切换到后台
2. 等待一段时间（如 30 秒）
3. 恢复应用到前台
4. **预期结果**：消息列表正常，无重复

## 查看日志

在 DevEco Studio 的 Log 窗口中过滤以下标签：

```
[SessionStore] getDedupedMessages: removed X dups
```
- 表示去重机制在工作

```
[SessionStore] syncMessagesFromServer: already syncing ...
```
- 表示并发保护生效

```
[ChatDetailPage] messagesChangedListener: skipped (no change)
```
- 表示 UI 层跳过了不必要的更新

## 如果还有重复

请提供以下信息：
1. 重复的消息类型（AI 回复 / 用户消息 / 工具调用）
2. 复现步骤
3. 相关日志输出
4. 消息列表截图（可脱敏）
