import { bundleManager, UIAbility, wantAgent } from '@kit.AbilityKit';
import { reminderAgentManager } from '@kit.BackgroundTasksKit';
import { BusinessError, deviceInfo } from '@kit.BasicServicesKit';
import { notificationManager } from '@kit.NotificationKit';
import {
  AbilityAware,
  AbilityPluginBinding,
  FlutterPlugin,
  FlutterPluginBinding,
  MethodCall,
  MethodCallHandler,
  MethodChannel,
  MethodResult
} from '@ohos/flutter_ohos';

class NotificationBridgeError extends Error {
  readonly code: string;

  constructor(code: string, message: string) {
    super(message);
    this.code = code;
  }
}

interface ReminderContent {
  title: string;
  body: string;
  playSound: boolean;
}

/** The feeding app owns one system reminder, independent of the Dart isolate. */
export default class FeedReminderNotifications implements FlutterPlugin, AbilityAware, MethodCallHandler {
  // Native requests can outlive their Flutter engine during a same-process restart.
  private static effects: Promise<void> = Promise.resolve();
  private channel: MethodChannel | null = null;
  private ability: UIAbility | undefined;
  private requestingPermission: boolean = false;

  getUniqueClassName(): string {
    return 'FeedReminderNotifications';
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.channel = new MethodChannel(binding.getBinaryMessenger(), 'feed_reminder/notifications');
    this.channel.setMethodCallHandler(this);
  }

  onDetachedFromEngine(_binding: FlutterPluginBinding): void {
    this.channel?.setMethodCallHandler(null);
    this.channel = null;
    this.ability = undefined;
    // Engine teardown must leave the next system reminder intact.
  }

  onAttachedToAbility(binding: AbilityPluginBinding): void {
    this.ability = binding.getAbility();
  }

  onDetachedFromAbility(): void {
    this.ability = undefined;
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    if (call.method === 'initialize') {
      // Restoring saved records must not implicitly open a permission dialog.
      result.success(null);
      return;
    }
    if (call.method === 'requestPermissions') {
      void this.requestPermissions(result);
      return;
    }
    if (call.method === 'openNotificationSettings') {
      void this.openNotificationSettings(result);
      return;
    }
    if (call.method !== 'show' && call.method !== 'schedule' && call.method !== 'cancelAll') {
      result.notImplemented();
      return;
    }
    // Serialize replacements and cancellations even when callers overlap.
    FeedReminderNotifications.effects = FeedReminderNotifications.effects.then(async () => {
      try {
        if (call.method === 'cancelAll') {
          await this.cancelAll();
        } else if (call.method === 'schedule') {
          await this.schedule(call);
        } else {
          await this.show(call);
        }
        result.success(null);
      } catch (error) {
        this.reportError(result, call.method, error as Error);
      }
    }).catch((error: Error) => {
      // Business errors were sent above. A destroyed engine may reject the
      // response itself; that must not poison the next engine's shared queue.
      console.error(`Notification bridge response failed: ${error.message}`);
    });
  }

  private async requestPermissions(result: MethodResult): Promise<void> {
    if (this.requestingPermission) {
      result.error('permission_request_in_progress', '系统通知授权正在处理中。', null);
      return;
    }
    this.requestingPermission = true;
    try {
      if (!await notificationManager.isNotificationEnabled()) {
        const ability = this.ability;
        if (ability === undefined) {
          throw new NotificationBridgeError('ability_unavailable', '请返回应用后开启系统通知权限。');
        }
        await notificationManager.requestEnableNotification(ability.context);
      }
      await this.requirePermission();
      result.success(null);
    } catch (error) {
      this.reportError(result, 'requestPermissions', error as Error);
    } finally {
      this.requestingPermission = false;
    }
  }

  private async openNotificationSettings(result: MethodResult): Promise<void> {
    try {
      const ability = this.ability;
      if (ability === undefined) {
        throw new NotificationBridgeError('ability_unavailable', '请返回应用后打开系统通知设置。');
      }
      if (deviceInfo.sdkApiVersion >= 26) {
        // API 26 completes when the user closes the settings sheet.
        await notificationManager.openNotificationSettingsWithResult(ability.context);
        result.success(true);
      } else {
        // Older systems only confirm opening; Dart must wait for the user's
        // return before synchronizing reminders with any permission change.
        await notificationManager.openNotificationSettings(ability.context);
        result.success(false);
      }
    } catch (error) {
      this.reportError(result, 'openNotificationSettings', error as Error);
    }
  }

  private async requirePermission(): Promise<void> {
    if (!await notificationManager.isNotificationEnabled()) {
      throw new NotificationBridgeError('notification_permission_denied', '系统通知未开启，请在系统设置中允许通知。');
    }
  }

  private readContent(call: MethodCall): ReminderContent {
    const title: string = call.argument('title');
    const body: string = call.argument('body');
    const playSound: boolean = call.argument('playSound');
    if (typeof title !== 'string' || title.trim().length === 0 ||
      typeof body !== 'string' || typeof playSound !== 'boolean') {
      throw new NotificationBridgeError('invalid_arguments', '提醒标题、内容或声音设置无效。');
    }
    return { title: title, body: body, playSound: playSound };
  }

  private slotFor(playSound: boolean): notificationManager.SlotType {
    // API 17 cannot set per-notification sound flags. CONTENT_INFORMATION is
    // low priority (notification center, no default banner/sound); the user's
    // system slot settings remain authoritative for both reminder modes.
    return playSound ? notificationManager.SlotType.SERVICE_INFORMATION :
      notificationManager.SlotType.CONTENT_INFORMATION;
  }

  private bundleName(): string {
    return bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION).name;
  }

  private async show(call: MethodCall): Promise<void> {
    const content = this.readContent(call);
    await this.requirePermission();
    const slot = this.slotFor(content.playSound);
    await notificationManager.addSlot(slot);
    const launchAgent = await wantAgent.getWantAgent({
      wants: [{ bundleName: this.bundleName(), abilityName: 'EntryAbility' }],
      operationType: wantAgent.OperationType.START_ABILITY,
      requestCode: 0,
      wantAgentFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
    });
    const request: notificationManager.NotificationRequest = {
      id: 0,
      notificationSlotType: slot,
      content: {
        notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
        normal: { title: content.title, text: content.body }
      },
      wantAgent: launchAgent,
      tapDismissed: true
    };
    await notificationManager.publish(request);
    // Proxy notifications use a system-owned label, so matching id=0 alone
    // does not replace their cards. Keep the successfully published foreground
    // card, then remove this cycle's proxy and its differently labelled card.
    await reminderAgentManager.cancelAllReminders();
  }

  private async schedule(call: MethodCall): Promise<void> {
    const content = this.readContent(call);
    const epochMilliseconds: number = call.argument('epochMilliseconds');
    if (typeof epochMilliseconds !== 'number' || !Number.isSafeInteger(epochMilliseconds)) {
      throw new NotificationBridgeError('invalid_arguments', '提醒时间必须是有效的毫秒时间戳。');
    }
    // Calendar reminders have second precision; round up to avoid firing early.
    const deadline = new Date(Math.ceil(epochMilliseconds / 1000) * 1000);
    if (!Number.isFinite(deadline.getTime()) || epochMilliseconds <= Date.now()) {
      throw new NotificationBridgeError('invalid_reminder_time', '提醒时间必须晚于当前时间。');
    }
    await this.requirePermission();
    const slot = this.slotFor(content.playSound);
    await reminderAgentManager.addNotificationSlot({ notificationType: slot });
    const request: reminderAgentManager.ReminderRequestCalendar = {
      reminderType: reminderAgentManager.ReminderType.REMINDER_TYPE_CALENDAR,
      notificationId: 0,
      title: content.title,
      content: content.body,
      slotType: slot,
      // Zero uses the notification slot, not the separate vibrating alarm tone.
      ringDuration: 0,
      tapDismissed: true,
      wantAgent: { pkgName: this.bundleName(), abilityName: 'EntryAbility' },
      dateTime: {
        year: deadline.getFullYear(),
        month: deadline.getMonth() + 1,
        day: deadline.getDate(),
        hour: deadline.getHours(),
        minute: deadline.getMinutes(),
        second: deadline.getSeconds()
      }
    };
    // The app has only one reminder type. Query-free cancellation also works
    // after a process restart, without a separate persisted reminder-id cache.
    await this.cancelAll();
    await reminderAgentManager.publishReminder(request);
  }

  private async cancelAll(): Promise<void> {
    let failure: Error | undefined;
    try {
      await reminderAgentManager.cancelAllReminders();
    } catch (error) {
      failure = error as Error;
    }
    // A failed proxy cancellation must not prevent removing the visible card.
    try {
      await notificationManager.cancelAll();
    } catch (error) {
      if (failure === undefined) {
        failure = error as Error;
      }
    }
    if (failure !== undefined) {
      throw failure;
    }
  }

  private reportError(result: MethodResult, method: string, error: Error): void {
    if (error instanceof NotificationBridgeError) {
      result.error(error.code, error.message, null);
      return;
    }
    const nativeError = error as BusinessError;
    if (nativeError.code === 1600004 || nativeError.code === 1700001) {
      result.error('notification_permission_denied', '系统通知未开启，请在系统设置中允许通知。', nativeError.code);
    } else if (nativeError.code === 201) {
      result.error('reminder_permission_denied',
        '系统未授予提醒权限，请检查后台代理提醒权限声明和应用签名授权。', nativeError.code);
    } else {
      result.error(`${method}_failed`, nativeError.message || '系统提醒服务暂不可用。', nativeError.code ?? null);
    }
  }
}
