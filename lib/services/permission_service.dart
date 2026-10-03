import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

/// 存储权限服务。
/// - 安卓：请求“所有文件访问”(MANAGE_EXTERNAL_STORAGE) 以读取任意路径；
///   若被拒则降级到普通存储权限。
/// - iOS：通过 file_picker 选取，无需额外授权。
class PermissionService {
  /// 请求存储访问权限，返回是否获得授权。
  static Future<bool> requestStorage() async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      if (await Permission.manageExternalStorage.isGranted) return true;
      final status = await Permission.manageExternalStorage.request();
      if (status.isGranted) return true;
      // 降级：仅媒体权限
      final media = await Permission.storage.request();
      return media.isGranted;
    }
    // iOS 通过 file_picker 选取文件，无需授权
    return true;
  }

  /// 当前是否已获得存储访问授权。
  static Future<bool> get hasStorage async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      if (await Permission.manageExternalStorage.isGranted) return true;
      return Permission.storage.isGranted;
    }
    return true;
  }

  /// 打开系统设置页，供用户手动开启“所有文件访问”。
  static Future<void> openSettings() => openAppSettings();
}
