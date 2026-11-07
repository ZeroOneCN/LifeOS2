import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/network/api_exception.dart';
import '../../shared/widgets/root_page_scaffold.dart';
import '../../shared/widgets/section_card.dart';

/// 步数录入：选择日期 + 时间段 + 步数，直接调 `POST /health/steps`。
///
/// 字段与网页端一致：`record_date` / `period` / `steps`；
/// 距离与消耗由后端按步幅自动计算（默认 70cm、0.04 kcal/步），不需要客户端传。
///
/// 为什么不做离线队列：步数录入的诉求是「录完立刻看到汇总变化」，
/// 而后端没有幂等键，排队重试可能重复入库（同一天同一时段会被 409 拦下，
/// 但用户得回队列里手动处理）；在线提交失败时用户就在表单前，可直接重试。
class HealthStepsCreatePage extends StatefulWidget {
  const HealthStepsCreatePage({super.key});

  @override
  State<HealthStepsCreatePage> createState() => _HealthStepsCreatePageState();
}

class _HealthStepsCreatePageState extends State<HealthStepsCreatePage> {
  /// 后端 `EXPECTED_PERIODS`：16 个整点时段 + `full`（全天最终累计）。
  static const List<({String value, String label})> _periods =
      <({String value, String label})>[
    (value: '08-09', label: '08:00-09:00'),
    (value: '09-10', label: '09:00-10:00'),
    (value: '10-11', label: '10:00-11:00'),
    (value: '11-12', label: '11:00-12:00'),
    (value: '12-13', label: '12:00-13:00'),
    (value: '13-14', label: '13:00-14:00'),
    (value: '14-15', label: '14:00-15:00'),
    (value: '15-16', label: '15:00-16:00'),
    (value: '16-17', label: '16:00-17:00'),
    (value: '17-18', label: '17:00-18:00'),
    (value: '18-19', label: '18:00-19:00'),
    (value: '19-20', label: '19:00-20:00'),
    (value: '20-21', label: '20:00-21:00'),
    (value: '21-22', label: '21:00-22:00'),
    (value: '22-23', label: '22:00-23:00'),
    (value: '23-24', label: '23:00-23:59'),
    (value: 'full', label: '23:59（全天最终）'),
  ];

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _steps = TextEditingController();

  DateTime _date = DateTime.now();
  String _period = _periodForNow();
  bool _saving = false;
  String? _error;

  /// 当前小时落在哪个时段；凌晨归到最早的 08-09（与网页端一致）。
  static String _periodForNow() {
    final int hour = DateTime.now().hour;
    if (hour >= 23) {
      return '23-24';
    }
    if (hour < 8) {
      return '08-09';
    }
    final String value = '$hour-${hour + 1}';
    return _periods.any((({String value, String label}) item) => item.value == value)
        ? value
        : 'full';
  }

  @override
  void dispose() {
    _steps.dispose();
    super.dispose();
  }

  /// `yyyy-MM-dd`（后端 `record_date` 口径）。
  String get _dateText {
    String two(int value) => value < 10 ? '0$value' : '$value';
    return '${_date.year}-${two(_date.month)}-${two(_date.day)}';
  }

  /// 选择录入日期。
  Future<void> _pickDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(DateTime.now().year + 1, 12, 31),
    );
    if (picked == null || !mounted) {
      return;
    }
    setState(() => _date = picked);
  }

  /// 提交：在线创建；409（同日期同时段已存在）在表单内提示并保留输入。
  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    final AppScope scope = AppScope.of(context);
    final NavigatorState navigator = Navigator.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    if (!scope.outbox.isOnline) {
      setState(() => _error = '当前无网络：步数录入需要联网，请恢复网络后重试');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await scope.apiClient.post<Map<String, dynamic>>(
        '/health/steps',
        data: <String, dynamic>{
          'record_date': _dateText,
          'period': _period,
          'steps': int.parse(_steps.text.trim()),
        },
      );
      if (!mounted) {
        return;
      }
      navigator.pop(true);
      messenger.showSnackBar(
        SnackBar(content: Text('已保存 ${_periodLabel(_period)} ${_steps.text.trim()} 步')),
      );
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _saving = false;
        _error = error.message.contains('已存在')
            ? '$_dateText 已存在 ${_periodLabel(_period)} 的记录，请换个时间段或去网页端编辑'
            : error.message;
      });
    }
  }

  /// 时段值 → 展示文案；未知值原样返回。
  static String _periodLabel(String value) {
    for (final ({String value, String label}) item in _periods) {
      if (item.value == value) {
        return item.label;
      }
    }
    return value;
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final int steps = int.tryParse(_steps.text.trim()) ?? 0;
    return DetailPageScaffold(
      title: '新增步数',
      child: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: <Widget>[
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 12,
              children: <Widget>[
                SectionCard(
                  title: '步数信息',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: 12,
                    children: <Widget>[
                      _FieldTile(
                        label: '日期',
                        value: _dateText,
                        icon: Icons.calendar_today_outlined,
                        onTap: _pickDate,
                      ),
                      DropdownButtonFormField<String>(
                        initialValue: _period,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: '时间段'),
                        items: <DropdownMenuItem<String>>[
                          for (final ({String value, String label}) item
                              in _periods)
                            DropdownMenuItem<String>(
                              value: item.value,
                              child: Text(item.label),
                            ),
                        ],
                        onChanged: (String? value) {
                          if (value != null) {
                            setState(() => _period = value);
                          }
                        },
                      ),
                      TextFormField(
                        controller: _steps,
                        autofocus: true,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: '步数',
                          hintText: '例如 3200',
                        ),
                        onChanged: (_) => setState(() {}),
                        validator: (String? value) {
                          final int? parsed = int.tryParse((value ?? '').trim());
                          if (parsed == null || parsed < 0) {
                            return '请输入不小于 0 的整数步数';
                          }
                          return null;
                        },
                      ),
                      Text(
                        '预计距离 ${(steps * 70 / 100000).toStringAsFixed(2)} km · '
                        '消耗 ${(steps * 0.04).toStringAsFixed(1)} kcal',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
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
                SizedBox(
                  height: 48,
                  child: FilledButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('保存'),
                  ),
                ),
                Text(
                  '保存后列表与区间汇总会立即刷新；同一天同一时间段的记录不能重复添加。',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
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

/// 只读字段行（日期等），点击后交给上层弹选择器。
class _FieldTile extends StatelessWidget {
  const _FieldTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final VoidCallback onTap;

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
            Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
