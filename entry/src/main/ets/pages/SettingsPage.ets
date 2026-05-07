import { Theme } from '../common/Theme'

/**
 * 设置页面
 */
@Component
export struct SettingsPage {
  @State isDarkMode: boolean = true
  @State notificationEnabled: boolean = true
  @State autoSaveEnabled: boolean = true

  build() {
    Column() {
      // 顶部标题 - 增加顶部间距，避免被系统状态栏遮挡
      Text('设置')
        .fontSize(Theme.FontTitle)
        .fontColor(Theme.TextPrimary)
        .fontWeight(FontWeight.Bold)
        .width('100%')
        .textAlign(TextAlign.Center)
        .padding({ top: 56, bottom: Theme.SpacingLG })  // 56 是状态栏高度 + 额外间距
      
      // 设置列表
      List({ space: Theme.SpacingMD }) {
        // 外观设置
        ListItem() {
          this.SettingSection('外观')
        }
        
        ListItem() {
          this.SettingItem('深色模式', '启用深色主题', this.isDarkMode, (value: boolean) => {
            this.isDarkMode = value
          })
        }
        
        // 通知设置
        ListItem() {
          this.SettingSection('通知')
        }
        
        ListItem() {
          this.SettingItem('推送通知', '接收消息推送', this.notificationEnabled, (value: boolean) => {
            this.notificationEnabled = value
          })
        }
        
        // 存储设置
        ListItem() {
          this.SettingSection('存储')
        }
        
        ListItem() {
          this.SettingItem('自动保存', '自动保存会话记录', this.autoSaveEnabled, (value: boolean) => {
            this.autoSaveEnabled = value
          })
        }
        
        // 关于
        ListItem() {
          this.SettingSection('关于')
        }
        
        ListItem() {
          this.AboutItem('版本', '1.0.0')
        }
      }
      .width('100%')
      .layoutWeight(1)
      .padding({ left: Theme.SpacingLG, right: Theme.SpacingLG })
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.BackgroundPrimary)
  }

  @Builder
  SettingSection(title: string) {
    Text(title)
      .fontSize(Theme.FontCaption)
      .fontColor(Theme.TextSecondary)
      .width('100%')
      .padding({ top: Theme.SpacingLG, bottom: Theme.SpacingSM })
  }

  @Builder
  SettingItem(title: string, subtitle: string, isEnabled: boolean, onChange: (value: boolean) => void) {
    Row() {
      Column() {
        Text(title)
          .fontSize(Theme.FontBody)
          .fontColor(Theme.TextPrimary)
          .width('100%')
        
        Text(subtitle)
          .fontSize(Theme.FontCaption)
          .fontColor(Theme.TextSecondary)
          .width('100%')
          .margin({ top: Theme.SpacingXS })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      
      Toggle({ type: ToggleType.Switch, isOn: isEnabled })
        .selectedColor(Theme.AccentBlue)
        .onChange((isOn: boolean) => {
          onChange(isOn)
        })
    }
    .width('100%')
    .padding(Theme.SpacingLG)
    .backgroundColor(Theme.BackgroundSecondary)
    .borderRadius(Theme.RadiusLarge)
  }

  @Builder
  AboutItem(title: string, value: string) {
    Row() {
      Text(title)
        .fontSize(Theme.FontBody)
        .fontColor(Theme.TextPrimary)
      
      Blank()
      
      Text(value)
        .fontSize(Theme.FontBody)
        .fontColor(Theme.TextSecondary)
    }
    .width('100%')
    .padding(Theme.SpacingLG)
    .backgroundColor(Theme.BackgroundSecondary)
    .borderRadius(Theme.RadiusLarge)
  }
}
