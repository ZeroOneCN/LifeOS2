import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_scope.dart';
import '../../core/data/overview_controller.dart';
import '../../core/models/lifestyle_models.dart';
import '../../core/network/api_exception.dart';
import '../../core/utils/formatters.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/root_page_scaffold.dart';
import '../../shared/widgets/section_card.dart';
import '../../shared/widgets/section_status.dart';

/// 卡片管理：汇总（数量 / 余额 / 信用额度）+ 银行卡分页列表 + 手机号卡只读区。
///
/// 数据（与网页端 `pages/lifestyle/cards.tsx` 一致）：
/// - `GET /lifestyle/bank-cards?page=&page_size=20`
/// - `GET /lifestyle/bank-cards/stats?days=30`
/// - `GET /lifestyle/phone-cards?page=&page_size=100`（只读，一次性加载）
///
/// 手机号卡充值 / 扣费 / 校准都是写操作，本轮不做，界面明确提示去网页端操作。
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

  int _page = 1;
  int _total = 0;
  bool _hasMore = true;
  bool _loadingMore = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _refresh();
      }
    });
  }

  /// 首屏 / 重试：并行拉汇总与第一页银行卡。
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

  /// 加载更多：追加下一页银行卡。
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

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final BankStats? stats = _stats;

    return DetailPageScaffold(
      title: '卡片管理',
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
              if (_status == LoadStatus.ready && stats != null) ...<Widget>[
                SectionCard(
                  title: '合计',
                  trailing: Text(
                    '银行卡 ${formatInt(_stats?.total)} · '
                    '手机号卡 ${formatInt(_phoneTotal)} · '
                    '合计 ${formatInt((_stats?.total ?? 0) + _phoneTotal)}',
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
                              value: formatMoney(stats.balanceTotal),
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
                        '列表完整显示卡号（每 4 位分组，不截断）；点每张卡右侧的复制按钮可复制纯号码。',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                SectionCard(
                  title: '手机号卡',
                  trailing: Text(
                    '共 $_phoneTotal 张 · 只读',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: 4,
                    children: <Widget>[
                      Text(
                        '只读：充值 / 扣费 / 校准请在网页端操作；号码完整显示，点复制按钮复制纯号码',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (_phones.isEmpty)
                        const EmptyState(
                          icon: Icons.sim_card_outlined,
                          title: '暂无手机号卡',
                          description: '充值 / 扣费 / 校准请在网页端操作',
                          compact: true,
                        )
                      else
                        for (final PhoneCard phone in _phones)
                          _PhoneCardRow(
                            card: phone,
                            onCopy: () => _copyNumber(
                              '手机号',
                              phone.copyableNumber,
                            ),
                          ),
                    ],
                  ),
                ),
                SectionCard(
                  title: '银行卡',
                  trailing: Text(
                    '共 $_total 张',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  child: _cards.isEmpty
                      ? const EmptyState(
                          icon: Icons.credit_card_outlined,
                          title: '暂无银行卡',
                          description: '可在网页端录入银行卡信息',
                          compact: true,
                        )
                      : Column(
                          spacing: 4,
                          children: <Widget>[
                            for (final BankCard card in _cards)
                              _CardRow(
                                card: card,
                                onCopy: () => _copyNumber(
                                  '卡号',
                                  card.copyableNumber,
                                ),
                              ),
                          ],
                        ),
                ),
                if (_cards.isNotEmpty)
                  _LoadMoreFooter(
                    loading: _loadingMore,
                    hasMore: _hasMore,
                    onPressed: _loadMore,
                  ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// 单张银行卡：卡名 + 完整卡号（分组、可换行）+ 复制按钮 + 银行/类型/状态 + 余额或额度。
class _CardRow extends StatelessWidget {
  const _CardRow({required this.card, required this.onCopy});

  final BankCard card;

  /// 复制纯号码（不带空格）。
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color muted = theme.colorScheme.onSurfaceVariant;
    final TextStyle? metaStyle =
        theme.textTheme.bodySmall?.copyWith(color: muted);
    final List<Widget> meta = <Widget>[
      Text(card.bank, style: metaStyle),
      Text(cardCategoryLabel(card.cardCategory), style: metaStyle),
      Text(cardFormLabel(card.cardForm), style: metaStyle),
      if (card.status != 'active')
        Text(cardStatusLabel(card.status), style: metaStyle),
      if (card.expireDate != null && card.expireDate!.isNotEmpty)
        Text('到期 ${card.expireDate}', style: metaStyle),
      if (card.billingText != null) Text(card.billingText!, style: metaStyle),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 12,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 3,
              children: <Widget>[
                // 主体：银行 + 卡名（同一行，字号更大更重）。
                Text(
                  '${card.bank} · ${card.cardName}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(
                      // 完整卡号：不设 maxLines / ellipsis，窄屏与 1.3x 自动换行。
                      child: Text(
                        card.displayNumber,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                          fontFeatures: const <FontFeature>[
                            FontFeature.tabularFigures(),
                          ],
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: onCopy,
                      tooltip: '复制卡号',
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 36,
                        minHeight: 36,
                      ),
                      icon: const Icon(Icons.copy_all_outlined, size: 18),
                    ),
                  ],
                ),
                // 元信息用 Wrap：窄屏 / 1.3x 字体下换行而不是省略号截断。
                Wrap(spacing: 8, runSpacing: 2, children: meta),
              ],
            ),
          ),
          // 余额 / 额度是配角：中性次要色，不与主体抢视觉。
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            spacing: 2,
            children: <Widget>[
              Text(
                formatMoney(card.isCredit ? card.creditLimit : card.balance),
                maxLines: 1,
                softWrap: false,
                style: metaStyle?.copyWith(
                  fontFeatures: const <FontFeature>[
                    FontFeature.tabularFigures(),
                  ],
                ),
              ),
              Text(
                card.isCredit ? '额度' : '余额',
                maxLines: 1,
                style: metaStyle,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 单张手机号卡（只读）：完整号码 + 复制按钮 + 运营商 / 套餐 / 账期 + 余额。
class _PhoneCardRow extends StatelessWidget {
  const _PhoneCardRow({required this.card, required this.onCopy});

  final PhoneCard card;

  /// 复制纯号码（不带空格）。
  final VoidCallback onCopy;

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
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 12,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 3,
              children: <Widget>[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(
                      // 主体：完整手机号（字号更大、字重更重），自动换行不截断。
                      child: Text(
                        card.displayNumber,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          fontFeatures: const <FontFeature>[
                            FontFeature.tabularFigures(),
                          ],
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: onCopy,
                      tooltip: '复制手机号',
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 36,
                        minHeight: 36,
                      ),
                      icon: const Icon(Icons.copy_all_outlined, size: 18),
                    ),
                  ],
                ),
                // 运营商 / 套餐 / 账期是次要信息，小字中性色。
                Wrap(spacing: 8, runSpacing: 2, children: meta),
              ],
            ),
          ),
          // 余额是配角：中性次要色，不用主色/警告色。
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            spacing: 2,
            children: <Widget>[
              Text(
                card.balance == null ? '—' : formatMoney(card.balance),
                maxLines: 1,
                softWrap: false,
                style: metaStyle?.copyWith(
                  fontFeatures: const <FontFeature>[
                    FontFeature.tabularFigures(),
                  ],
                ),
              ),
              Text('余额', maxLines: 1, style: metaStyle),
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
