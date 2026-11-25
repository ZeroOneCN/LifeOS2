import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_scope.dart';
import '../../core/data/overview_controller.dart';
import '../../core/models/finance_models.dart';
import '../../core/network/api_exception.dart';
import '../../core/utils/formatters.dart';
import '../../shared/widgets/app_buttons.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/root_page_scaffold.dart';
import '../../shared/widgets/v2/stat_rail.dart';
import '../../shared/widgets/v2/v2_page_kit.dart';
import '../../shared/widgets/v2/v2_rows.dart';
import '../../theme/app_tokens.dart';
import 'finance_repay_sheet.dart';

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
          .get<Map<String, dynamic>>('/finance/debts/${widget.debtId}')
          .then((value) => value.data);
      final Future<List<dynamic>?> paymentsFuture = scope.apiClient
          .get<List<dynamic>>('/finance/debts/${widget.debtId}/payments')
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
      final bool offline =
          scope.auth.hasLocalSession &&
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

  /// 打开还款/收款弹层：新增或编辑已有记录；成功后重拉债务与还款记录。
  Future<void> _openRepay({DebtPayment? payment}) async {
    final DebtItem? debt = _debt;
    if (debt == null) {
      return;
    }
    final bool? changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (BuildContext _) => DebtRepaySheet(debt: debt, payment: payment),
    );
    if (changed == true && mounted) {
      await _refresh();
    }
  }

  /// 编辑债务本体：保存后重拉详情；删除后连同详情一起退回列表，
  /// 避免停留在「记录不存在」的已删详情上。
  Future<void> _openEdit() async {
    final DebtItem? debt = _debt;
    if (debt == null) {
      return;
    }
    final Object? result = await context.push<Object?>(
      '/finance/debts/edit/${debt.id}',
      extra: debt,
    );
    if (!mounted) {
      return;
    }
    if (result == 'deleted') {
      context.pop();
    } else if (result == 'saved') {
      await _refresh();
    }
  }

  /// 底部常驻操作区：进行中且仍有未还金额时提供「记录还款 / 收款」+「编辑债务」，
  /// 已结清时只保留编辑入口（与旧版卡片内按钮逻辑一致）。
  Widget _bottomBar(DebtItem debt) {
    final Widget edit = AppSecondaryButton(
      label: '编辑债务',
      icon: Icons.edit_outlined,
      onPressed: _openEdit,
    );
    if (debt.status == 'settled' || debt.outstanding <= 0) {
      return edit;
    }
    return AppActionRow(
      first: AppPrimaryButton(
        label: debt.isLend ? '记录收款' : '记录还款',
        icon: Icons.payments_outlined,
        onPressed: _openRepay,
      ),
      second: edit,
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    final DebtItem? debt = _debt;

    return DetailPageScaffold(
      title: '债务明细',
      bottomBar: debt == null ? null : _bottomBar(debt),
      child: ListPageBody(
        status: _status,
        message: _message,
        onRetry: _refresh,
        blocks: <Widget>[
          if (debt != null) ...<Widget>[
            SummaryStrip(
              caption: _summaryCaption(debt),
              items: <StatRailItem>[
                StatRailItem(
                  label: '本金',
                  value: formatInt(debt.amount),
                  unit: '元',
                ),
                StatRailItem(
                  label: '未还',
                  value: formatInt(debt.outstanding),
                  unit: '元',
                  color: debt.outstanding > 0 ? tokens.red : null,
                ),
                StatRailItem(
                  label: '利息合计',
                  value: formatInt(debt.interestTotal),
                  unit: '元',
                ),
              ],
            ),
            const SectionHeader(title: '债务信息'),
            GroupCard(
              children: <Widget>[
                _DebtHeadRow(debt: debt),
                _DetailRow(label: '本金', value: formatMoney(debt.amount)),
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
                  _DetailRow(label: '备注', value: debt.note!.trim()),
              ],
            ),
            SectionHeader(
              title: '还款记录 · ${formatInt(_payments.length)} 笔',
            ),
            GroupCard(
              children: _payments.isEmpty
                  ? const <Widget>[
                      EmptyState(
                        icon: Icons.payments_outlined,
                        title: '暂无还款记录',
                        description: '该债务还没有还款',
                        compact: true,
                      ),
                    ]
                  : <Widget>[
                      for (final DebtPayment item in _payments)
                        _PaymentRow(
                          item: item,
                          onTap: () => _openRepay(payment: item),
                        ),
                    ],
            ),
            Text(
              '还款记录与网页端同源；点按记录可修改或删除。',
              style: AppType.rowMeta.copyWith(color: tokens.text3),
            ),
          ],
        ],
      ),
    );
  }

  /// 概览句只补时间线：借入日期与到期日，避免与下方信息卡重复方向/对方。
  String _summaryCaption(DebtItem debt) {
    final String date = debt.debtDate.isEmpty
        ? '日期未知'
        : formatListDate(debt.debtDate);
    final String due;
    if (debt.dueDate == null || debt.dueDate!.isEmpty) {
      due = debt.outstanding <= 0 ? '已结清' : '未设到期日';
    } else {
      due = '到期 ${formatListDate(debt.dueDate!)}';
    }
    return '$date · $due';
  }
}

/// 债务标题行：名称 + 方向 / 状态徽标在上，对方与发生日期 + 未还金额在下。
class _DebtHeadRow extends StatelessWidget {
  const _DebtHeadRow({required this.debt});

  final DebtItem debt;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    final String counterparty = (debt.counterparty ?? '').trim();
    final String meta = <String>[
      counterparty.isEmpty ? '对方未填写' : counterparty,
      if (debt.debtDate.isNotEmpty) debt.debtDate,
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 4,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  debt.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.rowTitle.copyWith(color: tokens.text),
                ),
              ),
              const SizedBox(width: 8),
              V2Badge(
                debtDirectionLabel(debt.direction),
                tone: debt.isLend ? V2BadgeTone.info : V2BadgeTone.warn,
              ),
              const SizedBox(width: 4),
              V2Badge(
                debtStatusLabel(debt.status),
                tone: debt.status == 'settled'
                    ? V2BadgeTone.green
                    : V2BadgeTone.info,
              ),
            ],
          ),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  meta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.rowMeta.copyWith(color: tokens.text2),
                ),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  '未还 ${formatMoney(debt.outstanding)}',
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: AppType.rowValue.copyWith(
                    color: debt.outstanding > 0 ? tokens.red : tokens.text,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 只读字段行：左标签（次要字色）右值（等宽数值，主字色），数值右对齐。
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
              style: AppType.rowValue.copyWith(color: tokens.text),
            ),
          ),
        ],
      ),
    );
  }
}

/// 还款记录行：日期 + 优惠徽标在上，备注说明 + 实付金额在下；点按进入编辑 / 删除。
class _PaymentRow extends StatelessWidget {
  const _PaymentRow({required this.item, required this.onTap});

  final DebtPayment item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    final String note = (item.note ?? '').trim();
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 52),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 4,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      formatListDate(item.repayDate),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.rowTitle.copyWith(color: tokens.text),
                    ),
                  ),
                  if (item.discount > 0) ...<Widget>[
                    const SizedBox(width: 8),
                    V2Badge(
                      '优惠 ${formatMoney(item.discount)}',
                      tone: V2BadgeTone.green,
                    ),
                  ],
                  const SizedBox(width: 2),
                  Icon(Icons.edit_outlined, size: 15, color: tokens.text3),
                ],
              ),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      note.isEmpty ? '实付金额' : note,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.rowMeta.copyWith(color: tokens.text2),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      formatMoney(item.actual),
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: AppType.rowValue.copyWith(color: tokens.text),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
