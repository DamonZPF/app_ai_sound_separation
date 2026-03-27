// Supabase 认证服务 — 基于设备 ID 的匿名登录
// 参考原 mini_ai_sound_separation 的 signInWithOpenId 模式
// Flutter 版本使用 deviceId 替代微信 OpenID
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter/foundation.dart';
import '../config/env.dart';

const String _deviceIdKey = 'app_device_id';
const String _wxOpenIdDomain = 'device.app.local';

final _secureStorage = FlutterSecureStorage();

/// 获取 Supabase 客户端
SupabaseClient get supabase => Supabase.instance.client;

/// 初始化 Supabase（在 main 中调用）
Future<void> initSupabase() async {
  await Supabase.initialize(
    url: Env.supabaseUrl,
    anonKey: Env.supabaseAnonKey,
    authOptions: const FlutterAuthClientOptions(
      authFlowType: AuthFlowType.implicit,
    ),
  );
}

/// 获取或生成设备 ID（存储在 Keychain/Keystore 中）
Future<String> getDeviceId() async {
  String? deviceId = await _secureStorage.read(key: _deviceIdKey);
  if (deviceId == null || deviceId.isEmpty) {
    deviceId = const Uuid().v4();
    await _secureStorage.write(key: _deviceIdKey, value: deviceId);
  }
  return deviceId;
}

/// 简单哈希（与原 simpleHash 一致）
String _simpleHash(String str) {
  int hash = 0;
  for (int i = 0; i < str.length; i++) {
    final char = str.codeUnitAt(i);
    hash = ((hash << 5) - hash + char) & 0xFFFFFFFF;
  }
  final hex1 = (hash & 0xFFFFFFFF).toRadixString(16).padLeft(8, '0');

  int hash2 = 0;
  for (int i = str.length - 1; i >= 0; i--) {
    final char = str.codeUnitAt(i);
    hash2 = ((hash2 << 7) - hash2 + char) & 0xFFFFFFFF;
  }
  final hex2 = (hash2 & 0xFFFFFFFF).toRadixString(16).padLeft(8, '0');

  int hash3 = 0;
  for (int i = 0; i < str.length; i++) {
    final char = str.codeUnitAt(i);
    hash3 = ((hash3 << 3) + hash3 + char * 31) & 0xFFFFFFFF;
  }
  final hex3 = (hash3 & 0xFFFFFFFF).toRadixString(16).padLeft(8, '0');

  int hash4 = 0;
  for (int i = 0; i < str.length; i++) {
    final char = str.codeUnitAt(i);
    hash4 = ((hash4 << 11) - hash4 + char * 37) & 0xFFFFFFFF;
  }
  final hex4 = (hash4 & 0xFFFFFFFF).toRadixString(16).padLeft(8, '0');

  return '$hex1$hex2$hex3$hex4';
}

String _buildGuestEmail(String deviceId) {
  final normalized = deviceId.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  return 'guest_$normalized@$_wxOpenIdDomain';
}

String _buildGuestPassword(String deviceId) {
  final digest = _simpleHash('mini_ai_sound_sep_auth::$deviceId');
  return '${digest.substring(0, 30)}Aa1!';
}

bool _shouldCreateAccount(String errorMessage) {
  final msg = errorMessage.toLowerCase();
  return msg.contains('invalid login credentials') ||
      msg.contains('user not found') ||
      msg.contains('invalid credentials');
}

/// 使用设备 ID 匿名登录 Supabase
/// 流程：获取 deviceId → 构建虚拟邮箱密码 → signIn/signUp
Future<void> signInWithDeviceId() async {
  try {
    // 如果已有有效 session，直接返回
    final session = supabase.auth.currentSession;
    if (session != null) {
      debugPrint('[Supabase] 已有有效 session, userId: ${session.user.id}');
      return;
    }

    // 1. 获取设备 ID
    final deviceId = await getDeviceId();
    debugPrint('[Supabase] deviceId: ${deviceId.substring(0, 10)}...');

    // 2. 构建虚拟邮箱和密码
    final email = _buildGuestEmail(deviceId);
    final password = _buildGuestPassword(deviceId);

    // 3. 尝试登录
    try {
      await supabase.auth.signInWithPassword(email: email, password: password);
      debugPrint('[Supabase] 登录成功 (已有账号)');
      return;
    } on AuthException catch (e) {
      if (!_shouldCreateAccount(e.message)) {
        rethrow;
      }
    }

    // 4. 账号不存在，注册
    final signUpRes = await supabase.auth.signUp(
      email: email,
      password: password,
      data: {'is_device_guest': true},
    );

    // signUp 可能不会立即返回 session，兜底再登录一次
    if (signUpRes.session == null) {
      await supabase.auth.signInWithPassword(email: email, password: password);
    }

    debugPrint('[Supabase] 注册并登录成功 (新账号)');
  } catch (err) {
    debugPrint('[Supabase] signInWithDeviceId failed: $err');
    rethrow;
  }
}

/// 获取当前用户 ID
Future<String?> getUserId() async {
  return supabase.auth.currentSession?.user.id;
}

/// 同步获取缓存中的 userId
String? getCachedUserId() {
  return supabase.auth.currentSession?.user.id;
}

/// 检查是否已登录
Future<bool> isLoggedIn() async {
  return supabase.auth.currentSession != null;
}
