import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import '../../models/album.dart';
import '../../services/database_service.dart';
import '../../providers/audio_provider.dart';
import 'now_playing_bar.dart';
import '../../utils/format.dart';

/// 音频专辑详情：分栏展示「剧集列表 / 目录 / 简介」，并内置播放控制。
/// 宽屏（平板）左右分栏；窄屏（手机）用顶部 Tab 切换。
class AlbumDetailScreen extends StatefulWidget {
  final Album album;
  const AlbumDetailScreen({required this.album, Key? key}) : super(key: key);

  @override
  State<AlbumDetailScreen> createState() => _AlbumDetailScreenState();
}

class _AlbumDetailScreenState extends State<AlbumDetailScreen> {
  late Album _album;

  @override
  void initState() {
    super.initState();
    _album = widget.album;
  }

  Future<void> _editDescription() async {
    final ctl = TextEditingController(text: _album.description);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('编辑简介'),
        content: TextField(
          controller: ctl,
          maxLines: 4,
          decoration: const InputDecoration(hintText: '填写专辑 / 剧集简介'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(ctl.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (result != null) {
      final updated = _album.copyWith(description: result);
      await DatabaseService.instance.updateAlbum(updated);
      setState(() => _album = updated);
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isWide = width > 600;
    return Scaffold(
      appBar: AppBar(
        title: Text(_album.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_note),
            tooltip: '编辑简介',
            onPressed: _editDescription,
          ),
        ],
      ),
      bottomNavigationBar: const NowPlayingBar(),
      body: isWide ? _wideLayout() : _narrowLayout(),
    );
  }

  /// 宽屏：左侧剧集列表，右侧简介 + 播放控制。
  Widget _wideLayout() {
    return Row(
      children: [
        Expanded(flex: 2, child: _EpisodeList(album: _album)),
        const VerticalDivider(width: 1),
        Expanded(
          flex: 3,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _IntroHeader(album: _album),
                const SizedBox(height: 16),
                _ControlPanel(album: _album),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// 窄屏：Tab 切换 剧集 / 简介。
  Widget _narrowLayout() {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          const TabBar(
            tabs: [Tab(text: '剧集'), Tab(text: '简介')],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _EpisodeList(album: _album),
                SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _IntroHeader(album: _album),
                      const SizedBox(height: 16),
                      _ControlPanel(album: _album),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 剧集列表（同时充当目录）：点击即播放对应集。
class _EpisodeList extends StatelessWidget {
  final Album album;
  const _EpisodeList({required this.album});

  @override
  Widget build(BuildContext context) {
    if (album.episodePaths.isEmpty) {
      return const Center(child: Text('该专辑暂无音频'));
    }
    return Consumer<AudioProvider>(
      builder: (ctx, audio, _) {
        return ListView.separated(
          itemCount: album.episodePaths.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (ctx, i) {
            final path = album.episodePaths[i];
            final title = p.basename(path);
            final isCurrent = audio.hasCurrent && audio.currentPath == path;
            return ListTile(
              leading: CircleAvatar(
                radius: 14,
                backgroundColor:
                    isCurrent ? Theme.of(ctx).primaryColor : Colors.grey.shade300,
                child: Text('${i + 1}',
                    style: const TextStyle(fontSize: 12, color: Colors.white)),
              ),
              title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: isCurrent
                  ? Text(audio.isPlaying ? '播放中…' : '已暂停')
                  : null,
              trailing: isCurrent
                  ? Icon(audio.isPlaying ? Icons.volume_up : Icons.pause,
                      color: Theme.of(ctx).primaryColor)
                  : null,
              onTap: () => audio.loadAlbum(album, index: i),
            );
          },
        );
      },
    );
  }
}

/// 简介头部：封面色块 + 名称 + 集数 + 简介文本。
class _IntroHeader extends StatelessWidget {
  final Album album;
  const _IntroHeader({required this.album});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 88,
          height: 88,
          decoration: BoxDecoration(
            color: Color(album.colorValue),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.audiotrack, color: Colors.white, size: 40),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(album.name,
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text('共 ${album.episodeCount} 集',
                  style: const TextStyle(color: Colors.grey)),
              const SizedBox(height: 8),
              Text(
                album.description.isNotEmpty ? album.description : '暂无简介',
                style: const TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 播放控制面板：上一集 / 播放暂停 / 下一集 + 倍速 + 音量。
class _ControlPanel extends StatelessWidget {
  final Album album;
  const _ControlPanel({required this.album});

  static const List<double> _speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

  @override
  Widget build(BuildContext context) {
    return Consumer<AudioProvider>(
      builder: (ctx, audio, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 主控制：上一项 / 播放暂停 / 下一项
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.skip_previous, size: 36),
                  onPressed: audio.hasCurrent ? audio.previous : null,
                ),
                IconButton(
                  icon: Icon(
                    audio.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
                    size: 56,
                    color: Theme.of(ctx).primaryColor,
                  ),
                  onPressed: audio.hasCurrent ? audio.toggle : null,
                ),
                IconButton(
                  icon: const Icon(Icons.skip_next, size: 36),
                  onPressed: audio.hasCurrent ? audio.next : null,
                ),
              ],
            ),
            const SizedBox(height: 12),
            // 进度条
            if (audio.hasCurrent)
              Column(
                children: [
                  Slider(
                    value: audio.duration.inMilliseconds == 0
                        ? 0
                        : audio.position.inMilliseconds
                            .toDouble()
                            .clamp(0, audio.duration.inMilliseconds.toDouble()),
                    min: 0,
                    max: audio.duration.inMilliseconds == 0
                        ? 1
                        : audio.duration.inMilliseconds.toDouble(),
                    onChanged: (v) => audio.seek(Duration(milliseconds: v.toInt())),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(formatDuration(audio.position),
                            style: const TextStyle(fontSize: 12, color: Colors.grey)),
                        Text(formatDuration(audio.duration),
                            style: const TextStyle(fontSize: 12, color: Colors.grey)),
                      ],
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 16),
            const Text('倍速', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: _speeds
                  .map((s) => ChoiceChip(
                        label: Text('${s}x'),
                        selected: (audio.speed - s).abs() < 0.01,
                        onSelected: (_) => audio.setSpeed(s),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 16),
            const Text('音量', style: TextStyle(fontWeight: FontWeight.bold)),
            Slider(
              value: audio.volume,
              min: 0,
              max: 1,
              divisions: 20,
              label: '${(audio.volume * 100).round()}%',
              onChanged: (v) => audio.setVolume(v),
            ),
          ],
        );
      },
    );
  }
}
