import 'package:flutter/material.dart';

import '../../core/data/overview_controller.dart';
import '../../core/models/investment_models.dart';
import '../../core/utils/formatters.dart';
import '../../shared/widgets/root_page_scaffold.dart';
import '../../shared/widgets/section_card.dart';
import '../../shared/widgets/section_status.dart';

/// 资金记录详情（**只读**）。
///
/// 资金数据由网页端导入，移动端只保留查看能力。
/// 后端没有 `GET /investment/funds/{id}` 单条接口，因此只能展示列表快照；
/// 拿不到快照时明确提示「请从列表进入」，不臆造数据。
class FundRecordDetailPage extends StatelessWidget {
  const FundRecordDetailPage({super.key, required this.recordId, this.record});

  final int recordId;
  final FundRecord? record;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final FundRecord? item = record;
    return DetailPageScaffold(
      title: '资金记录详情',
      child: ListView(
        children: <Widget>[
          if (item == null)
            ListStatusView(
              status: LoadStatus.failed,
              message: '没有拿到这条记录的详情，请从资金动态列表进入。',
              onRetry: () => Navigator.of(context).maybePop(),
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 12,
              children: <Widget>[
                SectionCard(
                  title: item.typeLabel,
                  child: Text(
                    formatUsdSigned(item.amount),
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: item.amount >= 0
                          ? theme.colorScheme.primary
                          : theme.colorScheme.error,
                    ),
                  ),
                ),
                SectionCard(
                  title: '记录明细',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: 10,
                    children: <Widget>[
                      _DetailRow(label: '编号', value: '#${item.id}'),
                      _DetailRow(label: '类型', value: item.typeLabel),
                      _DetailRow(label: '金额', value: formatUsdSigned(item.amount)),
                      _DetailRow(label: '日期', value: item.recordDate),
                      _DetailRow(
                        label: '备注',
                        value: (item.note ?? '').trim().isEmpty
                            ? '—'
                            : item.note!.trim(),
                      ),
                    ],
                  ),
                ),
                Text(
                  '资金数据由网页端导入，移动端仅支持查看。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// 只读字段行：左标签右值。
class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Row(
      spacing: 12,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: theme.textTheme.bodyMedium,
          ),
        ),
      ],
    );
  }
}
