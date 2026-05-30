// 修复后的 content_delta 和 thinking 处理逻辑
// 替换原有的 case 'content_delta' 和 case 'thinking' 部分

      case 'content_delta':
        // 添加调试日志
        console.info(`[SessionStore] content_delta received: sessionId=${sessionId}, blockType=${msg.blockType}, textLen=${(msg.text as string)?.length || 0}`)
        
        // 仅处理文本内容（blockType === "text" 或未指定）
        if (msg.blockType && msg.blockType !== 'text') {
          console.info(`[SessionStore] Skip content_delta with blockType=${msg.blockType}`)
          break
        }
        
        // 流式增量更新 Head 缓冲
        {
          const deltaText = typeof msg.text === 'string' ? msg.text as string : ''
          if (deltaText) {
            let head = this.streamHeads.get(sessionId)
            if (!head) {
              head = []
            }

            if (head.length > 0 && head[head.length - 1].type === 'assistant') {
              const last = head[head.length - 1]
              last.content = (last.content || '') + deltaText
            } else {
              head.push({
                id: 'stream-' + Date.now(),
                type: 'assistant',
                content: deltaText,
                isStreaming: true,
                timestamp: new Date().toISOString(),
              })
            }

            this.streamHeads.set(sessionId, head)
            // 降低节流阈值：每 20 字符更新一次 UI，提升短消息响应
            const lastMsg = head[head.length - 1]
            const contentLen = (lastMsg.content || '').length
            if (contentLen % 20 < deltaText.length || contentLen < 50) {
              console.info(`[SessionStore] content_delta notify UI: contentLen=${contentLen}`)
              this.notifyMessagesChanged(sessionId)
            }
          }
        }
        break

      case 'thinking':
        // 流式增量更新 Head 缓冲
        {
          const deltaText = typeof msg.text === 'string' ? msg.text as string : ''
          if (deltaText) {
            let head = this.streamHeads.get(sessionId)
            if (!head) {
              head = []
            }

            if (head.length > 0 && head[head.length - 1].type === 'thinking') {
              const last = head[head.length - 1]
              last.content = (last.content || '') + deltaText
            } else {
              head.push({
                id: 'thinking-' + Date.now(),
                type: 'thinking',
                content: deltaText,
                isStreaming: true,
                timestamp: new Date().toISOString(),
              })
            }

            this.streamHeads.set(sessionId, head)
            // 降低节流阈值：每 20 字符更新一次 UI
            const lastMsg = head[head.length - 1]
            const contentLen = (lastMsg.content || '').length
            if (contentLen % 20 < deltaText.length || contentLen < 50) {
              this.notifyMessagesChanged(sessionId)
            }
          }
        }
        break
