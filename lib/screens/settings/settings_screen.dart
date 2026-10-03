import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import '../../providers/theme_provider.dart';
import '../../providers/scan_notifier.dart';
import '../../services/database_service.dart';
import '../../app_version.dart';
import '../tools/m3u8_merge_screen.dart';

/// 功能区 / 设置：外观切换、扫描目录管理、进度清理。
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  List<String> _roots = [];

  @override
  void initState() {
    super.initState();
    _loadRoots();
  }

  Future<void> _loadRoots() async {
    final roots = await DatabaseService.instance.getScanRoots();
    if (mounted) setState(() => _roots = roots);
  }

  Future<void> _addRoot() async {
    final scan = Provider.of<ScanNotifier>(context, listen: false);
    final dir = await FilePicker.platform.getDirectoryPath();
    if (dir == null || dir.isEmpty) return;
    final roots = List<String>.from(_roots);
    if (!roots.contains(dir)) roots.add(dir);
    await DatabaseService.instance.setScanRoots(roots);
    scan.changed();
    _loadRoots();
  }

  Future<void> _removeRoot(String root) async {
    final scan = Provider.of<ScanNotifier>(context, listen: false);
    final roots = List<String>.from(_roots)..remove(root);
    await DatabaseService.instance.setScanRoots(roots);
    scan.changed();
    _loadRoots();
  }

  Future<void> _clearProgress() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空播放进度'),
        content: const Text('将删除所有视频 / 音频的播放位置记忆，确定？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await DatabaseService.instance.clearProgress();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('已清空播放进度')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);
    return Scaffold(
      appBar: AppBar(title: const Text('功能区 / 设置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ---------------- 外观 ----------------
          const Text('外观', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              _themeChip(theme, ThemeMode.system, '跟随系统'),
              _themeChip(theme, ThemeMode.light, '浅色'),
              _themeChip(theme, ThemeMode.dark, '深色'),
            ],
          ),
          const Divider(height: 32),

          // ---------------- 扫描目录 ----------------
          const Text('媒体扫描目录',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          const Text('视频区 / 音频区会从以下目录递归查找 mp4 / mp3 / m4a 文件。',
              style: TextStyle(color: Colors.grey, fontSize: 12)),
          const SizedBox(height: 8),
          ..._roots.map((r) => ListTile(
                leading: const Icon(Icons.folder),
                title: Text(r, style: const TextStyle(fontSize: 13)),
                trailing: IconButton(
                  icon: const Icon(Icons.close, color: Colors.grey),
                  onPressed: () => _removeRoot(r),
                ),
              )),
          ElevatedButton.icon(
            onPressed: _addRoot,
            icon: const Icon(Icons.add),
            label: const Text('添加扫描目录'),
          ),
          const Divider(height: 32),

          // ---------------- 进度管理 ----------------
          const Text('播放进度',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _clearProgress,
            icon: const Icon(Icons.delete_outline),
            label: const Text('清空所有播放进度'),
          ),
          const Divider(height: 32),

          // ---------------- 工具 ----------------
          const Text('本地工具',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          const Text('合并本机已缓存的 M3U8 + TS 分片为一个视频；合并结果会在视频区出现。',
              style: TextStyle(color: Colors.grey, fontSize: 12)),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () {
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const M3u8MergeScreen(),
              ));
            },
            icon: const Icon(Icons.merge_type),
            label: const Text('M3U8 / TS 批量合并'),
          ),
          const Divider(height: 32),

          // ---------------- 关于 ----------------
          const Text('关于', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(
            '${AppVersion.label}\n发布于 ${AppVersion.date}\n'
            '纯本地运行：不联网、不上传，所有数据仅存于本机。',
            style: const TextStyle(color: Colors.grey, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _themeChip(ThemeProvider theme, ThemeMode mode, String label) {
    return ChoiceChip(
      label: Text(label),
      selected: theme.mode == mode,
      onSelected: (_) => theme.setMode(mode),
    );
  }
}
