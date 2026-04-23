// Flutter ↔ iOS 原生后台上传通道
// 封装 MethodChannel + EventChannel，对接 BackgroundUploadManager.swift
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../config/env.dart';

class BackgroundUploadChannel {
  BackgroundUploadChannel._();
  static final BackgroundUploadChannel instance = BackgroundUploadChannel._();

  static const _methodChannel =
      MethodChannel('com.zpf.ai_sound_separation/background_upload');
  static const _eventChannel =
      EventChannel('com.zpf.ai_sound_separation/upload_events');

  /// 事件回调映射：uploadId → StreamController
  final Map<String, _UploadCallbacks> _callbacks = {};

  /// 全局事件监听（单次订阅）
  StreamSubscription? _eventSubscription;

  /// 初始化：开始监听原生事件
  void init() {
    _eventSubscription ??=
        _eventChannel.receiveBroadcastStream().listen(_handleEvent);
    debugPrint('[BGUpload] ✅ EventChannel 已初始化');
  }

  /// 释放
  void dispose() {
    _eventSubscription?.cancel();
    _eventSubscription = null;
    _callbacks.clear();
  }

  // ----------------------------------------------------------
  // 小文件 multipart 上传
  // ----------------------------------------------------------

  /// 上传小文件（< 10MB），返回服务器响应中的 stem_task_id
  Future<String> uploadFile({
    required String filePath,
    required String fileName,
    required String uploadId,
    required String userId,
    required String stem,
    required String trackTitle,
    String outputFormat = 'mp3',
    void Function(int progress)? onProgress,
  }) async {
    final completer = Completer<String>();

    _callbacks[uploadId] = _UploadCallbacks(
      onProgress: onProgress,
      onComplete: (body) {
        try {
          final data = json.decode(body) as Map<String, dynamic>;
          final stemTaskId =
              data['stem_task_id']?.toString() ?? data['task_id']?.toString() ?? '';
          if (stemTaskId.isEmpty) {
            completer.completeError(Exception('Server did not return stem_task_id'));
          } else {
            completer.complete(stemTaskId);
          }
        } catch (e) {
          completer.completeError(Exception('Failed to parse response: $e'));
        }
        _callbacks.remove(uploadId);
      },
      onError: (error) {
        completer.completeError(Exception(error));
        _callbacks.remove(uploadId);
      },
    );

    try {
      await _methodChannel.invokeMethod('uploadFile', {
        'filePath': filePath,
        'fileName': fileName,
        'uploadUrl': '${Env.stemApiUrl}/stem/separate_free',
        'apiKey': Env.stemApiKey,
        'uploadId': uploadId,
        'userId': userId,
        'stem': stem,
        'trackTitle': trackTitle,
        'outputFormat': outputFormat,
      });
    } catch (e) {
      _callbacks.remove(uploadId);
      rethrow;
    }

    return completer.future;
  }

  // ----------------------------------------------------------
  // 分块上传（服务端自动合并：最后一块上传完成后自动合并并返回 stem_task_id）
  // ----------------------------------------------------------

  /// 上传单个分块
  /// 返回 stem_task_id（最后一块自动合并时返回）或空字符串（非最后一块）
  Future<String> uploadChunk({
    required String filePath,
    required String uploadId,
    required int chunkIndex,
    required int chunkOffset,
    required int chunkLength,
    required String identifier,
    required String fileName,
    required int totalChunks,
    required int totalSize,
    required String userId,
    required String stem,
    required String trackTitle,
    String outputFormat = 'mp3',
    void Function(int progress)? onProgress,
  }) async {
    final chunkUploadId = '${uploadId}_chunk_$chunkIndex';
    final completer = Completer<String>();

    _callbacks[chunkUploadId] = _UploadCallbacks(
      onProgress: onProgress,
      onComplete: (body) {
        // 解析响应：如果服务端自动合并了，会返回 stem_task_id
        String stemTaskId = '';
        try {
          final data = json.decode(body) as Map<String, dynamic>;
          stemTaskId = data['stem_task_id']?.toString() ?? '';
          if (stemTaskId.isNotEmpty) {
            debugPrint('[BGUpload] 🎉 自动合并完成, stem_task_id: $stemTaskId');
          }
        } catch (_) {
          // 非 JSON 响应或解析失败，正常（非最后一块时不含 stem_task_id）
        }
        completer.complete(stemTaskId);
        _callbacks.remove(chunkUploadId);
      },
      onError: (error) {
        completer.completeError(Exception(error));
        _callbacks.remove(chunkUploadId);
      },
    );

    // 构建 URL：包含分块信息 + 分轨参数（让服务端在最后一块时自动合并）
    final url =
        '${Env.stemApiUrl}/stem/chunk/upload?identifier=${Uri.encodeComponent(identifier)}'
        '&index=$chunkIndex&chunkSize=$chunkLength'
        '&fileName=${Uri.encodeComponent(fileName)}'
        '&totalChunks=$totalChunks&totalSize=$totalSize'
        '&stem=${Uri.encodeComponent(stem)}'
        '&user_id=${Uri.encodeComponent(userId)}'
        '&track_title=${Uri.encodeComponent(trackTitle)}'
        '&output_format=${Uri.encodeComponent(outputFormat)}';

    try {
      await _methodChannel.invokeMethod('uploadChunk', {
        'filePath': filePath,
        'uploadUrl': url,
        'apiKey': Env.stemApiKey,
        'uploadId': uploadId,
        'chunkIndex': chunkIndex,
        'chunkOffset': chunkOffset,
        'chunkLength': chunkLength,
      });
    } catch (e) {
      _callbacks.remove(chunkUploadId);
      rethrow;
    }

    return completer.future;
  }



  // ----------------------------------------------------------
  // 事件处理
  // ----------------------------------------------------------

  /// 已警告过的 uploadId（避免日志刷屏）
  final Set<String> _warnedIds = {};

  void _handleEvent(dynamic event) {
    if (event is! Map) return;
    final map = Map<String, dynamic>.from(event);

    final type = map['type'] as String? ?? '';
    final uploadId = map['uploadId'] as String? ?? '';

    final callbacks = _callbacks[uploadId];
    if (callbacks == null) {
      // 仅在首次遇到时打印警告，避免残留任务日志刷屏
      if (_warnedIds.add(uploadId)) {
        debugPrint('[BGUpload] ⚠️ 忽略残留事件: uploadId=$uploadId (type=$type)');
      }
      return;
    }

    switch (type) {
      case 'progress':
        final progress = map['progress'] as int? ?? 0;
        debugPrint('[BGUpload] 📊 进度回调: uploadId=$uploadId, progress=$progress%');
        callbacks.onProgress?.call(progress);
        break;

      case 'complete':
        final body = map['body'] as String? ?? '';
        debugPrint('[BGUpload] ✅ 完成回调: uploadId=$uploadId');
        callbacks.onComplete?.call(body);
        break;

      case 'error':
        final error = map['error'] as String? ?? 'Unknown error';
        final isRetryable = map['isRetryable'] as bool? ?? false;
        debugPrint('[BGUpload] ${isRetryable ? "⚠️" : "❌"} 错误回调: uploadId=$uploadId, error=$error, retryable=$isRetryable');
        callbacks.onError?.call(error);
        break;
    }
  }
}

/// 内部回调容器
class _UploadCallbacks {
  final void Function(int progress)? onProgress;
  final void Function(String body)? onComplete;
  final void Function(String error)? onError;

  _UploadCallbacks({
    this.onProgress,
    this.onComplete,
    this.onError,
  });
}
