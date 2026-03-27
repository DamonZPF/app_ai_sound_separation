// 分块上传模块
// 对应原 chunked-uploader.ts
// 用于大文件上传（>10MB），分块上传 + 合并
import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../config/env.dart';

/// 默认分块大小：2MB
const int defaultChunkSize = 2 * 1024 * 1024;

/// 最大并发上传数
const int maxConcurrency = 5;

/// 单个分块上传超时（秒）— 慢网络下 2MB 分块需要更长时间
const int chunkUploadTimeoutSec = 300;

/// 单个分块最大重试次数
const int maxChunkRetries = 3;

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

/// 启动分块上传
void startChunkedUpload(ChunkedUploadOptions options) {
  _ChunkedUploader(options).run();
}

class _ChunkedUploader {
  final ChunkedUploadOptions opts;
  final Dio _dio = Dio();
  final int totalChunks;
  final String identifier;
  int uploadedCount = 0;
  bool aborted = false;

  _ChunkedUploader(this.opts)
      : totalChunks = (opts.totalSize / opts.chunkSize).ceil(),
        identifier =
            '${DateTime.now().millisecondsSinceEpoch}_${_randomString(8)}';

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

  /// 读取文件分块
  Future<Uint8List> _readChunk(int index) async {
    final file = File(opts.filePath);
    final raf = await file.open();
    try {
      final offset = index * opts.chunkSize;
      final length = min(opts.chunkSize, opts.totalSize - offset);
      await raf.setPosition(offset);
      final bytes = await raf.read(length);
      return Uint8List.fromList(bytes);
    } finally {
      await raf.close();
    }
  }

  /// 上传单个分块
  Future<void> _uploadChunk(int index, Uint8List data, int length) async {
    final url =
        '${Env.stemApiUrl}/stem/chunk/upload?identifier=${Uri.encodeComponent(identifier)}'
        '&index=$index&chunkSize=$length'
        '&fileName=${Uri.encodeComponent(opts.fileName)}'
        '&totalChunks=$totalChunks&totalSize=${opts.totalSize}';

    await _dio.post(
      url,
      data: data,
      options: Options(
        headers: {
          'X-API-Key': Env.stemApiKey,
          'Content-Type': 'application/octet-stream',
          'Content-Length': length,
        },
        sendTimeout: Duration(seconds: chunkUploadTimeoutSec),
        receiveTimeout: Duration(seconds: chunkUploadTimeoutSec),
      ),
    );
  }

  /// 上传单个分块（含重试）
  Future<void> _uploadChunkWithRetry(int index) async {
    final length = min(opts.chunkSize, opts.totalSize - index * opts.chunkSize);

    for (int attempt = 1; attempt <= maxChunkRetries; attempt++) {
      if (aborted) return;

      try {
        final data = await _readChunk(index);
        await _uploadChunk(index, data, length);

        uploadedCount++;
        final progress = (uploadedCount / totalChunks * 45).floor();
        opts.onProgress?.call(progress);
        debugPrint(
            '[ChunkedUpload] ✅ 分块 ${index + 1}/$totalChunks 完成 (进度: $progress%)');
        return;
      } catch (e) {
        debugPrint(
            '[ChunkedUpload] 分块 $index 第 $attempt/$maxChunkRetries 次失败: $e');
        if (attempt >= maxChunkRetries) rethrow;

        final waitMs = min(2000 * pow(2, attempt - 1).toInt(), 10000);
        debugPrint('[ChunkedUpload] ⏳ 等待 ${waitMs}ms 后重试分块 $index...');
        await Future.delayed(Duration(milliseconds: waitMs));
      }
    }
  }

  /// 并发控制器
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

  /// 合并分块
  Future<void> _mergeChunks() async {
    debugPrint('[ChunkedUpload] 🔗 所有分块上传完成，请求合并...');
    opts.onProgress?.call(47);

    final params = {
      'identifier': identifier,
      'fileName': opts.fileName,
      'user_id': opts.userId,
      'stem': opts.stem,
      'track_title': opts.trackTitle,
      'output_format': opts.outputFormat,
    };

    final queryStr =
        params.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&');

    final res = await _dio.get(
      '${Env.stemApiUrl}/stem/chunk/merge?$queryStr',
      options: Options(
        headers: {'X-API-Key': Env.stemApiKey},
        receiveTimeout: const Duration(seconds: 60),
      ),
    );

    final data = res.data;
    final stemTaskId = data?['stem_task_id'];
    if (stemTaskId == null) {
      throw Exception('服务器未返回 stem_task_id');
    }

    debugPrint('[ChunkedUpload] ✅ 合并成功，stem_task_id: $stemTaskId');
    opts.onProgress?.call(50);
    opts.onComplete?.call(stemTaskId.toString());
  }

  /// 主上传流程
  Future<void> run() async {
    try {
      debugPrint(
          '[ChunkedUpload] 🚀 开始分块上传: ${opts.fileName}, 大小: ${opts.totalSize}, '
          '分块数: $totalChunks, 并发: $maxConcurrency, identifier: $identifier');

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
