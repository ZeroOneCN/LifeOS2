import 'package:flutter/material.dart';

import '../../shared/widgets/add_record_fab.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/root_page_scaffold.dart';

/// 流水二级页：同样挂「记一笔」FAB（方案：FAB 只在财务域）。
class FinanceTransactionsPage extends StatelessWidget {
  const FinanceTransactionsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const DetailPageScaffold(
      title: '流水',
      floatingActionButton: AddRecordFab(),
      child: Center(
        child: EmptyState(
          icon: Icons.receipt_long_outlined,
          title: '流水占位页',
          description: 'P2 接后端分页接口，P1 不展示任何业务列表',
        ),
      ),
    );
  }
}
