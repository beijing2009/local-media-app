import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import '../../models/media_file.dart';
import '../../services/file_scanner.dart';
import '../../services/database_service.dart';
import '../../services/permission_service.dart';
import '../../services/auto_scanner.dart';
import '../../widgets/full_scan_dialog.dart';
import '../../providers/scan_notifier.dart';
import 'video_page.dart';
import '../file_browser_screen.dart';
import '../import/import_center_screen.dart';

/// 视频区：抖音风格上下滑动浏览（仅处理 mp4 视频）。
class VideoFeedScreen extends StatefulWidget {
  const VideoFeedScreen({Key? key}) : super(key: key);

  @override
  State<VideoFeedScreen> createState() => _VideoFeedScreenState();
}

class _VideoFeedScreenState extends State<VideoFeedScreen> {
  List<MediaFile> _videos = [];
  final TextEditingController _search = TextEditingController();
  final PageController _pageController = PageController();
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    // 进入视频区时申请存储权限（安卓），并加载扫描源
    PermissionService.requestStorage();
    _loadFromRoots();
    // 监听“功能区”扫描源变更，自动刷新
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<ScanNotifier>(context, listen: false)
          .addListener(_onScanChanged);
    });
  }

  void _onScanChanged() => _loadFromRoots();

  @override
  void dispose() {
    _pageController.dispose();
    Provider.of<ScanNotifier>(context, listen: false)
        .removeListener(_onScanChanged);
    super.dispose();
  }

  Future<void> _loadFromRoots() async {
    if (!mounted) return;
    setState(() => _loading = true);
    final roots = await DatabaseService.instance.getScanRoots();
    final List<MediaFile> all = [];
    for (final root in roots) {
      all.addAll(FileScanner.scanRecursive(root));
    }
    // 合并「导入中心」额外加入的单个视频文件（支持批量导入的文件）
    final imported = await DatabaseService.instance.getImportedPaths();
    for (final path in imported) {
      final file = File(path);
      if (!file.existsSync()) continue;
      final ext = p.extension(path).toLowerCase().replaceAll('.', '');
      if (!SupportedFormats.isVideo(ext)) continue;
      all.add(MediaFile(
        path: path,
        name: p.basename(path),
        type: MediaType.video,
        sizeBytes: file.lengthSync(),
      ));
    }
    // 仅保留视频并去重排序
    final videos = FileScanner.dedupeAndSort(
        all.where((m) => m.type == MediaType.video).toList());
    if (mounted) {
      setState(() {
        _videos = videos;
        _loading = false;
      });
    }
  }

  List<MediaFile> get _filtered =>
      FileScanner.filterByName(_videos, _search.text);

  /// 全盘扫描（仅安卓）：遍历整个存储根，把找到的 mp4/ts 视频自动导入，
  /// 复用「批量导入」管线，避免污染手动添加的扫描目录配置。
  Future<void> _fullScan() async {
    final messenger = ScaffoldMessenger.of(context);
    if (!AutoScanner.isAndroid) return;
    final ok = await PermissionService.requestStorage();
    if (!ok) {
      messenger.showSnackBar(const SnackBar(
        content: Text('需要「所有文件访问」权限才能扫描全盘'),
        action: SnackBarAction(
            label: '去设置', onPressed: PermissionService.openSettings),
      ));
      return;
    }
    final dirs = ValueNotifier<int>(0);
    final found = ValueNotifier<int>(0);
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => FullScanDialog(dirs: dirs, found: found),
    );
    List<MediaFile> media = const <MediaFile>[];
    try {
      media = await AutoScanner.scanMedia(
        onProgress: (d, f) {
          dirs.value = d;
          found.value = f;
        },
      );
    } catch (_) {}
    if (mounted) Navigator.of(context, rootNavigator: true).pop();

    final videos =
        media.where((m) => m.type == MediaType.video).map((m) => m.path).toList();
    if (videos.isEmpty) {
      messenger.showSnackBar(const SnackBar(content: Text('全盘未找到 mp4 / ts 视频')));
      return;
    }
    final added = await DatabaseService.instance.addImportedPaths(videos);
    await _loadFromRoots();
    messenger.showSnackBar(SnackBar(
      content: Text('已导入 $added 个视频（可在「批量导入」里管理）'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    return Scaffold(
      appBar: AppBar(
        title: const Text('视频区'),
        actions: [
          IconButton(
            icon: const Icon(Icons.downloading_outlined),
            tooltip: '批量导入视频',
            onPressed: () async {
              await Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const ImportCenterScreen(),
              ));
              _loadFromRoots();
            },
          ),
          IconButton(
            icon: const Icon(Icons.folder_open),
            tooltip: '浏览文件夹',
            onPressed: () async {
              await Navigator.of(context).push(MaterialPageRoute(
                builder: (_) =>
                    const FileBrowserScreen(mediaType: MediaType.video),
              ));
              _loadFromRoots();
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '重新扫描',
            onPressed: _loadFromRoots,
          ),
          if (AutoScanner.isAndroid)
            IconButton(
              icon: const Icon(Icons.storage),
              tooltip: '全盘扫描',
              onPressed: _fullScan,
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: TextField(
              controller: _search,
              decoration: const InputDecoration(
                hintText: '搜索视频文件名',
                prefixIcon: Icon(Icons.search, size: 20),
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
        ),
      ),
      body: _buildBody(filtered),
    );
  }

  Widget _buildBody(List<MediaFile> filtered) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (filtered.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.video_library_outlined,
                size: 64, color: Colors.grey),
            const SizedBox(height: 12),
            const Text('暂无视频'),
            const SizedBox(height: 4),
            const Text('点右上角「批量导入」加入本机视频，或添加扫描目录',
                style: TextStyle(color: Colors.grey, fontSize: 12)),
            const SizedBox(height: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ElevatedButton(
                  onPressed: () async {
                    await Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const ImportCenterScreen(),
                    ));
                    _loadFromRoots();
                  },
                  child: const Text('批量导入'),
                ),
                const SizedBox(width: 10),
                OutlinedButton(
                  onPressed: () async {
                    await Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) =>
                          const FileBrowserScreen(mediaType: MediaType.video),
                    ));
                    _loadFromRoots();
                  },
                  child: const Text('添加目录'),
                ),
              ],
            ),
          ],
        ),
      );
    }
    // 抖音式竖向滑动：每个页面一个视频
    return PageView.builder(
      controller: _pageController,
      scrollDirection: Axis.vertical,
      itemCount: filtered.length,
      itemBuilder: (ctx, i) => VideoPage(
        video: filtered[i],
        index: i,
        controller: _pageController,
      ),
    );
  }
}
