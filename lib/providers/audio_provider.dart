import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path/path.dart' as p;
import '../models/album.dart';
import '../services/database_service.dart';

/// 音频播放状态管理（全局单例），支持：
///  - 后台音频播放
///  - 播放倍速（0.5x ~ 2.0x）
///  - 上一集 / 下一集切换
///  - 音量调节
///  - 每集播放进度记忆 + 上次播放剧集记忆
///
/// 纯本地：所有状态只存在内存与本地数据库，无任何网络请求。
class AudioProvider extends ChangeNotifier {
  final AudioPlayer _player = AudioPlayer();
  final DatabaseService _db = DatabaseService.instance;

  Album? _album;
  int _index = 0;
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  double _speed = 1.0;
  double _volume = 1.0;

  StreamSubscription? _posSub;
  StreamSubscription? _durSub;
  StreamSubscription? _stateSub;
  StreamSubscription? _completeSub;
  int _lastSaveMs = 0;

  AudioProvider() {
    _init();
  }

  void _init() {
    _player.setReleaseMode(ReleaseMode.stop);
    _posSub = _player.onPositionChanged.listen((d) {
      _position = d;
      _throttledSave();
      notifyListeners();
    });
    _durSub = _player.onDurationChanged.listen((d) {
      _duration = d;
      notifyListeners();
    });
    _stateSub = _player.onPlayerStateChanged.listen((s) {
      _isPlaying = s == PlayerState.playing;
      notifyListeners();
    });
    _completeSub = _player.onPlayerComplete.listen((_) => _onComplete());
  }

  // ---------------- getters ----------------
  Album? get album => _album;
  int get index => _index;
  bool get isPlaying => _isPlaying;
  Duration get position => _position;
  Duration get duration => _duration;
  double get speed => _speed;
  double get volume => _volume;

  String? get currentPath =>
      (_album != null && _album!.episodePaths.isNotEmpty)
          ? _album!.episodePaths[_index]
          : null;

  String get currentTitle =>
      currentPath != null ? p.basename(currentPath!) : '';

  bool get hasCurrent => currentPath != null;

  // ---------------- 控制 ----------------
  /// 载入整张专辑并从指定集开始播放（自动续播上次进度）。
  Future<void> loadAlbum(Album album, {int index = 0}) async {
    _album = album;
    _index = index.clamp(0, album.episodePaths.length - 1);
    await _playCurrent();
    await _db.saveLastAudio(album.id, _index);
  }

  Future<void> _playCurrent() async {
    final path = currentPath;
    if (path == null) return;
    await _player.stop();
    final saved = await _db.getAudioPosition(path);
    await _player.play(
      DeviceFileSource(path),
      volume: _volume,
      position: saved > 0 ? Duration(milliseconds: saved) : null,
    );
    await _player.setPlaybackRate(_speed);
    _isPlaying = true;
    _position = Duration(milliseconds: saved);
    notifyListeners();
  }

  Future<void> play() async {
    if (currentPath == null) return;
    await _player.resume();
    _isPlaying = true;
    notifyListeners();
  }

  Future<void> pause() async {
    await _player.pause();
    await _savePosition();
    _isPlaying = false;
    notifyListeners();
  }

  Future<void> toggle() async {
    if (_isPlaying) {
      await pause();
    } else {
      await play();
    }
  }

  Future<void> seek(Duration d) async {
    await _player.seek(d);
    _position = d;
    notifyListeners();
  }

  Future<void> next() async {
    if (_album == null) return;
    if (_index < _album!.episodePaths.length - 1) {
      _index++;
      await _playCurrent();
      await _db.saveLastAudio(_album!.id, _index);
    } else {
      await _player.stop();
      _isPlaying = false;
      notifyListeners();
    }
  }

  Future<void> previous() async {
    if (_album == null) return;
    // 已播放超过 3 秒则回到本集开头，否则切到上一集
    if (_position.inSeconds > 3) {
      await seek(Duration.zero);
      return;
    }
    if (_index > 0) {
      _index--;
      await _playCurrent();
      await _db.saveLastAudio(_album!.id, _index);
    } else {
      await seek(Duration.zero);
    }
  }

  Future<void> setSpeed(double s) async {
    _speed = s;
    await _player.setPlaybackRate(s);
    notifyListeners();
  }

  Future<void> setVolume(double v) async {
    _volume = v;
    await _player.setVolume(v);
    notifyListeners();
  }

  void _onComplete() {
    _savePosition();
    if (_album != null && _index < _album!.episodePaths.length - 1) {
      next();
    } else {
      _isPlaying = false;
      notifyListeners();
    }
  }

  /// 节流保存进度（每 3 秒最多写库一次，避免频繁 IO）。
  void _throttledSave() {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastSaveMs > 3000) {
      _lastSaveMs = now;
      _savePosition();
    }
  }

  Future<void> _savePosition() async {
    final path = currentPath;
    if (path != null) {
      await _db.saveAudioPosition(path, _position.inMilliseconds);
    }
  }

  /// 离开页面 / 切后台时调用，确保进度落盘。
  Future<void> persist() async => _savePosition();

  @override
  void dispose() {
    _posSub?.cancel();
    _durSub?.cancel();
    _stateSub?.cancel();
    _completeSub?.cancel();
    _player.dispose();
    super.dispose();
  }
}
