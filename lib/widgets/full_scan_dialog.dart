import 'package:flutter/material.dart';

/// 全盘扫描进度对话框：不可手动关闭，由调用方在扫描完成后 pop。
///
/// 通过两个 [ValueNotifier] 把子 Isolate 的扫描进度实时反映到 UI，
/// 避免直接持有 State 引用。
class FullScanDialog extends StatelessWidget {
  final ValueNotifier<int> dirs;
  final ValueNotifier<int> found;

  const FullScanDialog({
    Key? key,
    required this.dirs,
    required this.found,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('全盘扫描中…'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const LinearProgressIndicator(),
          const SizedBox(height: 12),
          ValueListenableBuilder<int>(
            valueListenable: dirs,
            builder: (_, v, __) => Text('已扫描目录：$v'),
          ),
          ValueListenableBuilder<int>(
            valueListenable: found,
            builder: (_, v, __) => Text('已发现文件：$v'),
          ),
          const SizedBox(height: 6),
          const Text(
            '正在遍历整个存储，请稍候（不会访问网络）',
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
