// Stem API 服务
// 对应原 stem-api.ts 的全部功能
// 上传走 iOS 原生后台通道，轮询/查询仍用 Dio
import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../config/env.dart';
import '../models/stem_task.dart';
import 'background_upload_channel.dart';
import 'chunked_uploader.dart';
import 'supabase_service.dart';

/// 大文件阈值：10MB
const int _chunkedThreshold = 10 * 1024 * 1024;

class StemApiService {
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 30),
  ));
  final BackgroundUploadChannel _bgChannel = BackgroundUploadChannel.instance;
  final Uuid _uuid = const Uuid();

  /// 通用 header
  Map<String, dynamic> _getHeaders() => {
        'X-API-Key': Env.stemApiKey,
      };

  // ----------------------------------------------------------
  // 文件上传 + 分轨（separate_free）
  // ----------------------------------------------------------

  /// 上传文件并发起分轨
  /// 小文件直接 multipart POST，大文件走分块上传
  Future<String> uploadAndSeparate({
    required String filePath,
    required String fileName,
    required String stem,
    String outputFormat = 'mp3',
    void Function(int progress)? onProgress,
  }) async {
    final userId = getCachedUserId() ?? '';
    final file = File(filePath);
    final fileSize = await file.length();
    final trackTitle = _getTrackTitle(fileName);

    debugPrint(
        '[StemAPI] uploadAndSeparate: $fileName, size: $fileSize, stem: $stem');

    if (fileSize > _chunkedThreshold) {
      // 大文件—分块上传
      return _chunkedUpload(
        filePath: filePath,
        fileName: fileName,
        fileSize: fileSize,
        userId: userId,
        stem: stem,
        trackTitle: trackTitle,
        outputFormat: outputFormat,
        onProgress: onProgress,
      );
    } else {
      // 小文件—直接 multipart POST
      return _directUpload(
        filePath: filePath,
        fileName: fileName,
        userId: userId,
        stem: stem,
        trackTitle: trackTitle,
        outputFormat: outputFormat,
        onProgress: onProgress,
      );
    }
  }

  /// 直接上传（小文件，< 10MB）— 通过原生后台通道，含重试
  Future<String> _directUpload({
    required String filePath,
    required String fileName,
    required String userId,
    required String stem,
    required String trackTitle,
    required String outputFormat,
    void Function(int progress)? onProgress,
  }) async {
    onProgress?.call(5);

    const maxRetries = 3;
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        final uploadId = _uuid.v4();
        debugPrint('[StemAPI] 开始后台上传: $fileName (uploadId: $uploadId, 第 $attempt/$maxRetries 次)');

        final stemTaskId = await _bgChannel.uploadFile(
          filePath: filePath,
          fileName: fileName,
          uploadId: uploadId,
          userId: userId,
          stem: stem,
          trackTitle: trackTitle,
          outputFormat: outputFormat,
          onProgress: (p) {
            // 原生层进度 0~100 映射到 5~45
            final mapped = 5 + (p * 0.4).floor();
            onProgress?.call(mapped);
          },
        ).timeout(
          const Duration(seconds: 300),
          onTimeout: () {
            throw TimeoutException('小文件上传超时 (300s)', const Duration(seconds: 300));
          },
        );

        onProgress?.call(50);
        debugPrint('[StemAPI] ✅ 后台上传成功, stemTaskId: $stemTaskId');
        return stemTaskId;
      } catch (e) {
        debugPrint('[StemAPI] 小文件上传第 $attempt/$maxRetries 次失败: $e');
        if (attempt >= maxRetries) rethrow;
        final waitMs = 2000 * attempt;
        debugPrint('[StemAPI] ⏳ 等待 ${waitMs}ms 后重试...');
        await Future.delayed(Duration(milliseconds: waitMs));
      }
    }
    throw Exception('unreachable');
  }

  /// 分块上传（大文件，≥ 10MB）
  Future<String> _chunkedUpload({
    required String filePath,
    required String fileName,
    required int fileSize,
    required String userId,
    required String stem,
    required String trackTitle,
    required String outputFormat,
    void Function(int progress)? onProgress,
  }) async {
    final completer = Completer<String>();

    startChunkedUpload(ChunkedUploadOptions(
      filePath: filePath,
      fileName: fileName,
      totalSize: fileSize,
      userId: userId,
      stem: stem,
      trackTitle: trackTitle,
      outputFormat: outputFormat,
      onProgress: onProgress,
      onComplete: (stemTaskId) => completer.complete(stemTaskId),
      onError: (errMsg) => completer.completeError(Exception(errMsg)),
    ));

    return completer.future;
  }

  // ----------------------------------------------------------
  // URL 提交分轨
  // ----------------------------------------------------------

  /// 提交 URL 链接进行分轨
  Future<String> submitUrl({
    required String audioUrl,
    required String stem,
    String outputFormat = 'mp3',
  }) async {
    final userId = getCachedUserId() ?? '';
    final trackTitle = _getTrackTitleFromUrl(audioUrl);

    debugPrint('[StemAPI] submitUrl: $audioUrl, stem: $stem');

    final res = await _dio.post(
      '${Env.stemApiUrl}/stem/separate_free',
      data: {
        'audio_url': audioUrl,
        'user_id': userId,
        'stem': stem,
        'track_title': trackTitle,
        'output_format': outputFormat,
      },
      options: Options(headers: _getHeaders()),
    );

    final data = res.data;
    final stemTaskId = data['stem_task_id'] ?? data['task_id'] ?? '';
    if (stemTaskId.toString().isEmpty) {
      throw Exception('服务器未返回 stem_task_id');
    }

    debugPrint('[StemAPI] ✅ URL提交成功, stemTaskId: $stemTaskId');
    return stemTaskId.toString();
  }

  // ----------------------------------------------------------
  // 轮询任务状态
  // ----------------------------------------------------------

  /// 获取单个任务详情
  Future<Map<String, dynamic>> getTaskDetail(String stemTaskId) async {
    final res = await _dio.get(
      '${Env.stemApiUrl}/stem/task/$stemTaskId',
      options: Options(headers: _getHeaders()),
    );

    final data = res.data;
    return data is Map<String, dynamic> ? data : {};
  }

  /// 轮询任务，直到完成或失败
  Future<StemTask?> pollTask(
    String stemTaskId, {
    Duration interval = const Duration(seconds: 3),
    int maxAttempts = 200,
    void Function(int progress)? onProgress,
  }) async {
    for (int i = 0; i < maxAttempts; i++) {
      try {
        final data = await getTaskDetail(stemTaskId);
        final status = (data['status'] ?? '').toString();
        final progress = data['progress'];

        if (progress != null && onProgress != null) {
          onProgress(50 + ((progress as num).toInt() * 0.5).floor());
        }

        if (status == 'completed') {
          final List<dynamic>? rawResults = data['results'];
          final results = rawResults
              ?.map((r) => StemResultItem.fromJson(r as Map<String, dynamic>))
              .toList();

          return StemTask(
            stemTaskId: stemTaskId,
            trackTitle: data['track_title']?.toString() ?? '',
            stem: data['stem']?.toString() ?? '',
            status: 'completed',
            createdAt: data['created_at']?.toString() ?? '',
            progress: 100,
            results: results,
          );
        }

        if (status == 'failed' || status == 'error') {
          return StemTask(
            stemTaskId: stemTaskId,
            trackTitle: data['track_title']?.toString() ?? '',
            stem: data['stem']?.toString() ?? '',
            status: 'failed',
            createdAt: data['created_at']?.toString() ?? '',
            errorMessage: data['error']?.toString() ?? 'error_processing_failed',
          );
        }
      } catch (e) {
        debugPrint('[StemAPI] 轮询异常: $e');
      }

      await Future.delayed(interval);
    }

    return null; // 超时
  }

  // ----------------------------------------------------------
  // 历史记录 — 与小程序 getHistoryResults 对齐
  // GET /stem/free_results_all?user_id=xxx&page=1&page_size=50
  // ----------------------------------------------------------

  /// 获取用户历史记录（分轨结果列表）— 自动重试连接错误
  Future<List<StemResultItem>> getHistory({int page = 1, int pageSize = 50}) async {
    final userId = getCachedUserId() ?? '';
    if (userId.isEmpty) return [];

    try {
      final res = await _requestWithRetry(
        () => _dio.get(
          '${Env.stemApiUrl}/stem/free_results_all',
          queryParameters: {
            'user_id': userId,
            'page': page,
            'page_size': pageSize,
          },
          options: Options(headers: _getHeaders()),
        ),
      );

      final data = res.data;
      final List<dynamic> items = data['results'] ?? [];

      return items
          .map<StemResultItem>(
              (item) => StemResultItem.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[StemAPI] getHistory failed: $e');
      return [];
    }
  }

  /// 通用重试包装器（仅对连接类错误重试）
  Future<Response> _requestWithRetry(
    Future<Response> Function() request, {
    int maxRetries = 2,
  }) async {
    for (int attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        return await request();
      } on DioException catch (e) {
        final isRetryable = e.type == DioExceptionType.connectionError ||
            e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.receiveTimeout;

        if (!isRetryable || attempt >= maxRetries) rethrow;

        final waitMs = 1000 * (attempt + 1);
        debugPrint('[StemAPI] ⏳ 连接失败，${waitMs}ms 后重试 (${attempt + 1}/$maxRetries)');
        await Future.delayed(Duration(milliseconds: waitMs));
      }
    }
    throw Exception('unreachable');
  }

  // ----------------------------------------------------------
  // 删除结果 — 与小程序 deleteHistoryResult 对齐
  // DELETE /stem/free_result/{result_id}?user_id=xxx
  // ----------------------------------------------------------

  /// 删除一条历史记录
  Future<bool> deleteResult(String resultId) async {
    final userId = getCachedUserId() ?? '';
    try {
      await _dio.delete(
        '${Env.stemApiUrl}/stem/free_result/$resultId',
        queryParameters: {'user_id': userId},
        options: Options(headers: _getHeaders()),
      );
      debugPrint('[StemAPI] ✅ 删除成功: $resultId');
      return true;
    } catch (e) {
      debugPrint('[StemAPI] 删除失败: $e');
      return false;
    }
  }

  // ----------------------------------------------------------
  // 工具方法
  // ----------------------------------------------------------

  /// 从文件名得到 trackTitle（去扩展名）
  String _getTrackTitle(String fileName) {
    final dotIndex = fileName.lastIndexOf('.');
    return dotIndex > 0 ? fileName.substring(0, dotIndex) : fileName;
  }

  /// 从 URL 得到 trackTitle
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

