import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/data/overview_controller.dart';
import '../../core/models/investment_models.dart';
import '../../core/network/api_exception.dart';
import '../../core/utils/formatters.dart';
import '../../shared/widgets/root_page_scaffold.dart';
import '../../shared/widgets/section_card.dart';
import '../../shared/widgets/section_status.dart';
import '../../theme/app_typography.dart';

/// 外汇交易详情（**只读**）。
///
/// 行情与资金数据统一由网页端导入，移动端只保留查看能力：
/// 不提供新增、编辑、删除入口，页面内也不放任何写按钮。
///
/// 数据来源：
/// - 列表点击进入时用 `extra` 传入的快照，避免二次请求；
/// - 快照缺失（例如深链进入）时按 id 拉 `GET /investment/forex/{id}`。
class ForexDetailPage extends StatefulWidget {
  const ForexDetailPage({super.key, required this.tradeId, this.initial});

  final int tradeId;
  final ForexTrade? initial;

  @override
  State<ForexDetailPage> createState() => _ForexDetailPageState();
}

class _ForexDetailPageState extends State<ForexDetailPage> {
  ForexTrade? _trade;
  LoadStatus _status = LoadStatus.loading;
  String? _message;

  @override
  void initState() {
    super.initState();
    _trade = widget.initial;
    if (_trade != null) {
      _status = LoadStatus.ready;
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _load();
        }
      });
    }
  }

  /// 快照缺失时按 id 拉取详情。
  Future<void> _load() async {
    final AppScope scope = AppScope.of(context);
    setState(() {
      _status = LoadStatus.loading;
      _message = null;
    });
    try {
      final Map<String, dynamic>? json =
          (await scope.apiClient.get<Map<String, dynamic>>(
            '/investment/forex/${widget.tradeId}',
          )).data;
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
        _trade = ForexTrade.fromJson(json);
        _status = LoadStatus.ready;
      });
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _status = error.isUnauthorized
            ? LoadStatus.unauthenticated
            : LoadStatus.failed;
        _message = error.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ForexTrade? trade = _trade;

    return DetailPageScaffold(
      title: '交易详情',
      child: ListView(
        children: <Widget>[
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 12,
            children: <Widget>[
              ListStatusView(
                status: _status,
                message: _message,
                onRetry: _load,
              ),
              if (_status == LoadStatus.ready && trade != null) ...<Widget>[
                SectionCard(
                  title: trade.symbol,
                  trailing: Text(
                    trade.isOpen ? '持仓中' : '已平仓',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: trade.isOpen
                          ? theme.colorScheme.tertiary
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: 6,
                    children: <Widget>[
                      Text(
                        trade.pnl == null ? '—' : formatUsdSigned(trade.pnl),
                        style: AppTypography.amountLarge.copyWith(
                          color: trade.pnl == null
                              ? theme.colorScheme.onSurfaceVariant
                              : (trade.pnl! >= 0
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.error),
                        ),
                      ),
                      Text(
                        '${trade.orderTypeLabel} · ${_plain(trade.lotSize)} 手 · 盈亏金额',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                SectionCard(
                  title: '交易明细',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: 10,
                    children: <Widget>[
                      _DetailRow(label: '交易日期', value: trade.tradeDate),
                      _DetailRow(label: '品种', value: trade.symbol),
                      _DetailRow(label: '方向', value: trade.orderTypeLabel),
                      _DetailRow(label: '手数', value: _plain(trade.lotSize)),
                      _DetailRow(label: '开仓价', value: _plain(trade.openPrice)),
                      _DetailRow(
                        label: '平仓价',
                        value: trade.closePrice == null
                            ? '—'
                            : _plain(trade.closePrice!),
                      ),
                      _DetailRow(label: '开仓时间', value: _time(trade.openTime)),
                      _DetailRow(label: '平仓时间', value: _time(trade.closeTime)),
                      _DetailRow(
                        label: '持仓时长',
                        value: formatDuration(trade.holding),
                      ),
                      _DetailRow(
                        label: '手续费',
                        value: formatUsd(trade.commission),
                      ),
                      _DetailRow(
                        label: '隔夜费',
                        value: formatUsd(trade.overnightFee),
                      ),
                      _DetailRow(
                        label: '状态',
                        value: trade.isOpen ? '持仓中' : '已平仓',
                      ),
                    ],
                  ),
                ),
                if (trade.note != null && trade.note!.trim().isNotEmpty)
                  SectionCard(
                    title: '备注',
                    // 后端已按库内原文返回（字段名保留，不翻译、不重排），
                    // 这里只展示一次原文，不再做可读化解析或追加释义行。
                    child: Text(trade.note!, style: theme.textTheme.bodyMedium),
                  ),
                Text(
                  '行情数据由网页端导入，移动端仅支持查看。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  /// 数字去尾零：`0.1000` → `0.1`，`12.00` → `12`。
  String _plain(double value) {
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }
    return value.toString();
  }

  /// ISO 时间 → `yyyy-MM-dd HH:mm`；缺失显示「—」。
  String _time(String? value) {
    final String raw = (value ?? '').trim();
    if (raw.isEmpty) {
      return '—';
    }
    if (raw.length >= 16) {
      return raw.substring(0, 16).replaceFirst('T', ' ');
    }
    return raw;
  }
}

/// 只读字段行：左标签右值。
class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

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
            style: theme.textTheme.bodyMedium,
          ),
        ),
      ],
    );
  }
}
