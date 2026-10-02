import { UIAbility } from '@kit.AbilityKit';
import { privacyManager } from '@kit.AppGalleryKit';
import { BusinessError } from '@kit.BasicServicesKit';
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

/** Opens the declaration configured and published by AppGallery privacy hosting. */
export default class FeedReminderPrivacy implements FlutterPlugin, AbilityAware, MethodCallHandler {
  private channel: MethodChannel | null = null;
  private ability: UIAbility | undefined;
  private opening: boolean = false;

  getUniqueClassName(): string {
    return 'FeedReminderPrivacy';
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.channel = new MethodChannel(binding.getBinaryMessenger(), 'feed_reminder/privacy');
    this.channel.setMethodCallHandler(this);
  }

  onDetachedFromEngine(_binding: FlutterPluginBinding): void {
    this.channel?.setMethodCallHandler(null);
    this.channel = null;
    this.ability = undefined;
  }

  onAttachedToAbility(binding: AbilityPluginBinding): void {
    this.ability = binding.getAbility();
  }

  onDetachedFromAbility(): void {
    this.ability = undefined;
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    if (call.method !== 'openHostedPrivacyPolicy') {
      result.notImplemented();
      return;
    }
    void this.openHostedPrivacyPolicy(result);
  }

  private async openHostedPrivacyPolicy(result: MethodResult): Promise<void> {
    if (this.opening) {
      result.success(null);
      return;
    }
    this.opening = true;
    try {
      const ability = this.ability;
      if (ability === undefined) {
        throw new Error('The app is not attached to an ability.');
      }
      // Query the installed app's current hosted declaration; never substitute
      // a hard-coded or app-owned policy for the system-managed version.
      const info = privacyManager.getAppPrivacyMgmtInfo();
      const policy = info.privacyInfo.find((link: privacyManager.AppPrivacyLink) =>
        link.type === privacyManager.AppPrivacyLinkType.PRIVACY_STATEMENT_LINK
      );
      if (info.type !== privacyManager.AppPrivacyMgmtType.FULL_MODE ||
        policy === undefined || !policy.url.startsWith('https://')) {
        throw new Error('The hosted privacy declaration is unavailable.');
      }
      await ability.context.openLink(policy.url, { appLinkingOnly: false });
      result.success(null);
    } catch (error) {
      const businessError = error as BusinessError;
      result.error(
        'privacy_policy_unavailable',
        '隐私政策暂时无法打开，请检查网络后重试。',
        businessError.code?.toString() ?? ''
      );
    } finally {
      this.opening = false;
    }
  }
}
