import Flutter
import UIKit

/// iOS 原生后台上传管理器
/// 利用 URLSession background session 实现 App 进入后台/被杀死后仍能继续上传
class BackgroundUploadManager: NSObject, FlutterPlugin, URLSessionDataDelegate, URLSessionTaskDelegate {

    // MARK: - 常量
    static let channelName = "com.zpf.ai_sound_separation/background_upload"
    static let eventChannelName = "com.zpf.ai_sound_separation/upload_events"
    private static let sessionIdentifier = "com.zpf.ai_sound_separation.bgUpload"

    // MARK: - 单例
    static let shared = BackgroundUploadManager()

    // MARK: - 属性
    private var backgroundSession: URLSession!
    private var foregroundSession: URLSession!
    private var eventSink: FlutterEventSink?
    private var methodChannel: FlutterMethodChannel?

    /// App 是否在前台
    private var isInForeground = true

    /// 系统在后台唤醒 App 完成会话事件后调用的 completionHandler
    var backgroundCompletionHandler: (() -> Void)?

    /// taskIdentifier → 自定义上传 ID 映射
    private var taskIdMap: [Int: String] = [:]

    /// taskIdentifier → 服务端响应数据缓存
    private var responseDataMap: [Int: Data] = [:]

    // MARK: - 初始化

    private override init() {
        super.init()
        setupSession()

        NotificationCenter.default.addObserver(self, selector: #selector(appDidEnterBackground),
                                               name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appWillEnterForeground),
                                               name: UIApplication.willEnterForegroundNotification, object: nil)
    }

    @objc private func appDidEnterBackground() {
        isInForeground = false
        NSLog("[BackgroundUpload] 📱 App 进入后台")
    }

    @objc private func appWillEnterForeground() {
        isInForeground = true
        NSLog("[BackgroundUpload] 📱 App 回到前台")
    }

    private func setupSession() {
        // 后台会话 — App 退到后台时保持上传，重试时也用这个
        let bgConfig = URLSessionConfiguration.background(withIdentifier: BackgroundUploadManager.sessionIdentifier)
        bgConfig.isDiscretionary = false
        bgConfig.sessionSendsLaunchEvents = true
        bgConfig.shouldUseExtendedBackgroundIdleMode = true
        // 单次请求超时 120 秒：每个 chunk 5MB，120 秒足够；网络中断后尽快触发重试
        bgConfig.timeoutIntervalForRequest = 120
        // 总资源时限不限（整个上传流程可能持续较久）
        bgConfig.timeoutIntervalForResource = 0
        bgConfig.httpMaximumConnectionsPerHost = 6
        backgroundSession = URLSession(configuration: bgConfig, delegate: self, delegateQueue: nil)

        // 前台会话 — App 在前台时全速上传（无系统进程中转开销）
        let fgConfig = URLSessionConfiguration.default
        // 90 秒超时：网络变差时及时触发 chunked_uploader 的重试机制
        // 设为 0 会导致请求永远挂起，不会触发 didCompleteWithError
        fgConfig.timeoutIntervalForRequest = 90
        fgConfig.timeoutIntervalForResource = 0
        fgConfig.httpMaximumConnectionsPerHost = 6
        foregroundSession = URLSession(configuration: fgConfig, delegate: self, delegateQueue: nil)
    }

    /// 前台用 foreground session（快），后台用 background session（稳）
    /// 前台任务进入后台时可能失败，但 chunked_uploader 的重试机制会自动
    /// 创建新任务走 background session
    private var activeSession: URLSession {
        return isInForeground ? foregroundSession : backgroundSession
    }

    // MARK: - FlutterPlugin 注册

    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: channelName, binaryMessenger: registrar.messenger())
        let eventChannel = FlutterEventChannel(name: eventChannelName, binaryMessenger: registrar.messenger())

        shared.methodChannel = channel
        registrar.addMethodCallDelegate(shared, channel: channel)
        eventChannel.setStreamHandler(shared)
    }

    // MARK: - MethodChannel 处理

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "uploadFile":
            guard let args = call.arguments as? [String: Any] else {
                result(FlutterError(code: "INVALID_ARGS", message: "参数错误", details: nil))
                return
            }
            handleUploadFile(args: args, result: result)

        case "uploadChunk":
            guard let args = call.arguments as? [String: Any] else {
                result(FlutterError(code: "INVALID_ARGS", message: "参数错误", details: nil))
                return
            }
            handleUploadChunk(args: args, result: result)

        case "mergeChunks":
            guard let args = call.arguments as? [String: Any] else {
                result(FlutterError(code: "INVALID_ARGS", message: "参数错误", details: nil))
                return
            }
            handleMergeChunks(args: args, result: result)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - 小文件 multipart 上传

    private func handleUploadFile(args: [String: Any], result: @escaping FlutterResult) {
        guard let filePath = args["filePath"] as? String,
              let fileName = args["fileName"] as? String,
              let uploadUrl = args["uploadUrl"] as? String,
              let apiKey = args["apiKey"] as? String,
              let uploadId = args["uploadId"] as? String else {
            result(FlutterError(code: "MISSING_PARAMS", message: "缺少必要参数", details: nil))
            return
        }

        let userId = args["userId"] as? String ?? ""
        let stem = args["stem"] as? String ?? "vocals"
        let trackTitle = args["trackTitle"] as? String ?? ""
        let outputFormat = args["outputFormat"] as? String ?? "mp3"

        // 在后台线程构建 multipart body 并写入临时文件
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            let boundary = "Boundary-\(UUID().uuidString)"
            let tempFileURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("upload_\(uploadId).tmp")

            do {
                let fileData = try Data(contentsOf: URL(fileURLWithPath: filePath))

                var body = Data()
                // file 字段
                body.append("--\(boundary)\r\n")
                body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n")
                body.append("Content-Type: application/octet-stream\r\n\r\n")
                body.append(fileData)
                body.append("\r\n")

                // 其他表单字段
                let fields: [(String, String)] = [
                    ("user_id", userId),
                    ("stem", stem),
                    ("track_title", trackTitle),
                    ("output_format", outputFormat),
                ]
                for (key, value) in fields {
                    body.append("--\(boundary)\r\n")
                    body.append("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n")
                    body.append("\(value)\r\n")
                }
                body.append("--\(boundary)--\r\n")

                try body.write(to: tempFileURL)

                var request = URLRequest(url: URL(string: uploadUrl)!)
                request.httpMethod = "POST"
                request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
                request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")

                let task = self.activeSession.uploadTask(with: request, fromFile: tempFileURL)
                self.taskIdMap[task.taskIdentifier] = uploadId
                task.resume()

                DispatchQueue.main.async {
                    result(true)
                }
            } catch {
                DispatchQueue.main.async {
                    result(FlutterError(code: "FILE_ERROR", message: "文件读取失败: \(error.localizedDescription)", details: nil))
                }
            }
        }
    }

    // MARK: - 分块上传

    private func handleUploadChunk(args: [String: Any], result: @escaping FlutterResult) {
        guard let filePath = args["filePath"] as? String,
              let uploadUrl = args["uploadUrl"] as? String,
              let apiKey = args["apiKey"] as? String,
              let uploadId = args["uploadId"] as? String,
              let chunkIndex = args["chunkIndex"] as? Int,
              let chunkOffset = args["chunkOffset"] as? Int,
              let chunkLength = args["chunkLength"] as? Int else {
            result(FlutterError(code: "MISSING_PARAMS", message: "缺少必要参数", details: nil))
            return
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            let tempFileURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("chunk_\(uploadId)_\(chunkIndex).tmp")

            do {
                let fileHandle = try FileHandle(forReadingFrom: URL(fileURLWithPath: filePath))
                fileHandle.seek(toFileOffset: UInt64(chunkOffset))
                let chunkData = fileHandle.readData(ofLength: chunkLength)
                fileHandle.closeFile()

                try chunkData.write(to: tempFileURL)

                var request = URLRequest(url: URL(string: uploadUrl)!)
                request.httpMethod = "POST"
                request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
                request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
                request.setValue("\(chunkLength)", forHTTPHeaderField: "Content-Length")

                let chunkUploadId = "\(uploadId)_chunk_\(chunkIndex)"
                let task = self.activeSession.uploadTask(with: request, fromFile: tempFileURL)
                self.taskIdMap[task.taskIdentifier] = chunkUploadId
                task.resume()

                DispatchQueue.main.async {
                    result(true)
                }
            } catch {
                DispatchQueue.main.async {
                    result(FlutterError(code: "CHUNK_ERROR", message: "分块读取失败: \(error.localizedDescription)", details: nil))
                }
            }
        }
    }

    // MARK: - 合并请求

    private func handleMergeChunks(args: [String: Any], result: @escaping FlutterResult) {
        guard let mergeUrl = args["mergeUrl"] as? String,
              let apiKey = args["apiKey"] as? String,
              let uploadId = args["uploadId"] as? String else {
            result(FlutterError(code: "MISSING_PARAMS", message: "缺少必要参数", details: nil))
            return
        }

        // 合并是 GET 请求，用 dataTask 而非 uploadTask
        // 但 background session 不支持 dataTask, 所以用空文件的 upload task
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            let tempFileURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("merge_\(uploadId).tmp")

            do {
                // 写入空数据
                try Data().write(to: tempFileURL)

                var request = URLRequest(url: URL(string: mergeUrl)!)
                request.httpMethod = "GET"
                request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")

                let mergeUploadId = "\(uploadId)_merge"
                let task = self.activeSession.uploadTask(with: request, fromFile: tempFileURL)
                self.taskIdMap[task.taskIdentifier] = mergeUploadId
                task.resume()

                DispatchQueue.main.async {
                    result(true)
                }
            } catch {
                DispatchQueue.main.async {
                    result(FlutterError(code: "MERGE_ERROR", message: "合并请求失败: \(error.localizedDescription)", details: nil))
                }
            }
        }
    }

    // MARK: - URLSessionDataDelegate — 接收响应体数据

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let taskId = dataTask.taskIdentifier
        if responseDataMap[taskId] != nil {
            responseDataMap[taskId]!.append(data)
        } else {
            responseDataMap[taskId] = data
        }
    }

    // MARK: - URLSessionTaskDelegate — 任务完成/失败

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let taskIdentifier = task.taskIdentifier

        // 跳过没有映射的 task（上次 session 残留的后台任务）
        guard let uploadId = taskIdMap[taskIdentifier] else {
            NSLog("[BackgroundUpload] ⏭ 忽略残留任务 taskId=\(taskIdentifier)")
            return
        }

        // 清理临时文件
        cleanupTempFiles(for: uploadId)

        if let error = error {
            let nsError = error as NSError
            let isCancelled = nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
            let isTimeout = nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorTimedOut
            let isNetworkLost = nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorNetworkConnectionLost

            if isCancelled {
                NSLog("[BackgroundUpload] ⚠️ 任务被取消 \(uploadId)（可能 App 切后台），chunked_uploader 将自动重试")
            } else if isTimeout {
                NSLog("[BackgroundUpload] ⏰ 任务超时 \(uploadId)，chunked_uploader 将自动重试")
            } else if isNetworkLost {
                NSLog("[BackgroundUpload] 📡 网络连接中断 \(uploadId)，chunked_uploader 将自动重试")
            } else {
                NSLog("[BackgroundUpload] ❌ 任务失败 \(uploadId): \(error.localizedDescription)")
            }

            sendEvent([
                "type": "error",
                "uploadId": uploadId,
                "error": error.localizedDescription,
                "isRetryable": isCancelled || isTimeout || isNetworkLost,
            ])
        } else {
            // 尝试解析响应
            var responseBody: String? = nil
            if let data = responseDataMap[taskIdentifier] {
                responseBody = String(data: data, encoding: .utf8)
            }

            let httpResponse = task.response as? HTTPURLResponse
            let statusCode = httpResponse?.statusCode ?? 0

            NSLog("[BackgroundUpload] ✅ 任务完成 \(uploadId), status: \(statusCode)")

            if statusCode >= 200 && statusCode < 300 {
                sendEvent([
                    "type": "complete",
                    "uploadId": uploadId,
                    "statusCode": statusCode,
                    "body": responseBody ?? "",
                ])
            } else {
                sendEvent([
                    "type": "error",
                    "uploadId": uploadId,
                    "error": "HTTP \(statusCode): \(responseBody ?? "无响应")",
                ])
            }
        }

        // 清理映射
        taskIdMap.removeValue(forKey: taskIdentifier)
        responseDataMap.removeValue(forKey: taskIdentifier)
        lastProgressMap.removeValue(forKey: taskIdentifier)
    }

    // MARK: - URLSession 发送进度

    /// 上次发送的进度值（用于节流）
    private var lastProgressMap: [Int: Int] = [:]

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didSendBodyData bytesSent: Int64,
                    totalBytesSent: Int64,
                    totalBytesExpectedToSend: Int64) {
        let taskIdentifier = task.taskIdentifier

        // 跳过没有映射的 task（上次 session 残留的后台任务）
        guard let uploadId = taskIdMap[taskIdentifier] else {
            return
        }

        let progress: Int
        if totalBytesExpectedToSend > 0 {
            progress = Int(Double(totalBytesSent) / Double(totalBytesExpectedToSend) * 100)
        } else {
            progress = 0
        }

        // 节流：进度变化小于 1% 则不发送（避免淹没 EventChannel）
        let lastProgress = lastProgressMap[taskIdentifier] ?? -1
        if progress == lastProgress {
            return
        }
        lastProgressMap[taskIdentifier] = progress

        NSLog("[BackgroundUpload] 📊 进度: \(uploadId) → \(progress)% (\(totalBytesSent)/\(totalBytesExpectedToSend))")

        sendEvent([
            "type": "progress",
            "uploadId": uploadId,
            "bytesSent": totalBytesSent,
            "totalBytes": totalBytesExpectedToSend,
            "progress": progress,
        ])
    }

    // MARK: - 后台会话完成

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        NSLog("[BackgroundUpload] 后台会话事件处理完成")
        DispatchQueue.main.async { [weak self] in
            self?.backgroundCompletionHandler?()
            self?.backgroundCompletionHandler = nil
        }
    }

    // MARK: - 工具方法

    private func sendEvent(_ data: [String: Any]) {
        DispatchQueue.main.async { [weak self] in
            self?.eventSink?(data)
        }
    }

    private func cleanupTempFiles(for uploadId: String) {
        let tempDir = FileManager.default.temporaryDirectory
        let fileManager = FileManager.default

        // 尝试清理可能的临时文件
        let patterns = [
            "upload_\(uploadId).tmp",
            "merge_\(uploadId).tmp",
        ]

        for pattern in patterns {
            let url = tempDir.appendingPathComponent(pattern)
            try? fileManager.removeItem(at: url)
        }

        // 清理分块临时文件（匹配 chunk_uploadId_*.tmp）
        if let files = try? fileManager.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil) {
            let baseId = uploadId.components(separatedBy: "_chunk_").first ?? uploadId
            for file in files {
                if file.lastPathComponent.hasPrefix("chunk_\(baseId)_") {
                    try? fileManager.removeItem(at: file)
                }
            }
        }
    }
}

// MARK: - FlutterStreamHandler (EventChannel)

extension BackgroundUploadManager: FlutterStreamHandler {
    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = events
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        self.eventSink = nil
        return nil
    }
}

// MARK: - Data 扩展

private extension Data {
    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}
