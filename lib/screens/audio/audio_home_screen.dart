import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import '../../models/album.dart';
import '../../models/media_file.dart';
import '../../services/file_scanner.dart';
import '../../services/database_service.dart';
import '../../services/auto_scanner.dart';
import '../../services/permission_service.dart';
import '../../widgets/full_scan_dialog.dart';
import 'album_detail_screen.dart';

/// 音频区首页：专辑（听书）列表，支持自建专辑、剧集分类管理。
class AudioHomeScreen extends StatefulWidget {
  const AudioHomeScreen({Key? key}) : super(key: key);

  @override
  State<AudioHomeScreen> createState() => _AudioHomeScreenState();
}

class _AudioHomeScreenState extends State<AudioHomeScreen> {
  List<Album> _albums = [];
  final TextEditingController _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final albums = await DatabaseService.instance.getAlbums();
    if (mounted) setState(() => _albums = albums);
  }

  List<Album> get _filtered =>
      FileScanner.filterAlbumsByName(_albums, _search.text);

  Future<void> _createFromFiles() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.audio,
      allowMultiple: true,
    );
    if (result == null) return;
    final paths = result.paths.whereType<String>().toList();
    if (paths.isEmpty) return;
    final info = await _askAlbumInfo(defaultName: p.basenameWithoutExtension(paths.first));
    if (info == null) return;
    final album = Album(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: info.name,
      description: info.desc,
      episodePaths: paths,
      createdAt: DateTime.now(),
    );
    await DatabaseService.instance.insertAlbum(album);
    _load();
  }

  Future<void> _createFromFolder() async {
    final dir = await FilePicker.platform.getDirectoryPath();
    if (dir == null || dir.isEmpty) return;
    final files = FileScanner.scanRecursive(dir)
        .where((m) => m.type == MediaType.audio)
        .map((m) => m.path)
        .toList();
    if (files.isEmpty) {
      _toast('该文件夹下未找到 mp3 / m4a 音频');
      return;
    }
    files.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    final info = await _askAlbumInfo(defaultName: p.basename(dir));
    if (info == null) return;
    final album = Album(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: info.name,
      description: info.desc,
      episodePaths: files,
      createdAt: DateTime.now(),
    );
    await DatabaseService.instance.insertAlbum(album);
    _load();
  }

  /// 全盘扫描（仅安卓）：遍历整个存储根，按目录结构自动把音频归并为专辑。
  ///
  /// 分组规则：取存储根下的「一级/二级目录」作为专辑名，例如
  /// `/Music/古典/1.mp3` → 专辑「Music/古典」。避免把全盘音频平铺成一坨。
  Future<void> _fullScanAudio() async {
    if (!AutoScanner.isAndroid) return;
    final messenger = ScaffoldMessenger.of(context);
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

    final audios =
        media.where((m) => m.type == MediaType.audio).toList();
    if (audios.isEmpty) {
      messenger.showSnackBar(const SnackBar(content: Text('全盘未找到 mp3 / m4a 音频')));
      return;
    }
    if (audios.length > 5000) {
      messenger.showSnackBar(SnackBar(
        content: Text('发现音频过多（${audios.length} 个），请用「从文件夹新建」'),
      ));
      return;
    }

    final root = AutoScanner.androidStorageRoots
        .firstWhere((r) => Directory(r).existsSync(),
            orElse: () => AutoScanner.androidStorageRoots.first);
    final groups = <String, List<String>>{};
    for (final a in audios) {
      final rel = p.relative(a.path, from: root);
      final parts = rel.split(Platform.pathSeparator);
      final key = parts.length > 2
          ? '${parts[0]}/${parts[1]}'
          : (parts.length > 1 ? parts[0] : p.basename(p.dirname(a.path)));
      groups.putIfAbsent(key, () => <String>[]).add(a.path);
    }
    if (groups.length > 300) {
      messenger.showSnackBar(const SnackBar(
        content: Text('目录过多，请改用「从文件夹新建」逐个导入'),
      ));
      return;
    }

    final now = DateTime.now();
    for (var i = 0; i < groups.length; i++) {
      final entry = groups.entries.elementAt(i);
      final paths = entry.value..sort();
      final album = Album(
        id: '${now.millisecondsSinceEpoch}_$i',
        name: entry.key,
        description: '全盘扫描自动导入',
        episodePaths: paths,
        createdAt: now,
      );
      await DatabaseService.instance.insertAlbum(album);
    }
    _load();
    messenger.showSnackBar(SnackBar(
      content: Text('已建立 ${groups.length} 个专辑，共 ${audios.length} 个音频'),
    ));
  }

  /// 弹窗输入专辑名称与简介。
  Future<_AlbumInfo?> _askAlbumInfo({required String defaultName}) async {
    final nameCtl = TextEditingController(text: defaultName);
    final descCtl = TextEditingController();
    return showDialog<_AlbumInfo>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建专辑'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtl,
              decoration: const InputDecoration(labelText: '专辑名称'),
            ),
            TextField(
              controller: descCtl,
              decoration: const InputDecoration(labelText: '简介（可选）'),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('取消')),
          TextButton(
            onPressed: () {
              final name = nameCtl.text.trim();
              if (name.isEmpty) return;
              Navigator.of(ctx).pop(
                  _AlbumInfo(name: name, desc: descCtl.text.trim()));
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    // 作为首页「音频听书区分栏」嵌入，不再自带 AppBar / 底部播放器
    // （底部悬浮播放器由首页统一提供）。
    return Column(
      children: [
        // 顶部搜索 + 新建专辑
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _search,
                  decoration: const InputDecoration(
                    hintText: '搜索专辑名',
                    prefixIcon: Icon(Icons.search, size: 20),
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'files') _createFromFiles();
                  if (v == 'folder') _createFromFolder();
                  if (v == 'full') _fullScanAudio();
                },
                itemBuilder: (_) => <PopupMenuEntry<String>>[
                  const PopupMenuItem(value: 'files', child: Text('从音频文件新建')),
                  const PopupMenuItem(value: 'folder', child: Text('从文件夹新建')),
                  if (AutoScanner.isAndroid)
                    const PopupMenuItem(value: 'full', child: Text('全盘扫描')),
                ],
                icon: const Icon(Icons.add),
              ),
            ],
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.headphones, size: 64, color: Colors.grey),
                      SizedBox(height: 12),
                      Text('还没有专辑'),
                      Text('点击右侧 + 从文件或文件夹新建',
                          style: TextStyle(color: Colors.grey, fontSize: 12)),
                    ],
                  ),
                )
              : ListView.separated(
                  // 底部留出悬浮播放器高度，避免最后一条被遮挡
                  padding: const EdgeInsets.only(bottom: 84),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (ctx, i) {
                    final album = filtered[i];
                    return _AlbumTile(
                      album: album,
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => AlbumDetailScreen(album: album),
                      )),
                      onDelete: () async {
                        await DatabaseService.instance.deleteAlbum(album.id);
                        _load();
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _AlbumTile extends StatelessWidget {
  final Album album;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _AlbumTile({
    required this.album,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final color = Color(album.colorValue);
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: color,
        child: const Icon(Icons.audiotrack, color: Colors.white),
      ),
      title: Text(album.name),
      subtitle: Text(
        '${album.episodeCount} 集'
        '${album.description.isNotEmpty ? ' · ${album.description}' : ''}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline, color: Colors.grey),
        onPressed: () {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('删除专辑'),
              content: Text('确定删除「${album.name}」？仅删除记录，不删除原文件。'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('取消')),
                TextButton(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    onDelete();
                  },
                  child: const Text('删除'),
                ),
              ],
            ),
          );
        },
      ),
      onTap: onTap,
    );
  }
}

class _AlbumInfo {
  final String name;
  final String desc;
  const _AlbumInfo({required this.name, required this.desc});
}
