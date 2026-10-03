import 'dart:io';
import 'package:path/path.dart' as p;
import '../models/media_file.dart';
import '../models/album.dart';

/// 本地媒体文件扫描：递归遍历目录，识别 mp4 / mp3 / m4a。
class FileScanner {
  /// 扫描单个目录（不递归），返回该目录下的媒体文件。
  static List<MediaFile> scanDirectory(String dirPath) {
    final dir = Directory(dirPath);
    if (!dir.existsSync()) return [];
    final List<MediaFile> result = [];
    try {
      for (final entity in dir.listSync(followLinks: false)) {
        if (entity is File) {
          final ext = p.extension(entity.path).toLowerCase().replaceAll('.', '');
          if (SupportedFormats.isVideo(ext) || SupportedFormats.isAudio(ext)) {
            result.add(_toMedia(entity, ext));
          }
        }
      }
    } catch (_) {
      // 权限不足或目录不可读，直接忽略
    }
    return result;
  }

  /// 递归扫描（限制最大深度，避免极端目录结构导致卡死）。
  static List<MediaFile> scanRecursive(String root, {int maxDepth = 6}) {
    final List<MediaFile> result = [];
    final dir = Directory(root);
    if (dir.existsSync()) _scanRecursive(dir, 0, maxDepth, result);
    return result;
  }

  static void _scanRecursive(
      Directory dir, int depth, int maxDepth, List<MediaFile> out) {
    if (depth > maxDepth) return;
    List<FileSystemEntity> entries;
    try {
      entries = dir.listSync(followLinks: false);
    } catch (_) {
      return;
    }
    for (final e in entries) {
      if (e is Directory) {
        _scanRecursive(e, depth + 1, maxDepth, out);
      } else if (e is File) {
        final ext = p.extension(e.path).toLowerCase().replaceAll('.', '');
        if (SupportedFormats.isVideo(ext) || SupportedFormats.isAudio(ext)) {
          out.add(_toMedia(e, ext));
        }
      }
    }
  }

  static MediaFile _toMedia(File file, String ext) {
    return MediaFile(
      path: file.path,
      name: p.basename(file.path),
      type: SupportedFormats.isVideo(ext) ? MediaType.video : MediaType.audio,
      sizeBytes: file.lengthSync(),
    );
  }

  /// 按文件名过滤（忽略大小写，支持部分匹配）。
  static List<MediaFile> filterByName(List<MediaFile> list, String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return list;
    return list.where((m) => m.name.toLowerCase().contains(q)).toList();
  }

  /// 按专辑名过滤（用于音频区搜索）。
  static List<Album> filterAlbumsByName(List<Album> list, String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return list;
    return list.where((a) => a.name.toLowerCase().contains(q)).toList();
  }

  /// 去重（按路径）并按名称排序。
  static List<MediaFile> dedupeAndSort(List<MediaFile> list) {
    final seen = <String>{};
    final out = list.where((m) => seen.add(m.path)).toList();
    out.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return out;
  }
}
