import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import '../models/media_file.dart';
import '../services/database_service.dart';
import '../providers/scan_notifier.dart';

/// 本地文件浏览器：浏览手机存储中的文件夹，把选定目录加入“扫描源”。
/// 视频区 / 音频区均可复用此页选择媒体所在文件夹。
class FileBrowserScreen extends StatefulWidget {
  final MediaType mediaType;
  const FileBrowserScreen({required this.mediaType, Key? key})
      : super(key: key);

  @override
  State<FileBrowserScreen> createState() => _FileBrowserScreenState();
}

class _FileBrowserScreenState extends State<FileBrowserScreen> {
  String _current = '';
  List<FileSystemEntity> _entries = [];

  @override
  void initState() {
    super.initState();
    _initRoot();
  }

  Future<void> _initRoot() async {
    final roots = await DatabaseService.instance.getScanRoots();
    String start = '/storage/emulated/0';
    if (roots.isNotEmpty) {
      start = roots.first;
    } else if (!Directory(start).existsSync()) {
      start = Directory.systemTemp.path;
    }
    _goto(start);
  }

  Future<void> _goto(String path) async {
    final dir = Directory(path);
    List<FileSystemEntity> list = [];
    try {
      list = dir
          .listSync(followLinks: false)
          .where((e) =>
              e is Directory ||
              (e is File && _isTargetMedia(e.path)))
          .toList();
    } catch (_) {
      // 无权限或不可读，保持空列表
    }
    list.sort((a, b) {
      final aDir = a is Directory;
      final bDir = b is Directory;
      if (aDir != bDir) return aDir ? -1 : 1; // 文件夹在前
      return p.basename(a.path).compareTo(p.basename(b.path));
    });
    if (mounted) {
      setState(() {
        _current = path;
        _entries = list;
      });
    }
  }

  bool _isTargetMedia(String path) {
    final ext = p.extension(path).toLowerCase().replaceAll('.', '');
    return widget.mediaType == MediaType.video
        ? SupportedFormats.isVideo(ext)
        : SupportedFormats.isAudio(ext);
  }

  Future<void> _addDirAsRoot(String dirPath) async {
    // 在异步前先获取 notifier，避免跨异步使用 BuildContext 的告警
    final scan = Provider.of<ScanNotifier>(context, listen: false);
    final roots = await DatabaseService.instance.getScanRoots();
    if (!roots.contains(dirPath)) {
      roots.add(dirPath);
      await DatabaseService.instance.setScanRoots(roots);
      // 通知视频区 / 音频区重新扫描
      scan.changed();
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final isVideo = widget.mediaType == MediaType.video;
    return Scaffold(
      appBar: AppBar(
        title: Text(isVideo ? '浏览视频文件夹' : '浏览音频文件夹'),
        actions: [
          TextButton(
            onPressed: () => _addDirAsRoot(_current),
            child: const Text('添加此目录',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: Column(
        children: [
          // 当前路径展示 + 上级目录按钮
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: Theme.of(context).primaryColor.withOpacity(0.08),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_upward, size: 20),
                  tooltip: '上级目录',
                  onPressed: () {
                    final parent = p.dirname(_current);
                    if (parent != _current) _goto(parent);
                  },
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(_current,
                      style: const TextStyle(fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ),
          Expanded(
            child: _entries.isEmpty
                ? const Center(child: Text('该目录下无可访问内容'))
                : ListView.builder(
                    itemCount: _entries.length,
                    itemBuilder: (ctx, i) {
                      final e = _entries[i];
                      final isDir = e is Directory;
                      final name = p.basename(e.path);
                      return ListTile(
                        leading: Icon(isDir
                            ? Icons.folder
                            : (isVideo
                                ? Icons.video_file
                                : Icons.audio_file)),
                        title: Text(name),
                        onTap: () {
                          if (isDir) {
                            _goto(e.path);
                          } else {
                            // 点击媒体文件：将其所在目录加入扫描源并退出
                            _addDirAsRoot(p.dirname(e.path));
                          }
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
