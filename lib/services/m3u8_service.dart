import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 一个 TS 分片，连同该分片生效的密钥信息。
class M3u8Segment {
  final String localPath; // 解析出的本机路径
  final bool missing; // true = 本机找不到该分片
  final String? keyPath; // 该分片对应的本地密钥文件
  final String? keyIvHex; // 显式 IV（原始值，可能带 0x 前缀）
  final int sequence; // 分片序号，用于推导隐式 IV

  const M3u8Segment({
    required this.localPath,
    required this.missing,
    this.keyPath,
    this.keyIvHex,
    required this.sequence,
  });
}

/// 解析后的播放列表信息。
class M3u8Info {
  final String path;
  final String name;
  final bool isMaster; // 含 EXT-X-STREAM-INF 的多码率主列表
  final List<M3u8Segment> segments;
  final String method; // NONE / AES-128 / 其它加密标记
  final bool unreadable; // 需要 DRM 或无法纯本地处理
  final int totalBytes;

  const M3u8Info({
    required this.path,
    required this.name,
    required this.isMaster,
    required this.segments,
    required this.method,
    required this.unreadable,
    required this.totalBytes,
  });

  /// 不含扩展名的标题（用于「按原文件名」输出）
  String get baseName =>
      name.contains('.') ? name.substring(0, name.lastIndexOf('.')) : name;

  int get missingCount => segments.where((s) => s.missing).length;
  bool get encrypted => method != 'NONE' && !isMaster && segments.isNotEmpty;
}

/// 单次合并的结果。
class MergeOutcome {
  final String path;
  final int sizeBytes;
  final int merged;
  final int missing;
  final String? error;

  const MergeOutcome({
    required this.path,
    required this.sizeBytes,
    required this.merged,
    required this.missing,
    this.error,
  });

  bool get ok => error == null && merged > 0;
}

/// M3U8 / TS 合并服务（**纯本地**：只读本机已有文件，不做任何网络请求）。
///
/// 支持范围：
///  - 明文分片（无 EXT-X-KEY）
///  - AES-128（含 192/256，按密钥长度自动适配）：**密钥文件必须已在本机**
///    * 支持显式 IV，也支持按分片序号推导隐式 IV
///    * KEYFORMAT=identity 直接读取本地密钥文件
///
/// 不支持（属于内容保护破解，本项目不实现）：
///  - SAMPLE-AES、Widevine / FairPlay / PlayReady 等 DRM
///  - 联网下载分片或密钥；远程分片若本机没有则计为缺失
class M3u8Service {
  /// 递归查找 .m3u8 播放列表。
  static Future<List<M3u8Info>> scanPlaylists(List<String> roots,
      {int maxDepth = 6}) async {
    final found = <String>{};
    for (final root in roots) {
      if (root.isEmpty) continue;
      found.addAll(_findPlaylists(root, maxDepth: maxDepth));
    }
    final infos = <M3u8Info>[];
    for (final path in found) {
      try {
        infos.add(parse(path));
      } catch (_) {
        // 单个文件解析失败不影响整体
      }
    }
    // 主列表（多码率）排在后面，优先展示有分片的
    infos.sort((a, b) {
      if (a.isMaster != b.isMaster) return a.isMaster ? 1 : -1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return infos;
  }

  static List<String> _findPlaylists(String root, {required int maxDepth}) {
    final result = <String>[];
    void walk(Directory dir, int depth) {
      if (depth > maxDepth) return;
      List<FileSystemEntity> entries;
      try {
        entries = dir.listSync(followLinks: false);
      } catch (_) {
        return; // 无权限目录直接跳过
      }
      for (final e in entries) {
        if (e is Directory) {
          walk(e, depth + 1);
        } else if (e is File && e.path.toLowerCase().endsWith('.m3u8')) {
          result.add(e.path);
        }
      }
    }

    final d = Directory(root);
    if (d.existsSync()) walk(d, 0);
    return result;
  }

  /// 解析单个播放列表。
  static M3u8Info parse(String path) {
    final baseDir = p.dirname(path);
    final lines = const LineSplitter().convert(File(path).readAsStringSync());
    final segments = <M3u8Segment>[];

    bool isMaster = false;
    String method = 'NONE';
    bool unreadable = false;

    String? curKeyPath;
    String? curIvHex;

    int seq = 0;

    for (final raw in lines) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      if (line.startsWith('#')) {
        if (line.startsWith('#EXT-X-STREAM-INF')) isMaster = true;
        // 关键：HLS 规定隐式 IV 由「媒体序列号」推导，而非从 0 计数。
        // 直播/续传缓存的 MEDIA-SEQUENCE 通常不是 0，漏解析会导致解密全错。
        if (line.startsWith('#EXT-X-MEDIA-SEQUENCE')) {
          final n = int.tryParse(line.substring(line.indexOf(':') + 1).trim());
          if (n != null) seq = n;
        }
        if (line.startsWith('#EXT-X-KEY')) {
          final attrs = _parseAttrs(line);
          final m = (attrs['METHOD'] ?? 'NONE').toUpperCase();
          if (m == 'NONE') {
            method = 'NONE';
            curKeyPath = null;
            curIvHex = null;
            continue;
          }
          if (m != 'AES-128') {
            // SAMPLE-AES 及其它 DRM 体系：不做处理
            method = m;
            unreadable = true;
            curKeyPath = null;
            curIvHex = null;
            continue;
          }
          final keyFormat = (attrs['KEYFORMAT'] ?? 'identity').toLowerCase();
          final uri = attrs['URI'];
          if (uri == null || uri.isEmpty) {
            unreadable = true;
            curKeyPath = null;
            continue;
          }
          if (keyFormat != 'identity') {
            // 非 identity（如 DRM 证书 URI）无法纯本地使用
            method = '$m/$keyFormat';
            unreadable = true;
            curKeyPath = null;
            continue;
          }
          // 密钥必须已在本机：远程地址 / 本地缺失一律判为不可用，绝不联网拉取。
          final localKey = _resolveLocal(baseDir, uri);
          if (localKey == null) {
            method = '$m（本机无密钥文件）';
            unreadable = true;
            curKeyPath = null;
            curIvHex = null;
            continue;
          }
          method = 'AES-128';
          curIvHex = attrs['IV'];
          curKeyPath = localKey;
        }
        continue;
      }

      final local = _resolveLocal(baseDir, line);
      segments.add(M3u8Segment(
        localPath: local ?? line,
        missing: local == null,
        keyPath: curKeyPath,
        keyIvHex: curIvHex,
        sequence: seq,
      ));
      seq++;
    }

    int bytes = 0;
    for (final s in segments) {
      if (s.missing) continue;
      try {
        bytes += File(s.localPath).lengthSync();
      } catch (_) {}
    }

    return M3u8Info(
      path: path,
      name: p.basename(path),
      isMaster: isMaster,
      segments: segments,
      method: method,
      unreadable: unreadable,
      totalBytes: bytes,
    );
  }

  /// 把 URI 解析成本机已存在的文件路径（多种常见缓存布局都尝试）。
  static String? _resolveLocal(String baseDir, String uri) {
    final u = uri.split('?').first.split('#').first;
    final candidates = <String>[
      u,
      p.join(baseDir, u),
      p.join(baseDir, p.basename(u)),
    ];
    // 兼容 % 编码的路径（部分下载器会把空格 / 中文转成 %xx）
    if (u.contains('%')) {
      final decoded = _tryDecode(u);
      if (decoded != u) {
        candidates.addAll([decoded, p.join(baseDir, decoded)]);
      }
    }
    for (final c in candidates) {
      try {
        if (c.isNotEmpty && File(c).existsSync()) return c;
      } catch (_) {}
    }
    return null;
  }

  static String _tryDecode(String s) {
    try {
      return Uri.decodeComponent(s);
    } catch (_) {
      return s;
    }
  }

  /// 读取本地密钥文件，兼容两种常见存储形式：
  ///  1. **二进制密钥**（HLS 标准做法，长度 16 / 24 / 32）
  ///  2. **十六进制文本密钥**（不少下载器会把密钥写成 32 / 48 / 64 位 hex 字符串）
  static Uint8List _readKey(String keyPath) {
    final bytes = File(keyPath).readAsBytesSync();
    // ① 标准二进制密钥，直接使用
    if (bytes.length == 16 || bytes.length == 24 || bytes.length == 32) {
      return Uint8List.fromList(bytes);
    }
    // ② 尝试按 hex 文本解析
    final text = utf8.decode(bytes, allowMalformed: true).trim();
    if ((text.length == 32 || text.length == 48 || text.length == 64) &&
        RegExp(r'^[0-9a-fA-F]+$').hasMatch(text)) {
      final out = <int>[];
      for (var i = 0; i + 1 < text.length; i += 2) {
        out.add(int.parse(text.substring(i, i + 2), radix: 16));
      }
      return Uint8List.fromList(out);
    }
    // ③ 原始字节兜底（长度非法时交给 AES 构造抛错，由上层捕获为失败原因）
    return Uint8List.fromList(bytes);
  }

  /// 解析 EXT-X-KEY 等标签的属性键值对。
  static Map<String, String> _parseAttrs(String line) {
    final idx = line.indexOf(':');
    final body = idx < 0 ? '' : line.substring(idx + 1);
    final map = <String, String>{};
    final re = RegExp(r'([A-Z0-9\-]+)=("([^"]*)"|[^,]*)');
    for (final m in re.allMatches(body)) {
      final k = m.group(1);
      final v = m.group(3) ?? m.group(2) ?? '';
      if (k != null) map[k] = v;
    }
    return map;
  }

  /// 默认输出目录（优先外部 Movies，回退应用文档目录）。
  static Future<String> defaultOutputDir() async {
    try {
      final dirs = await getExternalStorageDirectories(type: StorageDirectory.movies);
      if (dirs != null && dirs.isNotEmpty) return dirs.first.path;
    } catch (_) {}
    try {
      final d = await getApplicationDocumentsDirectory();
      return p.join(d.path, 'Movies');
    } catch (_) {}
    return '';
  }

  /// 合并单个播放列表。
  static Future<MergeOutcome> mergeOne(
    M3u8Info info, {
    required String outputDir,
    required bool useOriginalName,
  }) async {
    // 纵深防御：加密方式不受支持（DRM / SAMPLE-AES / 缺密钥文件）时直接失败，
    // 绝不退化成「当明文拼接」——那样只会产出打不开的损坏文件。
    if (info.unreadable) {
      return MergeOutcome(
        path: '',
        sizeBytes: 0,
        merged: 0,
        missing: info.segments.length,
        error: '加密方式不支持：${info.method}',
      );
    }

    final dir = Directory(outputDir);
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final base = useOriginalName ? info.baseName : _timeName();
    final outPath = p.join(outputDir, '$base.ts');
    final out = File(outPath);
    if (out.existsSync()) out.deleteSync();

    final raf = out.openSync(mode: FileMode.append);
    final cache = <String, enc.Encrypter>{};
    int merged = 0;
    int missing = 0;
    String? error;

    try {
      for (final seg in info.segments) {
        if (seg.missing) {
          missing++;
          continue;
        }
        Uint8List bytes;
        try {
          bytes = await File(seg.localPath).readAsBytes();
        } catch (_) {
          missing++;
          continue;
        }
        final keyPath = seg.keyPath;
        if (keyPath != null && keyPath.isNotEmpty) {
          final crypter = cache.putIfAbsent(
            keyPath,
            () => enc.Encrypter(
              enc.AES(enc.Key(_readKey(keyPath)), mode: enc.AESMode.cbc),
            ),
          );
          bytes = Uint8List.fromList(
            crypter.decryptBytes(enc.Encrypted(bytes), iv: enc.IV(_ivFor(seg))),
          );
        }
        raf.writeFromSync(bytes);
        merged++;
      }
    } catch (e) {
      error = e.toString();
    } finally {
      raf.closeSync();
    }

    return MergeOutcome(
      path: outPath,
      sizeBytes: out.existsSync() ? out.lengthSync() : 0,
      merged: merged,
      missing: missing,
      error: error,
    );
  }

  /// 批量合并。
  static Future<List<MergeOutcome>> mergeMany(
    List<M3u8Info> list, {
    required String outputDir,
    required bool useOriginalName,
    void Function(int done, int total)? onProgress,
  }) async {
    final results = <MergeOutcome>[];
    for (var i = 0; i < list.length; i++) {
      results.add(await mergeOne(
        list[i],
        outputDir: outputDir,
        useOriginalName: useOriginalName,
      ));
      onProgress?.call(i + 1, list.length);
    }
    return results;
  }

  /// 计算分片的 IV：显式 IV 优先，否则按序号推导（HLS 默认规则）。
  static Uint8List _ivFor(M3u8Segment seg) {
    final hex = seg.keyIvHex;
    if (hex != null && hex.isNotEmpty) {
      var h = hex.toLowerCase().startsWith('0x') ? hex.substring(2) : hex;
      if (h.length % 2 == 1) h = '0$h';
      final bytes = <int>[];
      for (var i = 0; i + 1 < h.length; i += 2) {
        final v = int.tryParse(h.substring(i, i + 2), radix: 16);
        if (v != null) bytes.add(v);
      }
      final out = Uint8List(16);
      for (var i = 0; i < 16 && i < bytes.length; i++) {
        out[i] = bytes[i];
      }
      return out;
    }
    final out = Uint8List(16);
    var n = seg.sequence;
    for (var i = 15; i >= 0; i--) {
      out[i] = n & 0xff;
      n >>= 8;
    }
    return out;
  }

  /// 按时间自动命名：merged_20261004_060321
  static String _timeName() {
    final d = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return 'merged_${d.year}${two(d.month)}${two(d.day)}_'
        '${two(d.hour)}${two(d.minute)}${two(d.second)}';
  }
}
