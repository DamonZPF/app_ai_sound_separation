// 上传任务队列服务
// 对应小程序 stem-api.ts 中 pendingTasks 本地队列逻辑
// 管理本地上传任务的生命周期：添加 → 上传 → 轮询 → 完成/失败
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/stem_task.dart';
import 'stem_api_service.dart';
import 'pending_task_store.dart';

class UploadTaskQueue {
  UploadTaskQueue._();
  static final UploadTaskQueue instance = UploadTaskQueue._();

  final StemApiService _api = StemApiService();

  /// 本地待处理任务列表（UI 监听此 notifier 刷新界面）
  final ValueNotifier<List<StemTask>> tasksNotifier =
      ValueNotifier<List<StemTask>>([]);

  List<StemTask> get tasks => tasksNotifier.value;

  int _localIdCounter = 0;

  /// 添加一个新的本地上传任务，立即返回 taskId（不阻塞）
  String addTask({
    required String filePath,
    required String fileName,
    required String stem,
    String outputFormat = 'mp3',
  }) {
    final now = DateTime.now();
    final localId = 'local_${now.millisecondsSinceEpoch}_${_localIdCounter++}';
    final fileSize = File(filePath).lengthSync();

    final task = StemTask(
      stemTaskId: localId,
      trackTitle: _getTrackTitle(fileName),
      stem: stem,
      status: 'uploading',
      createdAt: now.toIso8601String(),
      progress: 0,
      uploadParams: UploadParams(
        filePath: filePath,
        fileName: fileName,
        stem: stem,
        outputFormat: outputFormat,
        fileSize: fileSize,
      ),
    );

    tasksNotifier.value = [task, ...tasks];
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

    final task = StemTask(
      stemTaskId: localId,
      trackTitle: _getTrackTitleFromUrl(audioUrl),
      stem: stem,
      status: 'uploading',
      createdAt: now.toIso8601String(),
      progress: 0,
      uploadParams: UploadParams(
        filePath: audioUrl, // URL 存在 filePath 字段
        fileName: audioUrl,
        stem: stem,
        outputFormat: outputFormat,
      ),
    );

    tasksNotifier.value = [task, ...tasks];
    debugPrint('[TaskQueue] ✅ 已添加URL任务: $localId');
    return localId;
  }

  /// 后台启动处理（上传 + 轮询），调用后立即返回
  void startProcessing(String localId) {
    _processTask(localId);
  }

  /// 重试失败任务
  void retryTask(String localId) {
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

  /// 移除本地任务
  void removeTask(String localId) {
    tasksNotifier.value =
        tasks.where((t) => t.stemTaskId != localId).toList();
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

      // 完成
      _updateTask(localId, (t) => StemTask(
            stemTaskId: t.stemTaskId,
            trackTitle: result.trackTitle,
            stem: result.stem,
            status: 'completed',
            createdAt: result.createdAt,
            progress: 100,
            uploadParams: t.uploadParams,
            results: result.results,
          ));

      // 完成后从持久化层移除
      await PendingTaskStore.instance.removeTask(stemTaskId);
      debugPrint('[TaskQueue] ✅ 任务完成: $localId');
    } catch (e) {
      debugPrint('[TaskQueue] ❌ 处理失败: $localId, $e');
      _markFailed(localId, e.toString());
    }
  }

  void _updateProgress(String localId, int progress) {
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
        ));
  }

  void _markFailed(String localId, String error) {
    _updateTask(localId, (t) => StemTask(
          stemTaskId: t.stemTaskId,
          trackTitle: t.trackTitle,
          stem: t.stem,
          status: 'failed',
          createdAt: t.createdAt,
          progress: t.progress,
          errorMessage: error,
          uploadParams: t.uploadParams,
        ));
  }

  void _updateTask(String localId, StemTask Function(StemTask) updater) {
    final newList = tasks.map((t) {
      if (t.stemTaskId == localId) return updater(t);
      return t;
    }).toList();
    tasksNotifier.value = newList;
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
}
