/**
 * 图片预览对话框 — 全屏图片查看器
 * 支持缩放、滑动关闭、保存到相册
 */

import { Theme } from '../common/Theme'
import { fileService } from '../services/FileService'
import { downloadService } from '../services/DownloadService'

@Component
export struct ImagePreviewDialog {
  @Prop imageSrc: string = ''
  @Prop imageAlt: string = ''
  @Prop fileName: string = ''
  @Link isVisible: boolean
  @State scaleValue: number = 1.0
  @State offsetY: number = 0
  @State isSaving: boolean = false
  @State saveResult: string = ''

  private dragStartY: number = 0
  private isPinching: boolean = false

  build() {
    Stack() {
      if (this.isVisible) {
        // 半透明背景
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('rgba(0, 0, 0, 0.9)')
          .onClick(() => { this.dismiss() })

        // 图片内容区域
        Column({ space: 0 }) {
          // 顶部工具栏
          Row({ space: 12 }) {
            // 关闭按钮
            SymbolGlyph($r('sys.symbol.xmark'))
              .fontSize(20)
              .fontColor([Theme.TextPrimary])
              .onClick(() => { this.dismiss() })

            Blank()

            // 文件名
            if (this.fileName) {
              Text(this.fileName)
                .fontSize(14)
                .fontColor(Theme.TextSecondary)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)
            }

            // 保存按钮
            Text('⬇')
              .fontSize(18)
              .fontColor(Theme.AccentBlue)
              .onClick(() => { this.saveToGallery() })
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 12, bottom: 12 })
          .alignItems(VerticalAlign.Center)

          // 图片展示区
          Scroll() {
            Column() {
              Image(this.imageSrc)
                .width('100%')
                .objectFit(ImageFit.Contain)
                .constraintSize({ maxHeight: '80%' })
                // 缩放变换
                .scale({ x: this.scaleValue, y: this.scaleValue })
            }
            .width('100%')
            .height('100%')
            .justifyContent(FlexAlign.Center)
          }
          .width('100%')
          .layoutWeight(1)
          .scale({ y: Math.max(0.3, 1 - Math.abs(this.offsetY) / 600) })
          .translate({ y: this.offsetY })

          // 底部信息
          if (this.imageAlt) {
            Text(this.imageAlt)
              .fontSize(12)
              .fontColor(Theme.TextTertiary)
              .textAlign(TextAlign.Center)
              .width('100%')
              .padding(12)
          }

          // 保存结果
          if (this.saveResult) {
            Text(this.saveResult)
              .fontSize(12)
              .fontColor(this.saveResult.includes('成功') ? Theme.SuccessColor : Theme.ErrorColor)
              .textAlign(TextAlign.Center)
              .width('100%')
              .padding({ bottom: 8 })
          }
        }
        .width('100%')
        .height('100%')

        // 缩放手势
        .gesture(
          PinchGesture({ fingers: 2 })
            .onActionStart(() => {
              this.isPinching = true
            })
            .onActionUpdate((event: GestureEvent) => {
              if (event.scale) {
                this.scaleValue = Math.max(0.5, Math.min(4.0, event.scale))
              }
            })
            .onActionEnd(() => {
              this.isPinching = false
              // 如果缩放超出范围，回弹到边界
              if (this.scaleValue < 1.0) {
                this.scaleValue = 1.0
              } else if (this.scaleValue > 3.0) {
                this.scaleValue = 3.0
              }
            })
        )
        // 滑动关闭手势（仅在未缩放时生效）
        .gesture(
          PanGesture({ direction: PanDirection.Vertical })
            .onActionStart((event: GestureEvent) => {
              // 缩放中或已缩放时禁用滑动关闭
              if (this.isPinching || this.scaleValue !== 1.0) {
                return
              }
              this.dragStartY = event.offsetY || 0
            })
            .onActionUpdate((event: GestureEvent) => {
              // 缩放中或已缩放时禁用滑动关闭
              if (this.isPinching || this.scaleValue !== 1.0) {
                this.offsetY = 0
                return
              }
              this.offsetY = (event.offsetY || 0) - this.dragStartY
            })
            .onActionEnd(() => {
              // 缩放中或已缩放时忽略
              if (this.isPinching || this.scaleValue !== 1.0) {
                this.offsetY = 0
                return
              }
              if (Math.abs(this.offsetY) > 150) {
                this.dismiss()
              } else {
                animateTo({ duration: 250, curve: Curve.FastOutSlowIn }, () => {
                  this.offsetY = 0
                })
              }
            })
        )
      }
    }
    .width('100%')
    .height('100%')
    .clip(true)
    .transition(TransitionEffect.OPACITY.animation({ duration: 250 }))
  }

  /**
   * 打开预览
   */
  show(src: string, alt: string = '', fileName: string = ''): void {
    this.imageSrc = src
    this.imageAlt = alt
    this.fileName = fileName
    this.scaleValue = 1.0
    this.offsetY = 0
    this.saveResult = ''
    this.isPinching = false
    this.isVisible = true
  }

  /**
   * 关闭预览
   */
  dismiss(): void {
    this.isVisible = false
    this.scaleValue = 1.0
    this.offsetY = 0
    this.isPinching = false
  }

  /**
   * 保存到相册（下载到应用缓存）
   */
  private async saveToGallery(): Promise<void> {
    if (this.isSaving) return
    this.isSaving = true
    this.saveResult = ''

    try {
      const fileName = this.fileName || 'image_' + Date.now() + '.png'
      const ext = fileName.indexOf('.') >= 0 ? '' : '.png'
      await downloadService.downloadImage(this.imageSrc, fileName + ext)
      this.saveResult = '已保存到相册'
      setTimeout(() => { this.saveResult = '' }, 2000)
    } catch (e) {
      console.error('[ImagePreview] Save error: ' + e)
      this.saveResult = '保存失败'
      setTimeout(() => { this.saveResult = '' }, 2000)
    }

    this.isSaving = false
  }
}
