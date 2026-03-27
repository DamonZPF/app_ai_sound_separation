import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    // 注册 iTunes 媒体库选择器 MethodChannel（通过 FlutterPluginRegistrar 避免 deprecation）
    let registrar = self.registrar(forPlugin: "ItunesMediaPickerHandler")!
    ItunesMediaPickerHandler.register(withRegistrar: registrar)

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
