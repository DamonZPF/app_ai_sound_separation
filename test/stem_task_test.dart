// StemTask 模型单元测试
// 覆盖 #13 copyWith、#6 queued 状态、序列化/反序列化
import 'package:flutter_test/flutter_test.dart';
import 'package:app_ai_sound_separation/models/stem_task.dart';

void main() {
  group('StemTask.copyWith', () {
    late StemTask base;

    setUp(() {
      base = StemTask(
        stemTaskId: 'local_abc',
        serverStemTaskId: 'server_123',
        trackTitle: 'Test Song',
        stem: 'vocals',
        status: 'uploading',
        createdAt: '2026-04-01T00:00:00Z',
        progress: 50,
        errorMessage: 'some error',
        uploadParams: UploadParams(
          filePath: '/path/to/file.mp3',
          fileName: 'file.mp3',
          stem: 'vocals',
          outputFormat: 'mp3',
        ),
      );
    });

    test('更新单一字段，其余保持不变', () {
      final updated = base.copyWith(status: 'processing');

      expect(updated.status, 'processing');
      expect(updated.stemTaskId, 'local_abc');
      expect(updated.serverStemTaskId, 'server_123');
      expect(updated.trackTitle, 'Test Song');
      expect(updated.stem, 'vocals');
      expect(updated.createdAt, '2026-04-01T00:00:00Z');
      expect(updated.progress, 50);
      expect(updated.errorMessage, 'some error');
      expect(updated.uploadParams?.filePath, '/path/to/file.mp3');
    });

    test('更新多个字段', () {
      final updated = base.copyWith(
        status: 'completed',
        progress: 100,
        trackTitle: 'Updated Title',
      );

      expect(updated.status, 'completed');
      expect(updated.progress, 100);
      expect(updated.trackTitle, 'Updated Title');
      // 未修改字段保持不变
      expect(updated.stemTaskId, 'local_abc');
      expect(updated.errorMessage, 'some error');
    });

    test('clearServerStemTaskId 显式置 null', () {
      final updated = base.copyWith(clearServerStemTaskId: true);

      expect(updated.serverStemTaskId, isNull);
      // 其他字段不受影响
      expect(updated.stemTaskId, 'local_abc');
    });

    test('clearErrorMessage 显式置 null', () {
      final updated = base.copyWith(clearErrorMessage: true);

      expect(updated.errorMessage, isNull);
      expect(updated.status, 'uploading');
    });

    test('同时清空和设置新值时，clearXxx 优先', () {
      // clearServerStemTaskId=true 但同时提供了新值
      // 按实现逻辑，clear 优先
      final updated = base.copyWith(
        clearServerStemTaskId: true,
        serverStemTaskId: 'new_server',
      );
      expect(updated.serverStemTaskId, isNull);
    });

    test('copyWith 不修改原对象（不可变性）', () {
      base.copyWith(status: 'failed', progress: 0);

      expect(base.status, 'uploading');
      expect(base.progress, 50);
    });

    test('copyWith 可设置 results', () {
      final results = <StemResultItem>[
        StemResultItem(id: '1', stemType: 'vocals', label: 'Vocals', displayLabel: 'Vocals', type: 'stem', url: 'https://example.com/vocals.mp3'),
      ];
      final updated = base.copyWith(results: results);

      expect(updated.results, isNotNull);
      expect(updated.results!.length, 1);
      expect(updated.results!.first.stemType, 'vocals');
    });
  });

  group('StemTask 状态判断', () {
    StemTask withStatus(String status) => StemTask(
          stemTaskId: 'test',
          trackTitle: 'Test',
          stem: 'vocals',
          status: status,
          createdAt: '2026-01-01',
        );

    test('#6: queued 应被识别为 isProcessing', () {
      expect(withStatus('queued').isProcessing, isTrue);
    });

    test('uploading 应被识别为 isProcessing', () {
      expect(withStatus('uploading').isProcessing, isTrue);
    });

    test('processing 应被识别为 isProcessing', () {
      expect(withStatus('processing').isProcessing, isTrue);
    });

    test('pending 应被识别为 isProcessing', () {
      expect(withStatus('pending').isProcessing, isTrue);
    });

    test('completed 不是 isProcessing', () {
      expect(withStatus('completed').isProcessing, isFalse);
    });

    test('failed 不是 isProcessing', () {
      expect(withStatus('failed').isProcessing, isFalse);
    });

    test('completed 是 isCompleted', () {
      expect(withStatus('completed').isCompleted, isTrue);
    });

    test('failed 是 isFailed', () {
      expect(withStatus('failed').isFailed, isTrue);
    });

    test('isLocal 判断 local_ 前缀', () {
      expect(withStatus('uploading').isLocal, isFalse); // stemTaskId = 'test'
      final localTask = StemTask(
        stemTaskId: 'local_abc-def',
        trackTitle: 'Test',
        stem: 'vocals',
        status: 'uploading',
        createdAt: '2026-01-01',
      );
      expect(localTask.isLocal, isTrue);
    });
  });

  group('StemTask 序列化', () {
    test('toJson → fromJson 往返一致', () {
      final original = StemTask(
        stemTaskId: 'local_test_123',
        serverStemTaskId: 'server_456',
        trackTitle: 'My Song',
        stem: 'drums',
        status: 'processing',
        createdAt: '2026-04-01T12:00:00Z',
        progress: 75,
        errorMessage: null,
        uploadParams: UploadParams(
          filePath: '/tmp/audio.wav',
          fileName: 'audio.wav',
          stem: 'drums',
          outputFormat: 'wav',
          fileSize: 1024000,
        ),
        results: [
          StemResultItem(id: '1', stemType: 'drums', label: 'Drums', displayLabel: 'Drums', type: 'stem', url: 'https://cdn.example.com/drums.wav'),
          StemResultItem(id: '2', stemType: 'no_drums', label: 'No Drums', displayLabel: 'No Drums', type: 'back', url: 'https://cdn.example.com/no_drums.wav'),
        ],
      );

      final json = original.toJson();
      final restored = StemTask.fromJson(json);

      expect(restored.stemTaskId, original.stemTaskId);
      expect(restored.serverStemTaskId, original.serverStemTaskId);
      expect(restored.trackTitle, original.trackTitle);
      expect(restored.stem, original.stem);
      expect(restored.status, original.status);
      expect(restored.createdAt, original.createdAt);
      expect(restored.progress, original.progress);
      expect(restored.errorMessage, original.errorMessage);
      expect(restored.uploadParams?.filePath, original.uploadParams?.filePath);
      expect(restored.uploadParams?.fileSize, original.uploadParams?.fileSize);
      expect(restored.results?.length, 2);
      expect(restored.results?.first.stemType, 'drums');
    });

    test('toJson 不包含 null 的 serverStemTaskId', () {
      final task = StemTask(
        stemTaskId: 'test',
        trackTitle: 'Test',
        stem: 'vocals',
        status: 'uploading',
        createdAt: '2026-01-01',
      );

      final json = task.toJson();
      expect(json.containsKey('serverStemTaskId'), isFalse);
    });

    test('fromJson 处理缺失字段的默认值', () {
      final json = <String, dynamic>{
        'stemTaskId': 'test',
        'trackTitle': 'Test',
        'stem': 'vocals',
        'status': 'pending',
        'createdAt': '2026-01-01',
      };

      final task = StemTask.fromJson(json);
      expect(task.progress, 0);
      expect(task.serverStemTaskId, isNull);
      expect(task.errorMessage, isNull);
      expect(task.results, isNull);
      expect(task.uploadParams, isNull);
    });

    test('#6: queued 状态可正确序列化和恢复', () {
      final task = StemTask(
        stemTaskId: 'local_test',
        trackTitle: 'Test',
        stem: 'vocals',
        status: 'queued',
        createdAt: '2026-01-01',
        progress: 0,
      );

      final json = task.toJson();
      final restored = StemTask.fromJson(json);

      expect(restored.status, 'queued');
      expect(restored.isProcessing, isTrue);
    });
  });

  group('StemTask copyWith 模拟队列操作', () {
    test('#6: uploading → queued → uploading 状态流转', () {
      final task = StemTask(
        stemTaskId: 'local_test',
        trackTitle: 'Test',
        stem: 'vocals',
        status: 'uploading',
        createdAt: '2026-01-01',
        uploadParams: UploadParams(
          filePath: '/tmp/test.mp3',
          fileName: 'test.mp3',
          stem: 'vocals',
          outputFormat: 'mp3',
        ),
      );

      // 模拟被排队
      final queued = task.copyWith(status: 'queued');
      expect(queued.status, 'queued');
      expect(queued.uploadParams, isNotNull); // 上传参数保留

      // 模拟从队列取出
      final dequeued = queued.copyWith(status: 'uploading');
      expect(dequeued.status, 'uploading');
      expect(dequeued.uploadParams?.filePath, '/tmp/test.mp3');
    });

    test('模拟 App 恢复后将 queued 标记为 failed', () {
      final queued = StemTask(
        stemTaskId: 'local_test',
        trackTitle: 'Test',
        stem: 'vocals',
        status: 'queued',
        createdAt: '2026-01-01',
        uploadParams: UploadParams(
          filePath: '/tmp/test.mp3',
          fileName: 'test.mp3',
          stem: 'vocals',
          outputFormat: 'mp3',
        ),
      );

      // 模拟 init() 恢复逻辑
      final restored = queued.copyWith(
        status: 'failed',
        errorMessage: 'error_upload_interrupted',
      );

      expect(restored.status, 'failed');
      expect(restored.isFailed, isTrue);
      expect(restored.errorMessage, 'error_upload_interrupted');
      expect(restored.uploadParams, isNotNull); // 保留以便重试
    });

    test('模拟 _markFailed 使用 copyWith', () {
      final processing = StemTask(
        stemTaskId: 'local_test',
        serverStemTaskId: 'server_abc',
        trackTitle: 'My Song',
        stem: 'vocals',
        status: 'processing',
        createdAt: '2026-01-01',
        progress: 60,
        uploadParams: UploadParams(
          filePath: '/tmp/test.mp3',
          fileName: 'test.mp3',
          stem: 'vocals',
          outputFormat: 'mp3',
        ),
      );

      final failed = processing.copyWith(
        status: 'failed',
        errorMessage: 'error_timeout',
      );

      expect(failed.status, 'failed');
      expect(failed.errorMessage, 'error_timeout');
      // 验证 copyWith 不会丢失关键字段
      expect(failed.serverStemTaskId, 'server_abc');
      expect(failed.progress, 60);
      expect(failed.uploadParams?.filePath, '/tmp/test.mp3');
      expect(failed.trackTitle, 'My Song');
    });

    test('模拟 processing → completed 使用 copyWith', () {
      final processing = StemTask(
        stemTaskId: 'local_test',
        serverStemTaskId: 'server_abc',
        trackTitle: 'Original Title',
        stem: 'vocals',
        status: 'processing',
        createdAt: '2026-01-01',
        progress: 60,
      );

      final completed = processing.copyWith(
        trackTitle: 'Server Updated Title',
        status: 'completed',
        progress: 100,
        results: [
          StemResultItem(id: '1', stemType: 'vocals', label: 'Vocals', displayLabel: 'Vocals', type: 'stem', url: 'https://cdn.example.com/vocals.mp3'),
        ],
      );

      expect(completed.status, 'completed');
      expect(completed.isCompleted, isTrue);
      expect(completed.progress, 100);
      expect(completed.trackTitle, 'Server Updated Title');
      expect(completed.results?.length, 1);
      expect(completed.serverStemTaskId, 'server_abc'); // 保留
    });
  });
}
