import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'album_detail_screen.dart' show AlbumDetailScreen; // 仅用于类型判断
import '../../providers/audio_provider.dart';

/// 底部迷你播放条：在音频区任意页面常驻显示，点击可展开专辑详情。
/// 无正在播放内容时自动隐藏，保持界面简洁。
class NowPlayingBar extends StatelessWidget {
  const NowPlayingBar({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Consumer<AudioProvider>(
      builder: (ctx, audio, _) {
        if (!audio.hasCurrent) return const SizedBox.shrink();
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return Material(
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          elevation: 8,
          child: InkWell(
            onTap: () => _onTap(ctx, audio),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                children: [
                  // 播放状态指示
                  Icon(
                    audio.isPlaying
                        ? Icons.graphic_eq
                        : Icons.headphones,
                    color: Theme.of(ctx).primaryColor,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(audio.album!.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                        Text(audio.currentTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 12, color: Colors.grey)),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(audio.isPlaying
                        ? Icons.pause
                        : Icons.play_arrow),
                    onPressed: audio.toggle,
                  ),
                  IconButton(
                    icon: const Icon(Icons.skip_next),
                    onPressed: audio.next,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _onTap(BuildContext context, AudioProvider audio) {
    // 若已经在专辑详情页，则不再重复跳转
    final alreadyOnDetail =
        context.findAncestorWidgetOfExactType<AlbumDetailScreen>() != null;
    if (alreadyOnDetail) return;
    if (audio.album != null) {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => AlbumDetailScreen(album: audio.album!),
      ));
    }
  }
}
