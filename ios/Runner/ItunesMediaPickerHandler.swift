import Flutter
import UIKit
import MediaPlayer
import AVFoundation

/// 通过 MethodChannel 调用 iOS 原生 MPMediaPickerController
/// 让用户从 iTunes / Apple Music 本地资料库中选取音乐
class ItunesMediaPickerHandler: NSObject, MPMediaPickerControllerDelegate {

    private var flutterResult: FlutterResult?
    private weak var registrar: FlutterPluginRegistrar?

    /// 通过 FlutterPluginRegistrar 注册 MethodChannel
    static func register(withRegistrar registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "com.app.itunesPicker",
            binaryMessenger: registrar.messenger()
        )
        let handler = ItunesMediaPickerHandler()
        handler.registrar = registrar
        channel.setMethodCallHandler { call, result in
            if call.method == "pickFromItunes" {
                // 获取当前最顶层的 ViewController 来展示 picker
                guard let viewController = UIApplication.shared.keyWindow?.rootViewController else {
                    result(FlutterError(code: "NO_VIEW_CONTROLLER",
                                        message: "无法获取当前视图控制器",
                                        details: nil))
                    return
                }
                // 找到最顶层正在展示的 VC
                var topVC = viewController
                while let presented = topVC.presentedViewController {
                    topVC = presented
                }
                handler.showMediaPicker(from: topVC, result: result)
            } else {
                result(FlutterMethodNotImplemented)
            }
        }
    }

    // MARK: - 展示媒体选择器

    private func showMediaPicker(from viewController: UIViewController, result: @escaping FlutterResult) {
        // 检查授权状态
        let status = MPMediaLibrary.authorizationStatus()
        switch status {
        case .authorized:
            presentPicker(from: viewController, result: result)
        case .notDetermined:
            MPMediaLibrary.requestAuthorization { [weak self] newStatus in
                DispatchQueue.main.async {
                    if newStatus == .authorized {
                        self?.presentPicker(from: viewController, result: result)
                    } else {
                        result(FlutterError(code: "PERMISSION_DENIED",
                                            message: "用户拒绝了媒体库访问权限",
                                            details: nil))
                    }
                }
            }
        default:
            result(FlutterError(code: "PERMISSION_DENIED",
                                message: "媒体库访问权限被拒绝，请在设置中开启",
                                details: nil))
        }
    }

    private func presentPicker(from viewController: UIViewController, result: @escaping FlutterResult) {
        self.flutterResult = result

        let picker = MPMediaPickerController(mediaTypes: .music)
        picker.delegate = self
        picker.allowsPickingMultipleItems = false
        picker.showsCloudItems = false
        picker.showsItemsWithProtectedAssets = false
        picker.prompt = "Select music to import"

        viewController.present(picker, animated: true)
    }

    // MARK: - MPMediaPickerControllerDelegate

    func mediaPicker(_ mediaPicker: MPMediaPickerController,
                     didPickMediaItems mediaItemCollection: MPMediaItemCollection) {
        mediaPicker.dismiss(animated: true)

        guard let item = mediaItemCollection.items.first else {
            flutterResult?(FlutterError(code: "NO_ITEM",
                                         message: "未选择任何音频",
                                         details: nil))
            flutterResult = nil
            return
        }

        // 获取音频文件的 Asset URL
        guard let assetURL = item.assetURL else {
            flutterResult?(FlutterError(code: "DRM_PROTECTED",
                                         message: "该音频受 DRM 保护，无法导出",
                                         details: nil))
            flutterResult = nil
            return
        }

        // 获取元数据
        let title = item.title ?? "Unknown"
        let artist = item.artist ?? ""
        let fileName = artist.isEmpty ? "\(title).m4a" : "\(artist) - \(title).m4a"

        // 将媒体资源导出到临时文件
        exportAsset(url: assetURL, fileName: fileName)
    }

    func mediaPickerDidCancel(_ mediaPicker: MPMediaPickerController) {
        mediaPicker.dismiss(animated: true)
        // 用户取消，返回 nil（Flutter 侧判断为取消）
        flutterResult?(nil)
        flutterResult = nil
    }

    // MARK: - 导出音频到临时目录

    private func exportAsset(url: URL, fileName: String) {
        let asset = AVURLAsset(url: url)
        guard let exporter = AVAssetExportSession(asset: asset,
                                                   presetName: AVAssetExportPresetAppleM4A) else {
            flutterResult?(FlutterError(code: "EXPORT_FAILED",
                                         message: "无法创建导出会话",
                                         details: nil))
            flutterResult = nil
            return
        }

        // 清理文件名中的非法字符
        let safeName = fileName
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")

        let tempDir = NSTemporaryDirectory()
        let outputPath = (tempDir as NSString).appendingPathComponent(safeName)
        let outputURL = URL(fileURLWithPath: outputPath)

        // 如果文件已存在，先删除
        try? FileManager.default.removeItem(at: outputURL)

        exporter.outputURL = outputURL
        exporter.outputFileType = .m4a

        exporter.exportAsynchronously { [weak self] in
            DispatchQueue.main.async {
                switch exporter.status {
                case .completed:
                    self?.flutterResult?([
                        "path": outputPath,
                        "name": safeName,
                    ])
                case .failed:
                    self?.flutterResult?(FlutterError(
                        code: "EXPORT_FAILED",
                        message: exporter.error?.localizedDescription ?? "导出失败",
                        details: nil
                    ))
                case .cancelled:
                    self?.flutterResult?(nil)
                default:
                    self?.flutterResult?(FlutterError(
                        code: "EXPORT_FAILED",
                        message: "导出状态异常: \(exporter.status.rawValue)",
                        details: nil
                    ))
                }
                self?.flutterResult = nil
            }
        }
    }
}
