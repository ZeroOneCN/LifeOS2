import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/data/overview_controller.dart';
import '../../core/models/finance_models.dart';
import '../../core/network/api_exception.dart';
import '../../core/utils/formatters.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/root_page_scaffold.dart';
import '../../shared/widgets/v2/v2_page_kit.dart';
import '../../shared/widgets/v2/v2_rows.dart';
import '../../theme/app_tokens.dart';

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
    final AppTokens tokens = AppTokens.of(context);
    return DetailPageScaffold(
      title: '支出流水',
      child: ListPageBody(
        status: _loading
            ? LoadStatus.loading
            : (_loadError == null ? LoadStatus.ready : LoadStatus.failed),
        message: _loadError,
        onRetry: _loadRecords,
        blocks: <Widget>[
          // 后端当前只有消费支出记录，没有收入流水；先把口径讲清楚。
          Text(
            '口径：当前仅包含消费支出（来自购物记录），收入流水暂未接入。',
            style: AppType.rowMeta.copyWith(color: tokens.text3),
          ),
          SectionHeader(
            title: '最近支出 · 共 ${_records.length} 条',
            actionLabel: '刷新',
            onAction: _loading ? null : _loadRecords,
          ),
          GroupCard(
            children: _records.isEmpty
                ? const <Widget>[
                    EmptyState(
                      icon: Icons.receipt_long_outlined,
                      title: '暂无支出记录',
                      description: '保存一笔支出后即可在这里看到',
                      compact: true,
                    ),
                  ]
                : <Widget>[
                    for (final ShoppingRecord record in _records)
                      RecordRow(
                        title: record.productName.isEmpty
                            ? '未命名支出'
                            : record.productName,
                        subtitle: formatListDate(record.recordDate),
                        value: formatMoney(record.totalPrice),
                      ),
                  ],
          ),
        ],
      ),
    );
  }
}
