/**
 * 深色主题配置 - 鸿蒙6.1.0液态玻璃风格
 */

export class Theme {
  // 背景色
  static readonly BackgroundPrimary: string = '#000000'
  static readonly BackgroundSecondary: string = 'rgba(28, 28, 30, 0.85)'
  static readonly BackgroundTertiary: string = 'rgba(44, 44, 46, 0.9)'

  // 文字颜色
  static readonly TextPrimary: string = '#FFFFFF'
  static readonly TextSecondary: string = '#8E8E93'
  static readonly TextTertiary: string = '#636366'

  // 强调色
  static readonly AccentBlue: string = '#0A84FF'
  static readonly AccentPurple: string = '#BF5AF2'
  static readonly AccentOrange: string = '#FF9F0A'
  static readonly AccentGreen: string = '#30D158'

  // 主题色
  static readonly PrimaryColor: string = '#0A84FF'
  static readonly PrimaryColorLight: string = 'rgba(10, 132, 255, 0.15)'
  static readonly TextOnPrimary: string = '#FFFFFF'
  static readonly ErrorColor: string = '#FF3B30'
  static readonly WarningColor: string = '#FF9F0A'
  static readonly SuccessColor: string = '#30D158'

  // 边框颜色
  static readonly Border: string = 'rgba(255, 255, 255, 0.1)'

  // 液态玻璃效果配置
  static readonly LiquidGlassBackground: string = 'rgba(255, 255, 255, 0.05)'
  static readonly LiquidGlassBackgroundLight: string = 'rgba(255, 255, 255, 0.08)'
  static readonly LiquidGlassBorderColor: string = 'rgba(255, 255, 255, 0.15)'
  static readonly LiquidGlassBorderWidth: number = 0.5
  static readonly LiquidGlassShadowRadius: number = 20
  static readonly LiquidGlassShadowColor: string = 'rgba(0, 0, 0, 0.3)'

  // Tab栏风格液态玻璃效果（胶囊悬浮样式）
  static readonly GlassBackground: string = 'rgba(255, 255, 255, 0.08)'
  static readonly GlassBorder: string = 'rgba(255, 255, 255, 0.15)'

  // 背景渐变颜色
  static readonly BackgroundGradientStart: string = '#0a0a0a'
  static readonly BackgroundGradientMiddle: string = '#1a1a1a'
  static readonly BackgroundGradientEnd: string = '#0a0a0a'

  // 圆角
  static readonly RadiusSmall: number = 8
  static readonly RadiusMedium: number = 12
  static readonly RadiusLarge: number = 16
  static readonly RadiusXLarge: number = 20

  // 间距
  static readonly SpacingXS: number = 4
  static readonly SpacingSM: number = 8
  static readonly SpacingMD: number = 12
  static readonly SpacingLG: number = 16
  static readonly SpacingXL: number = 20
  static readonly SpacingXXL: number = 24

  // 字号
  static readonly FontTitle: number = 28
  static readonly FontHeading: number = 18
  static readonly FontBody: number = 16
  static readonly FontCaption: number = 14
  static readonly FontTiny: number = 12

  // 动画时长
  static readonly DurationFast: number = 150
  static readonly DurationNormal: number = 250
  static readonly DurationSlow: number = 350
}
