import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/models/report_models.dart';
import '../../core/network/api_exception.dart';
import '../../shared/widgets/app_buttons.dart';
import '../../shared/widgets/root_page_scaffold.dart';
import '../../shared/widgets/section_card.dart';

/// 报告生成页：财务 / 投资 / 健康 / 生活报告共用。
///
/// 接口：`POST {source.apiPath}/generate`，请求体 `{days, start_date, end_date}`。
/// 区间口径与网页端 `ReportPeriodPicker` 一致：
/// - 近 7 / 30 / 90 天：结束日为今天，向前回溯 `days - 1` 天（含今天）；
/// - 自定义：显式给起止日期，后端按 `[start_date, end_date]` 闭区间统计，
///   起止顺序填反时由后端自动交换。
///
/// 生成成功后返回新报告 id，由列表页刷新并直接打开明细。
class ReportGeneratePage extends StatefulWidget {
  const ReportGeneratePage({super.key, required this.source});

  final ReportSource source;

  @override
  State<ReportGeneratePage> createState() => _ReportGeneratePageState();
}

class _ReportGeneratePageState extends State<ReportGeneratePage> {
  static const List<int> _presetDays = <int>[7, 30, 90];

  /// 选中的预设天数；为 null 表示自定义区间。
  int? _days = 30;

  DateTime? _start;
  DateTime? _end;

  bool _generating = false;
  String? _error;

  /// `yyyy-MM-dd`（后端 `date` 字段口径）。
  String _dateText(DateTime date) {
    String two(int value) => value < 10 ? '0$value' : '$value';
    return '${date.year}-${two(date.month)}-${two(date.day)}';
  }

  /// 选择起止日期；选择器默认带出已选值或今天。
  Future<void> _pickDate({required bool isStart}) async {
    final DateTime now = DateTime.now();
    final DateTime initial =
        (isStart ? _start : _end) ??
        (isStart ? now.subtract(const Duration(days: 29)) : now);
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 1, 12, 31),
    );
    if (picked == null || !mounted) {
      return;
    }
    setState(() {
      if (isStart) {
        _start = picked;
      } else {
        _end = picked;
      }
      _error = null;
    });
  }

  /// 生成报告：成功后退回列表并带上新报告 id。
  Future<void> _generate() async {
    final int? days = _days;
    if (days == null && (_start == null || _end == null)) {
      setState(() => _error = '请选择自定义区间的开始与结束日期');
      return;
    }
    final AppScope scope = AppScope.of(context);
    final NavigatorState navigator = Navigator.of(context);
    setState(() {
      _generating = true;
      _error = null;
    });
    final Map<String, dynamic> payload = <String, dynamic>{'days': days ?? 30};
    if (days == null) {
      payload['start_date'] = _dateText(_start!);
      payload['end_date'] = _dateText(_end!);
    }
    try {
      final Map<String, dynamic>? json =
          (await scope.apiClient.post<Map<String, dynamic>>(
            '${widget.source.apiPath}/generate',
            data: payload,
          )).data;
      if (json == null) {
        throw const ApiException(
          kind: ApiErrorKind.badResponse,
          message: '生成接口未返回报告',
        );
      }
      final int id = (json['id'] as num?)?.toInt() ?? 0;
      if (id <= 0) {
        throw const ApiException(
          kind: ApiErrorKind.badResponse,
          message: '生成接口未返回报告编号',
        );
      }
      if (!mounted) {
        return;
      }
      navigator.pop(id);
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _generating = false;
        _error = error.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color muted = theme.colorScheme.onSurfaceVariant;
    final bool custom = _days == null;
    final String range = custom
        ? (_start == null || _end == null
              ? '未选择'
              : '${_dateText(_start!)} ~ ${_dateText(_end!)}')
        : '${_dateText(DateTime.now().subtract(Duration(days: _days! - 1)))} ~ '
              '${_dateText(DateTime.now())}';

    return DetailPageScaffold(
      title: '生成${widget.source.pageTitle}',
      bottomBar: AppPrimaryButton(
        label: '生成报告',
        icon: Icons.auto_awesome_outlined,
        loading: _generating,
        onPressed: _generating ? null : _generate,
      ),
      child: Form(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: <Widget>[
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 16,
              children: <Widget>[
                SectionCard(
                  title: '统计区间',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: 12,
                    children: <Widget>[
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: <Widget>[
                          for (final int days in _presetDays)
                            ChoiceChip(
                              label: Text('近 $days 天'),
                              selected: _days == days,
                              onSelected: _generating
                                  ? null
                                  : (_) => setState(() {
                                      _days = days;
                                      _error = null;
                                    }),
                            ),
                          ChoiceChip(
                            label: const Text('自定义'),
                            selected: custom,
                            onSelected: _generating
                                ? null
                                : (_) => setState(() {
                                    _days = null;
                                    _error = null;
                                  }),
                          ),
                        ],
                      ),
                      if (custom) ...<Widget>[
                        _DateTile(
                          label: '开始日期',
                          value: _start == null ? '请选择' : _dateText(_start!),
                          onTap: _generating
                              ? null
                              : () => _pickDate(isStart: true),
                        ),
                        _DateTile(
                          label: '结束日期',
                          value: _end == null ? '请选择' : _dateText(_end!),
                          onTap: _generating
                              ? null
                              : () => _pickDate(isStart: false),
                        ),
                      ],
                      Text(
                        custom
                            ? '按自定义起止日期闭区间统计：$range'
                            : '含今天在内的近 ${_days ?? 30} 天：$range',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: muted,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_error != null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _error!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 日期行：只读展示 + 点击交给上层弹日期选择器。
class _DateTile extends StatelessWidget {
  const _DateTile({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: InputDecorator(
        decoration: InputDecoration(labelText: label),
        child: Row(
          children: <Widget>[
            Expanded(child: Text(value)),
            Icon(
              Icons.calendar_today_outlined,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}
