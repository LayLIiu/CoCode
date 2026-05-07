import { Theme } from '../common/Theme'
import { Constants, TabIndex } from '../common/Constants'
import { ConversationModel, TabType, DateGroup } from '../viewmodel/ConversationModel'
import { MockDataGenerator } from '../viewmodel/MockData'
import { ConversationItem } from '../components/ConversationItem'
import { SearchBar } from '../components/SearchBar'

/**
 * 会话列表页面 - 支持日期分组
 */
@Component
export struct ConversationListPage {
  @Prop tabType: TabType = TabType.CLAUDE
  @Prop pageTitle: string = Constants.TITLE_CLAUDE
  @State conversations: ConversationModel[] = []
  @State searchText: string = ''
  @State isNewDialogVisible: boolean = false

  aboutToAppear() {
    this.loadConversations()
  }

  private loadConversations() {
    this.conversations = MockDataGenerator.getConversationsByTab(this.tabType)
  }

  /**
   * 获取日期分组
   */
  private getDateGroup(date: Date): DateGroup {
    const now = new Date()
    const today = new Date(now.getFullYear(), now.getMonth(), now.getDate())
    const yesterday = new Date(today.getTime() - 24 * 60 * 60 * 1000)
    const sevenDaysAgo = new Date(today.getTime() - 7 * 24 * 60 * 60 * 1000)
    
    const targetDate = new Date(date.getFullYear(), date.getMonth(), date.getDate())
    
    if (targetDate.getTime() >= today.getTime()) {
      return DateGroup.TODAY
    } else if (targetDate.getTime() >= yesterday.getTime()) {
      return DateGroup.YESTERDAY
    } else if (targetDate.getTime() >= sevenDaysAgo.getTime()) {
      return DateGroup.LAST_SEVEN_DAYS
    } else {
      return DateGroup.EARLIER
    }
  }

  /**
   * 按日期分组会话
   */
  private getGroupedConversations(): Map<DateGroup, ConversationModel[]> {
    const grouped = new Map<DateGroup, ConversationModel[]>()
    
    grouped.set(DateGroup.TODAY, [])
    grouped.set(DateGroup.YESTERDAY, [])
    grouped.set(DateGroup.LAST_SEVEN_DAYS, [])
    grouped.set(DateGroup.EARLIER, [])
    
    this.conversations.forEach((conversation: ConversationModel) => {
      const group = this.getDateGroup(conversation.timestamp)
      const groupList = grouped.get(group)
      if (groupList) {
        groupList.push(conversation)
      }
    })
    
    return grouped
  }

  build() {
    Column() {
      this.NavigationBar()
      
      SearchBar({ 
        searchText: $searchText,
        onSearchChange: () => {
          this.loadConversations()
        }
      })
        .padding({ left: Theme.SpacingLG, right: Theme.SpacingLG, top: Theme.SpacingXL })
      
      if (this.conversations.length > 0) {
        List({ space: 0 }) {
          ForEach(Array.from(this.getGroupedConversations().entries()), (entry: [DateGroup, ConversationModel[]]) => {
            ListItemGroup({
              header: this.GroupHeader(entry[0])
            }) {
              ForEach(entry[1], (conversation: ConversationModel) => {
                ListItem() {
                  ConversationItem({ conversation: conversation })
                }
              }, (conversation: ConversationModel) => conversation.id)
            }
          }, (entry: [DateGroup, ConversationModel[]]) => entry[0])
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: Theme.SpacingLG, right: Theme.SpacingLG, top: Theme.SpacingMD })
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
      } else {
        this.EmptyState()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.BackgroundPrimary)
  }

  @Builder
  NavigationBar() {
    Row() {
      // 左边：导入消息按钮
      Column() {
        Image($r('app.media.ic_history'))
          .width(20)
          .height(20)
          .fillColor(Theme.TextPrimary)
      }
      .width(36)
      .height(36)
      .backgroundColor('rgba(255, 255, 255, 0.1)')
      .backgroundBlurStyle(BlurStyle.Thin)
      .borderRadius(18)
      .border({ width: 1, color: 'rgba(255, 255, 255, 0.1)' })
      .justifyContent(FlexAlign.Center)
      .onClick(() => {
        // 导入消息
        console.log('Import messages')
      })
      
      // 中间：标题
      Text(this.pageTitle)
        .fontSize(Theme.FontTitle)
        .fontColor(Theme.TextPrimary)
        .fontWeight(FontWeight.Bold)
        .layoutWeight(1)
        .textAlign(TextAlign.Center)
      
      // 右边：新建会话按钮
      Column() {
        Image($r('app.media.ic_add'))
          .width(20)
          .height(20)
          .fillColor(Theme.TextPrimary)
      }
      .width(36)
      .height(36)
      .backgroundColor('rgba(255, 255, 255, 0.1)')
      .backgroundBlurStyle(BlurStyle.Thin)
      .borderRadius(18)
      .border({ width: 1, color: 'rgba(255, 255, 255, 0.1)' })
      .justifyContent(FlexAlign.Center)
      .onClick(() => {
        this.createNewConversation()
      })
    }
    .width('100%')
    .height(80)
    .padding({ left: Theme.SpacingLG, right: Theme.SpacingLG, top: 56 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  GroupHeader(groupName: DateGroup) {
    Text(groupName)
      .fontSize(Theme.FontCaption)
      .fontColor(Theme.TextSecondary)
      .width('100%')
      .padding({ top: Theme.SpacingLG, bottom: Theme.SpacingSM })
  }

  @Builder
  EmptyState() {
    Column() {
      Image($r('app.media.ic_empty'))
        .width(80)
        .height(80)
        .fillColor(Theme.TextTertiary)
        .opacity(0.5)
      
      Text('暂无会话')
        .fontSize(Theme.FontBody)
        .fontColor(Theme.TextSecondary)
        .margin({ top: Theme.SpacingMD })
      
      Text('点击右上角 + 开始新对话')
        .fontSize(Theme.FontCaption)
        .fontColor(Theme.TextTertiary)
        .margin({ top: Theme.SpacingXS })
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  private createNewConversation() {
    console.log('Create new conversation for tab: ' + this.tabType)
  }
}
