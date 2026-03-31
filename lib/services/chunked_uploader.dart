// 分块上传模块
// 对应原 chunked-uploader.ts
// 用于大文件上传（>10MB），分块上传 + 合并
// 已改为通过 iOS 原生 BackgroundUploadChannel 实现后台上传
// 支持细粒度进度回调：每个分块的字节进度汇总计算总进度
import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'background_upload_channel.dart';

/// 默认分块大小：5MB（减少 HTTP 请求数以提升速度）
const int defaultChunkSize = 5 * 1024 * 1024;

/// 最大并发上传数
const int maxConcurrency = 5;

/// 单个分块最大重试次数
const int maxChunkRetries = 5;

class ChunkedUploadOptions {
  final String filePath;
  final String fileName;
  final int totalSize;
  final String userId;
  final String stem;
  final String trackTitle;
  final String outputFormat;
  final void Function(int progress)? onProgress;
  final void Function(String stemTaskId)? onComplete;
  final void Function(String errorMessage)? onError;
  final int chunkSize;

  ChunkedUploadOptions({
    required this.filePath,
    required this.fileName,
    required this.totalSize,
    required this.userId,
    required this.stem,
    required this.trackTitle,
    this.outputFormat = 'mp3',
    this.onProgress,
    this.onComplete,
    this.onError,
    this.chunkSize = defaultChunkSize,
  });
}

/// 启动分块上传（通过原生后台通道）
void startChunkedUpload(ChunkedUploadOptions options) {
  _ChunkedUploader(options).run();
}

class _ChunkedUploader {
  final ChunkedUploadOptions opts;
  final BackgroundUploadChannel _bgChannel = BackgroundUploadChannel.instance;
  final int totalChunks;
  final String identifier;
  bool aborted = false;

  /// 每个分块的进度（0~100），用于计算总体进度
  late final List<int> _chunkProgress;

  /// 上一次回调给外部的总进度值（避免重复回调相同值）
  int _lastReportedProgress = -1;

  _ChunkedUploader(this.opts)
      : totalChunks = (opts.totalSize / opts.chunkSize).ceil(),
        identifier =
            '${DateTime.now().millisecondsSinceEpoch}_${_randomString(8)}' {
    _chunkProgress = List.filled(totalChunks, 0);
  }

  static String _randomString(int length) {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final rng = Random();
    return List.generate(length, (_) => chars[rng.nextInt(chars.length)]).join();
  }

  void _handleError(String msg) {
    if (aborted) return;
    aborted = true;
    debugPrint('[ChunkedUpload] ❌ $msg');
    opts.onError?.call(msg);
  }

  /// 计算并回调总体进度（0~45 映射区间，留 45~50 给合并）
  void _reportAggregateProgress() {
    // 按字节加权计算进度，而非简单平均
    // 最后一块可能比其他块小，所以用实际大小加权
    double totalWeightedProgress = 0;
    bool anyStarted = false;
    for (int i = 0; i < totalChunks; i++) {
      if (_chunkProgress[i] > 0) anyStarted = true;
      final chunkLen = min(opts.chunkSize, opts.totalSize - i * opts.chunkSize);
      totalWeightedProgress += _chunkProgress[i] / 100.0 * chunkLen;
    }
    final overallPercent = totalWeightedProgress / opts.totalSize;

    // 映射到 1~45 的区间（有活动时至少显示 1%）
    int progress;
    if (!anyStarted) {
      progress = 0;
    } else {
      progress = max(1, (overallPercent * 44 + 1).round());
      progress = min(progress, 45);
    }

    if (progress != _lastReportedProgress) {
      _lastReportedProgress = progress;
      opts.onProgress?.call(progress);
    }
  }

  /// 上传单个分块（通过原生后台通道，含重试）
  /// 每个分块独立重试，超时保护 180 秒
  Future<void> _uploadChunkWithRetry(int index) async {
    final chunkOffset = index * opts.chunkSize;
    final chunkLength = min(opts.chunkSize, opts.totalSize - chunkOffset);

    for (int attempt = 1; attempt <= maxChunkRetries; attempt++) {
      if (aborted) return;

      try {
        // 添加超时保护：单个分块最多等待 120 秒
        await _bgChannel.uploadChunk(
          filePath: opts.filePath,
          uploadId: identifier,
          chunkIndex: index,
          chunkOffset: chunkOffset,
          chunkLength: chunkLength,
          identifier: identifier,
          fileName: opts.fileName,
          totalChunks: totalChunks,
          totalSize: opts.totalSize,
          onProgress: (p) {
            // 更新此分块的进度并计算总进度
            _chunkProgress[index] = p;
            _reportAggregateProgress();
          },
        ).timeout(
          const Duration(seconds: 180),
          onTimeout: () {
            throw TimeoutException('分块 $index 上传超时 (180s)', const Duration(seconds: 180));
          },
        );

        // 分块完成，标记为 100%
        _chunkProgress[index] = 100;
        _reportAggregateProgress();

        debugPrint(
            '[ChunkedUpload] ✅ 分块 ${index + 1}/$totalChunks 完成');
        return;
      } catch (e) {
        debugPrint(
            '[ChunkedUpload] 分块 $index 第 $attempt/$maxChunkRetries 次失败: $e');

        // 失败重置此分块进度
        _chunkProgress[index] = 0;

        if (attempt >= maxChunkRetries) rethrow;

        // 指数退避：1s → 2s → 4s → 8s → 10s（上限）
        final waitMs = min(1000 * pow(2, attempt - 1).toInt(), 10000);
        debugPrint('[ChunkedUpload] ⏳ 等待 ${waitMs}ms 后重试分块 $index (第 $attempt 次失败)...');
        await Future.delayed(Duration(milliseconds: waitMs));
      }
    }
  }

  /// 并发控制器
  /// 改进：单个分块失败不会立即 abort 其他分块
  /// 只有当分块重试全部耗尽后才终止整体上传
  Future<void> _runWithConcurrency(
      List<Future<void> Function()> tasks, int concurrency) async {
    int nextIndex = 0;
    final errors = <Object>[];

    Future<void> worker() async {
      while (nextIndex < tasks.length && !aborted) {
        final currentIndex = nextIndex++;
        try {
          await tasks[currentIndex]();
        } catch (e) {
          // 分块已经过 maxChunkRetries 次重试仍失败，终止整体上传
          debugPrint('[ChunkedUpload] 💀 分块 $currentIndex 重试耗尽，终止上传');
          errors.add(e);
          aborted = true;
          return;
        }
      }
    }

    final workers = List.generate(
      min(concurrency, tasks.length),
      (_) => worker(),
    );
    await Future.wait(workers);

    if (errors.isNotEmpty) {
      throw errors.first;
    }
  }

  /// 合并分块（通过原生后台通道，含重试）
  Future<void> _mergeChunks() async {
    debugPrint('[ChunkedUpload] 🔗 所有分块上传完成，请求合并...');
    opts.onProgress?.call(47);

    const maxMergeRetries = 3;
    for (int attempt = 1; attempt <= maxMergeRetries; attempt++) {
      try {
        final stemTaskId = await _bgChannel.mergeChunks(
          uploadId: identifier,
          identifier: identifier,
          fileName: opts.fileName,
          userId: opts.userId,
          stem: opts.stem,
          trackTitle: opts.trackTitle,
          outputFormat: opts.outputFormat,
        ).timeout(
          const Duration(seconds: 120),
          onTimeout: () {
            throw TimeoutException('合并请求超时 (120s)', const Duration(seconds: 120));
          },
        );

        debugPrint('[ChunkedUpload] ✅ 合并成功，stem_task_id: $stemTaskId');
        opts.onProgress?.call(50);
        opts.onComplete?.call(stemTaskId);
        return;
      } catch (e) {
        debugPrint('[ChunkedUpload] 合并请求第 $attempt/$maxMergeRetries 次失败: $e');
        if (attempt >= maxMergeRetries) rethrow;
        final waitMs = 2000 * attempt;
        debugPrint('[ChunkedUpload] ⏳ 等待 ${waitMs}ms 后重试合并...');
        await Future.delayed(Duration(milliseconds: waitMs));
      }
    }
  }

  /// 主上传流程
  Future<void> run() async {
    try {
      debugPrint(
          '[ChunkedUpload] 🚀 开始分块上传: ${opts.fileName}, 大小: ${opts.totalSize}, '
          '分块数: $totalChunks, 并发: $maxConcurrency, identifier: $identifier');

      // 初始进度
      opts.onProgress?.call(0);

      final tasks = List.generate(
        totalChunks,
        (i) => () => _uploadChunkWithRetry(i),
      );

      await _runWithConcurrency(tasks, maxConcurrency);

      if (!aborted) {
        await _mergeChunks();
      }
    } catch (e) {
      _handleError(e.toString());
    }
  }
}
