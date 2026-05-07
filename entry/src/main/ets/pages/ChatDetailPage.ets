import { Theme } from '../common/Theme'
import { MessageModel, MessageType } from '../viewmodel/MessageModel'
import { MockMessageData } from '../viewmodel/MockMessageData'
import { MessageItem } from '../components/MessageItem'
import { ChatNavigationBar } from '../components/ChatNavigationBar'
import { InputArea } from '../components/InputArea'
import router from '@ohos.router'

/**
 * 对话详情页 - 悬浮透明输入框
 */
@Entry
@Component
struct ChatDetailPage {
  @State messages: MessageModel[] = []
  @State inputText: string = ''
  @State conversationTitle: string = 'React Native项目优化讨论'
  @State conversationId: string = ''
  @State totalMessages: number = 8
  @State displayedMessages: number = 7
  @State showStatus: boolean = true
  @State statusText: string = '工具执行中'
  
  private scroller: Scroller = new Scroller()

  aboutToAppear() {
    this.getRouterParams()
    this.loadMessages()
  }

  private getRouterParams() {
    const params = router.getParams() as Record<string, string>
    if (params) {
      if (params.conversationId) {
        this.conversationId = params.conversationId
      }
      if (params.title) {
        this.conversationTitle = params.title
      }
    }
  }

  private loadMessages() {
    this.messages = MockMessageData.generateMessages()
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      // 底层：聊天内容区域
      Column() {
        ChatNavigationBar({
          title: this.conversationTitle,
          statusText: this.statusText,
          showStatus: this.showStatus,
          onBackClick: () => {
            this.goBack()
          },
          onMenuClick: () => {
            this.showMenu()
          }
        })
        
        Column() {
          this.LoadMoreIndicator()
          
          List({ scroller: this.scroller }) {
            ForEach(this.messages, (message: MessageModel) => {
              ListItem() {
                MessageItem({ message: message })
              }
            }, (message: MessageModel) => message.id)
            
            // 添加底部占位符，确保最后一条消息不被输入框遮挡
            ListItem() {
              Row()
                .width('100%')
                .height(70)  // 为输入框预留空间
            }
          }
          .width('100%')
          .layoutWeight(1)
          .padding({ left: Theme.SpacingLG, right: Theme.SpacingLG })
          .scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.Spring)
          .onReachStart(() => {
            this.loadEarlierMessages()
          })
        }
        .width('100%')
        .layoutWeight(1)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(Theme.BackgroundPrimary)

      // 顶层：悬浮输入框（无背景容器）
      InputArea({
        inputText: $inputText,
        onSend: (text: string) => {
          this.sendMessage(text)
        },
        onAddClick: () => {
          this.showAttachmentOptions()
        }
      })
      .width('96%')
      .margin({ bottom: 16 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.BackgroundPrimary)
  }

  @Builder
  LoadMoreIndicator() {
    Column() {
      Text(`已显示 ${this.displayedMessages}/${this.totalMessages} 条`)
        .fontSize(Theme.FontCaption)
        .fontColor(Theme.TextSecondary)
      
      Text('加载更早消息')
        .fontSize(Theme.FontCaption)
        .fontColor(Theme.TextTertiary)
        .margin({ top: Theme.SpacingXS })
    }
    .width('100%')
    .padding({ top: Theme.SpacingLG, bottom: Theme.SpacingLG })
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  private sendMessage(text: string) {
    const newMessage: MessageModel = {
      id: Date.now().toString(),
      type: MessageType.TEXT,
      content: text,
      timestamp: this.getCurrentTime(),
      isUser: true
    }
    
    this.messages.push(newMessage)
    this.totalMessages++
    this.displayedMessages++
    
    // 发送消息后滚动到底部，确保新消息显示在输入框上方
    setTimeout(() => {
      this.scroller.scrollEdge(Edge.Bottom)
    }, 100)
  }

  private loadEarlierMessages() {
    console.log('Load earlier messages')
  }

  private goBack() {
    router.back()
  }

  private showMenu() {
    console.log('Show menu')
  }

  private showAttachmentOptions() {
    console.log('Show attachment options')
  }

  private getCurrentTime(): string {
    const now = new Date()
    return `${now.getHours()}:${now.getMinutes().toString().padStart(2, '0')}`
  }
}
