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

/// 债务明细：单条债务字段 + 还款记录。
///
/// 数据：`GET /finance/debts/{id}`、`GET /finance/debts/{id}/payments`。
class FinanceDebtDetailPage extends StatefulWidget {
  const FinanceDebtDetailPage({super.key, required this.debtId});

  final int debtId;

  @override
  State<FinanceDebtDetailPage> createState() => _FinanceDebtDetailPageState();
}

class _FinanceDebtDetailPageState extends State<FinanceDebtDetailPage> {
  DebtItem? _debt;
  List<DebtPayment> _payments = const <DebtPayment>[];
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

  /// 并行拉债务详情与还款记录；任一失败进入失败态（保留已有数据）。
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
      _status = _debt == null ? LoadStatus.loading : LoadStatus.ready;
      _message = null;
    });
    try {
      final Future<Map<String, dynamic>?> debtFuture = scope.apiClient
          .get<Map<String, dynamic>>(
            '/finance/debts/${widget.debtId}',
          )
          .then((value) => value.data);
      final Future<List<dynamic>?> paymentsFuture = scope.apiClient
          .get<List<dynamic>>(
            '/finance/debts/${widget.debtId}/payments',
          )
          .then((value) => value.data);
      final Map<String, dynamic>? debtJson = await debtFuture;
      final List<dynamic> paymentsJson =
          await paymentsFuture ?? const <dynamic>[];
      if (debtJson == null) {
        throw const ApiException(
          kind: ApiErrorKind.badResponse,
          message: '债务详情返回为空',
        );
      }
      final List<DebtPayment> payments = paymentsJson
          .whereType<Map>()
          .map((Map item) => DebtPayment.fromJson(item.cast<String, dynamic>()))
          .toList(growable: false);
      if (!mounted) {
        return;
      }
      setState(() {
        _debt = DebtItem.fromJson(debtJson);
        _payments = payments;
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
    final DebtItem? debt = _debt;

    return DetailPageScaffold(
      title: '债务明细',
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
              if (_status == LoadStatus.ready && debt != null) ...<Widget>[
                SectionCard(
                  title: '债务信息',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: 10,
                    children: <Widget>[
                      Row(
                        spacing: 8,
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              debt.name,
                              style: theme.textTheme.titleMedium,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          StatusChip(
                            label: debtDirectionLabel(debt.direction),
                            tone: debt.isLend
                                ? StatusTone.info
                                : StatusTone.warning,
                          ),
                          StatusChip(
                            label: debtStatusLabel(debt.status),
                            tone: debt.status == 'settled'
                                ? StatusTone.success
                                : StatusTone.info,
                          ),
                        ],
                      ),
                      _DetailRow(
                        label: '对方',
                        value: debt.counterparty ?? '未填写',
                      ),
                      _DetailRow(label: '发生日期', value: debt.debtDate),
                      _DetailRow(
                        label: '本金',
                        value: formatMoney(debt.amount),
                      ),
                      _DetailRow(
                        label: '未还金额',
                        value: formatMoney(debt.outstanding),
                        valueColor: debt.outstanding > 0
                            ? context.semanticColors.danger
                            : null,
                      ),
                      if (debt.interestRate != null)
                        _DetailRow(
                          label: '利率',
                          value: formatPercent(debt.interestRate),
                        ),
                      _DetailRow(
                        label: '利息合计',
                        value: formatMoney(debt.interestTotal),
                      ),
                      if (debt.channel != null && debt.channel!.isNotEmpty)
                        _DetailRow(label: '渠道', value: debt.channel!),
                      if (debt.dueDate != null)
                        _DetailRow(label: '到期日', value: debt.dueDate!),
                      if (debt.note != null && debt.note!.trim().isNotEmpty)
                        _DetailRow(label: '备注', value: debt.note!),
                    ],
                  ),
                ),
                SectionCard(
                  title: '还款记录',
                  trailing: Text(
                    '${_payments.length} 笔',
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  ),
                  child: _payments.isEmpty
                      ? const EmptyState(
                          icon: Icons.payments_outlined,
                          title: '暂无还款记录',
                          description: '该债务还没有还款',
                          compact: true,
                        )
                      : Column(
                          spacing: 4,
                          children: <Widget>[
                            for (final DebtPayment item in _payments)
                              _PaymentRow(item: item),
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

/// 还款记录行：日期 + 实付（含优惠说明）。
class _PaymentRow extends StatelessWidget {
  const _PaymentRow({required this.item});

  final DebtPayment item;

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
