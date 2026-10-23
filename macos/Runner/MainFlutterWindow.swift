import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    // Content runs under a transparent title bar; the app keeps the top
    // 28pt clear for the window controls.
    self.styleMask.insert(.fullSizeContentView)
    self.titlebarAppearsTransparent = true
    self.titleVisibility = .hidden

    // Below this the phone layout would be cramped.
    self.minSize = NSSize(width: 420, height: 640)
    self.setFrame(NSRect(x: 0, y: 0, width: 1200, height: 800), display: true)
    self.center()
    // Reopens at the size and place it was left.
    self.setFrameAutosaveName("OpenRCMainWindow")

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
