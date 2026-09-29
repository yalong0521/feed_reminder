import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    UNUserNotificationCenter.current().delegate = self
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let notificationChannel = FlutterMethodChannel(
      name: "feed_reminder/notifications",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    notificationChannel.setMethodCallHandler { call, result in
      guard call.method == "openNotificationSettings" else {
        result(FlutterMethodNotImplemented)
        return
      }

      let settingsURL: String
      if #available(iOS 16.0, *) {
        settingsURL = UIApplication.openNotificationSettingsURLString
      } else if #available(iOS 15.4, *) {
        settingsURL = UIApplicationOpenNotificationSettingsURLString
      } else {
        settingsURL = UIApplication.openSettingsURLString
      }
      guard let url = URL(string: settingsURL) else {
        result(
          FlutterError(
            code: "notification_settings_unavailable",
            message: "Unable to open notification settings.",
            details: nil
          )
        )
        return
      }
      UIApplication.shared.open(url, options: [:]) { opened in
        if opened {
          result(nil)
        } else {
          result(
            FlutterError(
              code: "notification_settings_unavailable",
              message: "Unable to open notification settings.",
              details: nil
            )
          )
        }
      }
    }
  }
}
