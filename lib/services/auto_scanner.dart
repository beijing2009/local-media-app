import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import '../models/media_file.dart';

/// 全盘 / 多根自动扫描（在独立 Isolate 中执行，避免阻塞 UI）。
///
/// 仅安卓需要：iOS 受系统沙盒隔离，无法遍历全盘，维持原「文件 App 选目录」导入方式。
/// 扫描过程零网络请求，只读本机已存在的文件。
class AutoScanner {
  /// 安卓外置存储根候选（二者往往指向同一处，任取其一即可）。
  static const List<String> androidStorageRoots = <String>[
    '/storage/emulated/0',
    '/sdcard',
  ];

  /// 是否安卓平台（iOS 不应展示全盘扫描入口）。
  static bool get isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// 明显无媒体且遍历成本极高的系统目录，扫描时跳过（不进入其子树）。
  static const Set<String> _skipDirs = <String>{
    'lost+found',
    '.thumbnails',
    'node_modules',
    'venv',
    '.git',
  };

  /// 全盘扫描媒体文件（视频 + 音频），返回按名称排序的去重列表。
  ///
  /// [roots] 为空时默认扫描安卓外置存储根；[onProgress] 在主线程回调（已扫描目录数 / 已发现文件数）。
  static Future<List<MediaFile>> scanMedia({
    List<String>? roots,
    int maxDepth = 12,
    void Function(int dirs, int found)? onProgress,
  }) async {
    final rs = roots ?? androidStorageRoots;
    final items = await _run('media', rs, maxDepth, onProgress);
    final out = items
        .map((m) => MediaFile(
              path: m['path'] as String,
              name: p.basename(m['path'] as String),
              type: (m['type'] as String) == 'audio'
                  ? MediaType.audio
                  : MediaType.video,
              sizeBytes: m['size'] as int?,
            ))
        .toList();
    out.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return out;
  }

  /// 全盘扫描 M3U8 播放列表，返回解析前的路径列表。
  static Future<List<String>> scanM3u8({
    List<String>? roots,
    int maxDepth = 12,
    void Function(int dirs, int found)? onProgress,
  }) async {
    final rs = roots ?? androidStorageRoots;
    final items = await _run('m3u8', rs, maxDepth, onProgress);
    return items.map((m) => m['path'] as String).toList();
  }

  /// 在子 Isolate 中递归扫描，通过 SendPort 回传进度与最终结果。
  static Future<List<Map<String, dynamic>>> _run(
    String mode,
    List<String> roots,
    int maxDepth,
    void Function(int dirs, int found)? onProgress,
  ) async {
    final port = ReceivePort();
    final completer = Completer<List<Map<String, dynamic>>>();
    late StreamSubscription sub;
    sub = port.listen((msg) {
      if (msg is! Map) return;
      if (msg['t'] == 'p') {
        onProgress?.call(msg['dirs'] as int, msg['found'] as int);
      } else if (msg['t'] == 'd') {
        completer.complete(
            List<Map<String, dynamic>>.from(msg['items'] as List));
        sub.cancel();
        port.close();
      }
    });
    try {
      await Isolate.spawn(
        _entry,
        <dynamic>[
          port.sendPort,
          roots,
          maxDepth,
          mode,
          _skipDirs.toList(),
        ],
      );
    } catch (e) {
      sub.cancel();
      port.close();
      rethrow;
    }
    return completer.future;
  }

  /// 子 Isolate 入口：纯 dart:io 递归遍历，绝不访问任何平台插件。
  static void _entry(List<dynamic> args) {
    final SendPort send = args[0] as SendPort;
    final roots = List<String>.from(args[1] as List);
    final maxDepth = args[2] as int;
    final mode = args[3] as String;
    final skip = Set<String>.from(args[4] as List);

    final items = <Map<String, dynamic>>[];
    var dirs = 0;
    var found = 0;
    var tick = 0;

    void walk(Directory dir, int depth) {
      if (depth > maxDepth) return;
      List<FileSystemEntity> entries;
      try {
        entries = dir.listSync(followLinks: false);
      } catch (_) {
        return; // 无权限 / 不可读目录直接跳过
      }
      dirs++;
      for (final e in entries) {
        final name = p.basename(e.path);
        if (e is Directory) {
          if (skip.contains(name)) continue;
          walk(e, depth + 1);
        } else if (e is File) {
          final ext = p.extension(e.path).toLowerCase().replaceAll('.', '');
          if (mode == 'm3u8') {
            if (ext == 'm3u8') {
              items.add({'path': e.path, 'type': 'm3u8'});
              found++;
            }
          } else if (SupportedFormats.isVideo(ext) ||
              SupportedFormats.isAudio(ext)) {
            var size = 0;
            try {
              size = e.lengthSync();
            } catch (_) {}
            items.add({
              'path': e.path,
              'type': SupportedFormats.isAudio(ext) ? 'audio' : 'video',
              'size': size,
            });
            found++;
          }
        }
      }
      // 周期性回传进度（每 500 个目录一次，避免消息过密）
      tick++;
      if (tick % 500 == 0) {
        send.send({'t': 'p', 'dirs': dirs, 'found': found});
      }
    }

    for (final r in roots) {
      final d = Directory(r);
      if (d.existsSync()) walk(d, 0);
    }
    send.send({'t': 'd', 'items': items});
  }
}
