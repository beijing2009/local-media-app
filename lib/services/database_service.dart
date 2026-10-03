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
      version: 2,
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
        // 显式导入的视频文件清单（支持批量加入 / 批量移除）
        await database.execute('''
          CREATE TABLE imported_files (
            path TEXT PRIMARY KEY,
            added_at INTEGER
          )
        ''');
      },
      // v1 -> v2：仅新增导入清单表，老用户的播放进度、专辑数据完全不受影响
      onUpgrade: (database, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await database.execute('''
            CREATE TABLE IF NOT EXISTS imported_files (
              path TEXT PRIMARY KEY,
              added_at INTEGER
            )
          ''');
        }
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

  // ---------------- 显式导入文件（支持批量） ----------------
  /// 取出所有被显式导入的文件路径（按导入时间倒序）。
  Future<List<String>> getImportedPaths() async {
    final rows = await (await db)
        .query('imported_files', orderBy: 'added_at DESC');
    return rows.map((r) => r['path'] as String).toList();
  }

  /// 批量加入导入清单（同一事务，避免中途失败导致半写入）。
  Future<int> addImportedPaths(List<String> paths) async {
    final database = await db;
    final now = DateTime.now().millisecondsSinceEpoch;
    int added = 0;
    await database.transaction((txn) async {
      for (final path in paths) {
        final id = await txn.insert(
          'imported_files',
          {'path': path, 'added_at': now},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        if (id > 0) added++;
      }
    });
    return added;
  }

  /// 批量从导入清单移除。
  Future<int> removeImportedPaths(List<String> paths) async {
    final database = await db;
    int removed = 0;
    await database.transaction((txn) async {
      for (final path in paths) {
        final n = await txn.delete('imported_files',
            where: 'path = ?', whereArgs: [path]);
        removed += n;
      }
    });
    return removed;
  }

  /// 一键清空导入清单。
  Future<void> clearImportedPaths() async {
    await (await db).delete('imported_files');
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
