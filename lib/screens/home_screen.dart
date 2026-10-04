import 'package:flutter/material.dart';

import '../widgets/app_drawer.dart';
import 'audio/audio_home_screen.dart';
import 'audio/now_playing_bar.dart';
import 'video/video_feed_screen.dart';

/// 首页：顶部左右分栏切换【视频区】【音频听书区】，中间横向滑动切换。
///
/// 视频区内为全屏竖向分页（上下滑切换本地视频）；
/// 音频区为专辑 / 剧集列表（喜马拉雅风格）。
/// 本地文件浏览、导入、工具与设置统一放在功能侧边栏（Drawer）。
class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const List<String> _tabs = <String>['视频区', '音频听书区'];

  int _index = 0;
  late final PageController _controller;

  @override
  void initState() {
    super.initState();
    _controller = PageController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _switchTo(int i) {
    if (i == _index) return;
    _controller.animateToPage(
      i,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeInOut,
    );
    setState(() => _index = i);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 功能侧边栏（本地文件浏览 / 导入 / 工具 / 设置）
      drawer: const AppDrawer(),
      appBar: AppBar(
        // 顶部左右分栏切换
        titleSpacing: 0,
        title: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < _tabs.length; i++) _TabChip(
              label: _tabs[i],
              selected: i == _index,
              onTap: () => _switchTo(i),
            ),
          ],
        ),
        centerTitle: true,
      ),
      // 横向滑动切换两大板块（IndexedStack 之外用 PageView 以支持手势）
      body: PageView(
        controller: _controller,
        onPageChanged: (i) => setState(() => _index = i),
        children: const [
          VideoFeedScreen(),
          AudioHomeScreen(),
        ],
      ),
      // 音频悬浮播放器（未播放时不显示）
      bottomNavigationBar: const NowPlayingBar(),
    );
  }
}

/// 顶部分栏按钮：选中时加深色底 + 下划线，未选中为灰色文字。
class _TabChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _TabChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 16,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                color: selected
                    ? Colors.white
                    : Colors.white.withOpacity(0.65),
              ),
            ),
            const SizedBox(height: 3),
            // 选中指示条
            Container(
              width: 28,
              height: 2.5,
              decoration: BoxDecoration(
                color: selected ? Colors.white : Colors.transparent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
