import vibrator from '@ohos.vibrator'

type HapticUsage = 'unknown' | 'alarm' | 'ring' | 'notification' | 'communication' |
  'touch' | 'media' | 'physicalFeedback' | 'simulateReality'

class AppHapticFeedback {
  private lastVibrateAt: number = 0

  private canVibrate(): boolean {
    const now = Date.now()
    if (now - this.lastVibrateAt < 45) return false
    this.lastVibrateAt = now
    return true
  }

  private vibrateTime(duration: number, usage: HapticUsage = 'touch'): void {
    if (!this.canVibrate()) return
    try {
      vibrator.startVibration({
        type: 'time',
        duration: duration
      }, {
        id: 0,
        usage: usage
      })
    } catch (e) {}
  }

  private vibratePreset(effectId: string, fallbackDuration: number, intensity: number = 70): void {
    if (!this.canVibrate()) return
    try {
      if (vibrator.isSupportEffectSync(effectId)) {
        vibrator.startVibration({
          type: 'preset',
          effectId: effectId,
          count: 1,
          intensity: intensity
        }, {
          id: 0,
          usage: 'touch'
        })
        return
      }
    } catch (e) {}

    try {
      vibrator.startVibration({
        type: 'time',
        duration: fallbackDuration
      }, {
        id: 0,
        usage: 'touch'
      })
    } catch (e) {}
  }

  selection(): void {
    this.vibratePreset(vibrator.HapticFeedback.EFFECT_SOFT, 55, 55)
  }

  tap(): void {
    this.vibratePreset(vibrator.HapticFeedback.EFFECT_SHARP, 65, 70)
  }

  submit(): void {
    this.vibratePreset(vibrator.HapticFeedback.EFFECT_HARD, 85, 90)
  }

  success(): void {
    this.vibratePreset(vibrator.HapticFeedback.EFFECT_NOTICE_SUCCESS, 90, 80)
  }

  alert(): void {
    this.vibrateTime(300, 'alarm')
  }
}

export const hapticFeedback = new AppHapticFeedback()
