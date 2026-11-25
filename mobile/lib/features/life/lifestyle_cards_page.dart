import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_scope.dart';
import '../../core/data/overview_controller.dart';
import '../../core/models/lifestyle_models.dart';
import '../../core/network/api_exception.dart';
import '../../core/utils/formatters.dart';
import '../../shared/widgets/app_buttons.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/list_load_more_footer.dart';
import '../../shared/widgets/root_page_scaffold.dart';
import '../../shared/widgets/section_status.dart';
import '../../shared/widgets/v2/stat_rail.dart';
import '../../shared/widgets/v2/v2_page_kit.dart';
import '../../shared/widgets/v2/v2_rows.dart';
import '../../shared/widgets/v2/v2_segmented.dart';
import '../../theme/app_tokens.dart';
import 'card_form_page.dart';

/// 卡片管理：概览摘要 + 手机号卡 / 银行卡 / 运营商 / 卡账单四个内嵌栏目。
///
/// 数据（与网页端 `pages/lifestyle/cards.tsx` 一致）：
/// - `GET /lifestyle/bank-cards?page=&page_size=20`
/// - `GET /lifestyle/bank-cards/stats?days=30`
/// - `GET /lifestyle/phone-cards?page=&page_size=100`（只读，一次性加载）
///
/// 四个栏目使用独立 `ListView`（`IndexedStack` 常驻），切换时不跳转、各自保留
/// 滚动位置；新增入口放在各栏目标题右侧，避免四个栏目共用一个悬浮按钮。
class LifestyleCardsPage extends StatefulWidget {
  const LifestyleCardsPage({super.key});

  @override
  State<LifestyleCardsPage> createState() => _LifestyleCardsPageState();
}

class _LifestyleCardsPageState extends State<LifestyleCardsPage> {
  final List<BankCard> _cards = <BankCard>[];
  final List<PhoneCard> _phones = <PhoneCard>[];
  final List<Carrier> _carriers = <Carrier>[];
  final List<CardBill> _cardBills = <CardBill>[];

  BankStats? _stats;
  int _carrierTotal = 0;
  int _cardBillTotal = 0;

  /// 手机号卡余额合计与本月已扣：来自 `/lifestyle/phone-cards/stats`，
  /// 与银行卡口径分开统计，摘要区按当前栏目展示对应口径。
  double _phoneBalanceTotal = 0;
  double _phoneMonthDeduct = 0;
  LoadStatus _status = LoadStatus.loading;
  String? _message;

  /// 当前栏目：0 = 手机号卡，1 = 银行卡，2 = 运营商，3 = 卡账单。
  int _tab = 0;

  int _page = 1;
  int _total = 0;
  bool _hasMore = true;
  bool _loadingMore = false;

  /// 手机号卡流水：按卡片懒加载，展开状态与缓存都放在页面级，便于操作后统一失效。
  final Map<int, List<PhoneLedgerEntry>> _ledgers =
      <int, List<PhoneLedgerEntry>>{};
  final Set<int> _ledgerOpen = <int>{};
  int? _ledgerLoadingId;
  int? _deductingId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _refresh();
      }
    });
  }

  /// 首屏 / 重试：并行拉汇总、第一页银行卡与全部手机号卡。
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
      _status = _stats == null ? LoadStatus.loading : LoadStatus.ready;
      _message = null;
    });
    try {
      final Future<Object?> statsFuture = scope.apiClient
          .get<Map<String, dynamic>>('/lifestyle/bank-cards/stats',
              queryParameters: <String, dynamic>{'days': 30})
          .then((value) => value.data);
      final Future<Object?> listFuture = scope.apiClient
          .get<Map<String, dynamic>>('/lifestyle/bank-cards',
              queryParameters: <String, dynamic>{'page': 1, 'page_size': 20})
          .then((value) => value.data);
      // 手机号卡是只读附属区块：失败时隐藏区块，不阻塞银行卡分页。
      final Future<Map<String, dynamic>?> phoneFuture = scope.apiClient
          .get<Map<String, dynamic>>('/lifestyle/phone-cards',
              queryParameters: <String, dynamic>{'page': 1, 'page_size': 100})
          .then((value) => value.data)
          .catchError((Object _) => null);
      // 手机号卡汇总（余额合计 / 本月已扣）：与银行卡统计分开，摘要区按 Tab 取用。
      final Future<Map<String, dynamic>?> phoneStatsFuture = scope.apiClient
          .get<Map<String, dynamic>>('/lifestyle/phone-cards/stats',
              queryParameters: <String, dynamic>{'days': 30})
          .then((value) => value.data)
          .catchError((Object _) => null);
      // 运营商 / 卡账单为附属字典：失败时保留空表，不阻塞主列表。
      final Future<Map<String, dynamic>?> carrierFuture = scope.apiClient
          .get<Map<String, dynamic>>('/lifestyle/carriers',
              queryParameters: <String, dynamic>{'page': 1, 'page_size': 100})
          .then((value) => value.data)
          .catchError((Object _) => null);
      final Future<Map<String, dynamic>?> billFuture = scope.apiClient
          .get<Map<String, dynamic>>('/lifestyle/card-bills',
              queryParameters: <String, dynamic>{'page': 1, 'page_size': 100})
          .then((value) => value.data)
          .catchError((Object _) => null);
      final List<Object?> responses = await Future.wait<Object?>(
        <Future<Object?>>[
          statsFuture,
          listFuture,
          phoneFuture,
          carrierFuture,
          billFuture,
          phoneStatsFuture,
        ],
      );
      final Map<String, dynamic>? statsJson =
          responses[0] as Map<String, dynamic>?;
      final Map<String, dynamic>? listJson =
          responses[1] as Map<String, dynamic>?;
      final Map<String, dynamic>? phoneJson =
          responses[2] as Map<String, dynamic>?;
      final Map<String, dynamic>? carrierJson =
          responses[3] as Map<String, dynamic>?;
      final Map<String, dynamic>? billJson =
          responses[4] as Map<String, dynamic>?;
      final Map<String, dynamic>? phoneStatsJson =
          responses[5] as Map<String, dynamic>?;
      if (statsJson == null || listJson == null) {
        throw const ApiException(
          kind: ApiErrorKind.badResponse,
          message: '卡片接口返回数据为空',
        );
      }
      final List<BankCard> cards = _parseCards(listJson);
      final List<PhoneCard> phones = ((phoneJson?['items'] as List?) ??
              const <dynamic>[])
          .whereType<Map>()
          .map((Map item) => PhoneCard.fromJson(item.cast<String, dynamic>()))
          .toList();
      final List<Carrier> carriers = ((carrierJson?['items'] as List?) ??
              const <dynamic>[])
          .whereType<Map>()
          .map((Map item) => Carrier.fromJson(item.cast<String, dynamic>()))
          .toList();
      final List<CardBill> bills = ((billJson?['items'] as List?) ??
              const <dynamic>[])
          .whereType<Map>()
          .map((Map item) => CardBill.fromJson(item.cast<String, dynamic>()))
          .toList();
      if (!mounted) {
        return;
      }
      setState(() {
        _stats = BankStats.fromJson(statsJson);
        _cards
          ..clear()
          ..addAll(cards);
        _phones
          ..clear()
          ..addAll(phones);
        _carriers
          ..clear()
          ..addAll(carriers);
        _cardBills
          ..clear()
          ..addAll(bills);
        _phoneBalanceTotal =
            (phoneStatsJson?['balance_total'] as num?)?.toDouble() ?? 0;
        _phoneMonthDeduct =
            (phoneStatsJson?['month_deduct'] as num?)?.toDouble() ?? 0;
        _carrierTotal =
            (carrierJson?['total'] as num?)?.toInt() ?? carriers.length;
        _cardBillTotal =
            (billJson?['total'] as num?)?.toInt() ?? bills.length;
        _page = 1;
        _total = (listJson['total'] as num?)?.toInt() ?? cards.length;
        _hasMore = _cards.length < _total;
        _status = LoadStatus.ready;
      });
      // 与网页端一致：进入卡片页后幂等补齐手机号卡本月应扣；有扣费时再刷新余额。
      unawaited(_settlePhones());
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _status = _errorStatus(scope, error);
        _message = error.message;
      });
    }
  }

  /// 加载更多：追加下一页银行卡（只影响银行卡栏目）。
  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) {
      return;
    }
    final AppScope scope = AppScope.of(context);
    setState(() => _loadingMore = true);
    try {
      final Map<String, dynamic>? json = (await scope.apiClient
              .get<Map<String, dynamic>>('/lifestyle/bank-cards',
                  queryParameters: <String, dynamic>{
            'page': _page + 1,
            'page_size': 20,
          }))
          .data;
      if (json == null) {
        throw const ApiException(
          kind: ApiErrorKind.badResponse,
          message: '接口返回数据为空',
        );
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _page += 1;
        _cards.addAll(_parseCards(json));
        _total = (json['total'] as num?)?.toInt() ?? _cards.length;
        _hasMore = _cards.length < _total;
      });
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('加载更多失败：${error.message}')),
      );
    } finally {
      if (mounted) {
        setState(() => _loadingMore = false);
      }
    }
  }

  /// 分页响应 `items` → [BankCard]。
  List<BankCard> _parseCards(Map<String, dynamic> json) {
    return ((json['items'] as List?) ?? const <dynamic>[])
        .whereType<Map>()
        .map((Map item) => BankCard.fromJson(item.cast<String, dynamic>()))
        .toList();
  }

  /// 列表页错误分流：未登录 / 已保留登录态的连接失败 / 普通失败。
  LoadStatus _errorStatus(AppScope scope, ApiException error) {
    if (error.isUnauthorized) {
      return LoadStatus.unauthenticated;
    }
    final bool offline = scope.auth.hasLocalSession &&
        (error.kind == ApiErrorKind.network ||
            error.kind == ApiErrorKind.timeout);
    return offline ? LoadStatus.connectionFailed : LoadStatus.failed;
  }

  /// 复制纯号码：写入剪贴板并给出轻提示；缺号时提示去网页端补录。
  Future<void> _copyNumber(String label, String? number) async {
    if (number == null || number.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('这张卡没有填写号码，无法复制')),
      );
      return;
    }
    await Clipboard.setData(ClipboardData(text: number));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已复制$label')),
    );
  }

  /// 幂等结算手机号卡本月应扣；失败静默（不阻塞列表），有实际扣费时刷新余额。
  Future<void> _settlePhones() async {
    final AppScope scope = AppScope.of(context);
    try {
      final Map<String, dynamic>? json =
          (await scope.apiClient.post<Map<String, dynamic>>(
            '/lifestyle/phone-cards/settle',
          )).data;
      final int charges = (json?['charges'] as num?)?.toInt() ?? 0;
      if (charges > 0 && mounted) {
        await _refreshPhones();
      }
    } on ApiException {
      // 结算失败（如只读会话）不影响列表展示。
    }
  }

  /// 只刷新手机号卡列表：保留银行卡分页位置，同时失效流水缓存。
  Future<void> _refreshPhones() async {
    final AppScope scope = AppScope.of(context);
    try {
      final Map<String, dynamic>? json =
          (await scope.apiClient.get<Map<String, dynamic>>(
            '/lifestyle/phone-cards',
            queryParameters: <String, dynamic>{'page': 1, 'page_size': 100},
          )).data;
      if (json == null || !mounted) {
        return;
      }
      final List<PhoneCard> phones = ((json['items'] as List?) ??
              const <dynamic>[])
          .whereType<Map>()
          .map((Map item) => PhoneCard.fromJson(item.cast<String, dynamic>()))
          .toList();
      setState(() {
        _phones
          ..clear()
          ..addAll(phones);
        _ledgers.clear();
        _ledgerOpen.clear();
        _ledgerLoadingId = null;
      });
    } on ApiException {
      // 后台刷新失败保持旧数据，不打断用户。
    }
  }

  /// 打开充值页；保存成功后重拉列表，余额由后端流水派生。
  Future<void> _openRecharge(PhoneCard card) async {
    final bool? changed = await context.push<bool>(
      '/life/cards/phone/${card.id}/recharge',
      extra: card,
    );
    if (changed == true && mounted) {
      await _refresh();
    }
  }

  /// 打开校准页；保存成功后重拉列表。
  Future<void> _openAdjust(PhoneCard card) async {
    final bool? changed = await context.push<bool>(
      '/life/cards/phone/${card.id}/adjust',
      extra: card,
    );
    if (changed == true && mounted) {
      await _refresh();
    }
  }

  /// 打开新增 / 编辑表单；保存成功后整体刷新（派生余额可能变化）。
  Future<void> _openCardForm(
    CardKind kind, {
    int? id,
    PhoneCard? phone,
    BankCard? bank,
    Carrier? carrier,
    CardBill? bill,
  }) async {
    final Object? extra = phone ?? bank ?? carrier ?? bill;
    final bool? changed = await context.push<bool>(
      id == null
          ? '/life/cards/form/${kind.name}'
          : '/life/cards/form/${kind.name}?id=$id',
      extra: extra,
    );
    if (changed == true && mounted) {
      await _refresh();
    }
  }

  /// 删除卡片 / 字典：二次确认写明影响，成功后整体刷新。
  Future<void> _deleteCard(
    CardKind kind,
    int id,
    String label,
    String impact,
  ) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('删除「$label」？'),
          content: Text('$impact\n删除后无法恢复。'),
          actions: <Widget>[
            AppActionRow(
              first: AppSecondaryButton(
                label: '取消',
                compact: true,
                onPressed: () => Navigator.of(context).pop(false),
              ),
              second: AppDangerButton(
                label: '删除',
                compact: true,
                onPressed: () => Navigator.of(context).pop(true),
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
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final String path = switch (kind) {
      CardKind.phone => '/lifestyle/phone-cards',
      CardKind.bank => '/lifestyle/bank-cards',
      CardKind.carrier => '/lifestyle/carriers',
      CardKind.bill => '/lifestyle/card-bills',
    };
    try {
      await scope.apiClient.delete<dynamic>('$path/$id');
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(SnackBar(content: Text('已删除「$label」')));
      await _refresh();
    } on ApiException catch (error) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text('删除失败：${error.message}')));
      }
    }
  }

  /// 手机号卡菜单：编辑 / 删除。
  Future<void> _editPhone(PhoneCard phone) {
    return _openCardForm(CardKind.phone, id: phone.id, phone: phone);
  }

  /// 删除手机号卡：后端会级联清理流水与月度扣账账单。
  Future<void> _deletePhone(PhoneCard phone) {
    return _deleteCard(
      CardKind.phone,
      phone.id,
      phone.phoneNumber,
      '该卡的余额流水与月度扣账账单会一并删除，卡片合计余额会同步回退。',
    );
  }

  /// 银行卡菜单：编辑。
  Future<void> _editBank(BankCard card) {
    return _openCardForm(CardKind.bank, id: card.id, bank: card);
  }

  /// 删除银行卡：余额与额度不再计入合计。
  Future<void> _deleteBank(BankCard card) {
    return _deleteCard(
      CardKind.bank,
      card.id,
      '${card.bank} · ${card.cardName}',
      '该卡的余额与信用额度会从合计中移除。',
    );
  }

  /// 运营商菜单：编辑。
  Future<void> _editCarrier(Carrier carrier) {
    return _openCardForm(CardKind.carrier, id: carrier.id, carrier: carrier);
  }

  /// 删除运营商：已保存号卡的运营商文本不受影响。
  Future<void> _deleteCarrier(Carrier carrier) {
    return _deleteCard(
      CardKind.carrier,
      carrier.id,
      carrier.name,
      '已保存的手机号卡仍保留原运营商文本，仅后续新增时不再出现该选项。',
    );
  }

  /// 卡账单菜单：编辑。
  Future<void> _editBill(CardBill bill) {
    return _openCardForm(CardKind.bill, id: bill.id, bill: bill);
  }

  /// 删除卡账单：该月扣账记录移除，余额由后端重新派生。
  Future<void> _deleteBill(CardBill bill) {
    return _deleteCard(
      CardKind.bill,
      bill.id,
      '${bill.monthText} · ${formatMoney(bill.amount)}',
      '该月扣账记录会从账单与余额口径中移除。',
    );
  }

  /// 手动补扣本月：幂等写操作，成功后立即刷新余额。
  Future<void> _deduct(PhoneCard card) async {
    if (_deductingId != null) {
      return;
    }
    final AppScope scope = AppScope.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    if (!scope.connectivity.isOnline) {
      messenger.showSnackBar(
        const SnackBar(content: Text('当前无网络：扣费需要联网，请恢复网络后重试')),
      );
      return;
    }
    setState(() => _deductingId = card.id);
    try {
      await scope.apiClient.post<Map<String, dynamic>>(
        '/lifestyle/phone-cards/${card.id}/deduct',
      );
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(
        const SnackBar(content: Text('已补齐本月应扣，余额已刷新')),
      );
      await _refresh();
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(SnackBar(content: Text('扣费失败：${error.message}')));
    } finally {
      if (mounted) {
        setState(() => _deductingId = null);
      }
    }
  }

  /// 展开 / 收起某张卡的最近流水；展开时按需拉取最近 5 条。
  Future<void> _toggleLedger(PhoneCard card) async {
    if (_ledgerOpen.contains(card.id)) {
      setState(() => _ledgerOpen.remove(card.id));
      return;
    }
    final AppScope scope = AppScope.of(context);
    setState(() {
      _ledgerOpen.add(card.id);
      _ledgerLoadingId = card.id;
    });
    try {
      final List<dynamic>? data =
          (await scope.apiClient.get<List<dynamic>>(
            '/lifestyle/phone-cards/${card.id}/ledger',
            queryParameters: <String, dynamic>{'limit': 5},
          )).data;
      if (!mounted) {
        return;
      }
      setState(() {
        _ledgers[card.id] = (data ?? const <dynamic>[])
            .whereType<Map>()
            .map(
              (Map item) =>
                  PhoneLedgerEntry.fromJson(item.cast<String, dynamic>()),
            )
            .toList();
        _ledgerLoadingId = null;
      });
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _ledgerOpen.remove(card.id);
        _ledgerLoadingId = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('加载流水失败：${error.message}')),
      );
    }
  }

  /// 摘要区按当前栏目展示对应口径，避免在「手机号」Tab 下看到银行卡余额合计。
  ///
  /// [stats] 为银行卡统计；手机号卡余额与本月扣账来自独立统计接口。
  SummaryStrip _buildSummary(BankStats stats) {
    final int phoneCount = _phones.length;
    switch (_tab) {
      case 1:
        return SummaryStrip(
          caption: '余额与信用额度仅统计银行卡，不含手机号卡',
          items: <StatRailItem>[
            StatRailItem(label: '银行卡', value: formatInt(stats.total), unit: '张'),
            StatRailItem(label: '卡内余额合计', value: formatMoney(stats.balanceTotal)),
            StatRailItem(label: '信用额度', value: formatMoney(stats.creditTotal)),
          ],
        );
      case 2:
        return SummaryStrip(
          caption: '运营商平台用于手机号卡归属',
          items: <StatRailItem>[
            StatRailItem(label: '运营商', value: formatInt(_carrierTotal), unit: '家'),
            StatRailItem(label: '手机号卡', value: formatInt(phoneCount), unit: '张'),
            StatRailItem(label: '银行卡', value: formatInt(stats.total), unit: '张'),
          ],
        );
      case 3:
        return SummaryStrip(
          caption: '卡账单按月记录，支持新增与编辑',
          items: <StatRailItem>[
            StatRailItem(
              label: '卡账单',
              value: formatInt(_cardBillTotal),
              unit: '条',
            ),
            StatRailItem(label: '本月扣账', value: formatMoney(_phoneMonthDeduct)),
            StatRailItem(label: '手机号卡', value: formatInt(phoneCount), unit: '张'),
          ],
        );
      default:
        return SummaryStrip(
          caption: '余额由充值 / 扣费 / 校准流水自动汇总',
          items: <StatRailItem>[
            StatRailItem(label: '手机号卡', value: formatInt(phoneCount), unit: '张'),
            StatRailItem(label: '手机卡余额合计', value: formatMoney(_phoneBalanceTotal)),
            StatRailItem(label: '本月已扣', value: formatMoney(_phoneMonthDeduct)),
          ],
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final BankStats? stats = _stats;
    return DetailPageScaffold(
      title: '卡片管理',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: <Widget>[
          if (stats == null)
            Expanded(
              child: ListPageBody(
                status: _status,
                message: _message,
                onRetry: _refresh,
              ),
            )
          else ...<Widget>[
            // 刷新失败但仍有旧数据：保留内容，顶部提示可重试。
            if (_status != LoadStatus.ready && _status != LoadStatus.idle)
              OverviewStatusBanner(
                status: _status,
                message: _message,
                onRetry: _refresh,
              ),
            _buildSummary(stats),
            V2Segmented<int>(
              options: const <V2SegmentedOption<int>>[
                V2SegmentedOption<int>(label: '手机号', value: 0),
                V2SegmentedOption<int>(label: '银行卡', value: 1),
                V2SegmentedOption<int>(label: '运营商', value: 2),
                V2SegmentedOption<int>(label: '卡账单', value: 3),
              ],
              selected: _tab,
              onChanged: (int index) => setState(() => _tab = index),
            ),
            Expanded(
              child: IndexedStack(
                index: _tab,
                children: <Widget>[
                  _PhoneTab(
                    phones: _phones,
                    onCopy: (PhoneCard phone) => _copyNumber(
                      '手机号',
                      phone.copyableNumber,
                    ),
                    onRecharge: _openRecharge,
                    onAdjust: _openAdjust,
                    onDeduct: _deduct,
                    onCreate: () => _openCardForm(CardKind.phone),
                    onEdit: _editPhone,
                    onDelete: _deletePhone,
                    deductingId: _deductingId,
                    expandedIds: _ledgerOpen,
                    ledgers: _ledgers,
                    loadingLedgerId: _ledgerLoadingId,
                    onToggleLedger: _toggleLedger,
                  ),
                  _BankTab(
                    cards: _cards,
                    total: _total,
                    loadingMore: _loadingMore,
                    hasMore: _hasMore,
                    onLoadMore: _loadMore,
                    onCopy: (BankCard card) => _copyNumber(
                      '卡号',
                      card.copyableNumber,
                    ),
                    onCreate: () => _openCardForm(CardKind.bank),
                    onEdit: _editBank,
                    onDelete: _deleteBank,
                  ),
                  _CarrierTab(
                    carriers: _carriers,
                    total: _carrierTotal,
                    onCreate: () => _openCardForm(CardKind.carrier),
                    onEdit: _editCarrier,
                    onDelete: _deleteCarrier,
                  ),
                  _BillTab(
                    bills: _cardBills,
                    phones: _phones,
                    total: _cardBillTotal,
                    onCreate: () => _openCardForm(CardKind.bill),
                    onEdit: _editBill,
                    onDelete: _deleteBill,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 手机号卡栏目：独立滚动，切换不重置位置；每张卡提供充值 / 扣费 / 校准与最近流水。
class _PhoneTab extends StatelessWidget {
  const _PhoneTab({
    required this.phones,
    required this.onCopy,
    required this.onRecharge,
    required this.onAdjust,
    required this.onDeduct,
    required this.onCreate,
    required this.onEdit,
    required this.onDelete,
    required this.deductingId,
    required this.expandedIds,
    required this.ledgers,
    required this.loadingLedgerId,
    required this.onToggleLedger,
  });

  final List<PhoneCard> phones;
  final ValueChanged<PhoneCard> onCopy;
  final ValueChanged<PhoneCard> onRecharge;
  final ValueChanged<PhoneCard> onAdjust;
  final ValueChanged<PhoneCard> onDeduct;
  final VoidCallback onCreate;
  final ValueChanged<PhoneCard> onEdit;
  final ValueChanged<PhoneCard> onDelete;

  /// 正在补扣的卡片 id（菜单显示「扣费中…」，防止重复点击）。
  final int? deductingId;
  final Set<int> expandedIds;
  final Map<int, List<PhoneLedgerEntry>> ledgers;
  final int? loadingLedgerId;
  final ValueChanged<PhoneCard> onToggleLedger;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    return ListView(
      key: const PageStorageKey<String>('lifestyle-cards-phone'),
      padding: const EdgeInsets.only(bottom: 16),
      children: <Widget>[
        SectionHeader(
          title: '手机号卡 · 共 ${formatInt(phones.length)} 张',
          actionLabel: '新增',
          onAction: onCreate,
        ),
        GroupCard(
          children: <Widget>[
            if (phones.isEmpty)
              const EmptyState(
                icon: Icons.sim_card_outlined,
                title: '暂无手机号卡',
                description: '点「新增」录入第一张号卡',
                compact: true,
              )
            else
              for (final PhoneCard phone in phones)
                _PhoneCardRow(
                  card: phone,
                  onCopy: () => onCopy(phone),
                  onRecharge: () => onRecharge(phone),
                  onAdjust: () => onAdjust(phone),
                  onDeduct: () => onDeduct(phone),
                  onEdit: () => onEdit(phone),
                  onDelete: () => onDelete(phone),
                  deducting: deductingId == phone.id,
                  onToggleLedger: () => onToggleLedger(phone),
                  ledgerExpanded: expandedIds.contains(phone.id),
                  ledgerLoading: loadingLedgerId == phone.id,
                  ledger: ledgers[phone.id],
                ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          '充值 / 扣费 / 校准直接操作，余额由流水自动更新。',
          textAlign: TextAlign.center,
          style: AppType.rowMeta.copyWith(color: tokens.text3),
        ),
      ],
    );
  }
}

/// 银行卡栏目：独立滚动 + 分页页脚。
class _BankTab extends StatelessWidget {
  const _BankTab({
    required this.cards,
    required this.total,
    required this.loadingMore,
    required this.hasMore,
    required this.onLoadMore,
    required this.onCopy,
    required this.onCreate,
    required this.onEdit,
    required this.onDelete,
  });

  final List<BankCard> cards;
  final int total;
  final bool loadingMore;
  final bool hasMore;
  final VoidCallback onLoadMore;
  final ValueChanged<BankCard> onCopy;
  final VoidCallback onCreate;
  final ValueChanged<BankCard> onEdit;
  final ValueChanged<BankCard> onDelete;

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const PageStorageKey<String>('lifestyle-cards-bank'),
      padding: const EdgeInsets.only(bottom: 16),
      children: <Widget>[
        SectionHeader(
          title: '银行卡 · 共 ${formatInt(total)} 张',
          actionLabel: '新增',
          onAction: onCreate,
        ),
        GroupCard(
          children: <Widget>[
            if (cards.isEmpty)
              const EmptyState(
                icon: Icons.credit_card_outlined,
                title: '暂无银行卡',
                description: '点「新增」录入第一张银行卡',
                compact: true,
              )
            else
              for (final BankCard card in cards)
                _CardRow(
                  card: card,
                  onCopy: () => onCopy(card),
                  onEdit: () => onEdit(card),
                  onDelete: () => onDelete(card),
                ),
          ],
        ),
        if (cards.isNotEmpty)
          ListLoadMoreFooter(
            loading: loadingMore,
            hasMore: hasMore,
            onPressed: onLoadMore,
          ),
      ],
    );
  }
}

/// 号码 + 余额 + 复制按钮的同一行布局。
///
/// - 宽度够：一行展示「号码 · 余额 复制」，文本底部对齐（数字无降部，等同基线）。
/// - 宽度不够（长号码）：余额换到第二行右对齐，号码与复制按钮留在第一行，
///   复制按钮始终固定在行尾同一列（宽 40dp），不随号码长短漂移。
/// - 号码永不截断成省略号，必要时按 4 位分组换行。
class _NumberBalanceRow extends StatelessWidget {
  const _NumberBalanceRow({
    required this.number,
    required this.numberStyle,
    required this.balanceText,
    required this.balanceStyle,
    required this.copyTooltip,
    required this.onCopy,
  });

  final String number;
  final TextStyle? numberStyle;
  final String balanceText;
  final TextStyle? balanceStyle;
  final String copyTooltip;
  final VoidCallback onCopy;

  /// 复制按钮固定宽高：40dp 热区，行尾对齐。
  static const double _copySize = 40;
  static const double _gap = 8;

  /// 用 [TextPainter] 预量单行宽度，判断号码与余额能否排在同一行。
  ///
  /// [text] 为待测文本，[style] 为对应字阶；返回单行渲染宽度。
  double _measure(String text, TextStyle? style) {
    final TextPainter painter = TextPainter(
      text: TextSpan(text: text, style: style),
      maxLines: 1,
      textDirection: TextDirection.ltr,
    )..layout();
    return painter.width;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double numberWidth = _measure(number, numberStyle);
        final double balanceWidth = _measure(balanceText, balanceStyle);
        // 号码 + 间隔 + 中间点 + 余额 + 复制按钮 是否能放进一行。
        final bool inline = numberWidth +
                _gap +
                6 +
                balanceWidth +
                _gap +
                _copySize <=
            constraints.maxWidth;
        final Widget copy = _CopyButton(
          tooltip: copyTooltip,
          onPressed: onCopy,
        );
        if (inline) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Expanded(
                child: Text(number, style: numberStyle),
              ),
              const SizedBox(width: _gap),
              Text('·', style: balanceStyle),
              const SizedBox(width: 6),
              Text(
                balanceText,
                maxLines: 1,
                softWrap: false,
                style: balanceStyle,
              ),
              copy,
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 2,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                Expanded(child: Text(number, style: numberStyle)),
                copy,
              ],
            ),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                balanceText,
                maxLines: 1,
                softWrap: false,
                style: balanceStyle,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 40dp 复制热区：图标 18 + Tooltip 作无障碍标签。
class _CopyButton extends StatelessWidget {
  const _CopyButton({required this.tooltip, required this.onPressed});

  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    return SizedBox(
      width: 40,
      height: 40,
      child: IconButton(
        onPressed: onPressed,
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
        icon: Icon(
          Icons.copy_all_outlined,
          size: 18,
          color: tokens.text2,
        ),
      ),
    );
  }
}

/// 运营商栏目：名称 + 官网 / 客服 + 编辑 / 删除。
class _CarrierTab extends StatelessWidget {
  const _CarrierTab({
    required this.carriers,
    required this.total,
    required this.onCreate,
    required this.onEdit,
    required this.onDelete,
  });

  final List<Carrier> carriers;
  final int total;
  final VoidCallback onCreate;
  final ValueChanged<Carrier> onEdit;
  final ValueChanged<Carrier> onDelete;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    return ListView(
      key: const PageStorageKey<String>('lifestyle-cards-carrier'),
      padding: const EdgeInsets.only(bottom: 16),
      children: <Widget>[
        SectionHeader(
          title: '运营商 · 共 ${formatInt(total)} 家',
          actionLabel: '新增',
          onAction: onCreate,
        ),
        GroupCard(
          children: <Widget>[
            if (carriers.isEmpty)
              const EmptyState(
                icon: Icons.cell_tower_outlined,
                title: '暂无运营商',
                description: '点「新增」录入运营商字典',
                compact: true,
              )
            else
              for (final Carrier carrier in carriers)
                TaskRow(
                  title: carrier.name,
                  subtitle: <String>[
                    if ((carrier.website ?? '').isNotEmpty) carrier.website!,
                    if ((carrier.contact ?? '').isNotEmpty)
                      '客服 ${carrier.contact}',
                  ].join(' · '),
                  trailing: PopupMenuButton<String>(
                    tooltip: '更多操作',
                    icon: Icon(
                      Icons.more_vert,
                      size: 18,
                      color: tokens.text3,
                    ),
                    padding: EdgeInsets.zero,
                    onSelected: (String value) {
                      if (value == 'edit') {
                        onEdit(carrier);
                      } else {
                        onDelete(carrier);
                      }
                    },
                    itemBuilder: (BuildContext context) =>
                        <PopupMenuEntry<String>>[
                      const PopupMenuItem<String>(
                        value: 'edit',
                        child: Text('编辑'),
                      ),
                      PopupMenuItem<String>(
                        value: 'delete',
                        child: Text(
                          '删除',
                          style: TextStyle(color: tokens.red),
                        ),
                      ),
                    ],
                  ),
                ),
          ],
        ),
      ],
    );
  }
}

/// 卡账单栏目：月份 + 金额 + 号卡 + 扣账状态。
class _BillTab extends StatelessWidget {
  const _BillTab({
    required this.bills,
    required this.phones,
    required this.total,
    required this.onCreate,
    required this.onEdit,
    required this.onDelete,
  });

  final List<CardBill> bills;
  final List<PhoneCard> phones;
  final int total;
  final VoidCallback onCreate;
  final ValueChanged<CardBill> onEdit;
  final ValueChanged<CardBill> onDelete;

  /// 号卡 id → 号码；找不到时显示「未知号卡」。
  String _phoneText(int id) {
    for (final PhoneCard phone in phones) {
      if (phone.id == id) {
        return phone.phoneNumber;
      }
    }
    return '未知号卡';
  }

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    return ListView(
      key: const PageStorageKey<String>('lifestyle-cards-bill'),
      padding: const EdgeInsets.only(bottom: 16),
      children: <Widget>[
        SectionHeader(
          title: '卡账单 · 共 ${formatInt(total)} 条',
          actionLabel: '新增',
          onAction: onCreate,
        ),
        GroupCard(
          children: <Widget>[
            if (bills.isEmpty)
              const EmptyState(
                icon: Icons.receipt_long_outlined,
                title: '暂无卡账单',
                description: '点「新增」录入一条扣账记录',
                compact: true,
              )
            else
              for (final CardBill bill in bills)
                TaskRow(
                  title: '${bill.monthText} · ${formatMoney(bill.amount)}',
                  subtitle: <String>[
                    _phoneText(bill.phoneCardId),
                    if ((bill.deductedDate ?? '').isNotEmpty)
                      '扣账 ${formatListDate(bill.deductedDate)}',
                  ].join(' · '),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    spacing: 4,
                    children: <Widget>[
                      V2Badge(
                        bill.paid ? '已扣' : '未扣',
                        tone: bill.paid
                            ? V2BadgeTone.green
                            : V2BadgeTone.danger,
                      ),
                      PopupMenuButton<String>(
                        tooltip: '更多操作',
                        icon: Icon(
                          Icons.more_vert,
                          size: 18,
                          color: tokens.text3,
                        ),
                        padding: EdgeInsets.zero,
                        onSelected: (String value) {
                          if (value == 'edit') {
                            onEdit(bill);
                          } else {
                            onDelete(bill);
                          }
                        },
                        itemBuilder: (BuildContext context) =>
                            <PopupMenuEntry<String>>[
                          const PopupMenuItem<String>(
                            value: 'edit',
                            child: Text('编辑'),
                          ),
                          PopupMenuItem<String>(
                            value: 'delete',
                            child: Text(
                              '删除',
                              style: TextStyle(color: tokens.red),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
          ],
        ),
      ],
    );
  }
}

/// 单张银行卡：银行 + 卡名 → 卡号（主体）+ 余额（同行配角）→ 元信息。
class _CardRow extends StatelessWidget {
  const _CardRow({
    required this.card,
    required this.onCopy,
    required this.onEdit,
    required this.onDelete,
  });

  final BankCard card;
  final VoidCallback onCopy;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    final String meta = <String>[
      cardCategoryLabel(card.cardCategory),
      cardFormLabel(card.cardForm),
      if (card.status != 'active') cardStatusLabel(card.status),
      if ((card.expireDate ?? '').isNotEmpty)
        '到期 ${formatListDate(card.expireDate)}',
      if (card.billingText != null) card.billingText!,
    ].join(' · ');
    final String balanceLabel = card.isCredit ? '额度' : '余额';
    final num? amount = card.isCredit ? card.creditLimit : card.balance;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 4,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Text(
                  '${card.bank} · ${card.cardName}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.rowTitle.copyWith(
                    fontWeight: FontWeight.w600,
                    color: tokens.text,
                  ),
                ),
              ),
              PopupMenuButton<String>(
                tooltip: '更多操作',
                icon: Icon(Icons.more_vert, size: 18, color: tokens.text3),
                padding: EdgeInsets.zero,
                onSelected: (String value) {
                  if (value == 'edit') {
                    onEdit();
                  } else {
                    onDelete();
                  }
                },
                itemBuilder: (BuildContext context) =>
                    <PopupMenuEntry<String>>[
                  const PopupMenuItem<String>(
                    value: 'edit',
                    child: Text('编辑'),
                  ),
                  PopupMenuItem<String>(
                    value: 'delete',
                    child: Text(
                      '删除',
                      style: TextStyle(color: tokens.red),
                    ),
                  ),
                ],
              ),
            ],
          ),
          _NumberBalanceRow(
            number: card.displayNumber,
            numberStyle: AppType.rowTitle.copyWith(
              fontWeight: FontWeight.w500,
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
              letterSpacing: 0.4,
              color: tokens.text,
            ),
            balanceText: '$balanceLabel ${formatMoney(amount)}',
            balanceStyle: AppType.rowMeta.copyWith(
              color: tokens.text2,
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            ),
            copyTooltip: '复制卡号',
            onCopy: onCopy,
          ),
          if (meta.isNotEmpty)
            Text(
              meta,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppType.rowMeta.copyWith(color: tokens.text2),
            ),
        ],
      ),
    );
  }
}

/// 手机号卡卡片上的写操作（收在「操作」菜单里）。
enum _PhoneCardAction { recharge, deduct, adjust, edit, delete }

/// 单张手机号卡：号码 + 余额 → 运营商 / 套餐 / 账期 → 状态与操作 → 最近流水。
class _PhoneCardRow extends StatelessWidget {
  const _PhoneCardRow({
    required this.card,
    required this.onCopy,
    required this.onRecharge,
    required this.onAdjust,
    required this.onDeduct,
    required this.onEdit,
    required this.onDelete,
    required this.deducting,
    required this.onToggleLedger,
    required this.ledgerExpanded,
    required this.ledgerLoading,
    required this.ledger,
  });

  final PhoneCard card;
  final VoidCallback onCopy;
  final VoidCallback onRecharge;
  final VoidCallback onAdjust;
  final VoidCallback onDeduct;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final bool deducting;
  final VoidCallback onToggleLedger;
  final bool ledgerExpanded;
  final bool ledgerLoading;
  final List<PhoneLedgerEntry>? ledger;

  /// 账期文案：账单日 + 月租；都未设置时显示「账期未设置」。
  String get _billingText {
    final List<String> parts = <String>[
      if (card.billDay != null) '每月 ${card.billDay} 日',
      if (card.monthlyFee != null) '月租 ${formatMoney(card.monthlyFee)}',
    ];
    return parts.isEmpty ? '账期未设置' : parts.join(' · ');
  }

  /// 手机号卡状态中文：active / frozen / expired / disabled。
  String get _statusText {
    switch (card.status) {
      case 'frozen':
        return '已冻结';
      case 'expired':
        return '已过期';
      case 'disabled':
        return '已停用';
      default:
        return '正常';
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    final String meta = <String>[
      card.operator,
      card.planText,
      _billingText,
      if (card.status != 'active') _statusText,
      if ((card.note ?? '').trim().isNotEmpty) card.note!.trim(),
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 6,
        children: <Widget>[
          _NumberBalanceRow(
            number: card.displayNumber,
            numberStyle: AppType.rowTitle.copyWith(
              fontWeight: FontWeight.w700,
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
              letterSpacing: 0.3,
              color: tokens.text,
            ),
            balanceText: '余额 ${card.balanceText}',
            balanceStyle: AppType.rowMeta.copyWith(
              color: tokens.text2,
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            ),
            copyTooltip: '复制手机号',
            onCopy: onCopy,
          ),
          Text(
            meta,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppType.rowMeta.copyWith(color: tokens.text2),
          ),
          Row(
            children: <Widget>[
              if (card.monthBillText != null)
                Expanded(
                  child: Text(
                    card.monthBillText!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.rowMeta.copyWith(
                      color: card.billPaidThisMonth
                          ? tokens.text2
                          : tokens.orange,
                    ),
                  ),
                )
              else
                const Spacer(),
              TextButton(
                onPressed: onToggleLedger,
                style: TextButton.styleFrom(
                  foregroundColor: tokens.accent,
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  textStyle: AppType.action.copyWith(fontSize: 13),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  ledgerExpanded ? '收起流水' : '最近流水',
                  maxLines: 1,
                  softWrap: false,
                ),
              ),
              // 充值 / 扣费 / 校准 / 编辑 / 删除收进「操作」菜单，卡片只留流水入口。
              PopupMenuButton<_PhoneCardAction>(
                tooltip: '充值 / 扣费 / 校准',
                icon: Icon(Icons.more_vert, size: 18, color: tokens.text3),
                padding: EdgeInsets.zero,
                onSelected: (_PhoneCardAction action) {
                  switch (action) {
                    case _PhoneCardAction.recharge:
                      onRecharge();
                    case _PhoneCardAction.deduct:
                      onDeduct();
                    case _PhoneCardAction.adjust:
                      onAdjust();
                    case _PhoneCardAction.edit:
                      onEdit();
                    case _PhoneCardAction.delete:
                      onDelete();
                  }
                },
                itemBuilder: (BuildContext context) =>
                    <PopupMenuEntry<_PhoneCardAction>>[
                  const PopupMenuItem<_PhoneCardAction>(
                    value: _PhoneCardAction.recharge,
                    child: Text('充值'),
                  ),
                  PopupMenuItem<_PhoneCardAction>(
                    value: _PhoneCardAction.deduct,
                    enabled: !(deducting || card.billPaidThisMonth),
                    child: Text(
                      card.billPaidThisMonth
                          ? '扣费（本月已扣）'
                          : (deducting ? '扣费中…' : '扣费'),
                    ),
                  ),
                  const PopupMenuItem<_PhoneCardAction>(
                    value: _PhoneCardAction.adjust,
                    child: Text('校准'),
                  ),
                  const PopupMenuDivider(),
                  const PopupMenuItem<_PhoneCardAction>(
                    value: _PhoneCardAction.edit,
                    child: Text('编辑号卡'),
                  ),
                  PopupMenuItem<_PhoneCardAction>(
                    value: _PhoneCardAction.delete,
                    child: Text(
                      '删除号卡',
                      style: TextStyle(color: tokens.red),
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (ledgerExpanded)
            _LedgerPanel(
              loading: ledgerLoading,
              entries: ledger,
            ),
        ],
      ),
    );
  }
}

/// 最近流水面板：最多 5 条，日期 + 类型 + 带符号金额，备注另起一行。
class _LedgerPanel extends StatelessWidget {
  const _LedgerPanel({required this.loading, required this.entries});

  final bool loading;
  final List<PhoneLedgerEntry>? entries;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    final TextStyle metaStyle = AppType.rowMeta.copyWith(color: tokens.text2);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: tokens.fill2,
        borderRadius: BorderRadius.circular(AppTokens.controlRadius),
      ),
      child: loading
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Center(
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: tokens.text2,
                  ),
                ),
              ),
            )
          : entries == null || entries!.isEmpty
              ? Text('暂无流水记录', style: metaStyle)
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: 6,
                  children: <Widget>[
                    for (final PhoneLedgerEntry entry in entries!)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        spacing: 2,
                        children: <Widget>[
                          Row(
                            spacing: 8,
                            children: <Widget>[
                              SizedBox(
                                width: 100,
                                child: Text(
                                  entry.entryDate,
                                  style: metaStyle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Text(entry.typeLabel, style: metaStyle),
                              const Spacer(),
                              Text(
                                entry.amountText,
                                maxLines: 1,
                                softWrap: false,
                                style: AppType.rowValue.copyWith(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: entry.amount > 0
                                      ? tokens.green
                                      : (entry.amount < 0
                                          ? tokens.red
                                          : tokens.text),
                                ),
                              ),
                            ],
                          ),
                          if ((entry.note ?? '').trim().isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(left: 86),
                              child: Text(
                                entry.note!.trim(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppType.rowMeta.copyWith(
                                  color: tokens.text3,
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
