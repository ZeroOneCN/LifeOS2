import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/models/health_models.dart';
import '../../core/network/api_exception.dart';
import '../../shared/widgets/app_buttons.dart';
import '../../shared/widgets/app_select.dart';
import '../../shared/widgets/root_page_scaffold.dart';
import '../../shared/widgets/section_card.dart';
import '../../shared/widgets/v2/v2_page_kit.dart';

/// 步数录入 / 编辑：日期 + 时间段 + 步数。
///
/// - 新增：`POST /health/steps`，底部整行宽「保存」；保存后**不退出**，
///   自动跳到下一个时间段并清空步数，支持连续录入；最后一个时段保存后返回列表
///   （与网页端一致）。
/// - 编辑：`PUT /health/steps/{id}`，底部「左保存、右删除」，删除二次确认。
///
/// 字段与网页端一致：`record_date` / `period` / `steps`；
/// 距离与消耗由后端按步幅自动计算，编辑时回传原记录的 `stride_cm`，
/// 避免按默认 70cm 重算导致距离口径漂移。
///
/// 写入直接请求服务端：后端没有幂等键，延迟重试可能重复入库；
/// 保存失败时用户就在表单前，按「网络错误 / 服务端错误」提示后可直接重试。
class HealthStepsCreatePage extends StatefulWidget {
  const HealthStepsCreatePage({
    super.key,
    this.recordId,
    this.initial,
  });

  /// 编辑模式的记录 id；为空即新增。
  final int? recordId;

  /// 列表带进来的快照，用于打开即预填；为空时按 [recordId] 拉取。
  final StepRecord? initial;

  @override
  State<HealthStepsCreatePage> createState() => _HealthStepsCreatePageState();
}

class _HealthStepsCreatePageState extends State<HealthStepsCreatePage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _steps = TextEditingController();

  /// 连续录入时把焦点还给步数输入框，减少一次点击。
  final FocusNode _stepsFocus = FocusNode();

  DateTime _date = DateTime.now();
  String _period = _periodForNow();
  StepRecord? _record;

  bool _loading = false;
  bool _saving = false;
  bool _deleting = false;
  String? _error;

  /// 连续录入期间是否已成功保存过；返回列表时用它告诉父页需要刷新。
  bool _savedAny = false;

  bool get _editing => widget.recordId != null;

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
    return kStepPeriods.any(
          (({String value, String label}) item) => item.value == value,
        )
        ? value
        : 'full';
  }

  @override
  void initState() {
    super.initState();
    if (_editing) {
      final StepRecord? initial = widget.initial;
      if (initial != null) {
        _apply(initial);
      } else {
        _loading = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _loadRecord();
          }
        });
      }
    }
  }

  /// 用一条记录预填表单（日期 / 时段 / 步数）。
  void _apply(StepRecord record) {
    _record = record;
    _date = DateTime.tryParse(record.recordDate) ?? DateTime.now();
    _period = record.period;
    _steps.text = '${record.steps}';
  }

  /// 编辑模式兜底：没有快照时按 id 取最新记录。
  Future<void> _loadRecord() async {
    final AppScope scope = AppScope.of(context);
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final Map<String, dynamic>? json = (await scope.apiClient
              .get<Map<String, dynamic>>('/health/steps/${widget.recordId}'))
          .data;
      if (json == null) {
        throw const ApiException(
          kind: ApiErrorKind.badResponse,
          message: '步数记录返回为空',
        );
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _apply(StepRecord.fromJson(json));
        _loading = false;
      });
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = error.message;
      });
    }
  }

  @override
  void dispose() {
    _steps.dispose();
    _stepsFocus.dispose();
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

  /// 提交：新增走 POST、编辑走 PUT；409（同日期同时段已存在）在表单内提示并保留输入。
  ///
  /// 新增成功后与网页端一致：
  /// - 还有下一个时段：保留日期、切到下一个时段、清空步数，继续录入；
  /// - 已是最后一个时段：返回列表，由父页刷新汇总。
  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    final AppScope scope = AppScope.of(context);
    final NavigatorState navigator = Navigator.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    if (!scope.connectivity.isOnline) {
      setState(() => _error = '当前无网络：步数录入需要联网，请恢复网络后重试');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final String savedPeriod = _period;
    final String savedSteps = _steps.text.trim();
    final Map<String, dynamic> payload = <String, dynamic>{
      'record_date': _dateText,
      'period': savedPeriod,
      'steps': int.parse(savedSteps),
    };
    // 编辑时沿用原步幅，让后端按同一口径重算距离与热量。
    final double? stride = _record?.strideCm;
    if (stride != null) {
      payload['stride_cm'] = stride;
    }
    try {
      if (_editing) {
        await scope.apiClient.put<Map<String, dynamic>>(
          '/health/steps/${widget.recordId}',
          data: payload,
        );
      } else {
        await scope.apiClient.post<Map<String, dynamic>>(
          '/health/steps',
          data: payload,
        );
      }
      if (!mounted) {
        return;
      }
      _savedAny = true;
      // 编辑：保存后直接回列表；新增：优先跳到下一个时段连续录入。
      final int index = kStepPeriods.indexWhere(
        (({String value, String label}) item) => item.value == savedPeriod,
      );
      final bool hasNext =
          !_editing && index >= 0 && index < kStepPeriods.length - 1;
      if (!hasNext) {
        navigator.pop(true);
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              _editing
                  ? '已保存 $_dateText ${stepPeriodLabel(savedPeriod)} '
                      '$savedSteps 步'
                  : '已保存 ${stepPeriodLabel(savedPeriod)} $savedSteps 步，'
                      '该日最后一个时段已完成',
            ),
          ),
        );
        return;
      }
      final String nextPeriod = kStepPeriods[index + 1].value;
      setState(() {
        _saving = false;
        _period = nextPeriod;
        _steps.clear();
        _error = null;
      });
      // 保持键盘与焦点，录完一个时段可以直接继续输入下一个时段。
      _stepsFocus.requestFocus();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '已保存 ${stepPeriodLabel(savedPeriod)} $savedSteps 步，'
            '继续录入 ${stepPeriodLabel(nextPeriod)}',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _saving = false;
        _error = error.message.contains('已存在')
            ? '$_dateText 已存在 ${stepPeriodLabel(savedPeriod)} 的记录，请换个时间段'
            : error.message;
      });
    }
  }

  /// 删除：二次确认说明影响范围，成功后返回列表刷新统计。
  Future<void> _delete() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('删除该时段记录？'),
          content: Text(
            '将删除 $_dateText ${stepPeriodLabel(_period)} 的 '
            '${_steps.text.trim()} 步记录。\n'
            '删除后当天汇总、日均与分时段分布会同步回退，且无法恢复。',
          ),
          actions: <Widget>[
            AppActionRow(
              first: AppSecondaryButton(
                label: '取消',
                compact: true,
                onPressed: () => Navigator.of(context).pop(false),
              ),
              second: AppDangerButton(
                label: '删除',
                compact: true,
                onPressed: () => Navigator.of(context).pop(true),
              ),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) {
      return;
    }
    final AppScope scope = AppScope.of(context);
    final NavigatorState navigator = Navigator.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    setState(() {
      _deleting = true;
      _error = null;
    });
    try {
      await scope.apiClient.delete<dynamic>('/health/steps/${widget.recordId}');
      if (!mounted) {
        return;
      }
      navigator.pop(true);
      messenger.showSnackBar(const SnackBar(content: Text('已删除该时段记录')));
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _deleting = false;
        _error = error.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final int steps = int.tryParse(_steps.text.trim()) ?? 0;
    return PopScope(
      // 连续录入期间用户可能直接返回：只要保存过，就把 true 带回列表触发刷新。
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (didPop || !mounted) {
          return;
        }
        Navigator.of(context).pop(_savedAny ? true : result);
      },
      child: _buildPage(theme, steps),
    );
  }

  /// 页面主体：表单 + 底栏保存 / 删除。
  Widget _buildPage(ThemeData theme, int steps) {
    return DetailPageScaffold(
      title: _editing ? '编辑步数' : '新增步数',
      // 保存 / 删除统一放底栏（与其它编辑页一致）：底栏占位，表单不会压住底栏，
      // 键盘弹起时底栏随 body 上移，最末字段与主操作同时可达。
      bottomBar: _loading
          ? null
          : (_editing
              ? AppActionRow(
                  first: AppPrimaryButton(
                    label: '保存',
                    icon: Icons.save_outlined,
                    loading: _saving,
                    onPressed: _deleting ? null : _save,
                  ),
                  second: AppDangerButton(
                    label: '删除',
                    loading: _deleting,
                    onPressed: _saving || _deleting ? null : _delete,
                  ),
                )
              : AppPrimaryButton(
                  label: '保存',
                  icon: Icons.save_outlined,
                  loading: _saving,
                  onPressed: _save,
                )),
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.only(bottom: 32),
                children: <Widget>[
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: 16,
                    children: <Widget>[
                      SectionCard(
                        title: _editing ? '修改时段记录' : '步数信息',
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
                            AppSelectField<String>(
                              label: '时间段',
                              value: _period,
                              options: <AppSelectOption<String>>[
                                for (final ({String value, String label}) item
                                    in kStepPeriods)
                                  AppSelectOption<String>(
                                    value: item.value,
                                    label: item.label,
                                  ),
                                // 历史数据可能用了选项外的时段值，原样保留避免选中项丢失。
                                if (!kStepPeriods.any(
                                  (({String value, String label}) item) =>
                                      item.value == _period,
                                ))
                                  AppSelectOption<String>(
                                    value: _period,
                                    label: _period,
                                  ),
                              ],
                              onChanged: (String value) =>
                                  setState(() => _period = value),
                            ),
                            TextFormField(
                              controller: _steps,
                              focusNode: _stepsFocus,
                              autofocus: !_editing,
                              keyboardType: TextInputType.number,
                              textInputAction: TextInputAction.done,
                              decoration: const InputDecoration(
                                labelText: '步数',
                                hintText: '例如 3200',
                              ),
                              onChanged: (_) => setState(() {}),
                              // 键盘「完成」直接提交，和网页端按 Enter 连续录入一致。
                              onFieldSubmitted: (_) {
                                if (!_saving && !_deleting) {
                                  _save();
                                }
                              },
                              validator: (String? value) {
                                final int? parsed =
                                    int.tryParse((value ?? '').trim());
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
                      if (_error != null) V2ErrorBanner(message: _error!),
                      Text(
                        _editing
                            ? '保存与删除均在线提交；删除后当天汇总、日均与时段分布会立即刷新。'
                            : '保存后自动跳到下一个时间段，可连续录入；'
                                '录完最后一个时段自动返回列表。同一时段不能重复添加。',
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
