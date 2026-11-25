import 'package:flutter/material.dart';

import '../../core/data/overview_controller.dart';
import '../../core/models/investment_models.dart';
import '../../core/utils/formatters.dart';
import '../../shared/widgets/root_page_scaffold.dart';
import '../../shared/widgets/v2/stat_rail.dart';
import '../../shared/widgets/v2/v2_page_kit.dart';
import '../../shared/widgets/v2/v2_rows.dart';
import '../../theme/app_tokens.dart';

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
    final AppTokens tokens = AppTokens.of(context);
    final FundRecord? item = record;

    // 没拿到列表快照时不臆造字段：明确提示从资金动态列表进入。
    if (item == null) {
      return DetailPageScaffold(
        title: '资金记录详情',
        child: ListPageBody(
          status: LoadStatus.failed,
          message: '没有拿到这条记录的详情，请从资金动态列表进入。',
          onRetry: () => Navigator.of(context).maybePop(),
        ),
      );
    }

    // 金额颜色跟随资金类型语义：出金不是收益，即使金额为正也用危险色；
    // 入金用成功色，体验金用琥珀色，与资金列表行保持一致。
    final Color amountColor = switch (item.recordType) {
      'withdraw' => tokens.red,
      'deposit' => tokens.green,
      _ => tokens.orange,
    };
    return DetailPageScaffold(
      title: '资金记录详情',
      child: ListPageBody(
        // 本页为纯快照展示，数据始终就绪，无需重试。
        status: LoadStatus.ready,
        onRetry: () {},
        blocks: <Widget>[
          SummaryStrip(
            caption: '${formatListDate(item.recordDate)} · 资金记录由网页端导入',
            items: <StatRailItem>[
              StatRailItem(
                label: '金额',
                value: _usdCompact(item.amount, signed: true),
                color: amountColor,
              ),
              StatRailItem(label: '类型', value: item.typeLabel),
              StatRailItem(label: '编号', value: '#${item.id}'),
            ],
          ),
          const SectionHeader(title: '记录明细'),
          GroupCard(
            children: <Widget>[
              _DetailRow(label: '编号', value: '#${item.id}'),
              _DetailRow(label: '类型', value: item.typeLabel),
              _DetailRow(label: '金额', value: formatUsdSigned(item.amount)),
              _DetailRow(label: '日期', value: formatListDate(item.recordDate)),
              _DetailRow(
                label: '备注',
                value: (item.note ?? '').trim().isEmpty
                    ? '—'
                    : item.note!.trim(),
              ),
            ],
          ),
          Text(
            '资金数据由网页端导入，移动端仅支持查看。',
            style: AppType.rowMeta.copyWith(color: tokens.text3),
          ),
        ],
      ),
    );
  }
}

/// 指标轨用的紧凑美元金额：`+$1,284`，只保留整数，避免格子被小数撑破。
String _usdCompact(num? value, {bool signed = false}) {
  if (value == null) {
    return '—';
  }
  final String sign = value < 0 ? '-' : (value > 0 && signed ? '+' : '');
  return '$sign\$${formatInt(value.abs())}';
}

/// 只读字段行：左标签右值（2.0 字阶与色阶）。
class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        spacing: 12,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label, style: AppType.rowMeta.copyWith(color: tokens.text2)),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: AppType.rowTitle.copyWith(color: tokens.text),
            ),
          ),
        ],
      ),
    );
  }
}
