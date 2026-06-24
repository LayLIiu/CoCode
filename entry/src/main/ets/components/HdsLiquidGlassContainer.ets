import { hdsMaterial, HdsTabs } from '@kit.UIDesignKit';
/**
 * HdsLiquidGlassContainer 通用液态玻璃容器
 * 基于 HdsTabs 的 tabBar 承载任意自定义内容，并提供沉浸光感浮动材质效果
 */
@ComponentV2
export struct HdsLiquidGlassContainer {
  // ==================== 尺寸参数 ====================

  /**
   * 玻璃栏宽度
   * @default 50
   */
  @Param barWidth: number = 50;

  /**
   * 玻璃栏高度
   * @default 50
   */
  @Param barHeight: number = 50;

  /**
   * 兼容旧版本的容器内边距
   * 推荐新项目使用 horizontalOverflow / verticalOverflow 分别控制横向与纵向防裁切空间
   * @default 8
   */
  @Param contentPadding: number = 8;

  /**
   * 横向溢出缓冲，宿主容器会比玻璃栏左右各多出该值，防止液态玻璃光效被裁切
   * @default 32
   */
  @Param horizontalOverflow: number = 32;

  /**
   * 纵向溢出缓冲，宿主容器会比玻璃栏上下各多出该值，防止液态玻璃光效被裁切
   * @default 12
   */
  @Param verticalOverflow: number = 12;

  /**
   * 容器尺寸，优先使用此值，未设置时自动计算
   * @default undefined
   */
  @Param containerSize: SizeOptions | undefined = undefined;

  // ==================== 浮动样式参数 ====================

  /**
   * 遮罩颜色
   * @default Color.Transparent
   */
  @Param maskColor: ResourceColor = Color.Transparent;

  /**
   * 玻璃栏底部边距
   * @default 8
   */
  @Param barBottomMargin: number = 8;

  /**
   * 材质类型（沉浸式效果）
   * @default hdsMaterial.MaterialType.IMMERSIVE
   */
  @Param materialType: hdsMaterial.MaterialType = hdsMaterial.MaterialType.IMMERSIVE;

  /**
   * 材质级别
   * @default hdsMaterial.MaterialLevel.ADAPTIVE
   */
  @Param materialLevel: hdsMaterial.MaterialLevel = hdsMaterial.MaterialLevel.ADAPTIVE;

  /**
   * 是否启用自定义圆角模式
   * 开启后不再使用 HdsTabs 默认胶囊外形，改用可控圆角的矩形液态玻璃容器
   * @default false
   */
  @Param useCustomCornerRadius: boolean = false;

  /**
   * 自定义圆角，仅在 useCustomCornerRadius 为 true 时生效
   * @default 20
   */
  @Param cornerRadius: number = 20;

  /**
   * 自定义圆角模式下的边框颜色
   * @default '#65FFFFFF'
   */
  @Param customGlassBorderColor: ResourceColor = '#65FFFFFF';

  /**
   * 自定义圆角模式下的边框宽度
   * @default 0.5
   */
  @Param customGlassBorderWidth: number = 0.5;

  // ==================== 布局参数 ====================

  /**
   * 玻璃栏位置
   * @default BarPosition.End
   */
  @Param barPosition: BarPosition = BarPosition.End;

  /**
   * 玻璃栏是否与内容重叠
   * @default true
   */
  @Param barOverlap: boolean = true;

  // ==================== 事件回调 ====================

  /**
   * 玻璃栏点击事件回调
   * @default undefined
   */
  @Param onGlassClick: (() => void) | undefined = undefined;

  // ==================== 构建函数 ====================

  /**
   * 默认内容构建函数
   */
  @Builder
  defaultContentBuilder() {
    Blank()
  }

  /**
   * 自定义内容槽位，可传入 Button、TextInput、Row、Column 等任意 ArkUI 内容
   */
  @BuilderParam glassContent: () => void = this.defaultContentBuilder;

  // ==================== 私有方法 ====================

  /**
   * 计算容器尺寸
   * 如果已设置 containerSize 则直接使用，否则根据 barWidth、barHeight 和 padding 计算
   * @returns 容器尺寸配置
   */
  private getComputedContainerSize(): SizeOptions {
    if (this.containerSize !== undefined) {
      return this.containerSize;
    }
    return {
      width: this.barWidth + this.getHorizontalOverflow() * 2,
      height: this.barHeight + this.getVerticalOverflow() * 2
    };
  }

  /**
   * 计算横向防裁切缓冲
   * 保留 contentPadding 参与计算，兼容旧版本只配置 contentPadding 的写法
   */
  private getHorizontalOverflow(): number {
    return Math.max(this.horizontalOverflow, this.contentPadding);
  }

  /**
   * 计算纵向防裁切缓冲
   * 保留 contentPadding 参与计算，兼容旧版本只配置 contentPadding 的写法
   */
  private getVerticalOverflow(): number {
    return Math.max(this.verticalOverflow, this.contentPadding);
  }

  // ==================== UI 构建 ====================

  /**
   * 构建通用液态玻璃容器
   */
  build() {
    Row() {
      if (this.useCustomCornerRadius) {
        HdsTabs() {
          TabContent()
            .tabBar(this.glassContent())
        }
        .width(this.barWidth)
        .height(this.barHeight)
        .barWidth(this.barWidth)
        .barHeight(this.barHeight)
        .barOverlap(this.barOverlap)
        .barPosition(this.barPosition)
        .scrollable(false)
        .animationDuration(0)
        .barFloatingStyle({
          gradientMask: {
            maskColor: this.maskColor
          },
          barBottomMargin: 0,
          systemMaterialEffect: {
            materialType: this.materialType,
            materialLevel: this.materialLevel
          },
          barOpacity: 1
        })
        .backgroundColor(Color.Transparent)
        .border({ width: this.customGlassBorderWidth, color: this.customGlassBorderColor })
        .shadow({ radius: 0 })
        .borderRadius(this.cornerRadius)
        .onClick(() => {
          if (this.onGlassClick) {
            this.onGlassClick();
          }
        })
      } else {
        HdsTabs() {
          TabContent()
            .tabBar(this.glassContent())
        }
        .width(this.barWidth + this.getHorizontalOverflow() * 2)
        .height(this.barHeight + this.getVerticalOverflow() * 2)
        .padding({
          left: this.getHorizontalOverflow(),
          right: this.getHorizontalOverflow(),
          top: this.getVerticalOverflow(),
          bottom: this.getVerticalOverflow()
        })
        .barWidth(this.barWidth)
        .barHeight(this.barHeight)
        .barOverlap(this.barOverlap)
        .barPosition(this.barPosition)
        .scrollable(false)
        .animationDuration(0)
        .barFloatingStyle({
          gradientMask: {
            maskColor: this.maskColor
          },
          barBottomMargin: this.barBottomMargin,
          systemMaterialEffect: {
            materialType: this.materialType,
            materialLevel: this.materialLevel
          }
        })
        .onTabBarClick(() => {
          if (this.onGlassClick) {
            this.onGlassClick();
          }
        })
      }
    }
    .size(this.getComputedContainerSize())
    .backgroundColor(Color.Transparent)
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .clip(false)
  }
}
