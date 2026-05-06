import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    // Set window size constraints for tablet-like experience
    let minSize = NSSize(width: 400, height: 700)
    self.minSize = minSize
    self.setContentSize(NSSize(width: 450, height: 800))
    self.center()

    super.awakeFromNib()
  }
}
