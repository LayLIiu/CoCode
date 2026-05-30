/**
 * 图片懒加载组件
 * 支持占位图、渐进式加载、错误处理
 */

import { Theme } from '../common/Theme'

export interface LazyImageProps {
  src: string
  width: number | string
  height: number | string
  placeholder?: Resource
  errorPlaceholder?: Resource
  borderRadius?: number
  objectFit?: ImageFit
  fadeIn?: boolean
  fadeInDuration?: number
  onLoad?: () => void
  onError?: (error: Error) => void
}

@Component
export struct LazyImage {
  @Prop src: string = ''
  @Prop width: number | string = '100%'
  @Prop height: number | string = '100%'
  @Prop placeholder: Resource = $r('app.media.ic_placeholder')
  @Prop errorPlaceholder: Resource = $r('app.media.ic_error')
  @Prop borderRadius: number = 0
  @Prop objectFit: ImageFit = ImageFit.Cover
  @Prop fadeIn: boolean = true
  @Prop fadeInDuration: number = 300

  @State isLoading: boolean = true
  @State hasError: boolean = false
  @State opacity: number = 0

  private intersectionObserver: IntersectionObserver | null = null

  build() {
    Stack() {
      if (this.isLoading && !this.hasError) {
        // 占位图
        Image(this.placeholder)
          .width(this.width)
          .height(this.height)
          .borderRadius(this.borderRadius)
          .objectFit(this.objectFit)
      }

      if (this.hasError) {
        // 错误占位图
        Image(this.errorPlaceholder)
          .width(this.width)
          .height(this.height)
          .borderRadius(this.borderRadius)
          .objectFit(this.objectFit)
      }

      // 实际图片
      Image(this.src)
        .width(this.width)
        .height(this.height)
        .borderRadius(this.borderRadius)
        .objectFit(this.objectFit)
        .opacity(this.fadeIn && this.isLoading ? 0 : 1)
        .onComplete(() => {
          this.isLoading = false
          this.hasError = false
          
          if (this.fadeIn) {
            // 渐入动画
            animateTo({
              duration: this.fadeInDuration,
              curve: Curve.EaseInOut
            }, () => {
              this.opacity = 1
            })
          }
        })
        .onError(() => {
          this.isLoading = false
          this.hasError = true
        })
    }
    .width(this.width)
    .height(this.height)
  }
}

/**
 * 图片网格组件（支持懒加载）
 */
@Component
export struct LazyImageGrid {
  @Prop images: string[] = []
  @Prop columns: number = 3
  @Prop spacing: number = 4
  @Prop imageHeight: number = 120
  @Prop borderRadius: number = 8

  build() {
    Grid() {
      ForEach(this.images, (image: string, index: number) => {
        GridItem() {
          LazyImage({
            src: image,
            width: '100%',
            height: this.imageHeight,
            borderRadius: this.borderRadius,
            objectFit: ImageFit.Cover
          })
        }
      }, (image: string, index: number) => `image-${index}`)
    }
    .columnsTemplate(`1fr `.repeat(this.columns).trim())
    .rowsGap(this.spacing)
    .columnsGap(this.spacing)
    .width('100%')
  }
}

/**
 * 头像组件（支持懒加载和占位符）
 */
@Component
export struct LazyAvatar {
  @Prop src: string = ''
  @Prop name: string = ''
  @Prop size: number = 40
  @State showPlaceholder: boolean = true

  build() {
    Stack() {
      if (this.showPlaceholder || !this.src) {
        // 名字首字母占位符
        Text(this.getInitials())
          .fontSize(this.size * 0.4)
          .fontColor(Color.White)
          .fontWeight(FontWeight.Medium)
          .backgroundColor(this.getColorFromName())
          .width(this.size)
          .height(this.size)
          .borderRadius(this.size / 2)
          .textAlign(TextAlign.Center)
      }

      if (this.src) {
        Image(this.src)
          .width(this.size)
          .height(this.size)
          .borderRadius(this.size / 2)
          .objectFit(ImageFit.Cover)
          .onComplete(() => {
            this.showPlaceholder = false
          })
          .onError(() => {
            this.showPlaceholder = true
          })
      }
    }
    .width(this.size)
    .height(this.size)
  }

  private getInitials(): string {
    if (!this.name) return '?'
    const parts = this.name.split(' ')
    if (parts.length >= 2) {
      return (parts[0][0] + parts[1][0]).toUpperCase()
    }
    return this.name.substring(0, 2).toUpperCase()
  }

  private getColorFromName(): string {
    const colors = [
      Theme.AccentBlue,
      Theme.AccentGreen,
      Theme.AccentOrange,
      Theme.AccentPurple
    ]
    let hash = 0
    for (let i = 0; i < this.name.length; i++) {
      hash = this.name.charCodeAt(i) + ((hash << 5) - hash)
    }
    return colors[Math.abs(hash) % colors.length]
  }
}
