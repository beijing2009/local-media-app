import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter_test/flutter_test.dart';
import 'package:local_media_app/services/m3u8_service.dart';
import 'package:path/path.dart' as p;

/// 测试用临时根目录
late Directory _root;

void main() {
  setUp(() {
    _root = Directory.systemTemp.createTempSync('m3u8_test_');
  });

  tearDown(() {
    if (_root.existsSync()) _root.deleteSync(recursive: true);
  });

  test('① 明文分片：合并结果 == 各分片按序拼接', () async {
    final dir = Directory(p.join(_root.path, 'plain'))..createSync();
    final expected = <int>[];
    for (var i = 0; i < 3; i++) {
      final bytes = _randBytes(1000 + i * 137);
      File(p.join(dir.path, 'seg$i.ts')).writeAsBytesSync(bytes);
      expected.addAll(bytes);
    }
    final m3u = File(p.join(dir.path, 'index.m3u8'))
      ..writeAsStringSync('#EXTM3U\n'
          '#EXT-X-VERSION:3\n'
          '#EXTINF:10.0,\n'
          'seg0.ts\n'
          '#EXTINF:10.0,\n'
          'seg1.ts\n'
          '#EXTINF:10.0,\n'
          'seg2.ts\n');

    final info = M3u8Service.parse(m3u.path);
    expect(info.isMaster, false);
    expect(info.method, 'NONE');
    expect(info.segments.length, 3);

    final out = Directory(p.join(_root.path, 'out'))..createSync();
    final r = await M3u8Service.mergeOne(info,
        outputDir: out.path, useOriginalName: true);
    expect(r.error, isNull);
    expect(r.merged, 3);
    expect(File(p.join(out.path, "index.ts")).readAsBytesSync(), expected);
  });

  test('② AES-128 显式 IV：密文分片解密后 == 明文拼接', () async {
    final dir = Directory(p.join(_root.path, 'aes128iv'))..createSync();
    final key = enc.Key.fromUtf8('0123456789abcdef');
    final iv = enc.IV(Uint8List.fromList(
        List<int>.generate(16, (i) => 0xA0 + i))); // 显式 IV
    final crypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));

    File(p.join(dir.path, 'key.key')).writeAsBytesSync(key.bytes);

    final expected = <int>[];
    final ivHex = iv.base16.toLowerCase();
    for (var i = 0; i < 3; i++) {
      final plain = _randBytes(900 + i * 61);
      File(p.join(dir.path, 'seg$i.ts'))
          .writeAsBytesSync(crypter.encryptBytes(plain, iv: iv).bytes);
      expected.addAll(plain);
    }
    final m3u = File(p.join(dir.path, 'index.m3u8'))
      ..writeAsStringSync('#EXTM3U\n'
          '#EXT-X-KEY:METHOD=AES-128,URI="key.key",IV=0x$ivHex\n'
          'seg0.ts\n'
          'seg1.ts\n'
          'seg2.ts\n');

    final info = M3u8Service.parse(m3u.path);
    expect(info.encrypted, true);
    expect(info.unreadable, false);
    expect(info.method, 'AES-128');

    final out = Directory(p.join(_root.path, 'out'))..createSync();
    final r = await M3u8Service.mergeOne(info,
        outputDir: out.path, useOriginalName: true);
    expect(r.error, isNull);
    expect(File(p.join(out.path, "index.ts")).readAsBytesSync(), expected);
  });

  test('③ AES-128 隐式 IV + MEDIA-SEQUENCE 偏移（回归：曾按 0 起算导致解密全错）',
      () async {
    final dir = Directory(p.join(_root.path, 'aes128seq'))..createSync();
    const mediaSeq = 12345; // 真实缓存几乎不从 0 开始
    final key = enc.Key.fromUtf8('fedcba9876543210');
    final crypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
    File(p.join(dir.path, 'key.key')).writeAsBytesSync(key.bytes);

    // 服务端侧：按 HLS 规则用「媒体序列号」推导每个分片的 IV
    Uint8List deriveIv(int seq) {
      final out = Uint8List(16);
      var n = seq;
      for (var i = 15; i >= 0; i--) {
        out[i] = n & 0xff;
        n >>= 8;
      }
      return out;
    }

    final expected = <int>[];
    for (var i = 0; i < 4; i++) {
      final plain = _randBytes(188 * 30); // TS 包倍数
      final iv = enc.IV(deriveIv(mediaSeq + i));
      File(p.join(dir.path, 'seg$i.ts'))
          .writeAsBytesSync(crypter.encryptBytes(plain, iv: iv).bytes);
      expected.addAll(plain);
    }
    final m3u = File(p.join(dir.path, 'index.m3u8'))
      ..writeAsStringSync('#EXTM3U\n'
          '#EXT-X-MEDIA-SEQUENCE:$mediaSeq\n'
          '#EXT-X-KEY:METHOD=AES-128,URI="key.key"\n'
          'seg0.ts\n'
          'seg1.ts\n'
          'seg2.ts\n'
          'seg3.ts\n');

    final info = M3u8Service.parse(m3u.path);
    expect(info.segments.first.sequence, mediaSeq);

    final out = Directory(p.join(_root.path, 'out'))..createSync();
    final r = await M3u8Service.mergeOne(info,
        outputDir: out.path, useOriginalName: true);
    expect(r.error, isNull, reason: '隐式 IV 推导必须命中');
    expect(File(p.join(out.path, "index.ts")).readAsBytesSync(), expected);
  });

  test('④ 缺失分片被正确跳过并计数，不影响其余合并', () async {
    final dir = Directory(p.join(_root.path, 'missing'))..createSync();
    File(p.join(dir.path, 'seg0.ts')).writeAsBytesSync(_randBytes(500));
    // seg1 故意不存在
    File(p.join(dir.path, 'seg2.ts')).writeAsBytesSync(_randBytes(500));
    final m3u = File(p.join(dir.path, 'index.m3u8'))
      ..writeAsStringSync('#EXTM3U\nseg0.ts\nseg1.ts\nseg2.ts\n');

    final info = M3u8Service.parse(m3u.path);
    expect(info.missingCount, 1);
    expect(info.encrypted, false);

    final out = Directory(p.join(_root.path, 'out'))..createSync();
    final r = await M3u8Service.mergeOne(info,
        outputDir: out.path, useOriginalName: true);
    expect(r.merged, 2);
    expect(r.missing, 1);
    expect(File(p.join(out.path, 'index.ts')).lengthSync(), 1000);
  });

  test('⑤ 主播放列表（多码率）被识别且不参与合并', () async {
    final dir = Directory(p.join(_root.path, 'master'))..createSync();
    final m3u = File(p.join(dir.path, 'master.m3u8'))
      ..writeAsStringSync('#EXTM3U\n'
          '#EXT-X-STREAM-INF:BANDWIDTH=800000,RESOLUTION=640x360\n'
          '360/index.m3u8\n'
          '#EXT-X-STREAM-INF:BANDWIDTH=2400000,RESOLUTION=1280x720\n'
          '720/index.m3u8\n');
    if (File(p.join(dir.path, '360/index.m3u8')).existsSync()) {
      // 仅为占位，触发 lints
    }
    final info = M3u8Service.parse(m3u.path);
    expect(info.isMaster, true);
    expect(info.encrypted, false);
  });

  test('⑥ SAMPLE-AES / DRM：标记为不可读，合并直接失败（不产出损坏文件）',
      () async {
    final dir = Directory(p.join(_root.path, 'drm'))..createSync();
    File(p.join(dir.path, 'seg0.ts')).writeAsBytesSync(_randBytes(300));
    final m3u = File(p.join(dir.path, 'drm.m3u8'))
      ..writeAsStringSync('#EXTM3U\n'
          '#EXT-X-KEY:METHOD=SAMPLE-AES,'
          'URI="skd://key123",KEYFORMAT="com.apple.streamingkeydelivery"\n'
          'seg0.ts\n');

    final info = M3u8Service.parse(m3u.path);
    expect(info.unreadable, true);
    expect(info.method, contains('SAMPLE-AES'));

    final out = Directory(p.join(_root.path, 'out'))..createSync();
    final r = await M3u8Service.mergeOne(info,
        outputDir: out.path, useOriginalName: true);
    expect(r.error, isNotNull);
    expect(r.ok, false);
    // 关键：没有偷偷写出半成品文件
    expect(File(p.join(out.path, 'drm.ts')).existsSync(), false);
  });

  test('⑦ 密钥 URI 为远程且本机没有 → 不可读，绝不联网', () async {
    final dir = Directory(p.join(_root.path, 'remote'))..createSync();
    File(p.join(dir.path, 'seg0.ts')).writeAsBytesSync(_randBytes(300));
    final m3u = File(p.join(dir.path, 'remote.m3u8'))
      ..writeAsStringSync('#EXTM3U\n'
          '#EXT-X-KEY:METHOD=AES-128,URI="https://cdn.example.com/k.key"\n'
          'seg0.ts\n');
    final info = M3u8Service.parse(m3u.path);
    expect(info.unreadable, true);
  });

  test('⑧ 按时间自动命名：文件名形如 merged_YYYYMMDD_HHMMSS.ts', () async {
    final dir = Directory(p.join(_root.path, 'tname'))..createSync();
    File(p.join(dir.path, 'seg0.ts')).writeAsBytesSync(_randBytes(200));
    final m3u = File(p.join(dir.path, 'a.m3u8'))
      ..writeAsStringSync('#EXTM3U\nseg0.ts\n');
    final info = M3u8Service.parse(m3u.path);
    final out = Directory(p.join(_root.path, 'out'))..createSync();
    final r = await M3u8Service.mergeOne(info,
        outputDir: out.path, useOriginalName: false);
    expect(p.basename(r.path), matches(RegExp(r'^merged_\d{8}_\d{6}\.ts$')));
    expect(File(r.path).existsSync(), true);
  });

  test('⑨ 批量合并：多个列表一次处理，进度回调完整', () async {
    final base = Directory(p.join(_root.path, 'batch'))..createSync();
    final paths = <String>[];
    for (var n = 0; n < 3; n++) {
      final d = Directory(p.join(base.path, 'v$n'))..createSync();
      File(p.join(d.path, 'seg0.ts')).writeAsBytesSync(_randBytes(100 + n));
      final m3u = File(p.join(d.path, 'list$n.m3u8'))
        ..writeAsStringSync('#EXTM3U\nseg0.ts\n');
      paths.add(m3u.path);
    }
    final infos = await M3u8Service.scanPlaylists([base.path]);
    expect(infos.length, 3);

    final out = Directory(p.join(_root.path, 'out'))..createSync();
    final seen = <int>[];
    final rs = await M3u8Service.mergeMany(infos,
        outputDir: out.path,
        useOriginalName: true,
        onProgress: (done, total) {
          seen.add(done);
          expect(total, 3);
        });
    expect(seen, [1, 2, 3]);
    expect(rs.where((r) => r.ok).length, 3);
  });
  test('⑩ 十六进制文本形式的密钥文件（下载器常见写法）也能解密', () async {
    final dir = Directory(p.join(_root.path, 'hexkey'))..createSync();
    final key = enc.Key.fromUtf8('0123456789abcdef');
    final iv = enc.IV(Uint8List.fromList(List<int>.generate(16, (i) => 0x10 + i)));
    final crypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));

    // 故意写成 32 位 hex 文本再追加换行，模拟真实下载器输出
    File(p.join(dir.path, 'key.key'))
        .writeAsStringSync('${key.base16.toLowerCase()}\n');

    final expected = <int>[];
    final ivHex = iv.base16.toLowerCase();
    for (var i = 0; i < 2; i++) {
      final plain = _randBytes(700 + i);
      File(p.join(dir.path, 'seg$i.ts'))
          .writeAsBytesSync(crypter.encryptBytes(plain, iv: iv).bytes);
      expected.addAll(plain);
    }
    final m3u = File(p.join(dir.path, 'index.m3u8'))
      ..writeAsStringSync('#EXTM3U\n'
          '#EXT-X-KEY:METHOD=AES-128,URI="key.key",IV=0x$ivHex\n'
          'seg0.ts\n'
          'seg1.ts\n');

    final info = M3u8Service.parse(m3u.path);
    expect(info.unreadable, false);

    final out = Directory(p.join(_root.path, 'out'))..createSync();
    final r = await M3u8Service.mergeOne(info,
        outputDir: out.path, useOriginalName: true);
    expect(r.error, isNull);
    expect(File(p.join(out.path, 'index.ts')).readAsBytesSync(), expected);
  });

  test('⑪ 密钥 URI 带 % 编码也能定位到本机文件', () async {
    final dir = Directory(p.join(_root.path, 'encuri'))..createSync();
    final key = enc.Key.fromUtf8('abcdef0123456789');
    File(p.join(dir.path, 'my key.key')).writeAsBytesSync(key.bytes); // 含空格
    final m3u = File(p.join(dir.path, 'index.m3u8'))
      ..writeAsStringSync('#EXTM3U\n'
          '#EXT-X-KEY:METHOD=AES-128,URI="my%20key.key"\n'
          'seg0.ts\n');
    final info = M3u8Service.parse(m3u.path);
    expect(info.unreadable, false, reason: '应能解码 %20 并找到本机密钥');
  });

  test('⑫ AES-256 密钥长度：按密钥字节长度自动适配', () async {
    final dir = Directory(p.join(_root.path, 'aes256'))..createSync();
    final keyBytes = Uint8List.fromList(List<int>.generate(32, (i) => i * 7 & 0xff));
    final key = enc.Key(keyBytes);
    final iv = enc.IV.fromLength(16);
    final crypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
    File(p.join(dir.path, 'key.bin')).writeAsBytesSync(keyBytes);

    final expected = <int>[];
    for (var i = 0; i < 2; i++) {
      final plain = _randBytes(600 + i);
      File(p.join(dir.path, 's$i.ts'))
          .writeAsBytesSync(crypter.encryptBytes(plain, iv: iv).bytes);
      expected.addAll(plain);
    }
    final m3u = File(p.join(dir.path, 'index.m3u8'))
      ..writeAsStringSync('#EXTM3U\n'
          '#EXT-X-KEY:METHOD=AES-128,URI="key.bin",IV=0x${iv.base16.toLowerCase()}\n'
          's0.ts\n'
          's1.ts\n');
    final info = M3u8Service.parse(m3u.path);
    final out = Directory(p.join(_root.path, 'out'))..createSync();
    final r = await M3u8Service.mergeOne(info,
        outputDir: out.path, useOriginalName: true);
    expect(r.error, isNull);
    expect(File(p.join(out.path, 'index.ts')).readAsBytesSync(), expected);
  });

  test('⑬ 无扩展名哈希分片：URI 带 .ts 后缀也能对上本机文件', () async {
    // 模拟下载器缓存：分片被存成无扩展名的十六进制名，local.m3u8 里写 xxx.ts
    final dir = Directory(p.join(_root.path, 'noext'))..createSync();
    final names = <String>[
      'e04d87b55647e4bdba63d5c6b71652fb',
      'f2bef1af5902fcd4713d6d7c49eef712',
    ];
    final expected = <int>[];
    for (var i = 0; i < names.length; i++) {
      final bytes = _randBytes(800 + i * 33);
      File(p.join(dir.path, names[i])).writeAsBytesSync(bytes);
      expected.addAll(bytes);
    }
    final m3u = File(p.join(dir.path, 'local.m3u8'))
      ..writeAsStringSync('#EXTM3U\n'
          '${names[0]}.ts\n'
          '${names[1]}.ts\n');

    final info = M3u8Service.parse(m3u.path);
    expect(info.missingCount, 0, reason: '扩展名变体匹配应命中无后缀分片');

    final out = Directory(p.join(_root.path, 'out'))..createSync();
    final r = await M3u8Service.mergeOne(info,
        outputDir: out.path, useOriginalName: true);
    expect(r.error, isNull);
    expect(r.merged, 2);
    expect(File(p.join(out.path, 'local.ts')).readAsBytesSync(), expected);
  });

  test('⑭ 下载器哈希目录：URI 与本地文件名完全对不上时，按修改时间顺序兜底映射',
      () async {
    // 模拟：分片名为无意义哈希、播放列表里是原始网址（本机不存在同名文件）。
    // 下载器按播放顺序落盘 → 修改时间顺序 == 播放顺序。
    final dir = Directory(p.join(_root.path, 'hashdir'))..createSync();
    final hashNames = <String>['aabb001f', 'ccdd002e', 'eeff003d'];
    final expected = <int>[];
    final baseMs = DateTime.now().millisecondsSinceEpoch - 100000;
    for (var i = 0; i < hashNames.length; i++) {
      final bytes = _randBytes(700 + i * 11);
      final f = File(p.join(dir.path, hashNames[i]))..writeAsBytesSync(bytes);
      // 显式设置互不相同的修改时间，保证确定性
      f.setLastModifiedSync(
          DateTime.fromMillisecondsSinceEpoch(baseMs + i * 1000));
      expected.addAll(bytes);
    }
    final m3u = File(p.join(dir.path, 'local.m3u8'))
      ..writeAsStringSync('#EXTM3U\n'
          'https://cdn.example.com/v1/seg0.ts?sign=abc\n'
          'https://cdn.example.com/v1/seg1.ts?sign=abc\n'
          'https://cdn.example.com/v1/seg2.ts?sign=abc\n');

    final info = M3u8Service.parse(m3u.path);
    expect(info.missingCount, 0, reason: '数量一致时应按修改时间映射成功');

    final out = Directory(p.join(_root.path, 'out'))..createSync();
    final r = await M3u8Service.mergeOne(info,
        outputDir: out.path, useOriginalName: true);
    expect(r.error, isNull);
    expect(r.merged, 3);
    // 合并顺序必须等于播放顺序（即修改时间顺序），而非文件名字典序
    expect(File(p.join(out.path, 'local.ts')).readAsBytesSync(), expected);
  });

  test('⑮ 兜底不乱猜：候选数量对不上不映射；列表/密钥/图片/元数据不当分片',
      () async {
    final dir = Directory(p.join(_root.path, 'mismatch'))..createSync();
    File(p.join(dir.path, 'seg0.ts')).writeAsBytesSync(_randBytes(400));
    // 两个无扩展名哈希文件，但只缺 1 个分片 → 数量不一致，禁止映射
    File(p.join(dir.path, 'aaaa1111')).writeAsBytesSync(_randBytes(300));
    File(p.join(dir.path, 'bbbb2222')).writeAsBytesSync(_randBytes(300));
    // 非分片文件必须被排除出候选
    File(p.join(dir.path, 'cover.jpg')).writeAsBytesSync(_randBytes(50));
    File(p.join(dir.path, 'info.json')).writeAsBytesSync(_randBytes(20));
    final m3u = File(p.join(dir.path, 'local.m3u8'))
      ..writeAsStringSync('#EXTM3U\nseg0.ts\nnot_exist_seg.ts\n');

    final info = M3u8Service.parse(m3u.path);
    expect(info.missingCount, 1,
        reason: '候选(2) != 缺失(1) 时应保持缺失，不能拿哈希文件乱凑');
  });
}

/// 生成固定种子的随机字节，保证可复现（同时避免被 R8/压缩误判为常量）
Uint8List _randBytes(int n) {
  final rnd = Random(n);
  return Uint8List.fromList(List<int>.generate(n, (_) => rnd.nextInt(256)));
}
