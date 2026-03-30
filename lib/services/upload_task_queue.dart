// 上传任务队列服务
// 对应小程序 stem-api.ts 中 pendingTasks 本地队列逻辑
// 管理本地上传任务的生命周期：添加 → 上传 → 轮询 → 完成/失败
// 支持持久化：App 重启后恢复队列状态
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/stem_task.dart';
import 'stem_api_service.dart';
import 'pending_task_store.dart';

class UploadTaskQueue {
  UploadTaskQueue._();
  static final UploadTaskQueue instance = UploadTaskQueue._();

  final StemApiService _api = StemApiService();

  static const String _storageKey = 'upload_task_queue';

  /// 本地待处理任务列表（UI 监听此 notifier 刷新界面）
  final ValueNotifier<List<StemTask>> tasksNotifier =
      ValueNotifier<List<StemTask>>([]);

  List<StemTask> get tasks => tasksNotifier.value;

  int _localIdCounter = 0;

  /// 持久化防抖定时器（避免进度更新时高频写磁盘）
  Timer? _persistDebounceTimer;

  /// 上次回调给 UI 的进度值（用于节流，减少对象重建）
  final Map<String, int> _lastNotifiedProgress = {};

  /// 初始化：从持久化存储恢复队列
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_storageKey);
    if (jsonStr == null || jsonStr.isEmpty) {
      debugPrint('[TaskQueue] 📭 无持久化队列');
      return;
    }

    try {
      final List<dynamic> list = json.decode(jsonStr);
      final restored = list
          .map((e) => StemTask.fromJson(e as Map<String, dynamic>))
          .toList();

      if (restored.isEmpty) return;

      // 对恢复的任务进行状态修正
      for (int i = restored.length - 1; i >= 0; i--) {
        final task = restored[i];
        final filePath = task.uploadParams?.filePath ?? '';
        final isLocalFile = filePath.isNotEmpty && !filePath.startsWith('http');

        // 本地文件任务：检查文件是否还在
        if (isLocalFile && task.status != 'processing') {
          if (!File(filePath).existsSync()) {
            debugPrint('[TaskQueue] 🗑 移除失效任务: ${task.stemTaskId}（文件不存在）');
            restored.removeAt(i);
            continue;
          }
        }

        if (task.status == 'uploading') {
          // 上传中的任务：原生上传可能已经完成，但 Dart 回调已断
          // 标记为失败，用户可重试
          restored[i] = StemTask(
            stemTaskId: task.stemTaskId,
            trackTitle: task.trackTitle,
            stem: task.stem,
            status: 'failed',
            createdAt: task.createdAt,
            progress: task.progress,
            errorMessage: '上传已中断，请重试',
            uploadParams: task.uploadParams,
          );
        }
        // processing / completed / failed 保持原状
      }

      tasksNotifier.value = restored;
      await _persist();
      debugPrint('[TaskQueue] ♻️ 恢复 ${restored.length} 个队列任务');
    } catch (e) {
      debugPrint('[TaskQueue] 恢复失败: $e');
    }
  }

  /// 持久化当前队列到 SharedPreferences
  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // 只持久化未完成的任务（完成的会出现在远程历史中）
      final activeTasks = tasks.where((t) => !t.isCompleted).toList();
      final jsonStr = json.encode(activeTasks.map((t) => t.toJson()).toList());
      await prefs.setString(_storageKey, jsonStr);
    } catch (e) {
      debugPrint('[TaskQueue] 持久化失败: $e');
    }
  }

  /// 添加一个新的本地上传任务，立即返回 taskId（不阻塞）
  Future<String> addTask({
    required String filePath,
    required String fileName,
    required String stem,
    String outputFormat = 'mp3',
  }) async {
    final now = DateTime.now();
    final localId = 'local_${now.millisecondsSinceEpoch}_${_localIdCounter++}';
    final apiStem = mapTypeIdToStem(stem); // UI typeId → API stem

    // 将文件从 tmp 复制到永久目录，确保 App 重启后文件仍在
    final persistedPath = await _copyToPersistedPath(filePath, localId);
    final fileSize = File(persistedPath).lengthSync();

    final task = StemTask(
      stemTaskId: localId,
      trackTitle: _getTrackTitle(fileName),
      stem: apiStem,
      status: 'uploading',
      createdAt: now.toIso8601String(),
      progress: 0,
      uploadParams: UploadParams(
        filePath: persistedPath,
        fileName: fileName,
        stem: apiStem,
        outputFormat: outputFormat,
        fileSize: fileSize,
      ),
    );

    tasksNotifier.value = [task, ...tasks];
    _persist();
    debugPrint('[TaskQueue] ✅ 已添加任务: $localId ($fileName)');
    return localId;
  }

  /// 添加一个 URL 提交任务（无文件上传）
  String addUrlTask({
    required String audioUrl,
    required String stem,
    String outputFormat = 'mp3',
  }) {
    final now = DateTime.now();
    final localId = 'local_${now.millisecondsSinceEpoch}_${_localIdCounter++}';
    final apiStem = mapTypeIdToStem(stem);

    final task = StemTask(
      stemTaskId: localId,
      trackTitle: _getTrackTitleFromUrl(audioUrl),
      stem: apiStem,
      status: 'uploading',
      createdAt: now.toIso8601String(),
      progress: 0,
      uploadParams: UploadParams(
        filePath: audioUrl, // URL 存在 filePath 字段
        fileName: audioUrl,
        stem: apiStem,
        outputFormat: outputFormat,
      ),
    );

    tasksNotifier.value = [task, ...tasks];
    _persist();
    debugPrint('[TaskQueue] ✅ 已添加URL任务: $localId');
    return localId;
  }

  /// 后台启动处理（上传 + 轮询），调用后立即返回
  void startProcessing(String localId) {
    _processTask(localId);
  }

  /// 重试失败任务
  void retryTask(String localId) {
    final task = tasks.firstWhere(
      (t) => t.stemTaskId == localId,
      orElse: () => StemTask(stemTaskId: '', trackTitle: '', stem: '', status: 'unknown', createdAt: ''),
    );
    if (task.stemTaskId.isEmpty) return;

    // 检查文件是否存在
    final filePath = task.uploadParams?.filePath ?? '';
    if (filePath.isNotEmpty && !filePath.startsWith('http') && !File(filePath).existsSync()) {
      _markFailed(localId, '文件已被清理，请重新选择文件上传');
      return;
    }

    _updateTask(localId, (t) => StemTask(
          stemTaskId: t.stemTaskId,
          trackTitle: t.trackTitle,
          stem: t.stem,
          status: 'uploading',
          createdAt: t.createdAt,
          progress: 0,
          errorMessage: null,
          uploadParams: t.uploadParams,
        ));
    _processTask(localId);
  }

  /// 移除本地任务（同时清理持久化文件）
  void removeTask(String localId) {
    final task = tasks.firstWhere(
      (t) => t.stemTaskId == localId,
      orElse: () => StemTask(stemTaskId: '', trackTitle: '', stem: '', status: 'unknown', createdAt: ''),
    );
    // 清理持久化的文件副本
    _cleanupPersistedFile(task.uploadParams?.filePath);

    tasksNotifier.value =
        tasks.where((t) => t.stemTaskId != localId).toList();
    _persist();
  }

  // ──────────────────────────────────────────────
  // 内部：后台处理流程
  // ──────────────────────────────────────────────

  Future<void> _processTask(String localId) async {
    final task = tasks.firstWhere(
      (t) => t.stemTaskId == localId,
      orElse: () => StemTask(stemTaskId: '', trackTitle: '', stem: '', status: 'unknown', createdAt: ''),
    );
    if (task.stemTaskId.isEmpty) return;

    final params = task.uploadParams;
    if (params == null) {
      _markFailed(localId, '缺少上传参数');
      return;
    }

    try {
      String stemTaskId;

      // 判断是 URL 任务还是文件任务
      final isUrl = params.filePath.startsWith('http://') ||
          params.filePath.startsWith('https://');

      if (isUrl) {
        // URL 提交
        _updateProgress(localId, 10);
        stemTaskId = await _api.submitUrl(
          audioUrl: params.filePath,
          stem: params.stem,
          outputFormat: params.outputFormat,
        );
        _updateProgress(localId, 50);
      } else {
        // 文件上传
        stemTaskId = await _api.uploadAndSeparate(
          filePath: params.filePath,
          fileName: params.fileName,
          stem: params.stem,
          outputFormat: params.outputFormat,
          onProgress: (p) => _updateProgress(localId, p),
        );
      }

      debugPrint('[TaskQueue] 上传完成, stemTaskId: $stemTaskId, 开始轮询...');

      // 持久化到 PendingTaskStore（App 重启后可恢复轮询）
      final currentTask = tasks.firstWhere(
        (t) => t.stemTaskId == localId,
        orElse: () => StemTask(stemTaskId: '', trackTitle: '', stem: '', status: 'unknown', createdAt: ''),
      );
      if (currentTask.stemTaskId.isNotEmpty) {
        await PendingTaskStore.instance.addTask(PendingTask(
          stemTaskId: stemTaskId,
          trackTitle: currentTask.trackTitle,
          stem: currentTask.stem,
          createdAt: currentTask.createdAt,
        ));
      }

      // 更新状态为 processing，记录服务端 taskId
      _updateTask(localId, (t) => StemTask(
            stemTaskId: t.stemTaskId,
            trackTitle: t.trackTitle,
            stem: t.stem,
            status: 'processing',
            createdAt: t.createdAt,
            progress: 50,
            uploadParams: t.uploadParams,
          ));

      // 轮询
      final result = await _api.pollTask(
        stemTaskId,
        onProgress: (p) => _updateProgress(localId, p),
      );

      if (result == null) {
        _markFailed(localId, '处理超时');
        // 超时也从持久化层移除
        await PendingTaskStore.instance.removeTask(stemTaskId);
        return;
      }

      if (result.isFailed) {
        _markFailed(localId, result.errorMessage ?? '处理失败');
        // 失败也从持久化层移除
        await PendingTaskStore.instance.removeTask(stemTaskId);
        return;
      }

      // 完成 — 清理持久化文件 + 更新状态
      final completedTask = tasks.firstWhere(
        (t) => t.stemTaskId == localId,
        orElse: () => StemTask(stemTaskId: '', trackTitle: '', stem: '', status: 'unknown', createdAt: ''),
      );
      _cleanupPersistedFile(completedTask.uploadParams?.filePath);
      _lastNotifiedProgress.remove(localId);

      _updateTask(localId, (t) => StemTask(
            stemTaskId: t.stemTaskId,
            trackTitle: result.trackTitle,
            stem: result.stem,
            status: 'completed',
            createdAt: result.createdAt,
            progress: 100,
            uploadParams: t.uploadParams,
            results: result.results,
          ), persist: true);

      // 完成后从持久化层移除
      await PendingTaskStore.instance.removeTask(stemTaskId);
      debugPrint('[TaskQueue] ✅ 任务完成: $localId');
    } catch (e) {
      debugPrint('[TaskQueue] ❌ 处理失败: $localId, $e');
      _markFailed(localId, e.toString());
    }
  }

  void _updateProgress(String localId, int progress) {
    // 进度只增不减（防止分块重试或服务端波动导致回退）
    final lastProgress = _lastNotifiedProgress[localId] ?? -2;
    if (progress < lastProgress && progress != 0) {
      return;
    }
    // P3: 节流 — 进度变化 < 2% 时跳过 UI 更新，减少对象重建
    if ((progress - lastProgress).abs() < 2 && progress != 0 && progress != 100) {
      return;
    }
    _lastNotifiedProgress[localId] = progress;

    debugPrint('[TaskQueue] 📊 进度更新: $localId → $progress%');
    // P1: 进度更新不立即写磁盘，仅刷新 UI
    _updateTask(localId, (t) => StemTask(
          stemTaskId: t.stemTaskId,
          trackTitle: t.trackTitle,
          stem: t.stem,
          status: t.status,
          createdAt: t.createdAt,
          progress: progress,
          errorMessage: t.errorMessage,
          uploadParams: t.uploadParams,
          results: t.results,
        ), persist: false);
  }

  void _markFailed(String localId, String error) {
    _lastNotifiedProgress.remove(localId);
    _updateTask(localId, (t) => StemTask(
          stemTaskId: t.stemTaskId,
          trackTitle: t.trackTitle,
          stem: t.stem,
          status: 'failed',
          createdAt: t.createdAt,
          progress: t.progress,
          errorMessage: error,
          uploadParams: t.uploadParams,
        ), persist: true);
  }

  /// P1: persist 参数控制是否写磁盘
  /// - true: 关键状态变化（添加/完成/失败）立即写入
  /// - false: 进度更新仅刷新 UI，延迟 5 秒后批量写入
  void _updateTask(String localId, StemTask Function(StemTask) updater, {bool persist = true}) {
    final newList = tasks.map((t) {
      if (t.stemTaskId == localId) return updater(t);
      return t;
    }).toList();
    tasksNotifier.value = newList;

    if (persist) {
      _persistDebounceTimer?.cancel();
      _persist();
    } else {
      // 延迟持久化：避免进度更新高频写磁盘，但确保数据不丢
      _persistDebounceTimer?.cancel();
      _persistDebounceTimer = Timer(const Duration(seconds: 5), () {
        _persist();
      });
    }
  }

  // ──────────────────────────────────────────────
  // 工具
  // ──────────────────────────────────────────────

  String _getTrackTitle(String fileName) {
    final dotIndex = fileName.lastIndexOf('.');
    return dotIndex > 0 ? fileName.substring(0, dotIndex) : fileName;
  }

  String _getTrackTitleFromUrl(String url) {
    try {
      final uri = Uri.parse(url);
      final path = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : url;
      return _getTrackTitle(path);
    } catch (_) {
      return 'url_audio';
    }
  }

  /// 将文件从 tmp 复制到 App 永久目录（Documents/uploads/）
  Future<String> _copyToPersistedPath(String srcPath, String localId) async {
    final src = File(srcPath);
    // 如果源文件已经在永久目录中，直接返回
    final appDir = await getApplicationDocumentsDirectory();
    if (srcPath.startsWith(appDir.path)) return srcPath;

    final uploadsDir = Directory('${appDir.path}/uploads');
    if (!uploadsDir.existsSync()) {
      uploadsDir.createSync(recursive: true);
    }

    final ext = srcPath.contains('.') ? srcPath.substring(srcPath.lastIndexOf('.')) : '';
    final destPath = '${uploadsDir.path}/${localId}$ext';
    final dest = await src.copy(destPath);
    debugPrint('[TaskQueue] 📁 文件已复制: ${src.path} → ${dest.path}');
    return dest.path;
  }

  /// 清理持久化的文件副本
  void _cleanupPersistedFile(String? filePath) {
    if (filePath == null || filePath.isEmpty) return;
    try {
      final file = File(filePath);
      if (file.existsSync() && filePath.contains('/uploads/')) {
        file.deleteSync();
        debugPrint('[TaskQueue] 🗑 已清理文件: $filePath');
      }
    } catch (e) {
      debugPrint('[TaskQueue] 清理文件失败: $e');
    }
  }
}
