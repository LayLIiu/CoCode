/**
 * 附件预览栏组件 - 参考 codex-relay AttachmentRail
 * 在输入框上方显示待发送的附件缩略图
 */

import { Theme } from '../common/Theme'
import { AttachmentRef } from '../models/Models'

@Component
export struct AttachmentPreviewBar {
  @Prop attachments: AttachmentRef[] = []
  onRemove: (index: number) => void = () => {}

  @State hoveredIndex: number = -1

  private getTypeIcon(type: string): Resource {
    if (type === 'image') return $r('sys.symbol.camera')
    return $r('sys.symbol.doc_text')
  }

  private getTypeColor(type: string): string {
    if (type === 'image') return Theme.AccentGreen
    return Theme.AccentBlue
  }

  private getTypeLabel(type: string): string {
    if (type === 'image') return 'IMG'
    return 'FILE'
  }

  build() {
    if (this.attachments.length === 0) {
      return
    }

    Scroll() {
      Row({ space: 8 }) {
        ForEach(this.attachments, (attachment: AttachmentRef, index: number) => {
          this.AttachmentItem(attachment, index)
        }, (attachment: AttachmentRef, index: number) => `attach-${index}-${attachment.name}`)
      }
      .padding({ left: 12, right: 12, top: 8, bottom: 8 })
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
    .height(72)
    .backgroundColor('rgba(255, 255, 255, 0.02)')
  }

  @Builder
  AttachmentItem(attachment: AttachmentRef, index: number) {
    Stack() {
      // 背景
      Column() {
        if (attachment.type === 'image' && attachment.path) {
          // 图片缩略图
          Image(attachment.path)
            .width(52)
            .height(52)
            .objectFit(ImageFit.Cover)
            .borderRadius(8)
        } else {
          // 文件图标
          Column({ space: 4 }) {
            SymbolGlyph(this.getTypeIcon(attachment.type || 'file'))
              .fontSize(20)
              .fontColor([this.getTypeColor(attachment.type || 'file')])

            Text(this.getTypeLabel(attachment.type || 'file'))
              .fontSize(8)
              .fontColor(this.getTypeColor(attachment.type || 'file'))
              .fontWeight(FontWeight.Bold)
          }
          .width(52)
          .height(52)
          .backgroundColor('rgba(255, 255, 255, 0.04)')
          .borderRadius(8)
          .justifyContent(FlexAlign.Center)
        }
      }

      // 删除按钮
      Row() {
        SymbolGlyph($r('sys.symbol.xmark_circle_fill'))
          .fontSize(16)
          .fontColor([Theme.TextPrimary])
      }
      .width(18)
      .height(18)
      .position({ x: 42, y: -4 })
      .onClick(() => {
        this.onRemove(index)
      })
    }
    .width(52)
    .height(56)
  }
}

/**
 * 技能标签组件 - 参考 codex-relay 的 SkillMentionChip
 * 显示已选中的技能标签
 */
@Component
export struct SkillChip {
  @Prop name: string = ''
  @Prop displayName: string = ''
  onRemove: () => void = () => {}

  build() {
    Row({ space: 4 }) {
      SymbolGlyph($r('sys.symbol.star'))
        .fontSize(9)
        .fontColor([Theme.AccentOrange])

      Text(this.displayName || this.name)
        .fontSize(10)
        .fontColor(Theme.AccentOrange)
        .maxLines(1)

      Row() {
        SymbolGlyph($r('sys.symbol.xmark'))
          .fontSize(8)
          .fontColor([Theme.TextTertiary])
      }
      .width(14)
      .height(14)
      .borderRadius(7)
      .backgroundColor('rgba(255, 255, 255, 0.08)')
      .justifyContent(FlexAlign.Center)
      .onClick(() => {
        this.onRemove()
      })
    }
    .padding({ left: 8, right: 4, top: 4, bottom: 4 })
    .backgroundColor('rgba(255, 159, 10, 0.1)')
    .borderRadius(10)
    .border({ width: 0.5, color: 'rgba(255, 159, 10, 0.25)' })
  }
}

/**
 * 技能标签栏 - 显示多个技能标签
 */
@Component
export struct SkillChipsBar {
  @Prop skills: Array<{ name: string; displayName: string }> = []
  onRemove: (name: string) => void = () => {}

  build() {
    if (this.skills.length === 0) {
      return
    }

    Scroll() {
      Row({ space: 6 }) {
        ForEach(this.skills, (skill: { name: string; displayName: string }) => {
          SkillChip({
            name: skill.name,
            displayName: skill.displayName,
            onRemove: () => {
              this.onRemove(skill.name)
            }
          })
        }, (skill: { name: string }) => `skill-${skill.name}`)
      }
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
  }
}

/**
 * Plan Mode 指示器组件
 */
@Component
export struct PlanModeChip {
  @Prop isPlanMode: boolean = false
  onToggle: () => void = () => {}

  @State chipScale: number = 1.0

  build() {
    if (!this.isPlanMode) {
      return
    }

    Row({ space: 4 }) {
      SymbolGlyph($r('sys.symbol.doc_text'))
        .fontSize(9)
        .fontColor([Theme.AccentPurple])

      Text('计划模式')
        .fontSize(10)
        .fontColor(Theme.AccentPurple)
        .maxLines(1)
    }
    .padding({ left: 8, right: 8, top: 4, bottom: 4 })
    .backgroundColor('rgba(175, 82, 222, 0.12)')
    .borderRadius(10)
    .border({ width: 0.5, color: 'rgba(175, 82, 222, 0.25)' })
    .scale({ x: this.chipScale, y: this.chipScale })
    .animation({ duration: 150, curve: Curve.EaseInOut })
    .onClick(() => {
      animateTo({ duration: 100, curve: Curve.EaseOut }, () => {
        this.chipScale = 0.92
      })
      setTimeout(() => {
        animateTo({ duration: 100, curve: Curve.EaseOut }, () => {
          this.chipScale = 1.0
        })
      }, 50)
      this.onToggle()
    })
  }
}
