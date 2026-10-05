import { vibrator } from '@kit.SensorServiceKit';
import {
  FlutterPlugin,
  FlutterPluginBinding,
  MethodCall,
  MethodCallHandler,
  MethodChannel,
  MethodResult
} from '@ohos/flutter_ohos';

interface HapticEffect {
  effectId: string;
  intensity: number;
  fallbackDuration: number;
}

/** Short interaction feedback governed by the system's touch vibration policy. */
export default class FeedReminderHaptics implements FlutterPlugin, MethodCallHandler {
  private channel: MethodChannel | null = null;
  private readonly supportedEffects: Map<string, Promise<boolean>> = new Map();
  private lifecycle: number = 0;
  private playing: boolean = false;
  private foreground: boolean = false;

  getUniqueClassName(): string {
    return 'FeedReminderHaptics';
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.lifecycle++;
    this.channel = new MethodChannel(binding.getBinaryMessenger(), 'feed_reminder/haptics');
    this.channel.setMethodCallHandler(this);
  }

  onDetachedFromEngine(_binding: FlutterPluginBinding): void {
    this.lifecycle++;
    this.channel?.setMethodCallHandler(null);
    this.channel = null;
    this.foreground = false;
    this.playing = false;
    this.supportedEffects.clear();
  }

  setForeground(foreground: boolean): void {
    if (this.foreground === foreground) return;
    this.foreground = foreground;
    this.lifecycle++;
    this.playing = false;
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    if (call.method !== 'selection' && call.method !== 'success' && call.method !== 'warning') {
      result.notImplemented();
      return;
    }
    // Drop overlapping feedback rather than building up a delayed vibration queue.
    if (this.channel === null || !this.foreground || this.playing) {
      result.success(null);
      return;
    }
    this.playing = true;
    void this.play(call.method, this.lifecycle, result);
  }

  private effectFor(method: string): HapticEffect {
    switch (method) {
      case 'success':
        return { effectId: 'haptic.effect.soft', intensity: 55, fallbackDuration: 20 };
      case 'warning':
        return { effectId: 'haptic.effect.hard', intensity: 50, fallbackDuration: 35 };
      default:
        return { effectId: 'haptic.effect.soft', intensity: 35, fallbackDuration: 8 };
    }
  }

  private async supportsEffect(effectId: string): Promise<boolean> {
    const cached = this.supportedEffects.get(effectId);
    if (cached !== undefined) return cached;
    const support = vibrator.isSupportEffect(effectId);
    this.supportedEffects.set(effectId, support);
    try {
      return await support;
    } catch (_) {
      // Retry only on a later action. An old engine's failure must not remove
      // a newer query cached after detach and reattachment.
      if (this.supportedEffects.get(effectId) === support) {
        this.supportedEffects.delete(effectId);
      }
      throw new Error('Haptic effect support unavailable');
    }
  }

  private async play(method: string, lifecycle: number, result: MethodResult): Promise<void> {
    const requestedAt = Date.now();
    try {
      const effect = this.effectFor(method);
      const supported = await this.supportsEffect(effect.effectId);
      if (lifecycle !== this.lifecycle || this.channel === null || !this.foreground) return;
      // A slow first capability query must not turn into a late touch response.
      const age = Date.now() - requestedAt;
      if (age < 0 || age > 70) return;
      if (supported) {
        await vibrator.startVibration({
          type: 'preset', effectId: effect.effectId, count: 1, intensity: effect.intensity
        }, { usage: 'touch' });
      } else {
        await vibrator.startVibration({ type: 'time', duration: effect.fallbackDuration }, { usage: 'touch' });
      }
    } catch (_) {
      // Feedback is optional. Permission, device, or policy failures never block
      // the action and never trigger a second attempt with a different usage.
    } finally {
      if (lifecycle === this.lifecycle) this.playing = false;
      result.success(null);
    }
  }
}
