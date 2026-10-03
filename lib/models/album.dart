/// 音频专辑（听书 / 音频剧集容器）。
/// 为避免引入图片资源，封面用纯色占位（colorValue）。
class Album {
  final String id;
  final String name;
  final String description; // 简介
  final int colorValue; // 封面占位色（ARGB）
  final List<String> episodePaths; // 剧集文件路径列表（顺序即播放顺序）
  final DateTime createdAt;

  Album({
    required this.id,
    required this.name,
    this.description = '',
    this.colorValue = 0xFF6C63FF,
    required this.episodePaths,
    required this.createdAt,
  });

  /// 剧集数量
  int get episodeCount => episodePaths.length;

  /// 转为数据库行
  Map<String, dynamic> toRow() => {
        'id': id,
        'name': name,
        'description': description,
        'color': colorValue,
        // 用不可见分隔符（\u0001）拼接路径列表
        'episodes': episodePaths.join('\u0001'),
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  /// 从数据库行还原
  factory Album.fromRow(Map<String, dynamic> row) => Album(
        id: row['id'] as String,
        name: row['name'] as String,
        description: row['description'] as String? ?? '',
        colorValue: row['color'] as int? ?? 0xFF6C63FF,
        episodePaths: (row['episodes'] as String? ?? '')
            .split('\u0001')
            .where((e) => e.isNotEmpty)
            .toList(),
        createdAt:
            DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int? ?? 0),
      );

  Album copyWith({
    String? name,
    String? description,
    int? colorValue,
    List<String>? episodePaths,
  }) =>
      Album(
        id: id,
        name: name ?? this.name,
        description: description ?? this.description,
        colorValue: colorValue ?? this.colorValue,
        episodePaths: episodePaths ?? this.episodePaths,
        createdAt: createdAt,
      );
}
