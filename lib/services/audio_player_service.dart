// 音频播放服务 — 封装 just_audio，全局单例
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

class AudioPlayerService {
  AudioPlayerService._() {
    // 监听播放完成，重置状态
    _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        _currentUrl = null;
        currentUrlNotifier.value = null;
      }
    });
  }
  static final AudioPlayerService instance = AudioPlayerService._();

  final AudioPlayer _player = AudioPlayer();

  /// 当前正在播放的 URL
  String? _currentUrl;
  String? get currentUrl => _currentUrl;

  /// 用于 UI 响应式监听当前播放 URL 变化
  final ValueNotifier<String?> currentUrlNotifier = ValueNotifier(null);

  /// 播放状态流
  Stream<PlayerState> get playerStateStream => _player.playerStateStream;

  /// 当前播放位置
  Stream<Duration> get positionStream => _player.positionStream;

  /// 总时长
  Duration? get duration => _player.duration;
  Stream<Duration?> get durationStream => _player.durationStream;

  /// 是否正在播放
  bool get isPlaying => _player.playing;

  /// 播放指定 URL 的音频
  Future<void> play(String url) async {
    try {
      // 如果正在播放同一首，切换 暂停/播放
      if (_currentUrl == url) {
        if (_player.playing) {
          await _player.pause();
        } else {
          // 播放完成后再次点击同一首，从头开始
          if (_player.processingState == ProcessingState.completed) {
            await _player.seek(Duration.zero);
          }
          await _player.play();
        }
        return;
      }
      // 播放新的
      _currentUrl = url;
      currentUrlNotifier.value = url;
      await _player.setUrl(url);
      await _player.play();
    } catch (e) {
      debugPrint('[AudioPlayerService] play error: $e');
      _currentUrl = null;
      currentUrlNotifier.value = null;
      rethrow;
    }
  }

  /// 暂停
  Future<void> pause() async {
    await _player.pause();
  }

  /// 继续播放
  Future<void> resume() async {
    await _player.play();
  }

  /// 跳转到指定位置
  Future<void> seek(Duration position) async {
    await _player.seek(position);
  }

  /// 停止并重置
  Future<void> stop() async {
    await _player.stop();
    _currentUrl = null;
    currentUrlNotifier.value = null;
  }

  /// 释放资源
  Future<void> dispose() async {
    await _player.dispose();
  }
}
