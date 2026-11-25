import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/data/overview_controller.dart';
import '../../core/models/investment_models.dart';
import '../../core/network/api_exception.dart';
import '../../core/utils/formatters.dart';
import '../../shared/widgets/root_page_scaffold.dart';
import '../../shared/widgets/v2/stat_rail.dart';
import '../../shared/widgets/v2/v2_page_kit.dart';
import '../../shared/widgets/v2/v2_rows.dart';
import '../../theme/app_tokens.dart';

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
    final AppTokens tokens = AppTokens.of(context);
    final ForexTrade? trade = _trade;
    final double? pnl = trade?.pnl;
    final Color pnlColor = pnl == null
        ? tokens.text2
        : (pnl >= 0 ? tokens.green : tokens.red);

    return DetailPageScaffold(
      title: '交易详情',
      child: ListPageBody(
        status: _status,
        message: _message,
        onRetry: _load,
        blocks: <Widget>[
          if (trade != null) ...<Widget>[
            SummaryStrip(
              caption: '${trade.isOpen ? '持仓中' : '已平仓'} · '
                  '${trade.orderTypeLabel} · ${_plain(trade.lotSize)} 手',
              items: <StatRailItem>[
                StatRailItem(
                  label: '盈亏金额',
                  // 与旧版口径一致：详情主指标仍用盈亏（不含手续费 / 隔夜费），
                  // 净盈亏口径在列表行展示。
                  value: _usdSignedCompact(trade.pnl),
                  color: pnlColor,
                ),
                StatRailItem(
                  label: '手数',
                  value: _plain(trade.lotSize),
                  unit: '手',
                ),
                StatRailItem(
                  label: '持仓时长',
                  value: formatDuration(trade.holding),
                ),
              ],
            ),
            const SectionHeader(title: '交易明细'),
            GroupCard(
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
                _DetailRow(label: '手续费', value: formatUsd(trade.commission)),
                _DetailRow(label: '隔夜费', value: formatUsd(trade.overnightFee)),
                _DetailRow(
                  label: '状态',
                  value: trade.isOpen ? '持仓中' : '已平仓',
                ),
              ],
            ),
            if (trade.note != null && trade.note!.trim().isNotEmpty) ...<Widget>[
              const SectionHeader(title: '备注'),
              // 后端已按库内原文返回（字段名保留，不翻译、不重排），
              // 这里只展示一次原文，不再做可读化解析或追加释义行。
              GroupCard(
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      trade.note!,
                      style: AppType.rowMeta.copyWith(color: tokens.text),
                    ),
                  ),
                ],
              ),
            ],
            Text(
              '行情数据由网页端导入，移动端仅支持查看。',
              style: AppType.rowMeta.copyWith(color: tokens.text3),
            ),
          ],
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

/// 指标轨用的紧凑美元盈亏：`+$1,284` / `-$62`，整数避免小数把格子撑破。
///
/// 明细行的手续费 / 隔夜费仍用 [formatUsd] 保留两位小数，不丢精度。
String _usdSignedCompact(num? value) {
  if (value == null) {
    return '—';
  }
  final String sign = value > 0 ? '+' : (value < 0 ? '-' : '');
  return '$sign\$${formatInt(value.abs())}';
}

/// 只读字段行：左标签右值，数值统一等宽字阶保证右边界稳定。
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
