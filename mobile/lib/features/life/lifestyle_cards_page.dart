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
import '../../shared/widgets/app_tab_selector.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/root_page_scaffold.dart';
import '../../shared/widgets/section_card.dart';
import '../../shared/widgets/section_status.dart';

/// 卡片管理：合计概览 + 手机号卡 / 银行卡双 Tab 列表。
///
/// 数据（与网页端 `pages/lifestyle/cards.tsx` 一致）：
/// - `GET /lifestyle/bank-cards?page=&page_size=20`
/// - `GET /lifestyle/bank-cards/stats?days=30`
/// - `GET /lifestyle/phone-cards?page=&page_size=100`（只读，一次性加载）
///
/// 两个 Tab 使用独立 `ListView`（`IndexedStack` 常驻），切换时各自保留滚动位置。
/// Tab 组件与财务中心账单页共用 [AppTabSelector]，圆角、选中态完全一致。
class LifestyleCardsPage extends StatefulWidget {
  const LifestyleCardsPage({super.key});

  @override
  State<LifestyleCardsPage> createState() => _LifestyleCardsPageState();
}

class _LifestyleCardsPageState extends State<LifestyleCardsPage> {
  final List<BankCard> _cards = <BankCard>[];
  final List<PhoneCard> _phones = <PhoneCard>[];

  BankStats? _stats;
  int _phoneTotal = 0;
  LoadStatus _status = LoadStatus.loading;
  String? _message;

  /// 当前 Tab：0 = 手机号卡，1 = 银行卡。
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
      final List<Object?> responses = await Future.wait<Object?>(
        <Future<Object?>>[statsFuture, listFuture, phoneFuture],
      );
      final Map<String, dynamic>? statsJson =
          responses[0] as Map<String, dynamic>?;
      final Map<String, dynamic>? listJson =
          responses[1] as Map<String, dynamic>?;
      final Map<String, dynamic>? phoneJson =
          responses[2] as Map<String, dynamic>?;
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
        _phoneTotal =
            (phoneJson?['total'] as num?)?.toInt() ?? phones.length;
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

  /// 加载更多：追加下一页银行卡（只影响银行卡 Tab）。
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
        _phoneTotal = (json['total'] as num?)?.toInt() ?? phones.length;
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

  /// 手动补扣本月：幂等写操作，成功后立即刷新余额。
  Future<void> _deduct(PhoneCard card) async {
    if (_deductingId != null) {
      return;
    }
    final AppScope scope = AppScope.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    if (!scope.outbox.isOnline) {
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

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final BankStats? stats = _stats;
    final bool ready = _status == LoadStatus.ready && stats != null;

    // 余额合计口径：银行卡余额 + 手机号卡「已采集」余额。
    // 手机号卡没有单独的采集标记，与单卡「余额 —」用同一判定，避免合计与单卡矛盾。
    final double bankBalance = stats?.balanceTotal ?? 0;
    final int phoneCollectedCount = _phones
        .where((PhoneCard phone) => phone.collectedBalance != null)
        .length;
    final double phoneBalance = _phones.fold<double>(
      0,
      (double sum, PhoneCard phone) => sum + (phone.collectedBalance ?? 0),
    );
    final int phoneUncollectedCount = _phones.length - phoneCollectedCount;
    final double balanceTotal = bankBalance + phoneBalance;

    return DetailPageScaffold(
      title: '卡片管理',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: <Widget>[
          if (!ready)
            Expanded(
              child: ListView(
                children: <Widget>[
                  ListStatusView(
                    status: _status,
                    message: _message,
                    onRetry: _refresh,
                  ),
                ],
              ),
            )
          else ...<Widget>[
            SectionCard(
              title: '合计',
              trailing: Text(
                '银行卡 + 手机号卡',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              child: Column(
                spacing: 12,
                children: <Widget>[
                  Row(
                    spacing: 16,
                    children: <Widget>[
                      Expanded(
                        child: MetricPlaceholder(
                          label: '银行卡数',
                          value: formatInt(stats.total),
                        ),
                      ),
                      Expanded(
                        child: MetricPlaceholder(
                          label: '正常',
                          value: formatInt(stats.active),
                        ),
                      ),
                      Expanded(
                        child: MetricPlaceholder(
                          label: '余额合计',
                          value: formatMoney(balanceTotal),
                        ),
                      ),
                    ],
                  ),
                  Row(
                    spacing: 16,
                    children: <Widget>[
                      Expanded(
                        child: MetricPlaceholder(
                          label: '信用额度',
                          value: formatMoney(stats.creditTotal),
                        ),
                      ),
                      Expanded(
                        child: MetricPlaceholder(
                          label: '借记卡',
                          value: formatInt(stats.countOfCategory('debit')),
                        ),
                      ),
                      Expanded(
                        child: MetricPlaceholder(
                          label: '信用卡',
                          value: formatInt(stats.countOfCategory('credit')),
                        ),
                      ),
                    ],
                  ),
                  Text(
                    phoneUncollectedCount > 0
                        ? '口径：余额合计 = 银行卡 ${formatMoney(bankBalance)} + '
                            '手机号卡已采集 ${formatMoney(phoneBalance)}'
                            '（${formatInt(phoneCollectedCount)} 张已采集；'
                            '${formatInt(phoneUncollectedCount)} 张未采集，未计入）'
                        : '口径：余额合计 = 银行卡 ${formatMoney(bankBalance)} + '
                            '手机号卡 ${formatMoney(phoneBalance)}'
                            '（${formatInt(phoneCollectedCount)} 张均已采集）',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            AppTabSelector(
              labels: <String>[
                '手机号卡 ${formatInt(_phoneTotal)}',
                '银行卡 ${formatInt(_total)}',
              ],
              value: _tab,
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

/// 手机号卡 Tab：独立滚动，切换不重置位置；每张卡提供充值 / 扣费 / 校准与最近流水。
class _PhoneTab extends StatelessWidget {
  const _PhoneTab({
    required this.phones,
    required this.onCopy,
    required this.onRecharge,
    required this.onAdjust,
    required this.onDeduct,
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

  /// 正在补扣的卡片 id（按钮显示 loading，防止重复点击）。
  final int? deductingId;
  final Set<int> expandedIds;
  final Map<int, List<PhoneLedgerEntry>> ledgers;
  final int? loadingLedgerId;
  final ValueChanged<PhoneCard> onToggleLedger;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return ListView(
      key: const PageStorageKey<String>('lifestyle-cards-phone'),
      padding: EdgeInsets.zero,
      children: <Widget>[
        SectionCard(
          title: '手机号卡',
          trailing: Text(
            '共 ${formatInt(phones.length)} 张',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 4,
            children: <Widget>[
              Text(
                '充值 / 扣费 / 校准直接操作，余额由后端流水自动更新。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (phones.isEmpty)
                const EmptyState(
                  icon: Icons.sim_card_outlined,
                  title: '暂无手机号卡',
                  description: '可在网页端录入后再充值 / 扣费 / 校准',
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
                    deducting: deductingId == phone.id,
                    onToggleLedger: () => onToggleLedger(phone),
                    ledgerExpanded: expandedIds.contains(phone.id),
                    ledgerLoading: loadingLedgerId == phone.id,
                    ledger: ledgers[phone.id],
                  ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 银行卡 Tab：独立滚动 + 分页页脚。
class _BankTab extends StatelessWidget {
  const _BankTab({
    required this.cards,
    required this.total,
    required this.loadingMore,
    required this.hasMore,
    required this.onLoadMore,
    required this.onCopy,
  });

  final List<BankCard> cards;
  final int total;
  final bool loadingMore;
  final bool hasMore;
  final VoidCallback onLoadMore;
  final ValueChanged<BankCard> onCopy;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return ListView(
      key: const PageStorageKey<String>('lifestyle-cards-bank'),
      padding: EdgeInsets.zero,
      children: <Widget>[
        SectionCard(
          title: '银行卡',
          trailing: Text(
            '共 ${formatInt(total)} 张',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          child: cards.isEmpty
              ? const EmptyState(
                  icon: Icons.credit_card_outlined,
                  title: '暂无银行卡',
                  description: '可在网页端录入银行卡信息',
                  compact: true,
                )
              : Column(
                  spacing: 4,
                  children: <Widget>[
                    for (final BankCard card in cards)
                      _CardRow(card: card, onCopy: () => onCopy(card)),
                  ],
                ),
        ),
        if (cards.isNotEmpty)
          _LoadMoreFooter(
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
/// - 宽度不够（1.3x / 长号码）：余额换到第二行右对齐，号码与复制按钮留在第一行，
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
    return SizedBox(
      width: 40,
      height: 40,
      child: IconButton(
        onPressed: onPressed,
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
        icon: const Icon(Icons.copy_all_outlined, size: 18),
      ),
    );
  }
}

/// 单张银行卡：银行 + 卡名 → 卡号（主体）+ 余额（同行配角）→ 元信息。
class _CardRow extends StatelessWidget {
  const _CardRow({required this.card, required this.onCopy});

  final BankCard card;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color muted = theme.colorScheme.onSurfaceVariant;
    final TextStyle? metaStyle =
        theme.textTheme.bodySmall?.copyWith(color: muted);
    final TextStyle? balanceStyle = metaStyle?.copyWith(
      fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
    );
    final List<Widget> meta = <Widget>[
      Text(cardCategoryLabel(card.cardCategory), style: metaStyle),
      Text(cardFormLabel(card.cardForm), style: metaStyle),
      if (card.status != 'active')
        Text(cardStatusLabel(card.status), style: metaStyle),
      if (card.expireDate != null && card.expireDate!.isNotEmpty)
        Text('到期 ${card.expireDate}', style: metaStyle),
      if (card.billingText != null) Text(card.billingText!, style: metaStyle),
    ];
    final String balanceLabel = card.isCredit ? '额度' : '余额';
    final num? amount = card.isCredit ? card.creditLimit : card.balance;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 4,
        children: <Widget>[
          Text(
            '${card.bank} · ${card.cardName}',
            maxLines: 2,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          _NumberBalanceRow(
            number: card.displayNumber,
            numberStyle: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
              letterSpacing: 0.4,
            ),
            balanceText: '$balanceLabel ${formatMoney(amount)}',
            balanceStyle: balanceStyle,
            copyTooltip: '复制卡号',
            onCopy: onCopy,
          ),
          Wrap(spacing: 8, runSpacing: 2, children: meta),
        ],
      ),
    );
  }
}

/// 单张手机号卡：号码（主体）+ 余额同行 → 运营商 / 套餐 / 账期 → 三个写操作 → 最近流水。
class _PhoneCardRow extends StatelessWidget {
  const _PhoneCardRow({
    required this.card,
    required this.onCopy,
    required this.onRecharge,
    required this.onAdjust,
    required this.onDeduct,
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
    final ThemeData theme = Theme.of(context);
    final Color muted = theme.colorScheme.onSurfaceVariant;
    final TextStyle? metaStyle =
        theme.textTheme.bodySmall?.copyWith(color: muted);
    final TextStyle? balanceStyle = metaStyle?.copyWith(
      fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
    );
    final List<Widget> meta = <Widget>[
      Text(card.operator, style: metaStyle),
      Text(card.planText, style: metaStyle),
      Text(_billingText, style: metaStyle),
      if (card.status != 'active') Text(_statusText, style: metaStyle),
      if (card.note != null && card.note!.trim().isNotEmpty)
        Text(card.note!, style: metaStyle),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 6,
        children: <Widget>[
          _NumberBalanceRow(
            number: card.displayNumber,
            numberStyle: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
              letterSpacing: 0.3,
            ),
            balanceText: '余额 ${card.balanceText}',
            balanceStyle: balanceStyle,
            copyTooltip: '复制手机号',
            onCopy: onCopy,
          ),
          Wrap(spacing: 8, runSpacing: 2, children: meta),
          Row(
            spacing: 8,
            children: <Widget>[
              Expanded(
                child: AppSecondaryButton(
                  label: '充值',
                  compact: true,
                  onPressed: onRecharge,
                ),
              ),
              Expanded(
                child: AppSecondaryButton(
                  label: '扣费',
                  compact: true,
                  // 本月已扣满时禁止重复补扣（后端虽幂等，避免误以为还会扣钱）；
                  // 请求进行中同样禁用，防止连点重复提交。
                  onPressed: deducting || card.billPaidThisMonth
                      ? null
                      : onDeduct,
                ),
              ),
              Expanded(
                child: AppSecondaryButton(
                  label: '校准',
                  compact: true,
                  onPressed: onAdjust,
                ),
              ),
            ],
          ),
          Row(
            children: <Widget>[
              if (card.monthBillText != null)
                Expanded(
                  child: Text(
                    card.monthBillText!,
                    style: metaStyle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                )
              else
                const Spacer(),
              TextButton(
                onPressed: onToggleLedger,
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                child: Text(
                  ledgerExpanded ? '收起流水' : '最近流水',
                  maxLines: 1,
                  softWrap: false,
                ),
              ),
            ],
          ),
          if (ledgerExpanded) _LedgerPanel(
            loading: ledgerLoading,
            entries: ledger,
            theme: theme,
          ),
        ],
      ),
    );
  }
}

/// 最近流水面板：最多 5 条，日期 + 类型 + 带符号金额，备注另起一行。
class _LedgerPanel extends StatelessWidget {
  const _LedgerPanel({
    required this.loading,
    required this.entries,
    required this.theme,
  });

  final bool loading;
  final List<PhoneLedgerEntry>? entries;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final TextStyle? metaStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(8),
      ),
      child: loading
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Center(
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
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
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurface,
                                  fontWeight: FontWeight.w600,
                                  fontFeatures: const <FontFeature>[
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          if (entry.note != null && entry.note!.trim().isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(left: 86),
                              child: Text(entry.note!, style: metaStyle),
                            ),
                        ],
                      ),
                  ],
                ),
    );
  }
}

/// 列表页「加载更多 / 已全部加载」页脚（与 B3 列表一致的交互）。
class _LoadMoreFooter extends StatelessWidget {
  const _LoadMoreFooter({
    required this.loading,
    required this.hasMore,
    required this.onPressed,
  });

  final bool loading;
  final bool hasMore;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    if (loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (!hasMore) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(
          '已加载全部',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    return TextButton(onPressed: onPressed, child: const Text('加载更多'));
  }
}
