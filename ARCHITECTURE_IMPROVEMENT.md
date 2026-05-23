# 聊天界面架构改进方案

## 当前架构问题

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   ChatDetailPage │────▶│   SessionStore   │◄────│   WebSocket     │
│   (UI 层)        │     │   (状态管理层)    │     │   (数据层)      │
└─────────────────┘     └─────────────────┘     └─────────────────┘
         │                       │                       │
         │                       ▼                       │
         │              ┌─────────────────┐             │
         │              │   StorageService │             │
         │              │   (本地存储)     │             │
         │              └─────────────────┘             │
         │                                              │
         └──────────────────────────────────────────────┘
                            问题：多通道数据流导致重复
```

## 改进架构：单一数据源 + 事件溯源

```
┌─────────────────────────────────────────────────────────────┐
│                      ChatDetailPage (UI 层)                  │
│                      只读，不直接修改消息                      │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    MessageRepository (数据仓库层)             │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │
│  │  内存缓存    │  │  本地存储    │  │     去重引擎         │  │
│  │  (LRU)      │  │  (SQLite)   │  │  (Bloom Filter)     │  │
│  └─────────────┘  └─────────────┘  └─────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                  MessageSyncEngine (同步引擎层)               │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │
│  │  WS 接收器   │  │  HTTP 轮询  │  │   冲突解决器        │  │
│  │             │  │             │  │  (Last-Write-Wins)  │  │
│  └─────────────┘  └─────────────┘  └─────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                      Server (服务端)                         │
└─────────────────────────────────────────────────────────────┘
```

## 核心改进点

### 1. 引入消息指纹（Message Fingerprint）

```typescript
interface MessageFingerprint {
  id: string           // 消息唯一 ID
  contentHash: string  // 内容哈希（SHA-256）
  vectorClock: number  // 向量时钟（用于冲突解决）
  source: 'local' | 'websocket' | 'http' | 'sync'
  timestamp: number
}

// 生成指纹
function generateFingerprint(msg: Message): MessageFingerprint {
  const content = msg.content || msg.toolResult || ''
  const toolInfo = msg.toolName ? JSON.stringify(msg.toolInput) : ''
  const raw = `${msg.type}|${content}|${toolInfo}|${msg.toolUseId || ''}`
  
  // 使用简单的哈希（实际可用 crypto.subtle.digest）
  let hash = 0
  for (let i = 0; i < raw.length; i++) {
    const char = raw.charCodeAt(i)
    hash = ((hash << 5) - hash) + char
    hash = hash & hash
  }
  
  return {
    id: msg.id || `gen-${Date.now()}-${Math.random()}`,
    contentHash: String(hash),
    vectorClock: Date.now(),
    source: 'local',
    timestamp: new Date(msg.timestamp).getTime()
  }
}
```

### 2. 使用布隆过滤器快速去重

```typescript
class BloomFilter {
  private bits: boolean[]
  private size: number
  private hashCount: number
  
  constructor(size: number = 10000, hashCount: number = 3) {
    this.size = size
    this.hashCount = hashCount
    this.bits = new Array(size).fill(false)
  }
  
  add(item: string): void {
    for (let i = 0; i < this.hashCount; i++) {
      const index = this.hash(item, i) % this.size
      this.bits[index] = true
    }
  }
  
  mightContain(item: string): boolean {
    for (let i = 0; i < this.hashCount; i++) {
      const index = this.hash(item, i) % this.size
      if (!this.bits[index]) return false
    }
    return true
  }
  
  private hash(item: string, seed: number): number {
    let hash = seed
    for (let i = 0; i < item.length; i++) {
      hash = ((hash << 5) - hash) + item.charCodeAt(i)
      hash = hash & hash
    }
    return Math.abs(hash)
  }
}

// 使用
const messageFilter = new BloomFilter()

function isDuplicate(msg: Message): boolean {
  const fingerprint = generateFingerprint(msg)
  const key = `${fingerprint.id}:${fingerprint.contentHash}`
  
  if (messageFilter.mightContain(key)) {
    // 布隆过滤器命中，进行精确检查
    return checkExactDuplicate(msg)
  }
  
  messageFilter.add(key)
  return false
}
```

### 3. 事件溯源模式

```typescript
// 所有消息变更都通过事件
interface MessageEvent {
  id: string
  type: 'message_added' | 'message_updated' | 'message_deleted' | 'stream_delta'
  sessionId: string
  messageId: string
  payload: Message | Partial<Message>
  timestamp: number
  source: 'user' | 'websocket' | 'sync'
}

class MessageEventStore {
  private events: MessageEvent[] = []
  private listeners: Array<(event: MessageEvent) => void> = []
  
  emit(event: MessageEvent): void {
    // 去重检查
    if (this.isDuplicateEvent(event)) {
      console.info(`[EventStore] Duplicate event skipped: ${event.type} ${event.messageId}`)
      return
    }
    
    this.events.push(event)
    this.notifyListeners(event)
  }
  
  private isDuplicateEvent(event: MessageEvent): boolean {
    // 检查最近 100 个事件
    const recent = this.events.slice(-100)
    return recent.some(e => 
      e.type === event.type && 
      e.messageId === event.messageId &&
      e.source === event.source
    )
  }
  
  private notifyListeners(event: MessageEvent): void {
    this.listeners.forEach(l => l(event))
  }
  
  subscribe(listener: (event: MessageEvent) => void): void {
    this.listeners.push(listener)
  }
}
```

### 4. 改进的 UI 层

```typescript
@Entry
@Component
struct ChatDetailPage {
  // 不再直接操作消息数组，通过 Repository 获取
  @State messages: Message[] = []
  
  private messageRepository: MessageRepository
  private eventSubscription: (event: MessageEvent) => void
  
  aboutToAppear(): void {
    // 订阅事件流
    this.eventSubscription = (event) => {
      if (event.sessionId === this.sessionId) {
        this.refreshMessages()
      }
    }
    messageEventStore.subscribe(this.eventSubscription)
    
    // 初始加载
    this.refreshMessages()
  }
  
  private async refreshMessages(): Promise<void> {
    // 从 Repository 获取去重后的消息
    const msgs = await this.messageRepository.getMessages(this.sessionId)
    this.messages = msgs
  }
  
  build() {
    List() {
      ForEach(this.messages, (msg) => {
        MessageItem({ message: msg })
      }, (msg) => msg.id || generateFingerprint(msg).id)
    }
  }
}
```

## 实施建议

### 阶段 1：快速修复（当前）
- 应用 `DEDUPLICATION_FIX.md` 中的修复
- 增加日志监控重复情况

### 阶段 2：架构重构（下一版本）
- 引入 `MessageRepository` 层
- 实现事件溯源
- 添加布隆过滤器

### 阶段 3：服务端优化
- 服务端增加消息去重
- 统一消息 ID 生成策略
- 添加消息序列号

## 测试策略

```typescript
// 去重测试用例
describe('Message Deduplication', () => {
  it('should deduplicate identical messages', () => {
    const msg1 = createMessage({ id: '1', content: 'hello' })
    const msg2 = createMessage({ id: '1', content: 'hello' })
    
    store.addMessage('session-1', msg1)
    store.addMessage('session-1', msg2)
    
    expect(store.getMessages('session-1').length).toBe(1)
  })
  
  it('should handle WS double delivery', () => {
    const wsMsg = createWSMessage({ type: 'content_delta', text: 'hi' })
    
    // 模拟双通道投递
    handleWSMessage('session-1', wsMsg)
    handleWSMessage('session-1', wsMsg)
    
    expect(store.getMessages('session-1').length).toBe(1)
  })
  
  it('should merge local and server messages', () => {
    const localMsg = createMessage({ id: 'local-1', content: 'local' })
    const serverMsg = createMessage({ id: 'server-1', content: 'local' })
    
    store.addMessage('session-1', localMsg)
    store.syncMessagesFromServer('session-1', [serverMsg])
    
    expect(store.getMessages('session-1').length).toBe(1)
  })
})
```

## 性能优化

1. **虚拟列表**：只渲染可见消息
2. **增量更新**：只更新变化的消息
3. **Web Worker**：在后台线程进行去重计算
4. **IndexedDB**：大量消息时使用数据库存储
