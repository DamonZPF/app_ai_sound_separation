// 持久化待处理任务存储
// 对应小程序 stem-api.ts 中 pendingTasks 的 Storage 持久化逻辑
// 当文件上传成功并拿到服务端 stemTaskId 后，保存到本地
// App 重启后可恢复这些任务并继续轮询其服务端状态
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 待处理任务信息（已提交到服务端，等待完成）
class PendingTask {
  final String stemTaskId;
  final String trackTitle;
  final String stem;
  final String createdAt;

  PendingTask({
    required this.stemTaskId,
    required this.trackTitle,
    required this.stem,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'stemTaskId': stemTaskId,
        'trackTitle': trackTitle,
        'stem': stem,
        'createdAt': createdAt,
      };

  factory PendingTask.fromJson(Map<String, dynamic> json) => PendingTask(
        stemTaskId: json['stemTaskId'] ?? '',
        trackTitle: json['trackTitle'] ?? '',
        stem: json['stem'] ?? '',
        createdAt: json['createdAt'] ?? '',
      );
}

/// 持久化存储——用 SharedPreferences 管理 PendingTasks
class PendingTaskStore {
  PendingTaskStore._();
  static final PendingTaskStore instance = PendingTaskStore._();

  static const String _key = 'pending_tasks';

  /// 当前待处理任务列表（UI 可监听）
  final ValueNotifier<List<PendingTask>> tasksNotifier =
      ValueNotifier<List<PendingTask>>([]);

  List<PendingTask> get tasks => tasksNotifier.value;

  /// 初始化：从 Storage 恢复
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_key);
    if (jsonStr != null && jsonStr.isNotEmpty) {
      try {
        final List<dynamic> list = json.decode(jsonStr);
        tasksNotifier.value = list
            .map((e) => PendingTask.fromJson(e as Map<String, dynamic>))
            .toList();
        debugPrint(
            '[PendingTaskStore] 恢复 ${tasksNotifier.value.length} 个待处理任务');
      } catch (e) {
        debugPrint('[PendingTaskStore] 解析失败: $e');
        tasksNotifier.value = [];
      }
    }
  }

  /// 添加一个待处理任务
  Future<void> addTask(PendingTask task) async {
    // 避免重复
    if (tasks.any((t) => t.stemTaskId == task.stemTaskId)) return;

    tasksNotifier.value = [task, ...tasks];
    await _save();
    debugPrint('[PendingTaskStore] ✅ 已添加: ${task.stemTaskId}');
  }

  /// 移除一个已完成/失败的任务
  Future<void> removeTask(String stemTaskId) async {
    tasksNotifier.value =
        tasks.where((t) => t.stemTaskId != stemTaskId).toList();
    await _save();
    debugPrint('[PendingTaskStore] ✅ 已移除: $stemTaskId');
  }

  /// 清空所有
  Future<void> clear() async {
    tasksNotifier.value = [];
    await _save();
  }

  /// 保存到 SharedPreferences
  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = json.encode(tasks.map((t) => t.toJson()).toList());
    await prefs.setString(_key, jsonStr);
  }
}
