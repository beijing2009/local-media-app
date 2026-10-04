import 'dart:io';
import 'package:path/path.dart' as p;
import '../models/media_file.dart';
import 'file_scanner.dart';

/// 一个候选导入来源（本机目录）。
class ImportCandidate {
  final String path;
  final String label;
  final int videoCount;

  const ImportCandidate({
    required this.path,
    required this.label,
    required this.videoCount,
  });
}

/// 本地导入服务：探测本机常见的媒体存放目录，便于批量导入到视频列表。
///
/// 说明（重要）：
/// - **完全离线**，只读取本机已存在的文件，不做任何网络请求、不解析任何线上内容。
/// - 只按「通用目录名」定位（相册 / 影片 / 下载 / 图片等），
///   不针对任何第三方平台做适配或抓取，仅导入用户本机已有的本地文件。
class ImportService {
  /// 安卓常见外置存储根
  static const List<String> _storageRoots = <String>[
    '/storage/emulated/0',
    '/sdcard',
  ];

  /// 常见「本机媒体目录」候选：展示名 -> 可能的相对路径（多备选）。
  /// 只使用系统级通用目录名，不涉及任何第三方平台专有目录。
  static const Map<String, List<String>> _namedCandidates = <String, List<String>>{
    '相册 / 相机': <String>['DCIM/Camera', 'DCIM'],
    '影片': <String>['Movies', 'Movie'],
    '下载': <String>['Download', 'Downloads'],
    '图片': <String>['Pictures'],
    '音乐': <String>['Music'],
    '视频': <String>['Videos', 'Video'],
  };

  /// 探测本机中真实存在、且确实含视频的候选目录。
  static List<ImportCandidate> detectPlatformDirs() {
    final List<ImportCandidate> out = <ImportCandidate>[];
    final Set<String> seen = <String>{};
    for (final root in _storageRoots) {
      if (!Directory(root).existsSync()) continue;
      for (final entry in _namedCandidates.entries) {
        for (final sub in entry.value) {
          final String full = p.join(root, sub);
          if (!Directory(full).existsSync()) continue;
          if (!seen.add(full)) continue;
          final int count = _safeCountVideos(full);
          if (count > 0) {
            out.add(ImportCandidate(
              path: full,
              label: entry.key,
              videoCount: count,
            ));
          }
        }
      }
    }
    return out;
  }

  /// 安全统计目录内视频数量（失败按 0 处理，避免权限问题导致崩溃）。
  static int _safeCountVideos(String dir) {
    try {
      return FileScanner.scanRecursive(dir, maxDepth: 3)
          .where((m) => m.type == MediaType.video)
          .length;
    } catch (_) {
      return 0;
    }
  }

  /// 列出目录内的视频文件（默认最多向下 2 层），已去重并排序。
  static List<MediaFile> listVideos(String dirPath, {int maxDepth = 2}) {
    try {
      final videos = FileScanner.scanRecursive(dirPath, maxDepth: maxDepth)
          .where((m) => m.type == MediaType.video)
          .toList();
      return FileScanner.dedupeAndSort(videos);
    } catch (_) {
      return <MediaFile>[];
    }
  }
}
