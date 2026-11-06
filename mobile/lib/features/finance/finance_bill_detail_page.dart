import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/data/overview_controller.dart';
import '../../core/models/finance_models.dart';
import '../../core/network/api_exception.dart';
import '../../core/utils/formatters.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/root_page_scaffold.dart';
import '../../shared/widgets/section_card.dart';
import '../../shared/widgets/section_status.dart';
import '../../theme/app_theme.dart';
import 'finance_status_widgets.dart';

/// 账单明细：单条账单字段 + 该账单的还款记录。
///
/// 数据：`GET /finance/loan-bills/{id}`、`GET /finance/repayments?bill_id={id}`。
class FinanceBillDetailPage extends StatefulWidget {
  const FinanceBillDetailPage({
    super.key,
    required this.billId,
    this.platformName = '',
  });

  final int billId;
  final String platformName;

  @override
  State<FinanceBillDetailPage> createState() => _FinanceBillDetailPageState();
}

class _FinanceBillDetailPageState extends State<FinanceBillDetailPage> {
  BillItem? _bill;
  List<BillRepayment> _repayments = const <BillRepayment>[];
  LoadStatus _status = LoadStatus.loading;
  String? _message;

  @override
  void initState() {
    super.initState();
    // 首帧后再取 AppScope：initState 内不允许依赖 InheritedWidget。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _refresh();
      }
    });
  }

  /// 并行拉账单与还款记录；任一失败进入失败态（保留已有数据）。
  Future<void> _refresh() async {
    final AppScope scope = AppScope.of(context);
    if (!scope.auth.isLoggedIn) {
      setState(() {
        _status = scope.auth.connectionFailed
            ? LoadStatus.connectionFailed
            : LoadStatus.unauthenticated;
        _message = scope.auth.restoreError;
      });
      return;
    }
    setState(() {
      _status = _bill == null ? LoadStatus.loading : LoadStatus.ready;
      _message = null;
    });
    try {
      final Future<Map<String, dynamic>?> billFuture = scope.apiClient
          .get<Map<String, dynamic>>(
            '/finance/loan-bills/${widget.billId}',
          )
          .then((value) => value.data);
      final Future<List<dynamic>?> repaymentsFuture = scope.apiClient
          .get<List<dynamic>>(
            '/finance/repayments',
            queryParameters: <String, dynamic>{'bill_id': widget.billId},
          )
          .then((value) => value.data);
      final Map<String, dynamic>? billJson = await billFuture;
      final List<dynamic> repaymentsJson =
          await repaymentsFuture ?? const <dynamic>[];
      if (billJson == null) {
        throw const ApiException(
          kind: ApiErrorKind.badResponse,
          message: '账单详情返回为空',
        );
      }
      final List<BillRepayment> repayments = repaymentsJson
              .whereType<Map>()
              .map((Map item) =>
                  BillRepayment.fromJson(item.cast<String, dynamic>()))
              .toList(growable: false);
      if (!mounted) {
        return;
      }
      setState(() {
        _bill = BillItem.fromJson(billJson);
        _repayments = repayments;
        _status = LoadStatus.ready;
      });
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      final bool offline = scope.auth.hasLocalSession &&
          (error.kind == ApiErrorKind.network ||
              error.kind == ApiErrorKind.timeout);
      setState(() {
        _status = error.isUnauthorized
            ? LoadStatus.unauthenticated
            : (offline ? LoadStatus.connectionFailed : LoadStatus.failed);
        _message = error.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color muted = theme.colorScheme.onSurfaceVariant;
    final BillItem? bill = _bill;

    return DetailPageScaffold(
      title: '账单明细',
      child: ListView(
        children: <Widget>[
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 12,
            children: <Widget>[
              ListStatusView(
                status: _status,
                message: _message,
                onRetry: _refresh,
              ),
              if (_status == LoadStatus.ready && bill != null) ...<Widget>[
                SectionCard(
                  title: '账单信息',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: 10,
                    children: <Widget>[
                      Row(
                        spacing: 8,
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              widget.platformName.isEmpty
                                  ? '账单 #${bill.id}'
                                  : widget.platformName,
                              style: theme.textTheme.titleMedium,
                            ),
                          ),
                          StatusChip(
                            label: billStatusLabel(bill.status),
                            tone: billTone(bill.status),
                          ),
                          if (bill.overdue)
                            const StatusChip(
                              label: '逾期',
                              tone: StatusTone.danger,
                            ),
                        ],
                      ),
                      _DetailRow(
                        label: '账单月',
                        value: bill.billMonth.length >= 7
                            ? bill.billMonth.substring(0, 7)
                            : bill.billMonth,
                      ),
                      _DetailRow(
                        label: '到期日',
                        value: bill.dueDate ?? '未设置',
                      ),
                      _DetailRow(
                        label: '应还金额',
                        value: formatMoney(bill.amount),
                      ),
                      _DetailRow(
                        label: '已还金额',
                        value: formatMoney(bill.paidAmount),
                      ),
                      _DetailRow(
                        label: '待还金额',
                        value: formatMoney(bill.remaining),
                        valueColor: bill.remaining > 0
                            ? context.semanticColors.danger
                            : null,
                      ),
                      _DetailRow(
                        label: '利息',
                        value: formatMoney(bill.interest),
                      ),
                      if (bill.note != null &&
                          bill.note!.trim().isNotEmpty)
                        _DetailRow(label: '备注', value: bill.note!),
                    ],
                  ),
                ),
                SectionCard(
                  title: '还款记录',
                  trailing: Text(
                    '${_repayments.length} 笔',
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  ),
                  child: _repayments.isEmpty
                      ? const EmptyState(
                          icon: Icons.payments_outlined,
                          title: '暂无还款记录',
                          description: '该账单还没有还款',
                          compact: true,
                        )
                      : Column(
                          spacing: 4,
                          children: <Widget>[
                            for (final BillRepayment item in _repayments)
                              _RepaymentRow(item: item),
                          ],
                        ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// 明细字段行：左标签右值（值可带语义色）。
class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value, this.valueColor});

  final String label;
  final String value;
  final Color? valueColor;

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
            style: theme.textTheme.bodyMedium?.copyWith(
              color: valueColor,
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}

/// 还款记录行：日期 + 金额/优惠 + 实付。
class _RepaymentRow extends StatelessWidget {
  const _RepaymentRow({required this.item});

  final BillRepayment item;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color muted = theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        spacing: 12,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 2,
              children: <Widget>[
                Text(item.repayDate, style: theme.textTheme.bodyMedium),
                if (item.discount > 0 || item.note != null)
                  Text(
                    <String>[
                      if (item.discount > 0)
                        '优惠 ${formatMoney(item.discount)}',
                      if (item.note != null && item.note!.isNotEmpty)
                        item.note!,
                    ].join(' · '),
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  ),
              ],
            ),
          ),
          Text(
            formatMoney(item.actual),
            style: theme.textTheme.bodyMedium?.copyWith(
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
