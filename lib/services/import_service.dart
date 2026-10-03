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

/// 本地导入服务：探测抖音/快手等平台保存到本机的目录，便于批量导入到视频列表。
///
/// 说明（重要）：
/// - **完全离线**，只读取本机已存在的文件，不做任何网络请求、不解析任何线上链接。
/// - 视频来源是「用户自己在抖音/快手 App 里点『保存到相册/本地』」保存下来的本机文件，
///   不属于抓取行为，符合平台规则与版权要求。
class ImportService {
  /// 安卓常见外置存储根
  static const List<String> _storageRoots = <String>[
    '/storage/emulated/0',
    '/sdcard',
  ];

  /// 常见「平台保存目录」候选：展示名 -> 可能的相对路径（多备选）
  static const Map<String, List<String>> _namedCandidates = <String, List<String>>{
    '抖音': <String>[
      'DCIM/抖音',
      'DCIM/Douyin',
      'DCIM/douyin',
      'DCIM/aweme',
      'Pictures/抖音',
      'Movies/抖音',
      'Download/抖音',
      'Download/Douyin',
    ],
    '快手': <String>[
      'DCIM/快手',
      'DCIM/Kuaishou',
      'DCIM/kuaishou',
      'DCIM/gifshow',
      'Pictures/快手',
      'Movies/快手',
      'Download/快手',
      'Download/Kuaishou',
    ],
    '相册 / 相机': <String>['DCIM/Camera', 'DCIM'],
    '影片': <String>['Movies'],
    '下载': <String>['Download'],
    '图片': <String>['Pictures'],
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
