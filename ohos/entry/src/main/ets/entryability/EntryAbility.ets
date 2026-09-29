import { common } from '@kit.AbilityKit';
import { FlutterAbility, FlutterEngine } from '@ohos/flutter_ohos';
import { GeneratedPluginRegistrant } from '../plugins/GeneratedPluginRegistrant';
import FeedReminderNotifications from '../plugins/FeedReminderNotifications';

export default class EntryAbility extends FlutterAbility {
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
  }

  shouldDestroyEngineWithHost(): boolean {
    return true;
  }
}
