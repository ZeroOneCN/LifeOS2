import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/data/overview_controller.dart';
import '../../core/models/lifestyle_models.dart';
import '../../core/network/api_exception.dart';
import '../../core/utils/formatters.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/root_page_scaffold.dart';
import '../../shared/widgets/section_card.dart';
import '../../shared/widgets/section_status.dart';

/// 卡片管理：汇总（数量 / 余额 / 信用额度）+ 银行卡分页列表（卡号脱敏）。
///
/// 数据（与网页端 `pages/lifestyle/cards.tsx` 银行卡部分一致）：
/// - `GET /lifestyle/bank-cards?page=&page_size=20`
/// - `GET /lifestyle/bank-cards/stats?days=30`
class LifestyleCardsPage extends StatefulWidget {
  const LifestyleCardsPage({super.key});

  @override
  State<LifestyleCardsPage> createState() => _LifestyleCardsPageState();
}

class _LifestyleCardsPageState extends State<LifestyleCardsPage> {
  final List<BankCard> _cards = <BankCard>[];

  BankStats? _stats;
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
      final List<Object?> responses = await Future.wait<Object?>(
        <Future<Object?>>[statsFuture, listFuture],
      );
      final Map<String, dynamic>? statsJson =
          responses[0] as Map<String, dynamic>?;
      final Map<String, dynamic>? listJson =
          responses[1] as Map<String, dynamic>?;
      if (statsJson == null || listJson == null) {
        throw const ApiException(
          kind: ApiErrorKind.badResponse,
          message: '卡片接口返回数据为空',
        );
      }
      final List<BankCard> cards = _parseCards(listJson);
      if (!mounted) {
        return;
      }
      setState(() {
        _stats = BankStats.fromJson(statsJson);
        _cards
          ..clear()
          ..addAll(cards);
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
                    '全部银行卡',
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
                              label: '卡片总数',
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
                    ],
                  ),
                ),
                SectionCard(
                  title: '全部卡片',
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
                              _CardRow(card: card),
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

/// 单张银行卡：卡名 + 脱敏卡号 + 银行/类型/状态 + 余额或额度。
///
/// 安全底线：界面只允许出现 [BankCard.maskedNumber]，不展示完整卡号。
class _CardRow extends StatelessWidget {
  const _CardRow({required this.card});

  final BankCard card;

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
                Text(
                  card.cardName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium,
                ),
                Text(
                  card.maskedNumber,
                  maxLines: 1,
                  softWrap: false,
                  style: metaStyle?.copyWith(
                    fontFeatures: const <FontFeature>[
                      FontFeature.tabularFigures(),
                    ],
                    letterSpacing: 0.5,
                  ),
                ),
                // 元信息用 Wrap：窄屏 / 1.3x 字体下换行而不是省略号截断。
                Wrap(spacing: 8, runSpacing: 2, children: meta),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            spacing: 2,
            children: <Widget>[
              Text(
                formatMoney(card.isCredit ? card.creditLimit : card.balance),
                maxLines: 1,
                softWrap: false,
                style: theme.textTheme.bodyMedium?.copyWith(
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
