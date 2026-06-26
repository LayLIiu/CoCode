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
            this.DiffLines(
              (this.input['old_string'] as string).split('\n'),
              '-',
              Theme.ErrorColor,
              'rgba(255,69,58,0.1)'
            )
          }

          // 添加的内容（new_string / content）
          const newContent = (this.input['new_string'] as string) ||
            (this.toolName === 'Write' ? (this.input['content'] as string) : '')
          if (newContent) {
            this.DiffLines(
              newContent.split('\n'),
              '+',
              Theme.SuccessColor,
              'rgba(52,199,89,0.1)'
            )
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

  @Builder
  DiffLines(lines: string[], prefix: string, color: ResourceColor, bgColor: string) {
    const maxLines = 10
    const totalLines = lines.length
    const displayLines = lines.slice(0, maxLines)

    ForEach(displayLines, (line: string, idx: number) => {
      Row() {
        Text(prefix)
          .fontSize(Theme.FontTiny)
          .fontColor(color)
          .width(12)
        Text(line || ' ')
          .fontSize(Theme.FontTiny)
          .fontColor(color)
          .backgroundColor(bgColor)
          .layoutWeight(1)
      }
      .width('100%')
      .padding({ left: 4, right: 4 })
    }, (line: string, idx: number) => `${prefix}-${idx}`)

    if (totalLines > maxLines) {
      Text(`... 还有 ${totalLines - maxLines} 行`)
        .fontSize(Theme.FontTiny)
        .fontColor(Theme.TextTertiary)
    }
  }
}
