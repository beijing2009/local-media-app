import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../../models/media_file.dart';
import '../../services/database_service.dart';
import '../../utils/format.dart';

/// 单个视频页面（抖音式）：占满一屏，激活时自动播放，离开时暂停并记忆进度。
class VideoPage extends StatefulWidget {
  final MediaFile video;
  final int index;
  final PageController controller;

  const VideoPage({
    required this.video,
    required this.index,
    required this.controller,
    Key? key,
  }) : super(key: key);

  @override
  State<VideoPage> createState() => _VideoPageState();
}

class _VideoPageState extends State<VideoPage> {
  late VideoPlayerController _vc;
  final DatabaseService _db = DatabaseService.instance;

  bool _ready = false;
  bool _active = false;
  bool _showControls = false;
  double _volume = 1.0;
  int _lastUiQuarter = -1;
  int _lastSaveMs = 0;

  @override
  void initState() {
    super.initState();
    _vc = VideoPlayerController.file(File(widget.video.path));
    _vc.setLooping(false);
    _vc.addListener(_onVideoChanged);
    _vc.initialize().then((_) async {
      if (!mounted) return;
      final saved = await _db.getVideoPosition(widget.video.path);
      final dur = _vc.value.duration.inMilliseconds;
      // 续播：恢复到上次位置（留出 1 秒余量避免跳到结尾）
      if (saved > 1000 && saved < dur - 1000) {
        await _vc.seekTo(Duration(milliseconds: saved));
      }
      if (mounted) {
        setState(() => _ready = true);
        _updateActive();
      }
    });
    widget.controller.addListener(_updateActive);
    _updateActive();
  }

  /// 根据 PageView 当前页判断本页是否处于“激活（居中可见）”状态。
  void _updateActive() {
    final page = widget.controller.page;
    final active =
        page == null ? widget.index == 0 : page.round() == widget.index;
    if (active == _active) return;
    _active = active;
    if (_ready) {
      if (_active) {
        _vc.play();
      } else {
        _saveAndPause();
      }
    }
  }

  void _onVideoChanged() {
    if (!mounted) return;
    // 节流 UI 刷新：每 250ms 更新一次进度条
    final quarter = _vc.value.position.inMilliseconds ~/ 250;
    if (quarter != _lastUiQuarter) {
      _lastUiQuarter = quarter;
      setState(() {});
    }
    // 每 3 秒落盘一次播放进度
    if (_vc.value.isPlaying) {
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - _lastSaveMs > 3000) {
        _lastSaveMs = now;
        _db.saveVideoPosition(
            widget.video.path, _vc.value.position.inMilliseconds);
      }
    }
  }

  Future<void> _saveAndPause() async {
    await _db.saveVideoPosition(
        widget.video.path, _vc.value.position.inMilliseconds);
    await _vc.pause();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_updateActive);
    _vc.removeListener(_onVideoChanged);
    // 退出时保存进度
    _db.saveVideoPosition(
        widget.video.path, _vc.value.position.inMilliseconds);
    _vc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => setState(() => _showControls = !_showControls),
      child: Container(
        color: Colors.black,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (_ready)
              Center(
                child: AspectRatio(
                  aspectRatio: _vc.value.aspectRatio > 0
                      ? _vc.value.aspectRatio
                      : 16 / 9,
                  child: VideoPlayer(_vc),
                ),
              )
            else
              const CircularProgressIndicator(),
            // 文件名（左上角）
            Positioned(
              left: 16,
              top: 40,
              right: 16,
              child: Text(
                widget.video.name,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  shadows: [Shadow(blurRadius: 6, color: Colors.black)],
                ),
              ),
            ),
            // 中央播放/暂停按钮
            if (_showControls && _ready)
              IconButton(
                icon: Icon(
                  _vc.value.isPlaying
                      ? Icons.pause_circle_filled
                      : Icons.play_circle_filled,
                  color: Colors.white,
                  size: 64,
                ),
                onPressed: () {
                  if (_vc.value.isPlaying) {
                    _saveAndPause();
                  } else {
                    _vc.play();
                  }
                  setState(() {});
                },
              ),
            // 音量滑块（右侧竖条，仅在显示控件时出现）
            if (_showControls && _ready)
              Positioned(
                right: 12,
                top: 90,
                bottom: 120,
                child: RotatedBox(
                  quarterTurns: 3,
                  child: SizedBox(
                    width: 160,
                    child: Slider(
                      value: _volume,
                      min: 0,
                      max: 1,
                      divisions: 20,
                      label: '${(_volume * 100).round()}%',
                      onChanged: (v) {
                        setState(() => _volume = v);
                        _vc.setVolume(v);
                      },
                    ),
                  ),
                ),
              ),
            // 底部进度条与时间
            if (_ready)
              Positioned(
                left: 16,
                right: 16,
                bottom: 24,
                child: _progressBar(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _progressBar() {
    final pos = _vc.value.position;
    final dur = _vc.value.duration;
    final max =
        dur.inMilliseconds.toDouble().clamp(1, double.infinity).toDouble();
    final value =
        pos.inMilliseconds.toDouble().clamp(0, max).toDouble();
    return Column(
      children: [
        Slider(
          value: value,
          min: 0,
          max: max,
          onChanged: (v) => _vc.seekTo(Duration(milliseconds: v.toInt())),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(formatDuration(pos),
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
            Text(formatDuration(dur),
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ],
        ),
      ],
    );
  }
}
