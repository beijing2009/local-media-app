/// 应用版本与更新记录。
///
/// 约定：**每次功能更新都必须递增版本号并登记到 `CHANGELOG.md`**。
///  - 功能新增 / 变更：递增次版本号（x.Y.0）
///  - 修复补丁：递增修订号（x.y.Z）
///  - build code 必须单调自增（用于安卓 / iOS 包识别升级）
class AppVersion {
  /// 版本名（展示给用户）
  static const String name = '1.1.1';

  /// 构建号（每次出包都要 +1，不可重复）
  static const int code = 3;

  /// 发布日期
  static const String date = '2026-10-04';

  /// 完整展示文本，例如 “v1.1.0 (build 2)”
  static String get display => 'v$name (build $code)';

  /// 用于设置页的简短标题
  static String get label => '本地影音 $display';
}
