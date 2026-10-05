import { UIAbility, Want } from '@kit.AbilityKit';
import {
  AbilityAware, AbilityPluginBinding, FlutterPlugin, FlutterPluginBinding,
  MethodCall, MethodCallHandler, MethodChannel, MethodResult
} from '@ohos/flutter_ohos';
import { WidgetSnapshot, WidgetStore } from '../widgets/WidgetStore';

export default class FeedReminderHomeWidget implements FlutterPlugin, AbilityAware, MethodCallHandler {
  private static pendingAction: string | null = null;
  private static instance: FeedReminderHomeWidget | null = null;
  private static writes: Promise<void> = Promise.resolve();
  private channel: MethodChannel | null = null;
  private ability: UIAbility | undefined;

  static receiveWant(want: Want, notify: boolean): void {
    const action = want.parameters?.['feedWidgetAction'];
    if (action !== 'open_timer' && action !== 'record_feed') return;
    FeedReminderHomeWidget.pendingAction = action as string;
    // Dart reads the action atomically. The wake-up signal never consumes it,
    // so a cold engine or privacy gate cannot lose the request.
    if (notify) FeedReminderHomeWidget.instance?.channel?.invokeMethod('widgetAction', null);
  }

  getUniqueClassName(): string { return 'FeedReminderHomeWidget'; }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.channel = new MethodChannel(binding.getBinaryMessenger(), 'feed_reminder/home_widget');
    this.channel.setMethodCallHandler(this);
    FeedReminderHomeWidget.instance = this;
  }

  onDetachedFromEngine(_binding: FlutterPluginBinding): void {
    this.channel?.setMethodCallHandler(null);
    this.channel = null;
    this.ability = undefined;
    if (FeedReminderHomeWidget.instance === this) FeedReminderHomeWidget.instance = null;
  }

  onAttachedToAbility(binding: AbilityPluginBinding): void { this.ability = binding.getAbility(); }
  onDetachedFromAbility(): void { this.ability = undefined; }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    if (call.method === 'getPendingAction') {
      const action = FeedReminderHomeWidget.pendingAction;
      FeedReminderHomeWidget.pendingAction = null;
      result.success(action);
      return;
    }
    if (call.method !== 'updateSnapshot') {
      result.notImplemented();
      return;
    }
    FeedReminderHomeWidget.writes = FeedReminderHomeWidget.writes.then(async () => {
      try {
        const ability = this.ability;
        if (ability === undefined) throw new Error('Ability unavailable');
        const snapshot = new WidgetSnapshot();
        snapshot.schemaVersion = call.argument('schemaVersion');
        snapshot.generatedAtMs = call.argument('generatedAtMs');
        snapshot.dateKey = call.argument('dateKey');
        snapshot.zoneOffsetMinutes = call.argument('zoneOffsetMinutes');
        snapshot.latestTimeMs = call.argument('latestTimeMs');
        snapshot.latestTimeZoneOffsetMinutes = call.argument('latestTimeZoneOffsetMinutes');
        snapshot.latestMilkAmountMl = call.argument('latestMilkAmountMl');
        snapshot.dayTotalMl = call.argument('dayTotalMl');
        snapshot.dayCount = call.argument('dayCount');
        snapshot.nextFeedTimeMs = call.argument('nextFeedTimeMs');
        snapshot.nextFeedTimeZoneOffsetMinutes = call.argument('nextFeedTimeZoneOffsetMinutes');
        snapshot.reminderAcknowledged = call.argument('reminderAcknowledged');
        await WidgetStore.saveSnapshot(ability.context, snapshot);
        await WidgetStore.refreshAll(ability.context, snapshot);
        result.success(null);
      } catch (_) {
        result.error('widget_update_failed', '桌面卡片暂时无法更新。', null);
      }
    }).catch(() => { console.warn('Widget response unavailable'); });
  }
}
