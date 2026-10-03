import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import '../../models/media_file.dart';
import '../../services/import_service.dart';
import '../../services/database_service.dart';
import '../../providers/scan_notifier.dart';

/// 本地视频导入中心（支持批量操作）。
///
/// 三种批量场景：
/// 1) 来源目录批量多选 -> 一次性把目录内全部视频加入列表
/// 2) 进入目录后文件级批量多选 -> 精确挑选部分视频加入列表
/// 3) 已导入清单批量多选 -> 批量移除 / 一键清空
///
/// 全部为本地文件操作：读取本机已保存的视频，无任何网络请求。
class ImportCenterScreen extends StatefulWidget {
  const ImportCenterScreen({Key? key}) : super(key: key);

  @override
  State<ImportCenterScreen> createState() => _ImportCenterScreenState();
}

class _ImportCenterScreenState extends State<ImportCenterScreen> {
  final Set<String> _selectedDirs = <String>{};
  final Set<String> _selectedFiles = <String>{};
  final Set<String> _selectedImported = <String>{};

  List<ImportCandidate> _candidates = <ImportCandidate>[];
  List<String> _imported = <String>[];
  List<MediaFile> _dirVideos = <MediaFile>[];
  String? _currentDir;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  // ---------------- 数据加载 ----------------
  Future<void> _load() async {
    setState(() => _loading = true);
    // 先让 loading 指示器绘制一帧，避免扫描大目录时看起来卡死
    await Future<void>.delayed(Duration.zero);
    final cands = ImportService.detectPlatformDirs();
    final imported = await DatabaseService.instance.getImportedPaths();
    if (!mounted) return;
    setState(() {
      _candidates = cands;
      _imported = imported;
      _loading = false;
    });
  }

  // ---------------- 目录 / 文件切换 ----------------
  Future<void> _enterDir(String dir) async {
    setState(() => _loading = true);
    await Future<void>.delayed(Duration.zero);
    final videos = ImportService.listVideos(dir);
    if (!mounted) return;
    setState(() {
      _currentDir = dir;
      _dirVideos = videos;
      _selectedFiles.clear();
      _loading = false;
    });
  }

  void _exitDirMode() {
    setState(() {
      _currentDir = null;
      _dirVideos = <MediaFile>[];
      _selectedFiles.clear();
    });
  }

  // ---------------- 批量操作 ----------------
  Future<void> _importDirs(Set<String> dirs) async {
    final List<String> paths = <String>[];
    for (final d in dirs) {
      paths.addAll(ImportService.listVideos(d).map((m) => m.path));
    }
    await _addPaths(paths);
    if (mounted) setState(() => _selectedDirs.clear());
  }

  Future<void> _importFiles(Set<String> files) async {
    final messenger = ScaffoldMessenger.of(context);
    await _addPaths(files.toList());
    if (!mounted) return;
    setState(() => _selectedFiles.clear());
    messenger.showSnackBar(
        const SnackBar(content: Text('已加入，返回视频区即可看到')));
  }

  Future<void> _addPaths(List<String> paths) async {
    if (paths.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    final notifier = Provider.of<ScanNotifier>(context, listen: false);
    final n = await DatabaseService.instance.addImportedPaths(paths);
    await _load();
    if (!mounted) return;
    notifier.changed(); // 通知视频区刷新
    messenger.showSnackBar(SnackBar(content: Text('已批量加入 $n 个视频')));
  }

  Future<void> _removeImported(Set<String> paths) async {
    final messenger = ScaffoldMessenger.of(context);
    final notifier = Provider.of<ScanNotifier>(context, listen: false);
    final n = await DatabaseService.instance.removeImportedPaths(paths.toList());
    await _load();
    if (!mounted) return;
    setState(() => _selectedImported.clear());
    notifier.changed();
    messenger.showSnackBar(SnackBar(content: Text('已移除 $n 个文件')));
  }

  Future<void> _clearAllImported() async {
    final messenger = ScaffoldMessenger.of(context);
    final notifier = Provider.of<ScanNotifier>(context, listen: false);
    await DatabaseService.instance.clearImportedPaths();
    await _load();
    if (!mounted) return;
    setState(() => _selectedImported.clear());
    notifier.changed();
    messenger.showSnackBar(const SnackBar(content: Text('已清空导入清单')));
  }

  Future<void> _pickDir() async {
    final messenger = ScaffoldMessenger.of(context);
    final dir = await FilePicker.platform.getDirectoryPath();
    if (dir == null || dir.isEmpty) return;
    final exists = _candidates.indexWhere((c) => c.path == dir);
    if (exists >= 0) return;
    final count = ImportService.listVideos(dir).length;
    if (count <= 0) {
      messenger.showSnackBar(const SnackBar(content: Text('该目录内没有视频文件')));
      return;
    }
    setState(() {
      _candidates =
          List<ImportCandidate>.from(_candidates)..add(ImportCandidate(
            path: dir,
            label: '手动添加',
            videoCount: count,
          ));
    });
  }

  // ---------------- 选择辅助 ----------------
  void _selectAllDirs() {
    setState(() {
      _selectedDirs.clear();
      _selectedDirs.addAll(_candidates.map((c) => c.path));
    });
  }

  void _invertDirs() {
    setState(() {
      for (final c in _candidates) {
        if (!_selectedDirs.remove(c.path)) _selectedDirs.add(c.path);
      }
    });
  }

  void _selectAllFiles() {
    setState(() {
      _selectedFiles.clear();
      _selectedFiles.addAll(_dirVideos.map((m) => m.path));
    });
  }

  void _invertFiles() {
    setState(() {
      for (final m in _dirVideos) {
        if (!_selectedFiles.remove(m.path)) _selectedFiles.add(m.path);
      }
    });
  }

  void _selectAllImported() {
    setState(() {
      _selectedImported.clear();
      _selectedImported.addAll(_imported);
    });
  }

  void _invertImported() {
    setState(() {
      for (final e in _imported) {
        if (!_selectedImported.remove(e)) _selectedImported.add(e);
      }
    });
  }

  // ---------------- UI ----------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: _currentDir == null
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: _exitDirMode,
              ),
        title: Text(_currentDir == null ? '导入视频' : '选择文件加入'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '重新检测',
            onPressed: _load,
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'clear' && _imported.isNotEmpty) _clearAllImported();
            },
            itemBuilder: (_) => const [
              PopupMenuItem<String>(
                value: 'clear',
                child: Text('清空导入清单'),
              ),
            ],
          ),
        ],
      ),
      body: _buildBody(),
      bottomNavigationBar: _buildBatchBar(),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_currentDir != null) return _buildFileList();
    return _buildHome();
  }

  Widget _buildHome() {
    if (_candidates.isEmpty && _imported.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.folder_off_outlined, size: 64, color: Colors.grey),
              const SizedBox(height: 12),
              const Text('没有检测到可用的视频目录'),
              const SizedBox(height: 6),
              const Text(
                '请先在抖音/快手里「保存到本地/相册」，或手动选择一个文件夹',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                icon: const Icon(Icons.create_new_folder_outlined),
                label: const Text('手动选择文件夹'),
                onPressed: _pickDir,
              ),
            ],
          ),
        ),
      );
    }
    return ListView(
      children: [
        const _Section('自动识别的来源'),
        for (final c in _candidates) _candidateTile(c),
        ListTile(
          leading: const Icon(Icons.create_new_folder_outlined),
          title: const Text('手动选择文件夹'),
          subtitle: const Text('任意目录均可加入候选项'),
          onTap: _pickDir,
        ),
        _Section('已导入清单（${_imported.length}）'),
        if (_imported.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text('还没有导入任何视频', style: TextStyle(color: Colors.grey)),
          )
        else
          for (final path in _imported) _importedTile(path),
        const SizedBox(height: 80),
      ],
    );
  }

  Widget _buildFileList() {
    if (_dirVideos.isEmpty) {
      return const Center(child: Text('该目录内没有视频文件'));
    }
    return ListView.builder(
      itemCount: _dirVideos.length,
      itemBuilder: (ctx, i) {
        final m = _dirVideos[i];
        final selected = _selectedFiles.contains(m.path);
        return CheckboxListTile(
          value: selected,
          onChanged: (v) => setState(() {
            if (v == true) {
              _selectedFiles.add(m.path);
            } else {
              _selectedFiles.remove(m.path);
            }
          }),
          secondary: const Icon(Icons.video_file_outlined),
          title: Text(m.name, maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: Text(_fmtSize(m.sizeBytes)),
        );
      },
    );
  }

  Widget _candidateTile(ImportCandidate c) {
    final selected = _selectedDirs.contains(c.path);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: ListTile(
        leading: Checkbox(
          value: selected,
          onChanged: (v) => setState(() {
            if (v == true) {
              _selectedDirs.add(c.path);
            } else {
              _selectedDirs.remove(c.path);
            }
          }),
        ),
        title: Text(c.label),
        subtitle: Text(
          '${c.videoCount} 个视频\n${c.path}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        isThreeLine: true,
        trailing: IconButton(
          icon: const Icon(Icons.chevron_right),
          tooltip: '查看文件并挑选',
          onPressed: () => _enterDir(c.path),
        ),
        onTap: () => setState(() {
          if (!_selectedDirs.remove(c.path)) _selectedDirs.add(c.path);
        }),
      ),
    );
  }

  Widget _importedTile(String path) {
    final selected = _selectedImported.contains(path);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: CheckboxListTile(
        value: selected,
        onChanged: (v) => setState(() {
          if (v == true) {
            _selectedImported.add(path);
          } else {
            _selectedImported.remove(path);
          }
        }),
        secondary: const Icon(Icons.play_circle_outline),
        title: Text(p.basename(path), maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(path, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    );
  }

  Widget? _buildBatchBar() {
    if (_loading) return null;
    if (_currentDir != null) {
      return _batchBar(
        text: '已选 ${_selectedFiles.length} 个文件',
        onSelectAll: _dirVideos.isEmpty ? null : _selectAllFiles,
        onInvert: _dirVideos.isEmpty ? null : _invertFiles,
        onClear: () => setState(_selectedFiles.clear),
        actionLabel: '加入视频列表',
        onAction:
            _selectedFiles.isEmpty ? null : () => _importFiles(_selectedFiles),
      );
    }
    if (_selectedDirs.isNotEmpty) {
      return _batchBar(
        text: '已选 ${_selectedDirs.length} 个来源目录',
        onSelectAll: _selectAllDirs,
        onInvert: _invertDirs,
        onClear: () => setState(_selectedDirs.clear),
        actionLabel: '批量导入全部视频',
        onAction: () => _importDirs(_selectedDirs),
      );
    }
    if (_selectedImported.isNotEmpty) {
      return _batchBar(
        text: '已选 ${_selectedImported.length} 个已导入文件',
        onSelectAll: _selectAllImported,
        onInvert: _invertImported,
        onClear: () => setState(_selectedImported.clear),
        actionLabel: '批量移除',
        onAction: () => _removeImported(_selectedImported),
        danger: true,
      );
    }
    return null;
  }

  Widget _batchBar({
    required String text,
    required String actionLabel,
    required VoidCallback? onAction,
    VoidCallback? onSelectAll,
    VoidCallback? onInvert,
    VoidCallback? onClear,
    bool danger = false,
  }) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: theme.cardColor,
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(text,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton(
                          onPressed: onSelectAll, child: const Text('全选')),
                      TextButton(onPressed: onInvert, child: const Text('反选')),
                      TextButton(onPressed: onClear, child: const Text('清空')),
                    ],
                  ),
                ],
              ),
            ),
            ElevatedButton(
              style: danger
                  ? ElevatedButton.styleFrom(primary: Colors.red)
                  : null,
              onPressed: onAction,
              child: Text(actionLabel),
            ),
          ],
        ),
      ),
    );
  }

  String _fmtSize(int? bytes) {
    if (bytes == null || bytes <= 0) return '未知大小';
    final mb = bytes / (1024 * 1024);
    if (mb >= 1) return '${mb.toStringAsFixed(1)} MB';
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }
}

class _Section extends StatelessWidget {
  final String text;
  const _Section(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}
