import 'package:shared_preferences/shared_preferences.dart';

/// 收藏服务：仅在本机记录「收藏的视频路径」，无任何网络同步。
class FavoriteService {
  static const String _key = 'favorite_videos';

  /// 读取全部收藏路径。
  static Future<Set<String>> all() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_key) ?? <String>[];
    return list.toSet();
  }

  /// 是否已收藏。
  static Future<bool> contains(String path) async =>
      (await all()).contains(path);

  /// 切换收藏状态，返回切换后是否为「已收藏」。
  static Future<bool> toggle(String path) async {
    final prefs = await SharedPreferences.getInstance();
    final set = (prefs.getStringList(_key) ?? <String>[]).toSet();
    bool now;
    if (set.contains(path)) {
      set.remove(path);
      now = false;
    } else {
      set.add(path);
      now = true;
    }
    await prefs.setStringList(_key, set.toList());
    return now;
  }
}
