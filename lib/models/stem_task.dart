/// 数据模型：分轨任务和结果
class StemTask {
  final String stemTaskId;
  /// 服务端返回的任务 ID（上传完成后赋值，用于轮询和匹配）
  final String? serverStemTaskId;
  final String trackTitle;
  final String stem;
  final String status; // uploading / pending / processing / completed / failed
  final String createdAt;
  final int progress;
  final String? errorMessage;
  final List<StemResultItem>? results;
  // 本地上传参数（用于重试）
  final UploadParams? uploadParams;

  StemTask({
    required this.stemTaskId,
    this.serverStemTaskId,
    required this.trackTitle,
    required this.stem,
    this.status = 'pending',
    required this.createdAt,
    this.progress = 0,
    this.errorMessage,
    this.results,
    this.uploadParams,
  });

  /// 创建副本并覆盖指定字段
  /// [clearServerStemTaskId] 为 true 时将 serverStemTaskId 显式置 null
  /// [clearErrorMessage] 为 true 时将 errorMessage 显式置 null
  StemTask copyWith({
    String? stemTaskId,
    String? serverStemTaskId,
    bool clearServerStemTaskId = false,
    String? trackTitle,
    String? stem,
    String? status,
    String? createdAt,
    int? progress,
    String? errorMessage,
    bool clearErrorMessage = false,
    List<StemResultItem>? results,
    UploadParams? uploadParams,
  }) {
    return StemTask(
      stemTaskId: stemTaskId ?? this.stemTaskId,
      serverStemTaskId: clearServerStemTaskId
          ? null
          : (serverStemTaskId ?? this.serverStemTaskId),
      trackTitle: trackTitle ?? this.trackTitle,
      stem: stem ?? this.stem,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      progress: progress ?? this.progress,
      errorMessage: clearErrorMessage
          ? null
          : (errorMessage ?? this.errorMessage),
      results: results ?? this.results,
      uploadParams: uploadParams ?? this.uploadParams,
    );
  }

  Map<String, dynamic> toJson() => {
        'stemTaskId': stemTaskId,
        if (serverStemTaskId != null) 'serverStemTaskId': serverStemTaskId,
        'trackTitle': trackTitle,
        'stem': stem,
        'status': status,
        'createdAt': createdAt,
        'progress': progress,
        'errorMessage': errorMessage,
        if (uploadParams != null) 'uploadParams': uploadParams!.toJson(),
        if (results != null)
          'results': results!.map((r) => r.toJson()).toList(),
      };

  factory StemTask.fromJson(Map<String, dynamic> json) => StemTask(
        stemTaskId: json['stemTaskId'] ?? '',
        serverStemTaskId: json['serverStemTaskId'],
        trackTitle: json['trackTitle'] ?? '',
        stem: json['stem'] ?? '',
        status: json['status'] ?? 'pending',
        createdAt: json['createdAt'] ?? '',
        progress: json['progress'] ?? 0,
        errorMessage: json['errorMessage'],
        uploadParams: json['uploadParams'] != null
            ? UploadParams.fromJson(json['uploadParams'])
            : null,
        results: json['results'] != null
            ? (json['results'] as List)
                .map((r) => StemResultItem.fromJson(r as Map<String, dynamic>))
                .toList()
            : null,
      );

  bool get isLocal => stemTaskId.startsWith('local_');
  bool get isCompleted => status == 'completed';
  bool get isFailed => status == 'failed';
  bool get isProcessing =>
      status == 'pending' || status == 'processing' || status == 'uploading' || status == 'queued';
}

/// 分轨结果项
class StemResultItem {
  final String id;
  final String stemType;
  final String label;
  final String displayLabel;
  final String type; // 'stem' | 'back'
  final String url;
  final String? trackTitle;
  final String? audioUrl;
  final String? outputFormat;
  final String? status;
  final String? createdAt;

  StemResultItem({
    required this.id,
    required this.stemType,
    required this.label,
    required this.displayLabel,
    required this.type,
    required this.url,
    this.trackTitle,
    this.audioUrl,
    this.outputFormat,
    this.status,
    this.createdAt,
  });

  factory StemResultItem.fromJson(Map<String, dynamic> json) => StemResultItem(
        id: json['id']?.toString() ?? '',
        stemType: json['stem_type'] ?? '',
        label: json['label'] ?? '',
        displayLabel: json['display_label'] ?? '',
        type: json['type'] ?? 'stem',
        url: json['url'] ?? '',
        trackTitle: json['track_title'],
        audioUrl: json['audio_url'],
        outputFormat: json['output_format'],
        status: json['status'],
        createdAt: json['created_at'],
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'stem_type': stemType,
        'label': label,
        'display_label': displayLabel,
        'type': type,
        'url': url,
        'track_title': trackTitle,
        'audio_url': audioUrl,
        'output_format': outputFormat,
        'status': status,
        'created_at': createdAt,
      };
}

/// 本地上传参数（重试用）
class UploadParams {
  final String filePath;
  final String fileName;
  final String stem;
  final String outputFormat;
  final int fileSize;

  UploadParams({
    required this.filePath,
    required this.fileName,
    required this.stem,
    this.outputFormat = 'mp3',
    this.fileSize = 0,
  });

  Map<String, dynamic> toJson() => {
        'filePath': filePath,
        'fileName': fileName,
        'stem': stem,
        'outputFormat': outputFormat,
        'fileSize': fileSize,
      };

  factory UploadParams.fromJson(Map<String, dynamic> json) => UploadParams(
        filePath: json['filePath'] ?? '',
        fileName: json['fileName'] ?? '',
        stem: json['stem'] ?? '',
        outputFormat: json['outputFormat'] ?? 'mp3',
        fileSize: json['fileSize'] ?? 0,
      );
}

/// 首页 typeId → API stem 参数映射（与小程序 STEM_TYPE_MAP 一致）
const Map<String, String> stemTypeMap = {
  'vocals': 'vocals',
  'noise': 'voice_clean',
  'drums': 'drum',
  'bass': 'bass',
  'acoustic': 'acoustic_guitar',
  'electric': 'electric_guitar',
  'piano': 'piano',
  'synth': 'synthesizer',
  'strings': 'strings',
  'wind': 'wind',
};

String mapTypeIdToStem(String typeId) {
  return stemTypeMap[typeId] ?? 'vocals';
}
