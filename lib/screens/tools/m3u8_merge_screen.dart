import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import '../../services/m3u8_service.dart';
import '../../services/database_service.dart';
import '../../providers/scan_notifier.dart';

/// M3U8 + TS 合并工具（纯本地）。
///
/// 批量：多个播放列表可同时勾选合并；支持全选 / 反选 / 清空。
/// 命名：按原文件名，或按时间自动命名。
class M3u8MergeScreen extends StatefulWidget {
  const M3u8MergeScreen({Key? key}) : super(key: key);

  @override
  State<M3u8MergeScreen> createState() => _M3u8MergeScreenState();
}

class _M3u8MergeScreenState extends State<M3u8MergeScreen> {
  final Set<String> _selected = <String>{};

  List<M3u8Info> _infos = <M3u8Info>[];
  String _outputDir = '';
  bool _useOriginalName = true;
  bool _loading = false;
  bool _merging = false;
  int _done = 0;
  int _total = 0;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    setState(() => _loading = true);
    final dir = await M3u8Service.defaultOutputDir();
    if (!mounted) return;
    setState(() => _outputDir = dir);
    await _scan();
  }

  Future<void> _scan() async {
    setState(() => _loading = true);
    await Future<void>.delayed(Duration.zero);
    final roots = await DatabaseService.instance.getScanRoots();
    final infos = await M3u8Service.scanPlaylists(roots);
    if (!mounted) return;
    setState(() {
      _infos = infos;
      _loading = false;
    });
  }

  Future<void> _scanPickedDir() async {
    final messenger = ScaffoldMessenger.of(context);
    final dir = await FilePicker.platform.getDirectoryPath();
    if (dir == null || dir.isEmpty) return;
    setState(() => _loading = true);
    final infos = await M3u8Service.scanPlaylists(<String>[dir]);
    if (!mounted) return;
    setState(() {
      final merged = <String, M3u8Info>{
        for (final i in _infos) i.path: i,
      };
      for (final i in infos) {
        merged.putIfAbsent(i.path, () => i);
      }
      _infos = merged.values.toList();
      _loading = false;
    });
    messenger.showSnackBar(SnackBar(content: Text('已扫描目录：$dir')));
  }

  Future<void> _pickOutputDir() async {
    final dir = await FilePicker.platform.getDirectoryPath();
    if (dir == null || dir.isEmpty) return;
    setState(() => _outputDir = dir);
  }

  Future<void> _mergeSelected() async {
    if (_outputDir.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请先选择输出目录')));
      return;
    }
    final list = _infos
        .where((i) => _selected.contains(i.path) && _canSelect(i))
        .toList();
    if (list.isEmpty) return;

    final messenger = ScaffoldMessenger.of(context);
    final notifier = Provider.of<ScanNotifier>(context, listen: false);

    setState(() {
      _merging = true;
      _done = 0;
      _total = list.length;
    });

    final results = await M3u8Service.mergeMany(
      list,
      outputDir: _outputDir,
      useOriginalName: _useOriginalName,
      onProgress: (d, t) {
        if (mounted) {
          setState(() {
            _done = d;
            _total = t;
          });
        }
      },
    );

    // 合并结果落到扫描范围，保证能在视频区直接看到
    final roots = await DatabaseService.instance.getScanRoots();
    if (!roots.contains(_outputDir)) {
      roots.add(_outputDir);
      await DatabaseService.instance.setScanRoots(roots);
    }

    if (!mounted) return;
    setState(() {
      _merging = false;
      _selected.clear();
    });
    notifier.changed();

    final ok = results.where((r) => r.ok).length;
    final skipped = results.fold<int>(0, (a, b) => a + b.missing);
    messenger.showSnackBar(
      SnackBar(content: Text('完成 $ok / ${results.length} 个'
          '${skipped > 0 ? '（缺失分片 $skipped）' : ''}')),
    );
  }

  // 不可选：主列表 / 无分片 / 加密方式不支持（避免合出损坏文件）。
  bool _canSelect(M3u8Info info) =>
      !info.isMaster && !info.unreadable && info.segments.isNotEmpty;

  void _selectAll() {
    setState(() {
      _selected.clear();
      _selected.addAll(
          _infos.where(_canSelect).map((i) => i.path));
    });
  }

  void _invert() {
    setState(() {
      final can = _infos.where(_canSelect);
      for (final i in can) {
        if (!_selected.remove(i.path)) _selected.add(i.path);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('M3U8 合并'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '重新扫描',
            onPressed: _scan,
          ),
        ],
      ),
      body: _merging ? _buildProgress() : _buildBody(),
      bottomNavigationBar: (_merging || _selected.isEmpty)
          ? null
          : _buildBatchBar(),
    );
  }

  Widget _buildProgress() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text('正在合并 $_done / $_total'),
            const SizedBox(height: 4),
            const Text(
              '分片较多时会稍慢，请勿退出',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    return Column(
      children: [
        _buildSettings(),
        const Divider(height: 1),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _buildList(),
        ),
      ],
    );
  }

  Widget _buildSettings() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '输出目录：${_outputDir.isEmpty ? '未选择' : _outputDir}',
                  style: const TextStyle(fontSize: 12),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton(
                onPressed: _pickOutputDir,
                child: const Text('选择'),
              ),
            ],
          ),
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('使用原文件名'),
            subtitle: Text(
              _useOriginalName
                  ? '输出为「playlist.ts」'
                  : '输出为「merged_日期_时间.ts」',
              style: const TextStyle(fontSize: 12),
            ),
            value: _useOriginalName,
            onChanged: (v) => setState(() => _useOriginalName = v),
          ),
          Row(
            children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.folder_open, size: 18),
                label: const Text('指定目录扫描'),
                onPressed: _scanPickedDir,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
    if (_infos.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.movie_filter_outlined, size: 64, color: Colors.grey),
              SizedBox(height: 12),
              Text('没有找到 .m3u8 播放列表'),
              SizedBox(height: 6),
              Text(
                '请先在「功能区」添加缓存所在目录，或点上方「指定目录扫描」',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }
    return ListView.builder(
      itemCount: _infos.length,
      itemBuilder: (ctx, i) => _tile(_infos[i]),
    );
  }

  Widget _tile(M3u8Info info) {
    final can = _canSelect(info);
    final selected = _selected.contains(info.path);
    String sub;
    if (info.isMaster) {
      sub = '多码率主列表，无直接分片';
    } else if (info.unreadable) {
      sub = '加密方式不支持（${info.method}）：需 DRM 或超纲';
    } else {
      sub = '${info.segments.length} 个分片 · ${_fmt(info.totalBytes)}'
          ' · ${info.encrypted ? 'AES 加密' : '明文'}';
      if (info.missingCount > 0) sub += ' · 缺失 ${info.missingCount}';
    }
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: CheckboxListTile(
        value: can ? selected : false,
        onChanged: can
            ? (v) => setState(() {
                  if (v == true) {
                    _selected.add(info.path);
                  } else {
                    _selected.remove(info.path);
                  }
                })
            : null,
        secondary: Icon(
          info.unreadable
              ? Icons.lock
              : (info.encrypted ? Icons.lock_open : Icons.movie_outlined),
        ),
        title: Text(info.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis),
      ),
    );
  }

  Widget _buildBatchBar() {
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
                  Text('已选 ${_selected.length} 个列表',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton(onPressed: _selectAll, child: const Text('全选')),
                      TextButton(onPressed: _invert, child: const Text('反选')),
                      TextButton(
                        onPressed: () => setState(_selected.clear),
                        child: const Text('清空'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            ElevatedButton(
              onPressed: _mergeSelected,
              child: const Text('批量合并'),
            ),
          ],
        ),
      ),
    );
  }

  String _fmt(int bytes) {
    if (bytes <= 0) return '未知大小';
    final mb = bytes / (1024 * 1024);
    if (mb >= 1) return '${mb.toStringAsFixed(1)} MB';
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }
}
