import 'package:flutter/material.dart';
import 'video/video_feed_screen.dart';
import 'audio/audio_home_screen.dart';
import 'settings/settings_screen.dart';

/// 三大独立板块：【视频区】【音频区】【功能区】。
/// 使用 IndexedStack 保留各板块状态，切换互不干扰。
class TabsScreen extends StatefulWidget {
  const TabsScreen({Key? key}) : super(key: key);

  @override
  State<TabsScreen> createState() => _TabsScreenState();
}

class _TabsScreenState extends State<TabsScreen> {
  int _current = 0;

  // 三个板块各自独立，互不重建、互不干扰。
  final List<Widget> _pages = const [
    VideoFeedScreen(),
    AudioHomeScreen(),
    SettingsScreen(),
  ];

  static const List<_TabDef> _tabs = [
    _TabDef(icon: Icons.play_circle_outline, label: '视频区'),
    _TabDef(icon: Icons.headphones, label: '音频区'),
    _TabDef(icon: Icons.tune, label: '功能区'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // IndexedStack 同时挂载三页，仅显隐切换，保持各自播放/滚动状态。
      body: IndexedStack(
        index: _current,
        children: _pages,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _current,
        onTap: (i) => setState(() => _current = i),
        items: _tabs
            .map((t) =>
                BottomNavigationBarItem(icon: Icon(t.icon), label: t.label))
            .toList(),
      ),
    );
  }
}

class _TabDef {
  final IconData icon;
  final String label;
  const _TabDef({required this.icon, required this.label});
}
