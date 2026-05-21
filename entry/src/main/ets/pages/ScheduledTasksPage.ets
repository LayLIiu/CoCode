/**
 * 定时任务管理页面 - 创建、编辑、执行和监控定时任务
 * API：/api/scheduled-tasks/* (完整 CRUD + 执行记录)
 */

import { Theme } from '../common/Theme'
import { appState } from '../stores/AppState'
import { apiService, CronTask, TaskRunItem } from '../services/APIService'
import { HdsNavigation, HdsNavigationTitleMode, ScrollEffectType } from '@hms.hds.hdsBaseComponent'
import { hdsMaterial } from '@hms.hds.hdsMaterial'

@Entry
@Component
struct ScheduledTasksPage {
  @State tasks: CronTask[] = []
  @State isLoading: boolean = false
  @State errorMessage: string = ''
  @State showTaskSheet: boolean = false
  @State showRunsSheet: boolean = false
  @State isEditing: boolean = false

  // 编辑中的任务字段
  @State editName: string = ''
  @State editDescription: string = ''
  @State editCron: string = ''
  @State editPrompt: string = ''
  @State editEnabled: boolean = true
  @State editRecurring: boolean = true

  // 当前操作的任务 ID
  private editingTaskId: string = ''

  // 执行记录
  @State currentRuns: TaskRunItem[] = []
  @State runsTaskName: string = ''

  private scroller: Scroller = new Scroller()

  aboutToAppear(): void {
    this.loadTasks()
  }

  private async loadTasks(): Promise<void> {
    this.isLoading = true
    this.errorMessage = ''
    try {
      const response = await apiService.getScheduledTasks()
      if (response.tasks) {
        this.tasks = response.tasks
      }
    } catch (e) {
      console.error('[ScheduledTasksPage] Failed to load tasks:', e)
      this.errorMessage = '加载失败：' + (e as Error).message
    }
    this.isLoading = false
  }

  private openCreateSheet(): void {
    this.isEditing = false
    this.editingTaskId = ''
    this.editName = ''
    this.editDescription = ''
    this.editCron = ''
    this.editPrompt = ''
    this.editEnabled = true
    this.editRecurring = true
    this.showTaskSheet = true
  }

  private openEditSheet(task: CronTask): void {
    this.isEditing = true
    this.editingTaskId = task.id
    this.editName = task.name
    this.editDescription = task.description
    this.editCron = task.cron
    this.editPrompt = task.prompt
    this.editEnabled = task.enabled
    this.editRecurring = task.recurring
    this.showTaskSheet = true
  }

  private async saveTask(): Promise<void> {
    if (!this.editCron.trim()) {
      return
    }
    const data: Record<string, Object> = {}
    data['cron'] = this.editCron
    data['enabled'] = this.editEnabled
    data['recurring'] = this.editRecurring
    // 仅添加非空字段
    if (this.editName.trim()) {
      data['name'] = this.editName
    }
    if (this.editDescription.trim()) {
      data['description'] = this.editDescription
    }
    if (this.editPrompt.trim()) {
      data['prompt'] = this.editPrompt
    }

    try {
      if (this.isEditing && this.editingTaskId) {
        await apiService.updateScheduledTask(this.editingTaskId, data)
      } else {
        await apiService.createScheduledTask(data)
      }
      this.showTaskSheet = false
      this.loadTasks()
    } catch (e) {
      console.error('[ScheduledTasksPage] Failed to save task:', e)
    }
  }

  private async confirmDeleteTask(taskId: string, taskName: string): Promise<void> {
    AlertDialog.show({
      title: '删除任务',
      message: '确定要删除定时任务"' + taskName + '"吗？',
      primaryButton: {
        value: '取消',
        action: () => {}
      },
      secondaryButton: {
        value: '删除',
        fontColor: Theme.ErrorColor,
        action: async () => {
          try {
            await apiService.deleteScheduledTask(taskId)
            this.loadTasks()
          } catch (e) {
            console.error('[ScheduledTasksPage] Failed to delete task:', e)
          }
        }
      }
    })
  }

  private async executeTask(taskId: string): Promise<void> {
    try {
      await apiService.executeScheduledTask(taskId)
      AlertDialog.show({
        title: '执行已触发',
        message: '任务已提交执行，可在执行记录中查看进度。',
        primaryButton: {
          value: '好的',
          action: () => {}
        }
      })
    } catch (e) {
      console.error('[ScheduledTasksPage] Failed to execute task:', e)
    }
  }

  private async viewRuns(taskId: string, taskName: string): Promise<void> {
    this.runsTaskName = taskName
    this.currentRuns = []
    try {
      const response = await apiService.getScheduledTaskRuns(taskId)
      if (response.runs) {
        this.currentRuns = response.runs
      }
    } catch (e) {
      console.error('[ScheduledTasksPage] Failed to load runs:', e)
    }
    this.showRunsSheet = true
  }

  private formatCronDescription(cron: string): string {
    if (!cron) return '未设置'
    const parts = cron.split(' ')
    if (parts.length !== 5) return cron
    if (cron === '0 * * * *') return '每小时'
    if (cron === '0 9 * * *') return '每天 09:00'
    if (cron === '0 0 * * *') return '每天 00:00'
    if (cron === '0 0 * * 1') return '每周一'
    if (cron === '* * * * *') return '每分钟'
    return cron
  }

  private getRunStatusColor(status: string): ResourceColor {
    if (status === 'completed') return Theme.AccentGreen
    if (status === 'running') return Theme.AccentBlue
    if (status === 'failed') return Theme.ErrorColor
    if (status === 'timeout') return '#FF9500'
    return Theme.TextSecondary
  }

  private getRunStatusLabel(status: string): string {
    if (status === 'completed') return '已完成'
    if (status === 'running') return '运行中'
    if (status === 'failed') return '失败'
    if (status === 'timeout') return '超时'
    return status
  }

  build() {
    Stack() {
      HdsNavigation() {
        List({ space: Theme.SpacingMD, scroller: this.scroller }) {
          ListItem() {
            Row().width('100%').height(100)
          }

          if (this.isLoading) {
            ListItem() {
              Row() {
                LoadingProgress()
                  .width(24).height(24).color(Theme.PrimaryColor)
              }
              .width('100%')
              .height(120)
              .justifyContent(FlexAlign.Center)
            }
          } else if (this.errorMessage) {
            ListItem() {
              Column() {
                Text(this.errorMessage)
                  .fontSize(Theme.FontBody)
                  .fontColor(Theme.ErrorColor)

                Button() {
                  Text('重试')
                    .fontSize(Theme.FontBody)
                    .fontColor(Color.White)
                }
                .backgroundColor(Theme.PrimaryColor)
                .borderRadius(Theme.RadiusMedium)
                .height(36)
                .margin({ top: 12 })
                .onClick(() => {
                  this.loadTasks()
                })
              }
              .width('100%')
              .padding(Theme.SpacingMD)
              .backgroundColor(Theme.GlassBackground)
              .borderRadius(Theme.RadiusMedium)
              .border({ width: 0.5, color: Theme.GlassBorder })
            }
          } else if (this.tasks.length === 0) {
            ListItem() {
              Column() {
                Text('暂无定时任务')
                  .fontSize(Theme.FontBody)
                  .fontColor(Theme.TextSecondary)

                Text('点击右下角按钮创建新任务')
                  .fontSize(Theme.FontCaption)
                  .fontColor(Theme.TextTertiary)
                  .margin({ top: 4 })
              }
              .width('100%')
              .padding(Theme.SpacingXL)
              .backgroundColor(Theme.GlassBackground)
              .borderRadius(Theme.RadiusMedium)
              .border({ width: 0.5, color: Theme.GlassBorder })
              .alignItems(HorizontalAlign.Center)
            }
          } else {
            ForEach(this.tasks, (task: CronTask) => {
              ListItem() {
                this.TaskCard(task)
              }
            }, (task: CronTask) => task.id)
          }

          // 底部间距
          ListItem() {
            Row().width('100%').height(80)
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
          title: { mainTitle: '定时任务' },
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
      .linearGradient({
        angle: 180,
        colors: [
          [Theme.BackgroundGradientStart, 0.0],
          [Theme.BackgroundGradientMiddle, 0.5],
          [Theme.BackgroundGradientEnd, 1.0]
        ]
      })
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

      // 添加按钮 FAB
      Column() {
        Button() {
          SymbolGlyph($r('sys.symbol.plus'))
            .fontSize(22)
            .fontColor([Color.White])
        }
        .width(56)
        .height(56)
        .backgroundColor(Theme.PrimaryColor)
        .borderRadius(28)
        .shadow({ radius: 8, color: '#33000000', offsetX: 0, offsetY: 4 })
        .onClick(() => {
          this.openCreateSheet()
        })
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.End)
      .alignItems(HorizontalAlign.End)
      .padding({ bottom: 100, right: Theme.SpacingLG })

      // 创建/编辑弹窗
      if (this.showTaskSheet) {
        this.TaskFormSheet()
      }

      // 执行记录弹窗
      if (this.showRunsSheet) {
        this.RunsSheet()
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  TaskCard(task: CronTask) {
    Column({ space: 0 }) {
      Row() {
        Column({ space: 4 }) {
          Text(task.name || '未命名任务')
            .fontSize(Theme.FontBody)
            .fontWeight(FontWeight.Medium)
            .fontColor(Theme.TextPrimary)

          if (task.description) {
            Text(task.description)
              .fontSize(Theme.FontCaption)
              .fontColor(Theme.TextSecondary)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }

          Row({ space: 8 }) {
            Text(this.formatCronDescription(task.cron))
              .fontSize(Theme.FontTiny)
              .fontColor(Theme.AccentBlue)

            Text(task.recurring ? '重复' : '单次')
              .fontSize(Theme.FontTiny)
              .fontColor(Theme.TextTertiary)
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Toggle({ type: ToggleType.Switch, isOn: task.enabled })
          .onChange((isOn: boolean) => {
            const data: Record<string, Object> = {}
            data['enabled'] = isOn
            apiService.updateScheduledTask(task.id, data)
            // 乐观更新
            task.enabled = isOn
          })
      }
      .width('100%')
      .padding(Theme.SpacingMD)

      Divider().color(Theme.GlassBorder)

      Row({ space: 0 }) {
        // 执行按钮
        Column() {
          Text('执行')
            .fontSize(Theme.FontCaption)
            .fontColor(Theme.AccentGreen)
        }
        .layoutWeight(1)
        .onClick(() => {
          this.executeTask(task.id)
        })

        // 查看记录
        Column() {
          Text('记录')
            .fontSize(Theme.FontCaption)
            .fontColor(Theme.AccentBlue)
        }
        .layoutWeight(1)
        .onClick(() => {
          this.viewRuns(task.id, task.name)
        })

        // 编辑
        Column() {
          Text('编辑')
            .fontSize(Theme.FontCaption)
            .fontColor(Theme.TextSecondary)
        }
        .layoutWeight(1)
        .onClick(() => {
          this.openEditSheet(task)
        })

        // 删除
        Column() {
          Text('删除')
            .fontSize(Theme.FontCaption)
            .fontColor(Theme.ErrorColor)
        }
        .layoutWeight(1)
        .onClick(() => {
          this.confirmDeleteTask(task.id, task.name)
        })
      }
      .width('100%')
      .padding({ left: Theme.SpacingSM, right: Theme.SpacingSM, bottom: Theme.SpacingSM })
      .height(40)
    }
    .backgroundColor(Theme.GlassBackground)
    .borderRadius(Theme.RadiusMedium)
    .border({ width: 0.5, color: Theme.GlassBorder })
    .shadow({ radius: Theme.LiquidGlassShadowRadius, color: Theme.LiquidGlassShadowColor, offsetX: 0, offsetY: 4 })
  }

  @Builder
  TaskFormSheet() {
    Stack() {
      // 遮罩
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#66000000')
        .onClick(() => {
          this.showTaskSheet = false
        })

      // 表单 - 底部弹出
      Column({ space: 0 }) {
        Scroll() {
          Column({ space: Theme.SpacingMD }) {
            // 标题
            Text(this.isEditing ? '编辑任务' : '新建任务')
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor(Theme.TextPrimary)
              .width('100%')

            // 名称
            Column({ space: 6 }) {
              Text('任务名称')
                .fontSize(Theme.FontCaption)
                .fontColor(Theme.TextTertiary)
              TextInput({ placeholder: '例如：每日摘要', text: this.editName })
                .height(40)
                .onChange((value: string) => { this.editName = value })
            }
            .width('100%')

            // 描述
            Column({ space: 6 }) {
              Text('描述（可选）')
                .fontSize(Theme.FontCaption)
                .fontColor(Theme.TextTertiary)
              TextInput({ placeholder: '任务描述', text: this.editDescription })
                .height(40)
                .onChange((value: string) => { this.editDescription = value })
            }
            .width('100%')

            // Cron 表达式
            Column({ space: 6 }) {
              Text('Cron 表达式')
                .fontSize(Theme.FontCaption)
                .fontColor(Theme.TextTertiary)
              TextInput({ placeholder: '* * * * *', text: this.editCron })
                .height(40)
                .onChange((value: string) => { this.editCron = value })

              // 常用预设
              Column({ space: 4 }) {
                Text('预设：')
                  .fontSize(Theme.FontTiny)
                  .fontColor(Theme.TextTertiary)
                Row({ space: 6 }) {
                  Text('每分钟')
                    .fontSize(Theme.FontTiny)
                    .fontColor(Theme.AccentBlue)
                    .onClick(() => { this.editCron = '* * * * *' })
                  Text('每小时')
                    .fontSize(Theme.FontTiny)
                    .fontColor(Theme.AccentBlue)
                    .onClick(() => { this.editCron = '0 * * * *' })
                  Text('每天9点')
                    .fontSize(Theme.FontTiny)
                    .fontColor(Theme.AccentBlue)
                    .onClick(() => { this.editCron = '0 9 * * *' })
                  Text('每周一')
                    .fontSize(Theme.FontTiny)
                    .fontColor(Theme.AccentBlue)
                    .onClick(() => { this.editCron = '0 0 * * 1' })
                }
              }
            }
            .width('100%')

            // Prompt
            Column({ space: 6 }) {
              Text('提示词（可选）')
                .fontSize(Theme.FontCaption)
                .fontColor(Theme.TextTertiary)
              TextArea({ placeholder: '任务执行时发送给 AI 的提示词', text: this.editPrompt })
                .height(80)
                .onChange((value: string) => { this.editPrompt = value })
            }
            .width('100%')

            // 开关
            Row() {
              Text('启用')
                .fontSize(Theme.FontBody)
                .fontColor(Theme.TextPrimary)
              Blank()
              Toggle({ type: ToggleType.Switch, isOn: this.editEnabled })
                .onChange((isOn: boolean) => { this.editEnabled = isOn })
            }
            .width('100%')

            Row() {
              Text('重复执行')
                .fontSize(Theme.FontBody)
                .fontColor(Theme.TextPrimary)
              Blank()
              Toggle({ type: ToggleType.Switch, isOn: this.editRecurring })
                .onChange((isOn: boolean) => { this.editRecurring = isOn })
            }
            .width('100%')

            // 保存按钮
            Button() {
              Text(this.isEditing ? '更新' : '创建')
                .fontSize(Theme.FontBody)
                .fontColor(Color.White)
            }
            .width('100%')
            .height(44)
            .backgroundColor(Theme.PrimaryColor)
            .borderRadius(Theme.RadiusMedium)
            .onClick(() => {
              this.saveTask()
            })
            .enabled(this.editCron.trim().length > 0)

            // 取消
            Button() {
              Text('取消')
                .fontSize(Theme.FontBody)
                .fontColor(Theme.TextSecondary)
            }
            .width('100%')
            .height(44)
            .backgroundColor(Theme.BackgroundTertiary)
            .borderRadius(Theme.RadiusMedium)
            .onClick(() => {
              this.showTaskSheet = false
            })
          }
          .width('100%')
          .padding(Theme.SpacingLG)
        }
        .width('100%')
        .layoutWeight(1)
      }
      .width('100%')
      .backgroundColor(Theme.BackgroundPrimary)
      .borderRadius({ topLeft: 20, topRight: 20 })
      .align(Alignment.BottomStart)
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  RunsSheet() {
    Stack() {
      // 遮罩
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#66000000')
        .onClick(() => {
          this.showRunsSheet = false
        })

      // 执行记录内容 - 底部弹出
      Column({ space: 0 }) {
        // 标题
        Row() {
          Text(this.runsTaskName + ' - 执行记录')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(Theme.TextPrimary)
            .layoutWeight(1)

          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(18)
            .fontColor([Theme.TextSecondary])
            .onClick(() => {
              this.showRunsSheet = false
            })
        }
        .width('100%')
        .padding(Theme.SpacingLG)

        Divider().color(Theme.GlassBorder)

        if (this.currentRuns.length === 0) {
          Column() {
            Text('暂无执行记录')
              .fontSize(Theme.FontBody)
              .fontColor(Theme.TextSecondary)
          }
          .width('100%')
          .padding(Theme.SpacingXL)
          .alignItems(HorizontalAlign.Center)
        } else {
          Scroll() {
            Column({ space: Theme.SpacingSM }) {
              ForEach(this.currentRuns, (run: TaskRunItem) => {
                Column({ space: 4 }) {
                  Row() {
                    Text(run.taskName || '任务')
                      .fontSize(Theme.FontBody)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(Theme.TextPrimary)
                      .layoutWeight(1)

                    Text(this.getRunStatusLabel(run.status))
                      .fontSize(Theme.FontCaption)
                      .fontColor(this.getRunStatusColor(run.status))
                  }
                  .width('100%')

                  Row({ space: 8 }) {
                    if (run.startedAt) {
                      Text(run.startedAt.split('.')[0].replace('T', ' '))
                        .fontSize(Theme.FontTiny)
                        .fontColor(Theme.TextTertiary)
                    }

                    if (run.durationMs > 0) {
                      Text((run.durationMs / 1000).toFixed(1) + 's')
                        .fontSize(Theme.FontTiny)
                        .fontColor(Theme.TextTertiary)
                    }
                  }
                  .width('100%')

                  if (run.error) {
                    Text(run.error)
                      .fontSize(Theme.FontTiny)
                      .fontColor(Theme.ErrorColor)
                      .maxLines(3)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .width('100%')
                  }
                }
                .width('100%')
                .padding(Theme.SpacingMD)
                .backgroundColor(Theme.GlassBackground)
                .borderRadius(Theme.RadiusMedium)
                .border({ width: 0.5, color: Theme.GlassBorder })
              }, (run: TaskRunItem) => run.id)
            }
            .width('100%')
            .padding(Theme.SpacingLG)
          }
          .width('100%')
          .layoutWeight(1)
        }
      }
      .width('100%')
      .backgroundColor(Theme.BackgroundPrimary)
      .borderRadius({ topLeft: 20, topRight: 20 })
      .align(Alignment.BottomStart)
    }
    .width('100%')
    .height('100%')
  }
}