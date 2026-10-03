import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    let notificationChannel = FlutterMethodChannel(
      name: "feed_reminder/notifications",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    notificationChannel.setMethodCallHandler { call, result in
      guard call.method == "openNotificationSettings" else {
        result(FlutterMethodNotImplemented)
        return
      }

      // System Settings replaced the preference pane on macOS 13.
      var settingsURLs = ["x-apple.systempreferences:com.apple.preference.notifications"]
      if #available(macOS 13.0, *) {
        settingsURLs.insert(
          "x-apple.systempreferences:com.apple.Notifications-Settings.extension", at: 0
        )
      }
      for settingsURL in settingsURLs {
        if let url = URL(string: settingsURL), NSWorkspace.shared.open(url) {
          result(nil)
          return
        }
      }
      result(
        FlutterError(
          code: "notification_settings_unavailable",
          message: "Unable to open notification settings.",
          details: nil
        )
      )
    }

    // Match the smallest responsive content size, excluding window chrome.
    self.contentMinSize = NSSize(width: 400, height: 280)
    self.setContentSize(NSSize(width: 450, height: 800))
    self.center()

    super.awakeFromNib()
  }
}
