import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import '../models/album.dart';

/// 本地数据库服务：仅存储播放进度与用户数据，绝不联网、绝不上传。
///
/// 表结构：
///  - kv     通用键值（视频进度、音频进度、上次播放、扫描根目录等）
///  - albums 用户自建专辑（含剧集路径列表）
class DatabaseService {
  static Database? _db;
  static DatabaseService? _instance;

  DatabaseService._();

  /// 单例，全局复用同一数据库连接。
  static DatabaseService get instance {
    _instance ??= DatabaseService._();
    return _instance!;
  }

  Future<Database> get db async {
    _db ??= await openDatabase(
      p.join(await getDatabasesPath(), 'local_media.db'),
      version: 1,
      onCreate: (database, version) async {
        await database.execute('''
          CREATE TABLE kv (
            k TEXT PRIMARY KEY,
            v TEXT
          )
        ''');
        await database.execute('''
          CREATE TABLE albums (
            id TEXT PRIMARY KEY,
            name TEXT,
            description TEXT,
            color INTEGER,
            episodes TEXT,
            created_at INTEGER
          )
        ''');
      },
    );
    return _db!;
  }

  // ---------------- 通用 KV ----------------
  Future<String?> getKv(String key) async {
    final res = await (await db).query('kv', where: 'k = ?', whereArgs: [key]);
    return res.isEmpty ? null : res.first['v'] as String?;
  }

  Future<void> setKv(String key, String value) async {
    await (await db).insert('kv', {'k': key, 'v': value},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // ---------------- 视频进度记忆 ----------------
  Future<int> getVideoPosition(String path) async {
    final v = await getKv('vp:$path');
    return v == null ? 0 : int.tryParse(v) ?? 0;
  }

  Future<void> saveVideoPosition(String path, int ms) async {
    await setKv('vp:$path', ms.toString());
  }

  // ---------------- 音频进度记忆 ----------------
  Future<int> getAudioPosition(String path) async {
    final v = await getKv('ap:$path');
    return v == null ? 0 : int.tryParse(v) ?? 0;
  }

  Future<void> saveAudioPosition(String path, int ms) async {
    await setKv('ap:$path', ms.toString());
  }

  /// 记录“上次播放的专辑与集数”，用于下次进入音频区自动续播。
  Future<void> saveLastAudio(String albumId, int index) async {
    await setKv('last_album', albumId);
    await setKv('last_index', index.toString());
  }

  Future<String?> getLastAlbum() => getKv('last_album');

  Future<int> getLastIndex() async {
    final v = await getKv('last_index');
    return v == null ? 0 : int.tryParse(v) ?? 0;
  }

  // ---------------- 扫描根目录（功能区配置） ----------------
  Future<List<String>> getScanRoots() async {
    final v = await getKv('scan_roots');
    if (v == null || v.isEmpty) return [];
    return v.split('\u0001').where((e) => e.isNotEmpty).toList();
  }

  Future<void> setScanRoots(List<String> roots) async {
    await setKv('scan_roots', roots.join('\u0001'));
  }

  // ---------------- 专辑（听书管理） ----------------
  Future<List<Album>> getAlbums() async {
    final rows = await (await db).query('albums', orderBy: 'created_at DESC');
    return rows.map(Album.fromRow).toList();
  }

  Future<Album?> getAlbum(String id) async {
    final rows = await (await db)
        .query('albums', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : Album.fromRow(rows.first);
  }

  Future<void> insertAlbum(Album album) async {
    await (await db).insert('albums', album.toRow(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> updateAlbum(Album album) async {
    await (await db).update('albums', album.toRow(),
        where: 'id = ?', whereArgs: [album.id]);
  }

  Future<void> deleteAlbum(String id) async {
    await (await db).delete('albums', where: 'id = ?', whereArgs: [id]);
  }

  /// 清空所有播放进度（视频 vp: 与音频 ap: 键值）。
  Future<void> clearProgress() async {
    await (await db).delete('kv',
        where: "k LIKE ? OR k LIKE ?", whereArgs: ['vp:%', 'ap:%']);
  }
}
