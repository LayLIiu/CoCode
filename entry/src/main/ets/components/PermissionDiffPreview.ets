/**
 * 权限请求 Diff 预览组件
 *
 * 从 ChatDetailPage.PermissionDiffPreview 拆分而来。
 * 显示 Edit/Write 工具的文件变更 diff 预览。
 */

import { Theme } from '../common/Theme'

@Component
export struct PermissionDiffPreview {
  @Prop toolName: string = ''
  @Prop input: Record<string, Object> = {}

  build() {
    Column({ space: 4 }) {
      // 文件路径
      if (this.input['file_path'] as string) {
        Text(this.input['file_path'] as string)
          .fontSize(Theme.FontTiny)
          .fontColor(Theme.TextTertiary)
          .width('100%')
      }

      // 简化 diff 显示
      Scroll() {
        Column({ space: 2 }) {
          // 删除的内容（old_string）
          if (this.toolName === 'Edit' && (this.input['old_string'] as string)) {
            ForEach((this.input['old_string'] as string).split('\n').slice(0, 10), (line: string, idx: number) => {
              Row() {
                Text('-')
                  .fontSize(Theme.FontTiny)
                  .fontColor(Theme.ErrorColor)
                  .width(12)
                Text(line || ' ')
                  .fontSize(Theme.FontTiny)
                  .fontColor(Theme.ErrorColor)
                  .backgroundColor('rgba(255,69,58,0.1)')
                  .layoutWeight(1)
              }
              .width('100%')
              .padding({ left: 4, right: 4 })
            }, (line: string, idx: number) => `old-${idx}`)
            if ((this.input['old_string'] as string).split('\n').length > 10) {
              Text(`... 还有 ${(this.input['old_string'] as string).split('\n').length - 10} 行`)
                .fontSize(Theme.FontTiny)
                .fontColor(Theme.TextTertiary)
            }
          }

          // 添加的内容（new_string）
          if (this.toolName === 'Edit' && (this.input['new_string'] as string)) {
            ForEach((this.input['new_string'] as string).split('\n').slice(0, 10), (line: string, idx: number) => {
              Row() {
                Text('+')
                  .fontSize(Theme.FontTiny)
                  .fontColor(Theme.SuccessColor)
                  .width(12)
                Text(line || ' ')
                  .fontSize(Theme.FontTiny)
                  .fontColor(Theme.SuccessColor)
                  .backgroundColor('rgba(52,199,89,0.1)')
                  .layoutWeight(1)
              }
              .width('100%')
              .padding({ left: 4, right: 4 })
            }, (line: string, idx: number) => `new-${idx}`)
            if ((this.input['new_string'] as string).split('\n').length > 10) {
              Text(`... 还有 ${(this.input['new_string'] as string).split('\n').length - 10} 行`)
                .fontSize(Theme.FontTiny)
                .fontColor(Theme.TextTertiary)
            }
          }

          // Write 工具的 content
          if (this.toolName === 'Write' && (this.input['content'] as string)) {
            ForEach((this.input['content'] as string).split('\n').slice(0, 10), (line: string, idx: number) => {
              Row() {
                Text('+')
                  .fontSize(Theme.FontTiny)
                  .fontColor(Theme.SuccessColor)
                  .width(12)
                Text(line || ' ')
                  .fontSize(Theme.FontTiny)
                  .fontColor(Theme.SuccessColor)
                  .backgroundColor('rgba(52,199,89,0.1)')
                  .layoutWeight(1)
              }
              .width('100%')
              .padding({ left: 4, right: 4 })
            }, (line: string, idx: number) => `write-${idx}`)
            if ((this.input['content'] as string).split('\n').length > 10) {
              Text(`... 还有 ${(this.input['content'] as string).split('\n').length - 10} 行`)
                .fontSize(Theme.FontTiny)
                .fontColor(Theme.TextTertiary)
            }
          }
        }
        .width('100%')
      }
      .width('100%')
      .constraintSize({ maxHeight: 150 })
      .padding(8)
      .backgroundColor(Theme.BackgroundTertiary)
      .borderRadius(8)
    }
    .width('100%')
  }
}
