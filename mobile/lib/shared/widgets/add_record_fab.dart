import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// 全局「记一笔」FAB：按方案只挂在财务域（财务根页 + 流水页）。
class AddRecordFab extends StatelessWidget {
  const AddRecordFab({super.key});

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton.extended(
      onPressed: () => showAddRecordSheet(context),
      icon: const Icon(Icons.edit_note_outlined),
      label: const Text('记一笔'),
    );
  }
}

/// 四选一面板（支出 / 账单 / 用药 / 体重）。
/// 支出已接入离线队列表单，其余三类仍为后续批次占位。
Future<void> showAddRecordSheet(BuildContext context) {
  final NavigatorState navigator = Navigator.of(context);
  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (BuildContext sheetContext) {
      return SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                '记一笔',
                style: Theme.of(sheetContext).textTheme.titleMedium,
              ),
            ),
            _RecordOption(
              icon: Icons.payments_outlined,
              title: '支出',
              onTap: () {
                navigator.pop();
                context.push('/finance/expense/new');
              },
            ),
            _RecordOption(
              icon: Icons.receipt_long_outlined,
              title: '账单',
              onTap: () {
                Navigator.of(sheetContext).pop();
                _notify(messenger, '账单表单将在后续批次接入');
              },
            ),
            _RecordOption(
              icon: Icons.medication_outlined,
              title: '用药',
              onTap: () {
                Navigator.of(sheetContext).pop();
                _notify(messenger, '用药表单将在后续批次接入');
              },
            ),
            _RecordOption(
              icon: Icons.monitor_weight_outlined,
              title: '体重',
              onTap: () {
                Navigator.of(sheetContext).pop();
                _notify(messenger, '体重表单将在后续批次接入');
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
}

void _notify(ScaffoldMessengerState messenger, String message) {
  messenger.showSnackBar(SnackBar(content: Text(message)));
}

class _RecordOption extends StatelessWidget {
  const _RecordOption({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
