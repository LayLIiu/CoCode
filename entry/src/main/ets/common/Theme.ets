/**
 * 深色主题配置
 */
export class Theme {
  // 背景色 - 华为沉浸光感液态玻璃风格
  static readonly BackgroundPrimary: string = '#000000'
  static readonly BackgroundSecondary: string = 'rgba(28, 28, 30, 0.85)'  // 磨砂玻璃背景
  static readonly BackgroundTertiary: string = 'rgba(44, 44, 46, 0.9)'
  static readonly GlassBackground: string = 'rgba(255, 255, 255, 0.05)'  // 液态玻璃效果
  static readonly GlassBorder: string = 'rgba(255, 255, 255, 0.1)'  // 玻璃边框
  
  // 文字颜色
  static readonly TextPrimary: string = '#FFFFFF'
  static readonly TextSecondary: string = '#8E8E93'
  static readonly TextTertiary: string = '#636366'
  
  // 强调色
  static readonly AccentBlue: string = '#0A84FF'
  static readonly AccentPurple: string = '#BF5AF2'
  static readonly AccentOrange: string = '#FF9F0A'
  static readonly AccentGreen: string = '#30D158'
  
  // 渐变色
  static readonly GradientPurple: LinearGradient = new LinearGradient([
    { color: '#5E5CE6', offset: 0 },
    { color: '#BF5AF2', offset: 1 }
  ])
  
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
