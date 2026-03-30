import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    // 注册 iTunes 媒体库选择器 MethodChannel
    let itunesRegistrar = self.registrar(forPlugin: "ItunesMediaPickerHandler")!
    ItunesMediaPickerHandler.register(withRegistrar: itunesRegistrar)

    // 注册后台上传管理器 MethodChannel + EventChannel
    let uploadRegistrar = self.registrar(forPlugin: "BackgroundUploadManager")!
    BackgroundUploadManager.register(with: uploadRegistrar)

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // 系统在后台 URLSession 完成所有任务后调用此方法唤醒 App
  override func application(
    _ application: UIApplication,
    handleEventsForBackgroundURLSession identifier: String,
    completionHandler: @escaping () -> Void
  ) {
    BackgroundUploadManager.shared.backgroundCompletionHandler = completionHandler
  }
}
