/**
 * 聊天控制栏组件 - 参考 codex-relay ChatControls
 * 包含权限模式切换、上下文使用进度环
 */

import { curves } from '@kit.ArkUI'
import { Theme } from '../common/Theme'
import { PermissionMode, getPermissionModeDisplayName, getPermissionModeDescription } from '../models/Models'

// 权限模式选项数据
interface PermissionOption {
  mode: PermissionMode
  icon: Resource
  iconBgColor: string
  iconTintColor: string
  label: string
  subtitle: string
}

const PERMISSION_OPTIONS: PermissionOption[] = [
  {
    mode: PermissionMode.DEFAULT,
    icon: $r('sys.symbol.questionmark'),
    iconBgColor: 'rgba(255, 255, 255, 0.08)',
    iconTintColor: 'rgba(243, 244, 246, 0.72)',
    label: '询问权限',
    subtitle: '请求时确定文件编辑和高风险命令'
  },
  {
    mode: PermissionMode.ACCEPT_EDITS,
    icon: $r('sys.symbol.checkmark'),
    iconBgColor: 'rgba(125, 211, 252, 0.1)',
    iconTintColor: 'rgba(125, 211, 252, 0.76)',
    label: '自动编辑',
    subtitle: '无需询问即可写入磁盘'
  },
  {
    mode: PermissionMode.PLAN,
    icon: $r('sys.symbol.doc_text'),
    iconBgColor: 'rgba(175, 82, 222, 0.1)',
    iconTintColor: 'rgba(175, 82, 222, 0.76)',
    label: '计划模式',
    subtitle: '仅架构和推理，不操作文件'
  },
  {
    mode: PermissionMode.BYPASS_PERMISSIONS,
    icon: $r('sys.symbol.bolt_fill'),
    iconBgColor: 'rgba(255, 138, 69, 0.1)',
    iconTintColor: 'rgba(255, 171, 116, 0.76)',
    label: '完全访问',
    subtitle: '对 shell 和文件系统完全工具访问'
  }
]

@Component
export struct ChatControls {
  // 当前权限模式
  @Prop currentMode: PermissionMode = PermissionMode.DEFAULT
  // 上下文使用百分比（0-100）
  @Prop contextUsage: number = 0
  // 是否禁用
  @Prop disabled: boolean = false

  // 事件回调
  onModeChange: (mode: PermissionMode) => void = () => {}
  onContextTap: () => void = () => {}

  // 内部状态
  @State showPermSheet: boolean = false
  @State permButtonScale: number = 1.0
  @State contextButtonScale: number = 1.0

  private getCurrentOption(): PermissionOption {
    return PERMISSION_OPTIONS.find(opt => opt.mode === this.currentMode) || PERMISSION_OPTIONS[0]
  }

  private getRingColor(): ResourceColor {
    if (this.contextUsage > 80) return Theme.ErrorColor
    if (this.contextUsage > 50) return Theme.WarningColor
    return Theme.SuccessColor
  }

  private springPressPerm(): void {
    animateTo({ curve: curves.responsiveSpringMotion(0.5, 0.4) }, () => {
      this.permButtonScale = 0.92
    })
    setTimeout(() => {
      animateTo({ curve: curves.responsiveSpringMotion(0.4, 0.6) }, () => {
        this.permButtonScale = 1.0
      })
    }, 80)
  }

  private springPressContext(): void {
    animateTo({ curve: curves.responsiveSpringMotion(0.5, 0.4) }, () => {
      this.contextButtonScale = 0.92
    })
    setTimeout(() => {
      animateTo({ curve: curves.responsiveSpringMotion(0.4, 0.6) }, () => {
        this.contextButtonScale = 1.0
      })
    }, 80)
  }

  build() {
    Row({ space: 6 }) {
      // 权限模式胶囊按钮
      Row({ space: 4 }) {
        // 图标
        Row() {
          SymbolGlyph(this.getCurrentOption().icon)
            .fontSize(10)
            .fontColor([this.getCurrentOption().iconTintColor])
        }
        .width(14)
        .height(14)
        .backgroundColor(this.getCurrentOption().iconBgColor)
        .borderRadius(4)
        .justifyContent(FlexAlign.Center)

        // 标签
        Text(this.getCurrentOption().label)
          .fontSize(10)
          .fontColor(this.getCurrentOption().iconTintColor)
          .maxLines(1)
      }
      .padding({ left: 7, right: 7, top: 3, bottom: 3 })
      .backgroundColor('rgba(255, 255, 255, 0.04)')
      .borderRadius(10)
      .border({ width: 0.5, color: 'rgba(255, 255, 255, 0.08)' })
      .scale({ x: this.permButtonScale, y: this.permButtonScale })
      .animation({ duration: 150, curve: Curve.EaseInOut })
      .onClick(() => {
        if (this.disabled) return
        this.springPressPerm()
        this.showPermSheet = true
      })

      // 上下文使用环形进度
      Row() {
        Stack() {
          // 背景环
          Circle()
            .width(16)
            .height(16)
            .fill('transparent')
            .stroke('rgba(255, 255, 255, 0.1)', { width: 2 })

          // 进度环
          Progress({ value: this.contextUsage, total: 100, type: ProgressType.Ring })
            .width(16)
            .height(16)
            .color(this.getRingColor())
            .style({ strokeWidth: 2 })
        }
        .width(16)
        .height(16)
      }
      .width(24)
      .height(20)
      .justifyContent(FlexAlign.Center)
      .backgroundColor('rgba(255, 255, 255, 0.04)')
      .borderRadius(10)
      .border({ width: 0.5, color: 'rgba(255, 255, 255, 0.08)' })
      .scale({ x: this.contextButtonScale, y: this.contextButtonScale })
      .animation({ duration: 150, curve: Curve.EaseInOut })
      .onClick(() => {
        if (this.disabled) return
        this.springPressContext()
        this.onContextTap()
      })
    }
    .height(26)
    .bindSheet($$this.showPermSheet, this.PermissionSheet(), {
      height: 380,
      backgroundColor: Theme.BackgroundSecondary,
      dragBar: true,
      backgroundColor: Theme.BackgroundPrimary,
      onDisappear: () => {
        this.showPermSheet = false
      }
    })
  }

  @Builder
  PermissionSheet() {
    Column({ space: 0 }) {
      // 标题
      Column({ space: 4 }) {
        Text('权限模式')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.TextPrimary)

        Text('设置 AI 可以自动执行的操作范围')
          .fontSize(12)
          .fontColor(Theme.TextSecondary)
      }
      .width('100%')
      .padding({ top: 8, bottom: 16 })

      // 选项列表
      ForEach(PERMISSION_OPTIONS, (opt: PermissionOption) => {
        this.PermissionOptionRow(opt)
      }, (opt: PermissionOption) => opt.mode)
    }
    .width('100%')
    .padding({ left: 16, right: 16, bottom: 32 })
  }

  @Builder
  PermissionOptionRow(opt: PermissionOption) {
    Row({ space: 12 }) {
      // 图标
      Row() {
        SymbolGlyph(opt.icon)
          .fontSize(14)
          .fontColor([opt.iconTintColor])
      }
      .width(28)
      .height(28)
      .backgroundColor(opt.iconBgColor)
      .borderRadius(8)
      .justifyContent(FlexAlign.Center)

      // 文本
      Column({ space: 2 }) {
        Text(opt.label)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.currentMode === opt.mode ? opt.iconTintColor : Theme.TextPrimary)

        Text(opt.subtitle)
          .fontSize(11)
          .fontColor(Theme.TextTertiary)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      // 选中指示器
      if (this.currentMode === opt.mode) {
        Row() {
          SymbolGlyph($r('sys.symbol.checkmark'))
            .fontSize(10)
            .fontColor([Theme.TextOnPrimary])
        }
        .width(18)
        .height(18)
        .borderRadius(9)
        .backgroundColor(opt.iconTintColor)
        .justifyContent(FlexAlign.Center)
      } else {
        Row()
          .width(18)
          .height(18)
          .borderRadius(9)
          .border({ width: 1.5, color: 'rgba(255, 255, 255, 0.15)' })
      }
    }
    .width('100%')
    .padding({ top: 10, bottom: 10, left: 12, right: 12 })
    .backgroundColor(this.currentMode === opt.mode ? 'rgba(255, 255, 255, 0.03)' : 'transparent')
    .borderRadius(10)
    .onClick(() => {
      if (this.currentMode !== opt.mode) {
        this.onModeChange(opt.mode)
        this.showPermSheet = false
      }
    })
  }
}
