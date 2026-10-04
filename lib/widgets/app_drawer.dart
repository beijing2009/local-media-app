import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_version.dart';
import '../models/media_file.dart';
import '../providers/theme_provider.dart';
import '../screens/file_browser_screen.dart';
import '../screens/import/import_center_screen.dart';
import '../screens/settings/settings_screen.dart';
import '../screens/tools/m3u8_merge_screen.dart';

/// 功能侧边栏（Drawer）：承载本地文件浏览、批量导入、合并工具与设置入口。
class AppDrawer extends StatelessWidget {
  const AppDrawer({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context, listen: false);
    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            // 头部：应用名 + 版本（纯文字，无任何第三方品牌元素）
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
              color: Theme.of(context).primaryColor.withOpacity(0.12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    '本地影音',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 4),
                    Text(
                      // 版本号由常量拼接，可直接作为编译期常量
                      'v${AppVersion.name} (build ${AppVersion.code})',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  const _SectionTitle('本地文件'),
                  _DrawerItem(
                    icon: Icons.video_library_outlined,
                    label: '浏览视频文件',
                    onTap: () => _push(
                      context,
                      const FileBrowserScreen(mediaType: MediaType.video),
                    ),
                  ),
                  _DrawerItem(
                    icon: Icons.audiotrack_outlined,
                    label: '浏览音频文件',
                    onTap: () => _push(
                      context,
                      const FileBrowserScreen(mediaType: MediaType.audio),
                    ),
                  ),
                  _DrawerItem(
                    icon: Icons.downloading_outlined,
                    label: '批量导入视频',
                    onTap: () =>
                        _push(context, const ImportCenterScreen()),
                  ),
                  const _SectionTitle('工具'),
                  _DrawerItem(
                    icon: Icons.movie_filter_outlined,
                    label: 'M3U8 / TS 合并',
                    onTap: () => _push(context, const M3u8MergeScreen()),
                  ),
                  const _SectionTitle('外观'),
                  SwitchListTile(
                    secondary: const Icon(Icons.dark_mode_outlined),
                    title: const Text('深色模式'),
                    // 跟随系统时开关显示为关（跟随系统由设置页切换）
                    value: theme.mode == ThemeMode.dark,
                    onChanged: (_) => theme.toggle(),
                  ),
                  const _SectionTitle('其它'),
                  _DrawerItem(
                    icon: Icons.settings_outlined,
                    label: '系统设置',
                    onTap: () => _push(context, const SettingsScreen()),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Future<void> _push(BuildContext context, Widget page) async {
    Navigator.of(context).pop(); // 先收起侧边栏
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => page));
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          color: Colors.grey,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _DrawerItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _DrawerItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      onTap: onTap,
    );
  }
}
