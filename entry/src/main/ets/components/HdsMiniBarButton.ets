import { hdsMaterial, HdsTabs } from '@kit.UIDesignKit';

/**
 * HdsMiniBarButton 浮动迷你栏按钮组件
 * 基于 HdsTabs 的沉浸光感浮动按钮，支持全方位自定义配置
 */
@ComponentV2
export struct HdsMiniBarButton {
  // ==================== 尺寸参数 ====================

  /**
   * 按钮栏宽度
   * @defaults 50
   */
  @Param barWidth: number = 50;

  /**
   * 按钮栏高度
   * @defaults 50
   */
  @Param barHeight: number = 50;

  /**
   * 容器内边距（防止光效被裁切）
   * @defaults 12
   */
  @Param contentPadding: number = 12;

  /**
   * 容器尺寸，优先使用此值，未设置时自动计算
   * @defaults undefined
   */
  @Param containerSize: SizeOptions | undefined = undefined;

  // ==================== 图标参数 ====================

  /**
   * 图标资源（SymbolGlyph 资源类型）
   * @defaults $r('sys.symbol.plus')
   */
  @Param iconResource: Resource = $r('sys.symbol.plus');

  /**
   * 图标大小
   * @defaults 27
   */
  @Param iconSize: number = 27;

  /**
   * 图标颜色数组（支持渐变效果）
   * @defaults [Color.Gray]
   */
  @Param iconColor: ResourceColor[] = [Color.Gray];

  // ==================== 浮动样式参数 ====================

  /**
   * 遮罩颜色
   * @defaults Color.Transparent
   */
  @Param maskColor: ResourceColor = Color.Transparent;

  /**
   * 按钮栏底部边距
   * @defaults 8
   */
  @Param barBottomMargin: number = 8;

  /**
   * 材质类型（沉浸式效果）
   * @defaults hdsMaterial.MaterialType.IMMERSIVE
   */
  @Param materialType: hdsMaterial.MaterialType = hdsMaterial.MaterialType.IMMERSIVE;

  /**
   * 材质级别
   * @defaults hdsMaterial.MaterialLevel.ADAPTIVE
   */
  @Param materialLevel: hdsMaterial.MaterialLevel = hdsMaterial.MaterialLevel.ADAPTIVE;

  /**
   * 是否启用系统材质效果（沉浸光感）
   * 若在鸿蒙 6.1 出现异常阴影，可设为 false 关闭材质效果
   * @defaults true
   */
  @Param enableMaterialEffect: boolean = true;

  // ==================== 布局参数 ====================

  /**
   * 按钮栏位置
   * @defaults BarPosition.End
   */
  @Param barPosition: BarPosition = BarPosition.End;

  /**
   * 按钮栏是否与内容重叠
   * @defaults true
   */
  @Param barOverlap: boolean = true;

  // ==================== 事件回调 ====================

  /**
   * 按钮点击事件回调
   * @defaults undefined
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
   * 高度额外增加以容纳底部形变效果
   * @returns 容器尺寸配置
   */
  private getComputedContainerSize(): SizeOptions {
    if (this.containerSize !== undefined) {
      return this.containerSize;
    }
    return {
      width: this.barWidth + this.contentPadding * 4,
      height: this.barHeight + this.contentPadding * 5  // 高度额外增加，给底部更多空间
    };
  }

  // ==================== UI 构建 ====================

  /**
   * 构建组件 UI
   * 使用 Stack 让点击区域和视觉区域一致
   */
  build() {
    Stack() {
      // 液态玻璃效果层
      HdsTabs() {
        TabContent()
          .tabBar(this.buttonContent())
      }
      .barWidth(this.barWidth)
      .barHeight(this.barHeight)
      .barOverlap(this.barOverlap)
      .barPosition(this.barPosition)
      .scrollable(false)
      .animationDuration(0)
      .barFloatingStyle({
        gradientMask: {
          maskColor: 'rgba(0,0,0,0)'
        },
        barBottomMargin: this.barBottomMargin,
        systemMaterialEffect: this.enableMaterialEffect ? {
          materialType: this.materialType,
          materialLevel: this.materialLevel
        } : undefined
      })
      .backgroundColor(Color.Transparent)
      .border({ width: 0 })
      .shadow({ radius: 0 })
      .hitTestBehavior(HitTestMode.Transparent)  // 让点击穿透到外层

      // 透明点击层 - 覆盖整个按钮区域
      Column()
        .width(this.barWidth)
        .height(this.barHeight)
        .backgroundColor(Color.Transparent)
        .hitTestBehavior(HitTestMode.Block)  // 阻止点击穿透，确保接收所有点击
        .onClick(() => {
          if (this.onButtonClick) {
            this.onButtonClick();
          }
        })
    }
    .size(this.getComputedContainerSize())
    .alignContent(Alignment.Center)
    .backgroundColor(Color.Transparent)
    .border({ width: 0 })
    .shadow({ radius: 0 })
    .clip(false)
    .onClick(() => {
      // 外层 Stack 也响应点击，双重保障
      if (this.onButtonClick) {
        this.onButtonClick();
      }
    })
  }
}
