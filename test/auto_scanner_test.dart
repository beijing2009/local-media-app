import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_media_app/models/media_file.dart';
import 'package:local_media_app/services/auto_scanner.dart';
import 'package:path/path.dart' as p;

late Directory _root;

void main() {
  setUp(() {
    _root = Directory.systemTemp.createTempSync('autoscan_');
  });
  tearDown(() {
    if (_root.existsSync()) _root.deleteSync(recursive: true);
  });

  test('媒体扫描：仅匹配视频/音频，跳过系统目录，过滤无关扩展名', () async {
    File(p.join(_root.path, 'a.mp4')).writeAsBytesSync([1, 2, 3]);
    File(p.join(_root.path, 'b.mp3')).writeAsBytesSync([1]);
    File(p.join(_root.path, 'c.ts')).writeAsBytesSync([1]); // ts 也算视频
    File(p.join(_root.path, 'note.txt')).writeAsBytesSync([1]); // 忽略
    File(p.join(_root.path, 'x.mkv')).writeAsBytesSync([1]); // 不支持的视频格式，忽略

    // 应被跳过的系统目录
    final skipDir = Directory(p.join(_root.path, '.thumbnails'))..createSync();
    File(p.join(skipDir.path, 'junk.mp4')).writeAsBytesSync([1]);

    // 子目录里的音频
    final sub = Directory(p.join(_root.path, 'sub'))..createSync();
    File(p.join(sub.path, 'd.m4a')).writeAsBytesSync([1]);

    int? lastFound;
    int? lastDirs;
    final media = await AutoScanner.scanMedia(
      roots: [_root.path],
      maxDepth: 5,
      onProgress: (d, f) {
        lastDirs = d;
        lastFound = f;
      },
    );

    final names = media.map((m) => m.name).toList()..sort();
    expect(names, ['a.mp4', 'b.mp3', 'c.ts', 'd.m4a']);
    expect(media.where((m) => m.type == MediaType.video).length, 2);
    expect(media.where((m) => m.type == MediaType.audio).length, 2);
  });

  test('进度回调：目录足够多（>500）时会触发 onProgress', () async {
    for (var i = 0; i < 600; i++) {
      final d = Directory(p.join(_root.path, 'd$i'))..createSync();
      File(p.join(d.path, 'f.mp4')).writeAsBytesSync([1]);
    }
    var called = false;
    int? found;
    await AutoScanner.scanMedia(
      roots: [_root.path],
      maxDepth: 5,
      onProgress: (d, f) {
        called = true;
        found = f;
      },
    );
    expect(called, true);
    expect(found, greaterThan(0));
  });

  test('M3U8 扫描：找出 .m3u8，忽略其它扩展名与系统目录', () async {
    File(p.join(_root.path, 'play.m3u8')).writeAsBytesSync([1]);
    File(p.join(_root.path, 'other.txt')).writeAsBytesSync([1]);
    final sub = Directory(p.join(_root.path, 's'))..createSync();
    File(p.join(sub.path, 'x.m3u8')).writeAsBytesSync([1]);
    final skipDir = Directory(p.join(_root.path, 'node_modules'))..createSync();
    File(p.join(skipDir.path, 'z.m3u8')).writeAsBytesSync([1]);

    final paths = await AutoScanner.scanM3u8(roots: [_root.path], maxDepth: 5);
    expect(paths.length, 2);
    expect(paths.every((x) => x.endsWith('.m3u8')), true);
  });

  test('maxDepth 限制：超过深度的目录不会被扫描', () async {
    // root/a/b/c/d/e.mp4：深度 5 时 e.mp4 应被忽略，深度 6 应包含
    var dir = _root;
    for (var i = 0; i < 4; i++) {
      dir = Directory(p.join(dir.path, 'a$i'))..createSync();
    }
    File(p.join(dir.path, 'deep.mp4')).writeAsBytesSync([1]); // 距 root 深度 4

    final shallow = await AutoScanner.scanMedia(roots: [_root.path], maxDepth: 2);
    expect(shallow.any((m) => m.name == 'deep.mp4'), false);

    final deep = await AutoScanner.scanMedia(roots: [_root.path], maxDepth: 10);
    expect(deep.any((m) => m.name == 'deep.mp4'), true);
  });

  test('空/不存在的根：返回空列表且不抛异常', () async {
    final media = await AutoScanner.scanMedia(
      roots: ['/__definitely_not_exist_${DateTime.now().microsecondsSinceEpoch}'],
    );
    expect(media, isEmpty);
    final m3u8 = await AutoScanner.scanM3u8(
      roots: ['/__definitely_not_exist_${DateTime.now().microsecondsSinceEpoch}'],
    );
    expect(m3u8, isEmpty);
  });
}
