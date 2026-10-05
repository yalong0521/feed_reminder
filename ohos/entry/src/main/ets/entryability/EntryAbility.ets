import { AbilityConstant, common, Want } from '@kit.AbilityKit';
import { FlutterAbility, FlutterEngine } from '@ohos/flutter_ohos';
import { GeneratedPluginRegistrant } from '../plugins/GeneratedPluginRegistrant';
import FeedReminderNotifications from '../plugins/FeedReminderNotifications';
import FeedReminderPrivacy from '../plugins/FeedReminderPrivacy';
import FeedReminderHomeWidget from '../plugins/FeedReminderHomeWidget';
import FeedReminderDataFiles from '../plugins/FeedReminderDataFiles';

export default class EntryAbility extends FlutterAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    FeedReminderHomeWidget.receiveWant(want, false);
    super.onCreate(want, launchParam);
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    super.onNewWant(want, launchParam);
    FeedReminderHomeWidget.receiveWant(want, true);
  }

  provideFlutterEngine(context: common.Context): FlutterEngine {
    // Register channels during host attachment before the delegate starts Dart.
    // The default engine-group path starts Dart before configureFlutterEngine.
    const engine = new FlutterEngine(context, null, null, null);
    engine.init(context, this.getFlutterShellArgs().toArray(), false);
    return engine;
  }

  configureFlutterEngine(flutterEngine: FlutterEngine): void {
    super.configureFlutterEngine(flutterEngine);
    GeneratedPluginRegistrant.registerWith(flutterEngine);
    flutterEngine.getPlugins()?.add(new FeedReminderNotifications());
    flutterEngine.getPlugins()?.add(new FeedReminderPrivacy());
    flutterEngine.getPlugins()?.add(new FeedReminderHomeWidget());
    flutterEngine.getPlugins()?.add(new FeedReminderDataFiles());
  }

  shouldDestroyEngineWithHost(): boolean {
    return true;
  }
}
