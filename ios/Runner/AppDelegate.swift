import Flutter
import UIKit
import WidgetKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    let registrar = self.registrar(forPlugin: "com.openrc.app.widgets")
    let channel = FlutterMethodChannel(
      name: "com.openrc.app/widgets",
      binaryMessenger: registrar!.messenger()
    )
    channel.setMethodCallHandler { (call, result) in
      switch call.method {
      case "updateWidgetData":
        self.handleUpdateWidgetData(call: call, result: result)
      case "clearWidgetData":
        self.handleClearWidgetData(result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func handleClearWidgetData(result: @escaping FlutterResult) {
    let defaults = UserDefaults(suiteName: "group.com.openrc.app.widgets")
    defaults?.removeObject(forKey: "widget_data_json")
    defaults?.removeObject(forKey: "widget_currency_code")
    defaults?.synchronize()

    if #available(iOS 14.0, *) {
      WidgetCenter.shared.reloadAllTimelines()
    }

    result(true)
  }

  private func handleUpdateWidgetData(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any] else {
      result(FlutterError(code: "INVALID_ARGS", message: "Expected map argument", details: nil))
      return
    }

    do {
      let jsonData = try JSONSerialization.data(withJSONObject: args, options: [])
      guard let jsonString = String(data: jsonData, encoding: .utf8) else {
        result(FlutterError(code: "ENCODE_FAIL", message: "Failed to encode JSON string", details: nil))
        return
      }

      let defaults = UserDefaults(suiteName: "group.com.openrc.app.widgets")
      defaults?.set(jsonString, forKey: "widget_data_json")

      // Store currency code separately so widgets can read it independently
      if let currencyCode = args["currencyCode"] as? String {
        defaults?.set(currencyCode.uppercased(), forKey: "widget_currency_code")
      }

      defaults?.synchronize()

      if #available(iOS 14.0, *) {
        WidgetCenter.shared.reloadAllTimelines()
      }

      result(true)
    } catch {
      result(FlutterError(code: "JSON_ERROR", message: error.localizedDescription, details: nil))
    }
  }
}
