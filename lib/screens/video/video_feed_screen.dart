import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/media_file.dart';
import '../../services/file_scanner.dart';
import '../../services/database_service.dart';
import '../../services/permission_service.dart';
import '../../providers/scan_notifier.dart';
import 'video_page.dart';
import '../file_browser_screen.dart';

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

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    return Scaffold(
      appBar: AppBar(
        title: const Text('视频区'),
        actions: [
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
            const Text('请先在「功能区」添加包含 mp4 的扫描目录',
                style: TextStyle(color: Colors.grey, fontSize: 12)),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: () async {
                await Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) =>
                      const FileBrowserScreen(mediaType: MediaType.video),
                ));
                _loadFromRoots();
              },
              child: const Text('去添加目录'),
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
