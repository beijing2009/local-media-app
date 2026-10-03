import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import '../../models/album.dart';
import '../../models/media_file.dart';
import '../../services/file_scanner.dart';
import '../../services/database_service.dart';
import 'album_detail_screen.dart';
import 'now_playing_bar.dart';

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
    return Scaffold(
      appBar: AppBar(
        title: const Text('音频区'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'files') _createFromFiles();
              if (v == 'folder') _createFromFolder();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'files', child: Text('从音频文件新建')),
              PopupMenuItem(value: 'folder', child: Text('从文件夹新建')),
            ],
            icon: const Icon(Icons.add),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
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
        ),
      ),
      body: filtered.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(Icons.headphones, size: 64, color: Colors.grey),
                  SizedBox(height: 12),
                  Text('还没有专辑'),
                  Text('点击右上角 + 从文件或文件夹新建',
                      style: TextStyle(color: Colors.grey, fontSize: 12)),
                ],
              ),
            )
          : ListView.separated(
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
      bottomNavigationBar: const NowPlayingBar(),
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
