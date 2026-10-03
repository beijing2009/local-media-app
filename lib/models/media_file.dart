/// 媒体文件模型：统一描述本地视频 / 音频文件。
class MediaFile {
  final String path; // 文件系统绝对路径
  final String name; // 文件名（含扩展名）
  final MediaType type; // 类型：video / audio
  final int? sizeBytes; // 文件大小（可选）

  const MediaFile({
    required this.path,
    required this.name,
    required this.type,
    this.sizeBytes,
  });

  /// 不含扩展名的标题
  String get title =>
      name.contains('.') ? name.substring(0, name.lastIndexOf('.')) : name;

  /// 扩展名（小写，不含点）
  String get extension =>
      name.contains('.') ? name.substring(name.lastIndexOf('.') + 1).toLowerCase() : '';

  Map<String, dynamic> toJson() => {
        'path': path,
        'name': name,
        'type': type.index,
        'sizeBytes': sizeBytes,
      };

  factory MediaFile.fromJson(Map<String, dynamic> json) => MediaFile(
        path: json['path'] as String,
        name: json['name'] as String,
        type: MediaType.values[json['type'] as int],
        sizeBytes: json['sizeBytes'] as int?,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MediaFile && other.path == path;

  @override
  int get hashCode => path.hashCode;
}

enum MediaType { video, audio }

/// 按需求主支持 mp4 / mp3 / m4a 三类。
class SupportedFormats {
  static const Set<String> video = {'mp4'};
  static const Set<String> audio = {'mp3', 'm4a'};

  static bool isVideo(String ext) => video.contains(ext.toLowerCase());
  static bool isAudio(String ext) => audio.contains(ext.toLowerCase());
}
