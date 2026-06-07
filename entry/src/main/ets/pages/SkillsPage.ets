/**
 * 技能管理页面 - 管理 Claude 的自定义技能
 * 已接入真实 API：/api/skills
 */

import { Theme } from '../common/Theme'
import { apiService, SkillMeta } from '../services/APIService'
import { HdsNavigation, HdsNavigationTitleMode, ScrollEffectType } from '@hms.hds.hdsBaseComponent'
import { hdsMaterial } from '@hms.hds.hdsMaterial'

interface SkillItem {
  id: string
  name: string
  displayName: string
  description: string
  source: string
  userInvocable: boolean
  enabled: boolean
  version: string
}

@Entry
@Component
struct SkillsPage {
  @State skills: SkillItem[] = []
  @State isLoading: boolean = false

  private scroller: Scroller = new Scroller()

  aboutToAppear(): void {
    this.loadSkills()
  }

  private async loadSkills(): Promise<void> {
    this.isLoading = true
    try {
      const response = await apiService.getSkills()
      if (response.skills && response.skills.length > 0) {
        const items: SkillItem[] = []
        for (let i = 0; i < response.skills.length; i++) {
          const meta: SkillMeta = response.skills[i]
          const item: SkillItem = {
            id: meta.name,
            name: meta.displayName || meta.name,
            displayName: meta.displayName || '',
            description: meta.description || '暂无描述',
            source: meta.source,
            userInvocable: meta.userInvocable,
            enabled: true,
            version: meta.version || ''
          }
          items.push(item)
        }
        this.skills = items
      } else {
        this.skills = []
      }
    } catch (e) {
      console.error('[SkillsPage] Failed to load skills:', e)
    }
    this.isLoading = false
  }

  private toggleSkill(id: string, enabled: boolean): void {
    const idx = this.skills.findIndex(s => s.id === id)
    if (idx >= 0) {
      this.skills[idx].enabled = enabled
      this.skills = [...this.skills]
    }
    // 注意：服务端 skills 没有独立的 enable/disable 端点
    // 安装/卸载通过 POST /api/skills/install 和 POST /api/skills/uninstall 操作
  }

  private getSourceLabel(source: string): string {
    switch (source) {
      case 'user': return '用户'
      case 'project': return '项目'
      case 'plugin': return '插件'
      default: return source
    }
  }

  build() {
    Stack() {
      HdsNavigation() {
        List({ space: Theme.SpacingMD, scroller: this.scroller }) {
          ListItem() {
            Row().width('100%').height(100)
          }

          ListItem() {
            this.SkillsOverview()
          }

          ListItem() {
            Column({ space: Theme.SpacingSM }) {
              Text('自定义技能')
                .fontSize(Theme.FontCaption)
                .fontWeight(FontWeight.Medium)
                .fontColor(Theme.TextSecondary)
                .width('100%')

              if (this.isLoading) {
                Row() {
                  LoadingProgress()
                    .width(24)
                    .height(24)
                    .color(Theme.PrimaryColor)
                }
                .width('100%')
                .height(80)
                .justifyContent(FlexAlign.Center)
              } else if (this.skills.length === 0) {
                Column() {
                  Text('暂无技能')
                    .fontSize(Theme.FontBody)
                    .fontColor(Theme.TextPrimary)

                  Text('可通过桌面端安装 Claude 技能后在手机上查看')
                    .fontSize(Theme.FontCaption)
                    .fontColor(Theme.TextSecondary)
                    .margin({ top: 4 })
                }
                .width('100%')
                .padding(Theme.SpacingMD)
                .backgroundColor(Theme.GlassBackground)
                .borderRadius(Theme.RadiusMedium)
                .border({ width: 0.5, color: Theme.GlassBorder })
                .shadow({ radius: Theme.LiquidGlassShadowRadius, color: Theme.LiquidGlassShadowColor, offsetX: 0, offsetY: 4 })
              } else {
                ForEach(this.skills, (skill: SkillItem) => {
                  Column({ space: 0 }) {
                    Row() {
                      Column({ space: 4 }) {
                        Text(skill.name)
                          .fontSize(Theme.FontBody)
                          .fontColor(Theme.TextPrimary)

                        Text(skill.description)
                          .fontSize(Theme.FontTiny)
                          .fontColor(Theme.TextSecondary)
                          .maxLines(2)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })

                        Row({ space: 6 }) {
                          Text(this.getSourceLabel(skill.source))
                            .fontSize(10)
                            .fontColor(Theme.TextTertiary)
                            .backgroundColor(Theme.BackgroundTertiary)
                            .borderRadius(4)
                            .padding({ left: 6, right: 6, top: 2, bottom: 2 })

                          if (skill.version) {
                            Text(`v${skill.version}`)
                              .fontSize(10)
                              .fontColor(Theme.TextTertiary)
                          }
                        }
                        .margin({ top: 4 })
                      }
                      .layoutWeight(1)
                      .alignItems(HorizontalAlign.Start)

                      Toggle({ type: ToggleType.Switch, isOn: skill.enabled })
                        .onChange((isOn: boolean) => {
                          this.toggleSkill(skill.id, isOn)
                        })
                    }
                    .width('100%')
                    .padding(Theme.SpacingMD)
                  }
                  .backgroundColor(Theme.GlassBackground)
                  .borderRadius(Theme.RadiusMedium)
                  .border({ width: 0.5, color: Theme.GlassBorder })
                  .shadow({ radius: Theme.LiquidGlassShadowRadius, color: Theme.LiquidGlassShadowColor, offsetX: 0, offsetY: 4 })
                }, (skill: SkillItem) => skill.id)
              }
            }
            .width('100%')
          }
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: Theme.SpacingLG, right: Theme.SpacingLG })
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        .clip(false)
      }
      .titleBar({
        content: {
          title: { mainTitle: '技能管理' },
        },
        style: {
          scrollEffectOpts: {
            enableScrollEffect: true,
            scrollEffectType: ScrollEffectType.GRADIENT_BLUR,
          },
          systemMaterialEffect: {
            materialType: hdsMaterial.MaterialType.ADAPTIVE,
            materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE,
          },
        },
        avoidLayoutSafeArea: true,
        enableComponentSafeArea: false,
      })
      .bindToScrollable([this.scroller])
      .titleMode(HdsNavigationTitleMode.MINI)
      .hideBackButton(false)
      .backgroundColor('#000000')
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  SkillsOverview() {
    Column({ space: 14 }) {
      Row() {
        Column({ space: 5 }) {
          Text('技能中心')
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .fontColor(Theme.TextPrimary)

          Text('管理 Claude 可调用的扩展能力')
            .fontSize(Theme.FontCaption)
            .fontColor(Theme.TextSecondary)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Row({ space: 6 }) {
          Row()
            .width(8)
            .height(8)
            .borderRadius(4)
            .backgroundColor(this.skills.length > 0 ? Theme.AccentGreen : Theme.TextTertiary)

          Text(this.skills.length > 0 ? '可用' : '暂无')
            .fontSize(Theme.FontTiny)
            .fontColor(this.skills.length > 0 ? Theme.AccentGreen : Theme.TextTertiary)
        }
        .padding({ left: 10, right: 10, top: 6, bottom: 6 })
        .backgroundColor(this.skills.length > 0 ? 'rgba(48, 209, 88, 0.14)' : 'rgba(255, 255, 255, 0.055)')
        .borderRadius(10)
      }
      .width('100%')

      Row({ space: 8 }) {
        this.SkillMetric('总数', this.skills.length.toString(), Theme.AccentBlue)
        this.SkillMetric('启用', this.getEnabledSkillCount().toString(), Theme.AccentGreen)
        this.SkillMetric('状态', this.isLoading ? '加载中' : '就绪', this.isLoading ? Theme.AccentOrange : Theme.AccentGreen)
      }
      .width('100%')
    }
    .width('100%')
    .padding(Theme.SpacingLG)
    .backgroundColor('rgba(255, 255, 255, 0.055)')
    .border({ width: 0.5, color: 'rgba(255, 255, 255, 0.09)' })
    .borderRadius(Theme.RadiusLarge)
  }

  private getEnabledSkillCount(): number {
    let count = 0
    for (let i = 0; i < this.skills.length; i++) {
      if (this.skills[i].enabled) count++
    }
    return count
  }

  @Builder
  SkillMetric(label: string, value: string, color: ResourceColor) {
    Column({ space: 4 }) {
      Text(label).fontSize(11).fontColor(Theme.TextTertiary)
      Text(value).fontSize(Theme.FontTiny).fontWeight(FontWeight.Medium).fontColor(color)
    }
    .layoutWeight(1)
    .height(50)
    .padding({ left: 10, right: 10 })
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Start)
    .backgroundColor('rgba(255, 255, 255, 0.045)')
    .borderRadius(10)
  }
}
