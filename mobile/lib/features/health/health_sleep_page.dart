import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_scope.dart';
import '../../core/data/overview_controller.dart';
import '../../core/models/health_models.dart';
import '../../core/network/api_exception.dart';
import '../../core/utils/formatters.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/list_load_more_footer.dart';
import '../../shared/widgets/root_page_scaffold.dart';
import '../../shared/widgets/v2/stat_rail.dart';
import '../../shared/widgets/v2/v2_page_kit.dart';
import '../../shared/widgets/v2/v2_rows.dart';
import '../../theme/app_tokens.dart';

/// 睡眠体征：累计概览 + 分阶段均值 + 睡眠记录分页与增改删。
///
/// 数据：
/// - `GET /health/vitals-sleep/stats?days=0`
/// - `GET /health/vitals-sleep?page=&page_size=20`
/// - 写操作在睡眠表单页：POST / PUT / DELETE。
///
/// 深睡/浅睡/醒来次数/质量等字段可能未采集，一律显示「—」而不是 0；
/// 分阶段字段后端为 null 时连「深睡/浅睡」行都不展示，避免把缺失读成 0。
class HealthSleepPage extends StatefulWidget {
  const HealthSleepPage({super.key});

  @override
  State<HealthSleepPage> createState() => _HealthSleepPageState();
}

class _HealthSleepPageState extends State<HealthSleepPage> {
  final List<SleepRecord> _items = <SleepRecord>[];

  SleepStats? _stats;
  LoadStatus _status = LoadStatus.loading;
  String? _message;

  int _page = 1;
  int _total = 0;
  bool _hasMore = true;
  bool _loadingMore = false;

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

  /// 首屏/重试：并行拉统计与第一页记录，任一失败整体失败。
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
      final List<Map<String, dynamic>?> responses = await Future.wait(
        <Future<Map<String, dynamic>?>>[
          scope.apiClient
              .get<Map<String, dynamic>>(
                '/health/vitals-sleep/stats',
                queryParameters: <String, dynamic>{'days': 0},
              )
              .then((value) => value.data),
          scope.apiClient
              .get<Map<String, dynamic>>(
                '/health/vitals-sleep',
                queryParameters: <String, dynamic>{'page': 1, 'page_size': 20},
              )
              .then((value) => value.data),
        ],
      );
      final Map<String, dynamic>? statsJson = responses[0];
      final Map<String, dynamic>? listJson = responses[1];
      if (statsJson == null || listJson == null) {
        throw const ApiException(
          kind: ApiErrorKind.badResponse,
          message: '睡眠接口返回数据为空',
        );
      }
      final List<SleepRecord> items = _parseItems(listJson);
      if (!mounted) {
        return;
      }
      setState(() {
        _stats = SleepStats.fromJson(statsJson);
        _items
          ..clear()
          ..addAll(items);
        _page = 1;
        _total = (listJson['total'] as num?)?.toInt() ?? items.length;
        _hasMore = _items.length < _total;
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

  /// 加载更多睡眠记录；失败只提示，不清空已加载数据。
  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) {
      return;
    }
    final AppScope scope = AppScope.of(context);
    setState(() => _loadingMore = true);
    try {
      final Map<String, dynamic>? json =
          (await scope.apiClient.get<Map<String, dynamic>>(
            '/health/vitals-sleep',
            queryParameters: <String, dynamic>{
              'page': _page + 1,
              'page_size': 20,
            },
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
        _page += 1;
        _items.addAll(_parseItems(json));
        _total = (json['total'] as num?)?.toInt() ?? _items.length;
        _hasMore = _items.length < _total;
      });
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('加载更多失败：${error.message}')));
    } finally {
      if (mounted) {
        setState(() => _loadingMore = false);
      }
    }
  }

  /// 从分页响应中取出 `items` 并转为 [SleepRecord]。
  List<SleepRecord> _parseItems(Map<String, dynamic> json) {
    return ((json['items'] as List?) ?? const <dynamic>[])
        .whereType<Map>()
        .map((Map item) => SleepRecord.fromJson(item.cast<String, dynamic>()))
        .toList();
  }

  /// 打开睡眠表单：`record` 为空是新增，否则带快照直接预填编辑。
  ///
  /// 表单保存/删除成功后返回 true，本页重拉统计与第一页记录。
  Future<void> _openForm([SleepRecord? record]) async {
    final String path = record == null
        ? '/health/vitals-sleep/new'
        : '/health/vitals-sleep/${record.id}';
    final bool? changed = await context.push<bool>(path, extra: record);
    if (changed == true && mounted) {
      await _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    final SleepStats? stats = _stats;

    return DetailPageScaffold(
      title: '睡眠体征',
      child: ListPageBody(
        status: _status,
        message: _message,
        onRetry: _refresh,
        blocks: <Widget>[
          if (stats != null) ...<Widget>[
            SummaryStrip(
              // 均值已经在下方数值格里，标题只说明统计范围，避免重复数值。
              caption: '统计全部睡眠记录',
              items: <StatRailItem>[
                StatRailItem(
                  label: '平均时长',
                  value: _durationCompact(stats.avgDurationMin),
                ),
                StatRailItem(
                  label: '平均质量',
                  value: stats.avgQuality == null
                      ? '—'
                      : '${formatOneDecimal(stats.avgQuality)} / 10',
                ),
              ],
            ),
            const SectionHeader(title: '分阶段睡眠'),
            GroupCard(
              children: stats.hasStageData
                  ? <Widget>[
                      RecordRow(
                        title: '深睡',
                        subtitle: '设备上报均值',
                        value: formatDuration(stats.avgDeepMin?.round()),
                      ),
                      RecordRow(
                        title: '浅睡',
                        subtitle: '设备上报均值',
                        value: formatDuration(stats.avgLightMin?.round()),
                      ),
                    ]
                  : const <Widget>[
                      EmptyState(
                        icon: Icons.bedtime_outlined,
                        title: '暂无分阶段数据',
                        description: '当前记录未上报深睡/浅睡时长，未采集字段显示「—」',
                        compact: true,
                      ),
                    ],
            ),
            SectionHeader(
              title: '睡眠记录 · 共 ${formatInt(_total)} 条',
              actionLabel: '新增记录',
              onAction: () => _openForm(),
            ),
            GroupCard(
              children: <Widget>[
                if (_items.isEmpty)
                  const EmptyState(
                    icon: Icons.bedtime_outlined,
                    title: '暂无睡眠记录',
                    description: '点「新增记录」录入第一条',
                    compact: true,
                  )
                else
                  for (final SleepRecord record in _items)
                    _SleepRow(record: record, onTap: () => _openForm(record)),
              ],
            ),
            Text(
              '分阶段时长由设备上报，未采集时显示「—」。',
              style: AppType.rowMeta.copyWith(color: tokens.text3),
            ),
          ],
        ],
        footer: _items.isNotEmpty
            ? ListLoadMoreFooter(
                loading: _loadingMore,
                hasMore: _hasMore,
                onPressed: _loadMore,
              )
            : null,
      ),
    );
  }

  /// 摘要轨里的时长压缩：`432` → `7h12m`，空值显示「—」。
  static String _durationCompact(int? minutes) {
    if (minutes == null || minutes <= 0) {
      return '—';
    }
    final int hours = minutes ~/ 60;
    final int rest = minutes % 60;
    if (hours == 0) {
      return '${rest}m';
    }
    return rest == 0 ? '${hours}h' : '${hours}h${rest}m';
  }
}

/// 睡眠记录行：日期 + 时长/质量 + 入睡/起床 + 分阶段与醒来次数。
///
/// 分阶段字段为 null 时不渲染对应文字（不显示「深睡 —」），
/// 其余未采集字段仍按「—」展示。
class _SleepRow extends StatelessWidget {
  const _SleepRow({required this.record, required this.onTap});

  final SleepRecord record;
  final VoidCallback onTap;

  /// 血压 / 心率 / 血氧 / 血糖 / 体温中已采集的部分，全部缺失返回 null。
  String? get _vitalsText {
    final List<String> parts = <String>[];
    if (record.bloodPressureHigh != null || record.bloodPressureLow != null) {
      parts.add(
        '血压 ${record.bloodPressureHigh ?? '—'}/${record.bloodPressureLow ?? '—'}',
      );
    }
    if (record.heartRate != null) {
      parts.add('心率 ${record.heartRate}');
    }
    if (record.bloodOxygen != null) {
      parts.add('血氧 ${formatOneDecimal(record.bloodOxygen)}%');
    }
    if (record.bloodGlucose != null) {
      parts.add('血糖 ${formatOneDecimal(record.bloodGlucose)}');
    }
    if (record.bodyTemp != null) {
      parts.add('体温 ${formatOneDecimal(record.bodyTemp)}℃');
    }
    return parts.isEmpty ? null : parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    final String wakeLabel = record.wakeCount == null
        ? '—'
        : '${record.wakeCount} 次';
    final String? vitals = _vitalsText;
    // 入睡/起床、体征、分阶段与醒来次数合并为一行副信息，超长时最多两行。
    final String meta = <String>[
      '入睡 ${record.bedtime ?? '—'} · 起床 ${record.wakeTime ?? '—'}',
      ?vitals,
      if (record.deepSleepMin != null)
        '深睡 ${formatDuration(record.deepSleepMin)}',
      if (record.lightSleepMin != null)
        '浅睡 ${formatDuration(record.lightSleepMin)}',
      '醒来 $wakeLabel',
      if ((record.note ?? '').trim().isNotEmpty) record.note!.trim(),
    ].join(' · ');

    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 52),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      formatListDate(record.recordDate),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.rowTitle.copyWith(color: tokens.text),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      meta,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.rowMeta.copyWith(color: tokens.text2),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Text(
                    formatDuration(record.durationMin),
                    maxLines: 1,
                    softWrap: false,
                    style: AppType.rowValue.copyWith(color: tokens.text),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    record.sleepQuality == null
                        ? '质量 —'
                        : '质量 ${record.sleepQuality}/10',
                    maxLines: 1,
                    softWrap: false,
                    style: AppType.rowMeta.copyWith(color: tokens.text2),
                  ),
                ],
              ),
              const SizedBox(width: 6),
              Icon(Icons.chevron_right, size: 15, color: tokens.text3),
            ],
          ),
        ),
      ),
    );
  }
}
