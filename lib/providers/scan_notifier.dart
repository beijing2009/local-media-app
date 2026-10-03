import 'package:flutter/material.dart';

/// 扫描配置变更通知器。
/// 当“功能区”中新增 / 删除扫描目录时，通知视频区、音频区重新加载，
/// 保证三大板块相互独立又能在配置变更后同步刷新。
class ScanNotifier extends ChangeNotifier {
  void changed() => notifyListeners();
}
