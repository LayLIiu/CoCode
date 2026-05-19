import { liveViewManager } from '@kit.LiveViewKit'
import { wantAgent, WantAgent } from '@kit.AbilityKit'
import { BusinessError } from '@kit.BasicServicesKit'
import { hilog } from '@kit.PerformanceAnalysisKit'

const DOMAIN = 0x0000

export class AiProfile {
  name: string = ''
  color: string = ''
  iconRes: string = ''
  constructor(name: string, color: string, iconRes: string) {
    this.name = name
    this.color = color
    this.iconRes = iconRes
  }
}

const AI_PROFILES: Record<string, AiProfile> = {
  'claude': new AiProfile('Claude', '#9B59B6', 'ic_claude'),
  'codex': new AiProfile('CodeX', '#3498DB', 'ic_codex'),
  'opencode': new AiProfile('OpenCode', '#2ECC71', 'ic_opencode')
}

export function getAiDisplayName(aiTool?: string): string {
  const profile = aiTool ? AI_PROFILES[aiTool] : undefined
  return profile?.name || 'AI'
}

export function getAiColor(aiTool?: string): string {
  const profile = aiTool ? AI_PROFILES[aiTool] : undefined
  return profile?.color || '#FF317AF7'
}

export class LiveViewService {
  private static instance: LiveViewService
  private activeLiveViewId: number = -1
  private bundleName: string = ''
  private isAvailable: boolean = false
  private activeAiName: string = 'AI'
  private activeAiTool: string = ''

  static getInstance(): LiveViewService {
    if (!LiveViewService.instance) {
      LiveViewService.instance = new LiveViewService()
    }
    return LiveViewService.instance
  }

  setBundleName(name: string): void {
    this.bundleName = name
  }

  async checkAvailability(): Promise<boolean> {
    try {
      this.isAvailable = await liveViewManager.isLiveViewEnabled()
      return this.isAvailable
    } catch (e) {
      this.isAvailable = false
      hilog.warn(DOMAIN, 'testTag', 'LiveView not available: %{public}s', JSON.stringify(e))
      return false
    }
  }

  async showThinking(sessionId: string, aiTool?: string): Promise<void> {
    if (!await this.checkAvailability()) return
    await this.stopLiveView()
    this.activeAiTool = aiTool || ''
    this.activeAiName = getAiDisplayName(aiTool)
    const liveView = await this.buildProgressLiveView(sessionId, this.activeAiName + ' 思考中...', true, 0)
    try {
      const result = await liveViewManager.startLiveView(liveView)
      if (result.resultCode === 0) {
        this.activeLiveViewId = liveView.id
        hilog.info(DOMAIN, 'testTag', 'LiveView started: thinking')
      }
    } catch (e) {
      hilog.error(DOMAIN, 'testTag', 'LiveView start error: %{public}s', JSON.stringify(e))
    }
  }

  async showStreaming(sessionId: string, content: string): Promise<void> {
    if (this.activeLiveViewId < 0) return
    const preview = content.length > 40 ? content.substring(0, 37) + '...' : content
    const liveView = this.buildProgressLiveView(sessionId, this.activeAiName + ' 回复中...', true, 0)
    liveView.id = this.activeLiveViewId
    liveView.liveViewData.primary.content = [{ text: preview }]
    try {
      await liveViewManager.updateLiveView(liveView)
    } catch (e) {
      hilog.error(DOMAIN, 'testTag', 'LiveView update error: %{public}s', JSON.stringify(e))
    }
  }

  async showComplete(sessionId: string): Promise<void> {
    if (this.activeLiveViewId < 0) return
    const liveView = this.buildTextLiveView(sessionId, '回复完成 ✓', this.activeAiName + ' 回复完成')
    liveView.id = this.activeLiveViewId
    try {
      await liveViewManager.updateLiveView(liveView)
    } catch (e) {
      hilog.error(DOMAIN, 'testTag', 'LiveView complete update error: %{public}s', JSON.stringify(e))
    }
    setTimeout(() => {
      this.stopLiveView()
    }, 5000)
  }

  async stopLiveView(): Promise<void> {
    if (this.activeLiveViewId < 0) return
    try {
      await liveViewManager.stopLiveView({
        id: this.activeLiveViewId,
        event: 'DELIVERY',
        liveViewData: {
          primary: {
            title: '',
            content: [{ text: '' }],
            keepTime: 0
          }
        }
      })
      hilog.info(DOMAIN, 'testTag', 'LiveView stopped')
    } catch (e) {
      hilog.error(DOMAIN, 'testTag', 'LiveView stop error: %{public}s', JSON.stringify(e))
    }
    this.activeLiveViewId = -1
  }

  private buildProgressLiveView(sessionId: string, statusText: string, indeterminate: boolean, progress: number): liveViewManager.LiveView {
    const id = this.hashSessionId(sessionId)
    const aiColor = getAiColor(this.activeAiTool)
    const capsuleContent = this.activeAiName + ' ' + statusText
    return {
      id: id,
      event: 'DELIVERY',
      liveViewData: {
        primary: {
          title: statusText,
          content: [{ text: statusText }],
          keepTime: 30,
          clickAction: undefined,
          layoutData: {
            layoutType: liveViewManager.LayoutType.LAYOUT_TYPE_FLIGHT,
            firstTitle: this.activeAiName,
            firstContent: statusText,
            style: liveViewManager.FlightLayoutStyle.STYLE_FLIGHT_EMPHASIS
          } as liveViewManager.FlightLayout
        },
        capsule: {
          type: liveViewManager.CapsuleType.CAPSULE_TYPE_PROGRESS,
          status: 1,
          content: capsuleContent,
          indeterminate: indeterminate,
          progress: progress,
          max: 100,
          backgroundColor: aiColor
        } as liveViewManager.ProgressCapsule
      }
    }
  }

  private buildTextLiveView(sessionId: string, title: string, text: string): liveViewManager.LiveView {
    const id = this.hashSessionId(sessionId)
    const aiColor = getAiColor(this.activeAiTool)
    const capsuleContent = this.activeAiName + ' ' + title
    return {
      id: id,
      event: 'DELIVERY',
      liveViewData: {
        primary: {
          title: title,
          content: [{ text: text }],
          keepTime: 30,
          clickAction: undefined,
          layoutData: {
            layoutType: liveViewManager.LayoutType.LAYOUT_TYPE_FLIGHT,
            firstTitle: this.activeAiName,
            firstContent: text,
            style: liveViewManager.FlightLayoutStyle.STYLE_FLIGHT_EMPHASIS
          } as liveViewManager.FlightLayout
        },
        capsule: {
          type: liveViewManager.CapsuleType.CAPSULE_TYPE_TEXT,
          status: 1,
          content: capsuleContent,
          backgroundColor: aiColor
        } as liveViewManager.TextCapsule
      }
    }
  }

  private async buildWantAgent(sessionId: string): Promise<WantAgent | undefined> {
    try {
      const info: wantAgent.WantAgentInfo = {
        wants: [{
          bundleName: this.bundleName || 'com.cocode.app',
          abilityName: 'EntryAbility',
          parameters: {
            sessionId: sessionId,
            fromNotification: 'true'
          }
        }],
        operationType: wantAgent.OperationType.START_ABILITY,
        requestCode: 0,
        wantAgentFlags: [wantAgent.WantAgentFlags.CONSTANT_FLAG]
      }
      return await wantAgent.getWantAgent(info)
    } catch (e) {
      return undefined
    }
  }

  private hashSessionId(sessionId: string): number {
    let hash = 0
    for (let i = 0; i < sessionId.length; i++) {
      hash = ((hash << 5) - hash) + sessionId.charCodeAt(i)
      hash = hash & hash
    }
    return Math.abs(hash) % 2147483647
  }
}

export const liveViewService = LiveViewService.getInstance()
