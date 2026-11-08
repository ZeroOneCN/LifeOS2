import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/models/finance_models.dart';
import '../../core/network/api_exception.dart';
import '../../core/utils/formatters.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/root_page_scaffold.dart';
import '../../shared/widgets/section_card.dart';

/// 流水页：展示服务端 `GET /finance/shopping/records` 前 5 条支出。
///
/// 离线队列已下线，写操作一律直连服务端；本页只做只读展示。
/// 完整的流水分页列表留到后续批次，本页不做横向/分页处理。
class FinanceTransactionsPage extends StatefulWidget {
  const FinanceTransactionsPage({super.key});

  @override
  State<FinanceTransactionsPage> createState() =>
      _FinanceTransactionsPageState();
}

class _FinanceTransactionsPageState extends State<FinanceTransactionsPage> {
  final List<ShoppingRecord> _records = <ShoppingRecord>[];
  bool _initialized = false;
  bool _loading = true;
  String? _loadError;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) {
      return;
    }
    _initialized = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _loadRecords();
      }
    });
  }

  /// 拉最近 5 条支出；[silent] 时保留旧数据，失败只在页内提示。
  Future<void> _loadRecords({bool silent = false}) async {
    final AppScope scope = AppScope.of(context);
    if (!scope.auth.isLoggedIn) {
      setState(() {
        _loading = false;
        _loadError = '未登录，登录后显示服务端支出';
      });
      return;
    }
    if (!silent) {
      setState(() {
        _loading = true;
        _loadError = null;
      });
    }
    try {
      final Map<String, dynamic>? json =
          (await scope.apiClient.get<Map<String, dynamic>>(
            '/finance/shopping/records',
            queryParameters: <String, dynamic>{'page': 1, 'page_size': 5},
          )).data;
      if (!mounted) {
        return;
      }
      final List<dynamic> items =
          json?['items'] as List<dynamic>? ?? <dynamic>[];
      setState(() {
        _records
          ..clear()
          ..addAll(
            items
                .whereType<Map>()
                .map(
                  (Map item) =>
                      ShoppingRecord.fromJson(item.cast<String, dynamic>()),
                )
                .toList(),
          );
        _loading = false;
        _loadError = null;
      });
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _loadError = error.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return DetailPageScaffold(
      title: '支出流水',
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: <Widget>[
          // 后端当前只有消费支出记录，没有收入流水；先把口径讲清楚。
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: _hint(
              theme,
              Icons.info_outline,
              '口径：当前仅包含消费支出（来自购物记录），收入流水暂未接入。',
            ),
          ),
          const SizedBox(height: 12),
          _recentCard(theme),
        ],
      ),
    );
  }

  /// 最近支出卡片：服务端前 5 条，确认队列推送后真实数据补上。
  Widget _recentCard(ThemeData theme) {
    return SectionCard(
      title: '最近支出',
      // 图标 + 文字：纯文字按钮在 375/1.3x 下点击区偏小，也不够显眼。
      trailing: TextButton.icon(
        onPressed: _loading ? null : _loadRecords,
        icon: const Icon(Icons.refresh, size: 18),
        label: const Text('刷新'),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 8,
        children: <Widget>[
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          if (_loadError != null)
            _hint(
              theme,
              Icons.error_outline,
              _loadError!,
              color: theme.colorScheme.error,
            ),
          if (!_loading && _loadError == null && _records.isEmpty)
            const EmptyState(
              icon: Icons.receipt_long_outlined,
              title: '暂无支出记录',
              description: '保存一笔支出后即可在这里看到',
              compact: true,
            ),
          for (final ShoppingRecord record in _records)
            _RecentRow(record: record),
        ],
      ),
    );
  }

  /// 页内提示条：图标 + 文案，可选错误色。
  Widget _hint(ThemeData theme, IconData icon, String text, {Color? color}) {
    final Color contentColor = color ?? theme.colorScheme.onSurfaceVariant;
    return Row(
      spacing: 8,
      children: <Widget>[
        Icon(icon, size: 18, color: contentColor),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodySmall?.copyWith(color: contentColor),
          ),
        ),
      ],
    );
  }
}

/// 服务端最近支出行。
class _RecentRow extends StatelessWidget {
  const _RecentRow({required this.record});

  final ShoppingRecord record;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        spacing: 12,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 2,
              children: <Widget>[
                Text(
                  record.productName.isEmpty ? '未命名支出' : record.productName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium,
                ),
                Text(
                  formatListDate(record.recordDate),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontFeatures: const <FontFeature>[
                      FontFeature.tabularFigures(),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Text(
            formatMoney(record.totalPrice),
            style: theme.textTheme.bodyMedium?.copyWith(
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
