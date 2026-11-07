import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/models/finance_models.dart';
import '../../core/network/api_exception.dart';
import '../../core/utils/formatters.dart';
import '../../shared/widgets/app_buttons.dart';
import '../../theme/app_theme.dart';
import 'finance_bill_form_page.dart';
import 'finance_repay_sheet.dart';
import 'finance_status_widgets.dart';

/// 详情层返回值：编辑（由列表页跳转表单）、已删除或还款后有变更（列表页直接刷新）。
enum BillDetailAction { edit, deleted, changed }

/// 账单详情层：三个 Tab 的列表项点按后先看完整字段，再决定是否编辑/删除。
///
/// 关闭后列表页仍保持原滚动位置（详情以模态底部弹层呈现，不压栈替换列表）。
class FinanceBillDetailSheet extends StatefulWidget {
  const FinanceBillDetailSheet({
    super.key,
    required this.kind,
    this.bill,
    this.housing,
    this.utility,
    this.subscription,
    this.platformName,
    this.housingName,
  });

  final BillKind kind;

  /// 网贷账单（kind == loan 时必传）。
  final BillItem? bill;

  /// 住房记录（kind == housing 时必传）。
  final HousingItem? housing;

  /// 水电记录（kind == utility 时必传）。
  final UtilityItem? utility;

  /// 订阅记录（kind == subscription 时必传）。
  final SubscriptionItem? subscription;

  /// 网贷平台名称（仅展示用）。
  final String? platformName;

  /// 水电记录所属住房名称（仅展示用）。
  final String? housingName;

  @override
  State<FinanceBillDetailSheet> createState() => _FinanceBillDetailSheetState();
}

class _FinanceBillDetailSheetState extends State<FinanceBillDetailSheet> {
  List<BillRepayment> _repayments = const <BillRepayment>[];
  bool _loadingRepayments = false;
  String? _repaymentsError;
  bool _deleting = false;

  /// 网贷账单当前快照：还款后重新拉取，保证已还/剩余/状态实时更新。
  BillItem? _bill;

  /// 本层内是否发生过还款相关变更；关闭时回传，让列表页刷新汇总。
  bool _mutated = false;

  @override
  void initState() {
    super.initState();
    _bill = widget.bill;
    if (widget.kind == BillKind.loan && widget.bill != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _loadRepayments();
        }
      });
    }
  }

  /// 网贷账单的还款记录（列表项本身不含，需要单独取一次）。
  Future<void> _loadRepayments() async {
    final BillItem? bill = _bill;
    if (bill == null) {
      return;
    }
    final AppScope scope = AppScope.of(context);
    setState(() {
      _loadingRepayments = true;
      _repaymentsError = null;
    });
    try {
      final List<dynamic>? data = (await scope.apiClient.get<List<dynamic>>(
        '/finance/repayments',
        queryParameters: <String, dynamic>{'bill_id': bill.id},
      ))
          .data;
      if (!mounted) {
        return;
      }
      setState(() {
        _repayments = (data ?? const <dynamic>[])
            .whereType<Map>()
            .map((Map item) =>
                BillRepayment.fromJson(item.cast<String, dynamic>()))
            .toList(growable: false);
      });
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _repaymentsError = error.message);
    } finally {
      if (mounted) {
        setState(() => _loadingRepayments = false);
      }
    }
  }

  /// 重新拉取账单本体：还款/删除记录后已还、剩余与状态由后端重算。
  Future<void> _reloadBill() async {
    final BillItem? bill = _bill;
    if (bill == null) {
      return;
    }
    try {
      final Map<String, dynamic>? data =
          (await AppScope.of(context).apiClient.get<Map<String, dynamic>>(
        '/finance/loan-bills/${bill.id}',
      ))
              .data;
      if (!mounted || data == null) {
        return;
      }
      setState(() => _bill = BillItem.fromJson(data));
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('账单刷新失败：${error.message}')),
      );
    }
  }

  /// 还款入口：新增或编辑还款记录；成功后刷新账单与记录并标记有变更。
  Future<void> _openRepay({BillRepayment? repayment}) async {
    final BillItem? bill = _bill;
    if (bill == null) {
      return;
    }
    final bool? changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (BuildContext _) =>
          LoanRepaySheet(bill: bill, repayment: repayment),
    );
    if (changed == true && mounted) {
      _mutated = true;
      await Future.wait(<Future<void>>[_reloadBill(), _loadRepayments()]);
    }
  }

  /// 当前记录 id（四类记录共用）。
  int get _id {
    switch (widget.kind) {
      case BillKind.loan:
        return _bill?.id ?? 0;
      case BillKind.housing:
        return widget.housing?.id ?? 0;
      case BillKind.utility:
        return widget.utility?.id ?? 0;
      case BillKind.subscription:
        return widget.subscription?.id ?? 0;
    }
  }

  /// 与网页端同源的资源路径。
  String get _resource {
    switch (widget.kind) {
      case BillKind.loan:
        return '/finance/loan-bills';
      case BillKind.housing:
        return '/finance/housing';
      case BillKind.utility:
        return '/finance/utilities';
      case BillKind.subscription:
        return '/finance/subscriptions';
    }
  }

  /// 记录类型短名（用于删除提示与标题）。
  String get _kindLabel {
    switch (widget.kind) {
      case BillKind.loan:
        return '网贷账单';
      case BillKind.housing:
        return '住房记录';
      case BillKind.utility:
        return '水电缴费记录';
      case BillKind.subscription:
        return '订阅';
    }
  }

  /// 详情层标题：优先可识别名称。
  String get _title {
    switch (widget.kind) {
      case BillKind.loan:
        final String name = (widget.platformName ?? '').trim();
        return name.isEmpty ? '网贷账单 #$_id' : name;
      case BillKind.housing:
        return widget.housing?.name ?? '住房记录';
      case BillKind.utility:
        final UtilityItem? item = widget.utility;
        return item == null ? '水电缴费记录' : '${_shortMonth(item.billMonth)} · ${_feeTypeLabel(item.feeType)}';
      case BillKind.subscription:
        final SubscriptionItem? item = widget.subscription;
        if (item == null) {
          return '订阅';
        }
        final String plan = (item.planName ?? '').trim();
        return plan.isEmpty ? item.name : '${item.name} · $plan';
    }
  }

  /// 详情层副标题：记录类型的稳定说明，避免标题歧义。
  String get _subtitle => _kindLabel;

  /// 删除确认文案：写清删的是哪条、影响什么、能否恢复。
  String get _deleteDescription {
    switch (widget.kind) {
      case BillKind.loan:
        final BillItem? bill = _bill;
        return '将删除 ${_shortMonth(bill?.billMonth ?? '')} 的网贷账单'
            '（应还 ${formatMoney(bill?.amount ?? 0)}），'
            '不会删除平台资料。删除后无法恢复。';
      case BillKind.housing:
        return '将删除住房「${widget.housing?.name ?? ''}」及其租房信息，'
            '不会自动删除关联的水电缴费记录。删除后无法恢复。';
      case BillKind.utility:
        final UtilityItem? item = widget.utility;
        return '将删除 ${_shortMonth(item?.billMonth ?? '')} 的'
            '${_feeTypeLabel(item?.feeType ?? '')}记录'
            '（${formatMoney(item?.amount ?? 0)}）。删除后无法恢复。';
      case BillKind.subscription:
        return '将删除订阅「${widget.subscription?.name ?? ''}」，'
            '不影响已发生的账单记录。删除后无法恢复。';
    }
  }

  /// 编辑：关闭详情层并把「去编辑」意图交回列表页，由列表页压栈表单。
  void _edit() {
    Navigator.of(context).pop(BillDetailAction.edit);
  }

  /// 删除：二次确认 → 在线 DELETE → 关闭详情层并回传「已删除」。
  Future<void> _delete() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text('删除$_kindLabel？'),
          content: Text(_deleteDescription),
          actions: <Widget>[
            AppActionRow(
              first: AppSecondaryButton(
                label: '取消',
                compact: true,
                onPressed: () => Navigator.of(dialogContext).pop(false),
              ),
              second: AppDangerButton(
                label: '删除',
                compact: true,
                onPressed: () => Navigator.of(dialogContext).pop(true),
              ),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) {
      return;
    }
    final AppScope scope = AppScope.of(context);
    final NavigatorState navigator = Navigator.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    setState(() => _deleting = true);
    try {
      await scope.apiClient.delete<dynamic>('$_resource/$_id');
      if (!mounted) {
        return;
      }
      navigator.pop(BillDetailAction.deleted);
      messenger.showSnackBar(SnackBar(content: Text('已删除$_kindLabel')));
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _deleting = false);
      messenger.showSnackBar(SnackBar(content: Text('删除失败：${error.message}')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color muted = theme.colorScheme.onSurfaceVariant;
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.86,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 12,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 2,
                      children: <Widget>[
                        Text(_title, style: theme.textTheme.titleMedium),
                        Text(
                          _subtitle,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: muted),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(
                      _mutated ? BillDetailAction.changed : null,
                    ),
                    tooltip: '关闭',
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              _statusChips(),
              ..._fieldRows(theme, muted),
              if (widget.kind == BillKind.loan) ..._repaymentSection(theme, muted),
              if (widget.kind == BillKind.loan &&
                  (_bill?.status != 'cleared' || (_bill?.remaining ?? 0) > 0) &&
                  _bill != null) ...<Widget>[
                const SizedBox(height: 4),
                AppPrimaryButton(
                  label: '还款',
                  icon: Icons.payments_outlined,
                  onPressed: _deleting ? null : _openRepay,
                ),
              ],
              const SizedBox(height: 4),
              AppActionRow(
                first: AppPrimaryButton(
                  label: '编辑',
                  icon: Icons.edit_outlined,
                  onPressed: _deleting ? null : _edit,
                ),
                second: AppDangerButton(
                  label: '删除',
                  loading: _deleting,
                  onPressed: _delete,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 状态芯片：按类型展示可一眼判断的字段。
  Widget _statusChips() {
    final List<Widget> chips = <Widget>[];
    switch (widget.kind) {
      case BillKind.loan:
        final BillItem? bill = _bill;
        if (bill != null) {
          chips.add(StatusChip(
            label: billStatusLabel(bill.status),
            tone: billTone(bill.status),
          ));
          if (bill.overdue) {
            chips.add(const StatusChip(
              label: '已逾期',
              tone: StatusTone.danger,
            ));
          }
        }
      case BillKind.utility:
        final bool paid = widget.utility?.paid ?? false;
        chips.add(StatusChip(
          label: paid ? '已缴费' : '未缴费',
          tone: paid ? StatusTone.success : StatusTone.warning,
        ));
      case BillKind.subscription:
        final SubscriptionItem? item = widget.subscription;
        if (item != null) {
          chips.add(StatusChip(
            label: item.statusLabel,
            tone: item.status == 'active'
                ? StatusTone.success
                : StatusTone.info,
          ));
        }
      case BillKind.housing:
        break;
    }
    if (chips.isEmpty) {
      return const SizedBox.shrink();
    }
    return Wrap(spacing: 8, runSpacing: 8, children: chips);
  }

  /// 按记录类型输出完整字段（字段名与后端 / 网页端一致）。
  List<Widget> _fieldRows(ThemeData theme, Color muted) {
    final List<({String label, String value, Color? color})> rows;
    switch (widget.kind) {
      case BillKind.loan:
        final BillItem? bill = _bill;
        if (bill == null) {
          rows = const <({String label, String value, Color? color})>[];
        } else {
          rows = <({String label, String value, Color? color})>[
            (label: '账单月份', value: _shortMonth(bill.billMonth), color: null),
            (label: '到期日', value: _opt(bill.dueDate), color: null),
            (label: '应还金额', value: formatMoney(bill.amount), color: null),
            (label: '已还金额', value: formatMoney(bill.paidAmount), color: null),
            (
              label: '待还金额',
              value: formatMoney(bill.remaining),
              color: bill.remaining > 0
                  ? context.semanticColors.danger
                  : context.semanticColors.success,
            ),
            (label: '利息', value: formatMoney(bill.interest), color: null),
            (
              label: '容时服务',
              value: bill.graceApplied ? '已申请（固定顺延 3 天）' : '未申请',
              color: null,
            ),
            (label: '备注', value: _opt(bill.note), color: null),
          ];
        }
      case BillKind.housing:
        final HousingItem? item = widget.housing;
        if (item == null) {
          rows = const <({String label, String value, Color? color})>[];
        } else {
          rows = <({String label, String value, Color? color})>[
            (label: '显示缩写', value: _opt(item.shortName), color: null),
            (label: '租房渠道', value: _opt(item.channel), color: null),
            (label: '房屋朝向', value: _opt(item.orientation), color: null),
            (label: '入住日期', value: _opt(item.moveInDate), color: null),
            (label: '退租日期', value: _opt(item.moveOutDate), color: null),
            (label: '付款期次', value: item.rentTermLabel, color: null),
            (
              label: '实际月租',
              value: formatMoney(item.actualMonthlyRent),
              color: null,
            ),
            (label: '押金', value: formatMoney(item.deposit), color: null),
            (
              label: '已扣押金',
              value: formatMoney(item.depositRefunded),
              color: null,
            ),
            (
              label: '押金退还渠道',
              value: _opt(item.depositRefundChannel),
              color: null,
            ),
            (label: '中介费', value: formatMoney(item.agentFee), color: null),
            (label: '保洁费', value: formatMoney(item.cleanFee), color: null),
            (label: '服务费', value: formatMoney(item.serviceFee), color: null),
            (label: '洗衣费', value: formatMoney(item.laundryFee), color: null),
            (label: '备注', value: _opt(item.note), color: null),
          ];
        }
      case BillKind.utility:
        final UtilityItem? item = widget.utility;
        if (item == null) {
          rows = const <({String label, String value, Color? color})>[];
        } else {
          rows = <({String label, String value, Color? color})>[
            (label: '所属住房', value: _opt(widget.housingName), color: null),
            (label: '账单月份', value: _shortMonth(item.billMonth), color: null),
            (label: '费用类型', value: _feeTypeLabel(item.feeType), color: null),
            (label: '金额', value: formatMoney(item.amount), color: null),
            (label: '到期日', value: _opt(item.dueDate), color: null),
            (label: '缴费状态', value: item.paid ? '已缴费' : '未缴费', color: null),
            (label: '备注', value: _opt(item.note), color: null),
          ];
        }
      case BillKind.subscription:
        final SubscriptionItem? item = widget.subscription;
        if (item == null) {
          rows = const <({String label, String value, Color? color})>[];
        } else {
          rows = <({String label, String value, Color? color})>[
            (label: '方案名称', value: _opt(item.planName), color: null),
            (label: '分类', value: _opt(item.category), color: null),
            (label: '计费周期', value: item.billingCycleLabel, color: null),
            (label: '每期金额', value: formatMoney(item.amount), color: null),
            (label: '开通日期', value: _opt(item.startDate), color: null),
            (label: '到期日期', value: _opt(item.endDate), color: null),
            (label: '自动续费', value: item.autoRenew ? '开启' : '关闭', color: null),
            (label: '状态', value: item.statusLabel, color: null),
            (label: '备注', value: _opt(item.note), color: null),
          ];
        }
    }
    return <Widget>[
      for (final ({String label, String value, Color? color}) row in rows)
        _SheetRow(label: row.label, value: row.value, valueColor: row.color),
      if (rows.isEmpty)
        Text('没有可展示的字段', style: theme.textTheme.bodySmall?.copyWith(
          color: muted,
        )),
    ];
  }

  /// 网贷账单的还款记录（其余类型不展示该区块）。
  List<Widget> _repaymentSection(ThemeData theme, Color muted) {
    return <Widget>[
      const Divider(height: 20),
      Row(
        children: <Widget>[
          Expanded(
            child: Text('还款记录', style: theme.textTheme.titleSmall),
          ),
          if (_loadingRepayments)
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Text(
              '${_repayments.length} 笔',
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
        ],
      ),
      if (_repaymentsError != null)
        Text(
          '还款记录加载失败：$_repaymentsError',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.error,
          ),
        )
      else if (!_loadingRepayments && _repayments.isEmpty)
        Text('暂无还款记录', style: theme.textTheme.bodySmall?.copyWith(color: muted)),
      for (final BillRepayment item in _repayments)
        InkWell(
          onTap: _deleting ? null : () => _openRepay(repayment: item),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              spacing: 8,
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 2,
                    children: <Widget>[
                      Text(item.repayDate, style: theme.textTheme.bodyMedium),
                      if (item.discount > 0 || item.method != null || item.note != null)
                        Text(
                          <String>[
                            if (item.discount > 0)
                              '优惠 ${formatMoney(item.discount)}',
                            if (item.method != null &&
                                item.method!.trim().isNotEmpty)
                              item.method!,
                            if (item.note != null && item.note!.isNotEmpty)
                              item.note!,
                          ].join(' · '),
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: muted),
                        ),
                    ],
                  ),
                ),
                Text(
                  formatMoney(item.actual),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontFeatures: const <FontFeature>[
                      FontFeature.tabularFigures(),
                    ],
                  ),
                ),
                const Icon(Icons.edit_outlined, size: 16),
              ],
            ),
          ),
        ),
    ];
  }

  /// `yyyy-MM-dd` → `yyyy-MM`。
  static String _shortMonth(String value) {
    return value.length >= 7 ? value.substring(0, 7) : (value.isEmpty ? '—' : value);
  }

  /// 空值统一显示为「—」。
  static String _opt(String? value) {
    final String text = (value ?? '').trim();
    return text.isEmpty ? '—' : text;
  }

  /// 水电费用类型文案（与网页端一致）。
  static String _feeTypeLabel(String value) {
    switch (value) {
      case 'water':
        return '水费';
      case 'gas':
        return '燃气费';
      case 'property':
        return '物业费';
      case 'broadband':
        return '宽带费';
      case 'other':
        return '其他';
      default:
        return '电费';
    }
  }
}

/// 详情字段行：左标签右值（值可带语义色），长值右对齐换行。
class _SheetRow extends StatelessWidget {
  const _SheetRow({required this.label, required this.value, this.valueColor});

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
