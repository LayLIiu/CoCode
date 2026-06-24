import { hdsMaterial } from '@kit.UIDesignKit';
import { HdsLiquidGlassContainer } from './HdsLiquidGlassContainer';

/**
 * HdsMiniBarButton 浮动迷你栏按钮组件
 * 基于 HdsTabs 的沉浸光感浮动按钮，支持全方位自定义配置
 */
@ComponentV2
export struct HdsMiniBarButton {
  // ==================== 尺寸参数 ====================

  /**
   * 按钮栏宽度
   * @default 50
   */
  @Param barWidth: number = 50;

  /**
   * 按钮栏高度
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
   * 横向溢出缓冲，宿主容器会比按钮栏左右各多出该值，防止液态玻璃光效被裁切
   * @default 32
   */
  @Param horizontalOverflow: number = 32;

  /**
   * 纵向溢出缓冲，宿主容器会比按钮栏上下各多出该值，防止液态玻璃光效被裁切
   * @default 12
   */
  @Param verticalOverflow: number = 12;

  /**
   * 容器尺寸，优先使用此值，未设置时自动计算
   * @default undefined
   */
  @Param containerSize: SizeOptions | undefined = undefined;

  // ==================== 图标参数 ====================

  /**
   * 图标资源（SymbolGlyph 资源类型）
   * @default $r('sys.symbol.plus')
   */
  @Param iconResource: Resource = $r('sys.symbol.plus');

  /**
   * 图标大小
   * @default 27
   */
  @Param iconSize: number = 27;

  /**
   * 图标颜色数组（支持渐变效果）
   * @default [Color.Gray]
   */
  @Param iconColor: ResourceColor[] = [Color.Gray];

  // ==================== 浮动样式参数 ====================

  /**
   * 遮罩颜色
   * @default Color.Transparent
   */
  @Param maskColor: ResourceColor = Color.Transparent;

  /**
   * 按钮栏底部边距
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
   * 按钮栏位置
   * @default BarPosition.End
   */
  @Param barPosition: BarPosition = BarPosition.End;

  /**
   * 按钮栏是否与内容重叠
   * @default true
   */
  @Param barOverlap: boolean = true;

  // ==================== 事件回调 ====================

  /**
   * 按钮点击事件回调
   * @default undefined
   */
  @Param onButtonClick: (() => void) | undefined = undefined;

  // ==================== 构建函数 ====================

  /**
   * 默认按钮图标构建函数
   * 使用 SymbolGlyph 渲染默认图标
   */
  @Builder
  defaultButtonBuilder() {
    SymbolGlyph(this.iconResource)
      .fontSize(this.iconSize)
      .fontColor(this.iconColor)
  }

  /**
   * 自定义内容槽位
   * 默认使用图标构建函数，可通过尾随闭包自定义内容
   */
  @BuilderParam buttonContent: () => void = this.defaultButtonBuilder;

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
   * 构建组件 UI
   * 复用通用液态玻璃容器实现浮动按钮效果
   */
  build() {
    HdsLiquidGlassContainer({
      barWidth: this.barWidth,
      barHeight: this.barHeight,
      contentPadding: this.contentPadding,
      horizontalOverflow: this.horizontalOverflow,
      verticalOverflow: this.verticalOverflow,
      containerSize: this.getComputedContainerSize(),
      maskColor: this.maskColor,
      barBottomMargin: this.barBottomMargin,
      materialType: this.materialType,
      materialLevel: this.materialLevel,
      useCustomCornerRadius: this.useCustomCornerRadius,
      cornerRadius: this.cornerRadius,
      customGlassBorderColor: this.customGlassBorderColor,
      customGlassBorderWidth: this.customGlassBorderWidth,
      barPosition: this.barPosition,
      barOverlap: this.barOverlap,
      onGlassClick: this.onButtonClick
    }) {
      this.buttonContent()
    }
  }
}
