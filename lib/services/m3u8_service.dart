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
  final String? keyUri; // AES-128 但本机缺密钥文件时，记录密钥 URI 供用户手动补齐
  final int totalBytes;

  const M3u8Info({
    required this.path,
    required this.name,
    required this.isMaster,
    required this.segments,
    required this.method,
    required this.unreadable,
    this.keyUri,
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
///    * 密钥文件名/扩展名变体自动匹配：列表里写 `mysecret`，本机是
///      `mysecret.key` / `mysecret.bin` / `mysecret`（无后缀）都能定位
///    * **本地密钥自动搜索**：同目录找不到时，自动在父级、同级（兄弟）目录查找；
///      若仍找不到且在 `scanPlaylists` 提供的根目录内，再做有界递归（深度/文件数上限），
///      自动定位下载器放在 `Downloader/key.key` 或 `Downloader/keys/*` 的密钥
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
        // 把用户选定的根目录作为密钥有界递归搜索根（见 _resolveKey ③）
        infos.add(parse(path, keySearchRoots: roots));
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
  /// [keySearchRoots] 一般为 `scanPlaylists` 传入的用户选定根目录：在密钥
  /// 不在本目录时，于这些根内做**有界**递归搜索（深度/文件数上限）。
  /// 为空时只做「同目录 + 父级/同级」就近搜索（用于全盘扫描，避免整机递归）。
  static M3u8Info parse(String path, {List<String>? keySearchRoots}) {
    final baseDir = p.dirname(path);
    final lines = const LineSplitter().convert(File(path).readAsStringSync());
    final segments = <M3u8Segment>[];

    bool isMaster = false;
    String method = 'NONE';
    bool unreadable = false;
    String? unresolvedKeyUri;

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
          final localKey = _resolveKey(baseDir, uri, searchRoots: keySearchRoots);
          if (localKey == null) {
            method = '$m（本机无密钥文件）';
            unreadable = true;
            unresolvedKeyUri = uri; // 记录地址，供 UI 展示，用户可手动下载补齐
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

    // 第二阶段兜底：分片被下载器重命名成无扩展名哈希名时，按修改时间映射
    _fallbackMapByMtime(baseDir, segments);

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
      keyUri: unresolvedKeyUri,
      totalBytes: bytes,
    );
  }

  /// 把 URI 解析成本机已存在的文件路径（多种常见缓存布局都尝试）。
  ///
  /// 兼容：
  ///  - 相对路径 / 绝对路径 / 仅基名
  ///  - `%` 编码路径（空格 / 中文 / 完整网址被编码）
  ///  - **扩展名变体**：不少下载器把分片存成无扩展名的哈希文件名
  ///    （如 `e04d87b5...`），而播放列表里写的是 `e04d87b5....ts` 或完整网址；
  ///    反之亦然。此处对「带 / 不带 `.ts`」两种形态互试。
  static String? _resolveLocal(String baseDir, String uri) {
    final u = uri.split('?').first.split('#').first;

    // 生成同一文件的多种可能命名（去重保序：先精确后变体）
    final names = <String>{};
    void addName(String n) {
      if (n.isEmpty) return;
      names.add(n);
      final dot = n.lastIndexOf('.');
      if (dot > 0) {
        names.add(n.substring(0, dot)); // 去扩展名
        names.add('${n.substring(0, dot)}.ts'); // 换成 .ts
      } else {
        names.add('$n.ts'); // 补 .ts
      }
    }

    addName(u);
    addName(p.basename(u));
    if (u.contains('%')) {
      final decoded = _tryDecode(u);
      if (decoded != u) {
        addName(decoded);
        addName(p.basename(decoded));
      }
    }

    for (final n in names) {
      for (final c in <String>[n, p.join(baseDir, n)]) {
        try {
          if (File(c).existsSync()) return c;
        } catch (_) {}
      }
    }
    return null;
  }

  /// 解析本地密钥文件。查找顺序（**纯本地，绝不联网**）：
  ///  1. 同目录：分片同款解析（相对/绝对/基名/ % 编码 / .ts 变体）+ 密钥扩展名变体；
  ///  2. 父级 / 同级目录：沿祖先链向上找，并检查每个祖先的直接子目录（兄弟目录）；
  ///  3. 指定扫描根（可选）：在用户选定的扫描根内做**有界**递归搜索（深度/文件数上限）。
  ///
  /// 典型场景：下载器把密钥存在 `Downloader/key.key` 或 `Downloader/keys/xxx.key`，
  /// 而 `local.m3u8` 在 `Downloader/<哈希>/` 下。只要密钥文件名与播放列表里写的
  /// 一致（本机为 `xxx.key` / `xxx.bin` / `xxx`），即可自动定位，无需手动复制下载。
  ///
  /// [searchRoots] 一般为 `scanPlaylists` 传入的用户选定根目录；为空时只做 1、2 两步
  /// （用于全盘扫描时避免整机递归）。
  static String? _resolveKey(String baseDir, String uri,
      {List<String>? searchRoots}) {
    // ① 同目录（分片同款 + 密钥扩展名变体），命中即返回
    final bySegment = _resolveLocal(baseDir, uri);
    if (bySegment != null) return bySegment;

    final u = uri.split('?').first.split('#').first;
    final base = p.basename(u);
    if (base.isEmpty) return null;
    final names = _keyCandidateNames(base);

    // ② 父级 / 同级：祖先链 + 每个祖先的直接子目录（有界、纯本地）
    for (final dir in _nearbyDirs(baseDir)) {
      for (final n in names) {
        final c = p.join(dir, n);
        try {
          if (File(c).existsSync()) return c;
        } catch (_) {}
      }
    }

    // ③ 指定扫描根内的有界递归（depth/count 双上限，防止整机卡死）
    if (searchRoots != null) {
      for (final root in searchRoots) {
        final hit = _findKeyByName(root, names);
        if (hit != null) return hit;
      }
    }
    return null;
  }

  /// 密钥可能的本机文件名（去重保序）。覆盖：
  ///  原样 / .key / .bin / 去后缀 / 同目录通用 key.key / key.bin。
  static List<String> _keyCandidateNames(String base) {
    final names = <String>{};
    void add(String n) {
      if (n.isNotEmpty) names.add(n);
    }
    final dot = base.lastIndexOf('.');
    final stem = dot > 0 ? base.substring(0, dot) : base;
    add(base); // 原样
    add('$stem.key'); // 常见的 .key 后缀
    add('$stem.bin'); // 常见的 .bin 后缀
    add(stem); // 去掉任何后缀（无扩展名密钥）
    add('key.key'); // 同目录下通用命名
    add('key.bin');
    return names.toList();
  }

  /// 返回 baseDir 周围的「近邻目录」：祖先链（父级）以及每个祖先的直接子目录（同级）。
  /// 上限 8 层，避免极端深层目录造成死循环。
  static List<String> _nearbyDirs(String baseDir) {
    final dirs = <String>[];
    Directory? d = Directory(baseDir).parent;
    var levels = 0;
    while (d != null && levels < 8) {
      dirs.add(d.path);
      try {
        for (final e in d.listSync(followLinks: false)) {
          if (e is Directory) dirs.add(e.path); // 同级 / 兄弟目录
        }
      } catch (_) {}
      final parent = d.parent;
      if (parent.path == d.path) break; // 已到文件系统根
      d = parent;
      levels++;
    }
    return dirs;
  }

  /// 在 [root] 内有界递归查找文件名命中 [names] 之一的文件。
  /// 深度上限 [maxDepth]、累计文件数上限 [maxFiles]，超限即放弃（避免整机扫描卡死）。
  static String? _findKeyByName(String root, List<String> names,
      {int maxDepth = 4, int maxFiles = 2000}) {
    final rootDir = Directory(root);
    if (!rootDir.existsSync()) return null;
    var scanned = 0;
    String? walk(Directory dir, int depth) {
      if (depth > maxDepth) return null;
      List<FileSystemEntity> entries;
      try {
        entries = dir.listSync(followLinks: false);
      } catch (_) {
        return null;
      }
      for (final e in entries) {
        if (scanned > maxFiles) return null;
        if (e is Directory) {
          final hit = walk(e, depth + 1);
          if (hit != null) return hit;
        } else if (e is File) {
          scanned++;
          if (names.contains(p.basename(e.path))) return e.path;
        }
      }
      return null;
    }
    return walk(rootDir, 0);
  }

  static String _tryDecode(String s) {
    try {
      return Uri.decodeComponent(s);
    } catch (_) {
      return s;
    }
  }

  /// 兜底映射时要排除的「非分片文件」扩展名（列表 / 密钥 / 元数据 / 图片字幕等）。
  static const Set<String> _nonSegmentExts = <String>{
    'm3u8', 'm3u', 'key', 'json', 'txt', 'html', 'xml', 'ini', 'log', 'url',
    'jpg', 'jpeg', 'png', 'webp', 'gif', 'srt', 'ass', 'ssa', 'vtt', 'nfo',
  };

  /// 第二阶段兜底：下载器缓存目录常把分片**重命名成无扩展名的哈希文件**
  /// （如 `Downloader/<哈希>/e04d87b5...` + `local.m3u8`），名字与播放列表里的
  /// URI 完全对不上。此类下载器按播放顺序依次下载落盘，因此
  /// **文件修改时间顺序 == 播放顺序**。
  ///
  /// 规则（宁缺勿错，绝不联网）：
  ///  - 仅当「目录内剩余候选文件数 == 未解析分片数」时才映射；
  ///  - 候选文件排除列表 / 密钥 / 图片 / 字幕等（见 [_nonSegmentExts]），
  ///    以及已按名称解析成功的文件；
  ///  - 候选按修改时间升序（平局按文件名）与未解析分片按播放顺序一一对应。
  static void _fallbackMapByMtime(String baseDir, List<M3u8Segment> segments) {
    final unresolved = <int>[];
    final used = <String>{};
    for (var i = 0; i < segments.length; i++) {
      final s = segments[i];
      if (s.missing) {
        unresolved.add(i);
      } else {
        used.add(s.localPath);
      }
    }
    if (unresolved.isEmpty || baseDir.isEmpty) return;

    List<FileSystemEntity> entries;
    try {
      entries = Directory(baseDir).listSync(followLinks: false);
    } catch (_) {
      return;
    }
    final candidates = <File>[];
    for (final e in entries) {
      if (e is! File) continue;
      final ext = p.extension(e.path).replaceFirst('.', '').toLowerCase();
      if (_nonSegmentExts.contains(ext)) continue;
      if (used.contains(e.path)) continue;
      candidates.add(e);
    }
    // 数量对不上（有缺失 / 有多余文件）时不能乱猜，保持「缺失」原状
    if (candidates.length != unresolved.length) return;

    int mtime(File f) {
      try {
        return f.lastModifiedSync().millisecondsSinceEpoch;
      } catch (_) {
        return 0;
      }
    }

    candidates.sort((a, b) {
      final c = mtime(a).compareTo(mtime(b));
      if (c != 0) return c;
      return a.path.toLowerCase().compareTo(b.path.toLowerCase());
    });
    for (var k = 0; k < unresolved.length; k++) {
      final idx = unresolved[k];
      segments[idx] = M3u8Segment(
        localPath: candidates[k].path,
        missing: false,
        keyPath: segments[idx].keyPath,
        keyIvHex: segments[idx].keyIvHex,
        sequence: segments[idx].sequence,
      );
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
