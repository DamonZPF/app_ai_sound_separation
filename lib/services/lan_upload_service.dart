// 局域网上传服务 — 在 App 内启动 HTTP Server
// 用户通过电脑浏览器访问页面拖拽上传文件到 App
import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

class LanUploadService {
  LanUploadService._();
  static final LanUploadService instance = LanUploadService._();

  HttpServer? _server;
  final ValueNotifier<bool> isRunning = ValueNotifier(false);
  final ValueNotifier<String?> serverUrl = ValueNotifier(null);

  /// 收到文件时的回调
  void Function(String filePath, String fileName)? onFileReceived;

  /// 获取本机局域网 IP（优先 en0 WiFi 接口）
  Future<String?> _getLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      String? wifiIp;     // en0 上的地址（最优先）
      String? fallbackIp;  // 其他接口的局域网地址
      for (final iface in interfaces) {
        debugPrint('[LanUpload] 网络接口: ${iface.name}');
        for (final addr in iface.addresses) {
          debugPrint('[LanUpload]   地址: ${addr.address} (loopback=${addr.isLoopback})');
          if (addr.isLoopback) continue;

          final isPrivate = addr.address.startsWith('192.168.') ||
              addr.address.startsWith('172.') ||
              addr.address.startsWith('10.');

          if (!isPrivate) continue;

          // en0 是 iOS/macOS 的 WiFi 接口，最优先
          if (iface.name == 'en0') {
            wifiIp = addr.address;
          } else {
            fallbackIp ??= addr.address;
          }
        }
      }
      return wifiIp ?? fallbackIp;
    } catch (e) {
      debugPrint('[LanUpload] 获取IP失败: $e');
    }
    return null;
  }

  /// 启动服务器
  Future<bool> start() async {
    if (_server != null) return true;

    final ip = await _getLocalIp();
    if (ip == null) {
      debugPrint('[LanUpload] 无法获取局域网IP');
      return false;
    }

    final router = Router();

    // 首页：上传界面
    router.get('/', (Request request) {
      return Response.ok(_buildHtmlPage(), headers: {
        'Content-Type': 'text/html; charset=utf-8',
      });
    });

    // 文件上传接口
    router.post('/upload', _handleUpload);

    try {
      _server = await shelf_io.serve(
        router.call,
        InternetAddress.anyIPv4,
        8080,
        shared: true, // 允许端口复用，避免重启时 Address already in use
      );
      final url = 'http://$ip:8080';
      serverUrl.value = url;
      isRunning.value = true;
      debugPrint('[LanUpload] ✅ 服务已启动: $url');
      debugPrint('[LanUpload] ✅ 实际绑定: ${_server!.address.address}:${_server!.port}');
      return true;
    } catch (e) {
      debugPrint('[LanUpload] ❌ 启动失败: $e');
      return false;
    }
  }

  /// 停止服务器
  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    serverUrl.value = null;
    isRunning.value = false;
    debugPrint('[LanUpload] ⏹ 服务已停止');
  }

  /// 处理文件上传
  Future<Response> _handleUpload(Request request) async {
    try {
      final contentType = request.headers['content-type'] ?? '';
      if (!contentType.contains('multipart/form-data')) {
        return Response(400, body: '{"error":"Invalid content type"}');
      }

      // 解析 boundary
      final boundaryMatch = RegExp(r'boundary=(.+)').firstMatch(contentType);
      if (boundaryMatch == null) {
        return Response(400, body: '{"error":"Missing boundary"}');
      }
      final boundary = boundaryMatch.group(1)!;

      // 读取整个 body
      final bytes = await request.read().expand((e) => e).toList();
      final body = bytes;

      // 手动解析 multipart
      final boundaryBytes = '--$boundary'.codeUnits;
      final parts = _splitMultipart(body, boundaryBytes);

      String? fileName;
      List<int>? fileData;

      for (final part in parts) {
        final headerEnd = _findHeaderEnd(part);
        if (headerEnd < 0) continue;

        final headerStr = String.fromCharCodes(part.sublist(0, headerEnd));
        final dataStart = headerEnd + 4; // skip \r\n\r\n

        if (headerStr.contains('filename=')) {
          final nameMatch = RegExp(r'filename="([^"]+)"').firstMatch(headerStr);
          fileName = nameMatch?.group(1) ?? 'upload_${DateTime.now().millisecondsSinceEpoch}';
          fileData = part.sublist(dataStart);
        }
      }

      if (fileName == null || fileData == null) {
        return Response(400, body: '{"error":"No file found"}');
      }

      // 保存到 Documents/uploads/
      final docDir = await getApplicationDocumentsDirectory();
      final uploadsDir = Directory('${docDir.path}/uploads');
      if (!uploadsDir.existsSync()) {
        uploadsDir.createSync(recursive: true);
      }
      final savePath = '${uploadsDir.path}/wifi_${DateTime.now().millisecondsSinceEpoch}_$fileName';
      final file = File(savePath);
      await file.writeAsBytes(fileData);

      debugPrint('[LanUpload] 📥 收到文件: $fileName (${fileData.length} bytes) → $savePath');

      // 通知 Flutter 端
      onFileReceived?.call(savePath, fileName);

      return Response.ok(
        '{"success":true,"fileName":"$fileName","size":${fileData.length}}',
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      debugPrint('[LanUpload] 上传处理失败: $e');
      return Response.internalServerError(
        body: '{"error":"$e"}',
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  /// 查找 \r\n\r\n 位置
  int _findHeaderEnd(List<int> data) {
    for (int i = 0; i < data.length - 3; i++) {
      if (data[i] == 13 && data[i + 1] == 10 &&
          data[i + 2] == 13 && data[i + 3] == 10) {
        return i;
      }
    }
    return -1;
  }

  /// 按 boundary 分割 multipart 数据
  List<List<int>> _splitMultipart(List<int> data, List<int> boundary) {
    final parts = <List<int>>[];
    int start = 0;

    while (start < data.length) {
      final pos = _indexOf(data, boundary, start);
      if (pos < 0) break;

      if (start > 0) {
        // 去掉末尾 \r\n
        int end = pos;
        if (end >= 2 && data[end - 1] == 10 && data[end - 2] == 13) {
          end -= 2;
        }
        if (end > start) {
          parts.add(data.sublist(start, end));
        }
      }
      start = pos + boundary.length;
      // 跳过 \r\n 或 --
      if (start < data.length - 1) {
        if (data[start] == 13 && data[start + 1] == 10) {
          start += 2;
        } else if (data[start] == 45 && data[start + 1] == 45) {
          break; // 结束标记 --boundary--
        }
      }
    }

    return parts;
  }

  int _indexOf(List<int> data, List<int> pattern, int from) {
    for (int i = from; i <= data.length - pattern.length; i++) {
      bool match = true;
      for (int j = 0; j < pattern.length; j++) {
        if (data[i + j] != pattern[j]) {
          match = false;
          break;
        }
      }
      if (match) return i;
    }
    return -1;
  }

  /// 生成网页上传界面（支持中英文自动切换）
  String _buildHtmlPage() {
    return '''<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>AI Sound Separation - WiFi Transfer</title>
<style>
* { margin: 0; padding: 0; box-sizing: border-box; }
body {
  font-family: -apple-system, 'Segoe UI', Roboto, 'Helvetica Neue', sans-serif;
  background: linear-gradient(135deg, #0f0c29, #302b63, #24243e);
  min-height: 100vh;
  display: flex;
  align-items: center;
  justify-content: center;
  color: #fff;
}
.container {
  width: 90%;
  max-width: 520px;
  padding: 40px;
  background: rgba(255,255,255,0.06);
  border-radius: 24px;
  border: 1px solid rgba(255,255,255,0.1);
  backdrop-filter: blur(20px);
  box-shadow: 0 20px 60px rgba(0,0,0,0.4);
}
h1 {
  font-size: 24px;
  font-weight: 700;
  margin-bottom: 8px;
  text-align: center;
  background: linear-gradient(135deg, #667eea, #764ba2);
  -webkit-background-clip: text;
  -webkit-text-fill-color: transparent;
}
.subtitle {
  text-align: center;
  color: rgba(255,255,255,0.5);
  font-size: 14px;
  margin-bottom: 32px;
}
.drop-zone {
  border: 2px dashed rgba(255,255,255,0.2);
  border-radius: 16px;
  padding: 48px 24px;
  text-align: center;
  cursor: pointer;
  transition: all 0.3s;
  position: relative;
  overflow: hidden;
}
.drop-zone:hover, .drop-zone.dragover {
  border-color: #667eea;
  background: rgba(102,126,234,0.08);
}
.drop-zone .icon {
  font-size: 48px;
  margin-bottom: 16px;
  display: block;
}
.drop-zone p { color: rgba(255,255,255,0.6); font-size: 15px; }
.drop-zone .hint { font-size: 12px; color: rgba(255,255,255,0.3); margin-top: 8px; }
input[type="file"] { display: none; }

.progress-wrap {
  margin-top: 24px;
  display: none;
}
.progress-wrap.active { display: block; }
.file-name {
  font-size: 14px;
  color: rgba(255,255,255,0.7);
  margin-bottom: 8px;
  word-break: break-all;
}
.progress-bar {
  height: 6px;
  background: rgba(255,255,255,0.1);
  border-radius: 3px;
  overflow: hidden;
}
.progress-bar .fill {
  height: 100%;
  background: linear-gradient(90deg, #667eea, #764ba2);
  border-radius: 3px;
  width: 0%;
  transition: width 0.3s;
}
.status {
  text-align: center;
  margin-top: 12px;
  font-size: 14px;
}
.status.success { color: #48bb78; }
.status.error { color: #f56565; }
.formats {
  margin-top: 24px;
  text-align: center;
  color: rgba(255,255,255,0.3);
  font-size: 12px;
}
</style>
</head>
<body>
<div class="container">
  <h1 data-i18n="title">🎵 AI Sound Separation</h1>
  <p class="subtitle" data-i18n="subtitle">Transfer files from computer to phone via WiFi</p>

  <div class="drop-zone" id="dropZone">
    <span class="icon">📁</span>
    <p data-i18n="dropText">Drag & drop file here, or click to select</p>
    <p class="hint" data-i18n="formatHint">Supports MP3, WAV, FLAC, M4A, MP4, MOV, etc.</p>
    <input type="file" id="fileInput" accept=".mp3,.wav,.flac,.m4a,.aac,.ogg,.wma,.mp4,.mov,.avi,.mkv,.webm">
  </div>

  <div class="progress-wrap" id="progressWrap">
    <div class="file-name" id="fileName"></div>
    <div class="progress-bar"><div class="fill" id="progressFill"></div></div>
    <div class="status" id="statusText"></div>
  </div>

  <p class="formats" data-i18n="maxSize">Max 200MB per file</p>
</div>

<script>
// ── i18n ──
const i18n = {
  zh: {
    title: '🎵 AI音频分离',
    subtitle: '通过 WiFi 从电脑传输文件到手机',
    dropText: '拖拽文件到此处，或点击选择',
    formatHint: '支持 MP3、WAV、FLAC、M4A、MP4、MOV 等格式',
    maxSize: '单文件最大 200MB',
    uploading: '上传中...',
    uploadingPct: (pct) => '上传中... ' + pct + '%',
    success: '✅ 上传成功！文件已传输到手机App',
    errorUpload: (msg) => '❌ 上传失败：' + msg,
    errorNetwork: '❌ 网络错误，请检查连接',
    errorSize: '文件大小超过 200MB 限制',
  },
  en: {
    title: '🎵 AI Sound Separation',
    subtitle: 'Transfer files from computer to phone via WiFi',
    dropText: 'Drag & drop file here, or click to select',
    formatHint: 'Supports MP3, WAV, FLAC, M4A, MP4, MOV, etc.',
    maxSize: 'Max 200MB per file',
    uploading: 'Uploading...',
    uploadingPct: (pct) => 'Uploading... ' + pct + '%',
    success: '✅ Upload successful! File transferred to phone.',
    errorUpload: (msg) => '❌ Upload failed: ' + msg,
    errorNetwork: '❌ Network error, check your connection',
    errorSize: 'File exceeds 200MB limit',
  }
};

const lang = navigator.language.startsWith('zh') ? 'zh' : 'en';
const t = i18n[lang];

// Apply static text
document.querySelectorAll('[data-i18n]').forEach(el => {
  const key = el.getAttribute('data-i18n');
  if (t[key]) el.textContent = t[key];
});
document.title = t.title.replace('🎵 ', '') + ' - WiFi Transfer';

// ── Upload logic ──
const dropZone = document.getElementById('dropZone');
const fileInput = document.getElementById('fileInput');
const progressWrap = document.getElementById('progressWrap');
const progressFill = document.getElementById('progressFill');
const fileNameEl = document.getElementById('fileName');
const statusText = document.getElementById('statusText');

dropZone.addEventListener('click', () => fileInput.click());

dropZone.addEventListener('dragover', (e) => {
  e.preventDefault();
  dropZone.classList.add('dragover');
});

dropZone.addEventListener('dragleave', () => {
  dropZone.classList.remove('dragover');
});

dropZone.addEventListener('drop', (e) => {
  e.preventDefault();
  dropZone.classList.remove('dragover');
  if (e.dataTransfer.files.length > 0) uploadFile(e.dataTransfer.files[0]);
});

fileInput.addEventListener('change', () => {
  if (fileInput.files.length > 0) uploadFile(fileInput.files[0]);
});

function uploadFile(file) {
  if (file.size > 200 * 1024 * 1024) {
    alert(t.errorSize);
    return;
  }

  fileNameEl.textContent = file.name + ' (' + formatSize(file.size) + ')';
  progressWrap.classList.add('active');
  progressFill.style.width = '0%';
  statusText.textContent = t.uploading;
  statusText.className = 'status';

  const formData = new FormData();
  formData.append('file', file);

  const xhr = new XMLHttpRequest();
  xhr.open('POST', '/upload', true);

  xhr.upload.onprogress = (e) => {
    if (e.lengthComputable) {
      const pct = Math.round(e.loaded / e.total * 100);
      progressFill.style.width = pct + '%';
      statusText.textContent = t.uploadingPct(pct);
    }
  };

  xhr.onload = () => {
    if (xhr.status === 200) {
      progressFill.style.width = '100%';
      statusText.textContent = t.success;
      statusText.className = 'status success';
    } else {
      statusText.textContent = t.errorUpload(xhr.statusText);
      statusText.className = 'status error';
    }
  };

  xhr.onerror = () => {
    statusText.textContent = t.errorNetwork;
    statusText.className = 'status error';
  };

  xhr.send(formData);
}

function formatSize(bytes) {
  if (bytes < 1024) return bytes + ' B';
  if (bytes < 1048576) return (bytes / 1024).toFixed(1) + ' KB';
  return (bytes / 1048576).toFixed(1) + ' MB';
}
</script>
</body>
</html>''';
  }
}
