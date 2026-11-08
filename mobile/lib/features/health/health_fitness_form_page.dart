import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/models/health_models.dart';
import '../../core/network/api_exception.dart';
import '../../shared/widgets/app_buttons.dart';
import '../../shared/widgets/app_select.dart';
import '../../shared/widgets/root_page_scaffold.dart';
import '../../shared/widgets/section_card.dart';

/// 运动记录录入 / 编辑：日期 + 类型 + 时长（必填）+ 热量 / 距离 / 备注（可选）。
///
/// 与网页端 `/health/fitness?tab=exercise` 口径一致：
/// - 新增：`POST /health/fitness`，底部整行「保存」；输入类型与时长后
///   调用 `GET /health/fitness/estimate`（300ms 防抖）自动推算热量。
/// - 编辑：`PUT /health/fitness/{id}`，底部「左保存、右删除」，删除二次确认。
/// - 热量 / 距离留空提交 null，由后端保留为空并在列表显示「—」，
///   绝不把「未填写」写成 0。
/// - 估算仅在新增时触发（与网页端一致）；编辑时允许手改所有字段，
///   避免改正类型/时长还要回网页端。
class HealthFitnessFormPage extends StatefulWidget {
  const HealthFitnessFormPage({super.key, this.recordId, this.initial});

  /// 编辑模式的记录 id；为空即新增。
  final int? recordId;

  /// 列表带进来的快照，用于打开即预填；为空时按 [recordId] 拉取。
  final FitnessRecord? initial;

  @override
  State<HealthFitnessFormPage> createState() => _HealthFitnessFormPageState();
}

class _HealthFitnessFormPageState extends State<HealthFitnessFormPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _duration = TextEditingController();
  final TextEditingController _calories = TextEditingController();
  final TextEditingController _distance = TextEditingController();
  final TextEditingController _note = TextEditingController();

  DateTime _date = DateTime.now();
  String _type = '';

  bool _loading = false;
  bool _saving = false;
  bool _deleting = false;
  String? _error;

  /// 热量估算状态：请求中 / 已命中 / 未命中（无内置 MET 参数）。
  bool _estimating = false;
  bool _estimated = false;
  bool _estimateMiss = false;
  int _estimateSeq = 0;
  Timer? _estimateTimer;

  bool get _editing => widget.recordId != null;

  @override
  void initState() {
    super.initState();
    if (_editing) {
      final FitnessRecord? initial = widget.initial;
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

  @override
  void dispose() {
    _estimateTimer?.cancel();
    _duration.dispose();
    _calories.dispose();
    _distance.dispose();
    _note.dispose();
    super.dispose();
  }

  /// 用一条记录预填表单；类型按网页端口径转成中文展示名。
  void _apply(FitnessRecord record) {
    _date = DateTime.tryParse(record.recordDate) ?? DateTime.now();
    _type = fitnessTypeLabel(record.exerciseType);
    _duration.text = '${record.durationMin}';
    _calories.text = record.calories == null ? '' : _plain(record.calories!);
    _distance.text = record.distanceKm == null
        ? ''
        : _plain(record.distanceKm!);
    _note.text = record.note ?? '';
  }

  /// 编辑模式兜底：没有快照时按 id 取最新记录。
  Future<void> _loadRecord() async {
    final AppScope scope = AppScope.of(context);
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final Map<String, dynamic>? json =
          (await scope.apiClient.get<Map<String, dynamic>>(
            '/health/fitness/${widget.recordId}',
          )).data;
      if (json == null) {
        throw const ApiException(
          kind: ApiErrorKind.badResponse,
          message: '运动记录返回为空',
        );
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _apply(FitnessRecord.fromJson(json));
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

  /// `yyyy-MM-dd`（后端 `record_date` 口径）。
  String get _dateText {
    String two(int value) => value < 10 ? '0$value' : '$value';
    return '${_date.year}-${two(_date.month)}-${two(_date.day)}';
  }

  /// 选择运动日期。
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

  /// 可空数值字段：留空返回 null，非法输入交给校验器拦截。
  double? _optional(TextEditingController controller) {
    final String text = controller.text.replaceAll(',', '').trim();
    return text.isEmpty ? null : double.tryParse(text);
  }

  /// 类型或时长变化后安排一次估算：300ms 防抖，序号防止旧请求覆盖新结果。
  ///
  /// 仅新增时触发（网页端编辑模式不自动重算），避免编辑时手填的热量
  /// 被异步请求意外覆盖。
  void _scheduleEstimate() {
    if (_editing) {
      return;
    }
    _estimateTimer?.cancel();
    final String type = _type.trim();
    final int? duration = int.tryParse(_duration.text.trim());
    if (type.isEmpty || duration == null || duration <= 0) {
      return;
    }
    _estimateTimer = Timer(const Duration(milliseconds: 300), () {
      _estimate(type, duration);
    });
  }

  /// 调后端 MET 估算接口并回填热量字段。
  ///
  /// 未命中内置参数时保持留空（不写 0），并提示可手动填写。
  Future<void> _estimate(String type, int duration) async {
    final AppScope scope = AppScope.of(context);
    final int seq = ++_estimateSeq;
    setState(() => _estimating = true);
    try {
      final Map<String, dynamic>? json =
          (await scope.apiClient.get<Map<String, dynamic>>(
            '/health/fitness/estimate',
            queryParameters: <String, dynamic>{
              'exercise_type': type,
              'duration_min': duration,
            },
          )).data;
      if (!mounted || seq != _estimateSeq) {
        return;
      }
      final double? calories = (json?['calories'] as num?)?.toDouble();
      final bool matched = json?['matched'] as bool? ?? false;
      setState(() {
        _estimating = false;
        _estimated = matched && calories != null && calories > 0;
        _estimateMiss = !_estimated;
        if (_estimated) {
          _calories.text = _plain(calories!);
        }
      });
    } on ApiException {
      if (!mounted || seq != _estimateSeq) {
        return;
      }
      // 估算失败不阻塞保存：热量留空，后端会按同一套 MET 兜底。
      setState(() {
        _estimating = false;
        _estimated = false;
        _estimateMiss = false;
      });
    }
  }

  /// 提交：新增走 POST、编辑走 PUT；失败保留输入便于修正。
  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    if (_type.trim().isEmpty) {
      setState(() => _error = '请选择运动类型');
      return;
    }
    final AppScope scope = AppScope.of(context);
    final NavigatorState navigator = Navigator.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    if (!scope.connectivity.isOnline) {
      setState(() => _error = '当前无网络：运动记录需要联网，请恢复网络后重试');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final int duration = int.parse(_duration.text.trim());
    final Map<String, dynamic> payload = <String, dynamic>{
      'record_date': _dateText,
      'exercise_type': _type.trim(),
      'duration_min': duration,
      // 显式回传 null：允许把历史误填的热量 / 距离清空，后端不会写成 0。
      'calories': _optional(_calories),
      'distance_km': _optional(_distance),
      'note': _note.text.trim().isEmpty ? null : _note.text.trim(),
    };
    try {
      if (_editing) {
        await scope.apiClient.put<Map<String, dynamic>>(
          '/health/fitness/${widget.recordId}',
          data: payload,
        );
      } else {
        await scope.apiClient.post<Map<String, dynamic>>(
          '/health/fitness',
          data: payload,
        );
      }
      if (!mounted) {
        return;
      }
      navigator.pop(true);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            _editing
                ? '已保存 $_dateText 的${_type.trim()}记录'
                : '已添加 ${_type.trim()} · $duration 分钟',
          ),
        ),
      );
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _saving = false;
        _error = error.message;
      });
    }
  }

  /// 删除：二次确认说明汇总会同步回退，成功后返回列表刷新统计。
  Future<void> _delete() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('删除该条运动记录？'),
          content: Text(
            '将删除 $_dateText 的${_type.trim()}记录。\n'
            '删除后总时长、总消耗、运动次数与按类型汇总会同步回退，且无法恢复。',
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
      await scope.apiClient.delete<dynamic>(
        '/health/fitness/${widget.recordId}',
      );
      if (!mounted) {
        return;
      }
      navigator.pop(true);
      messenger.showSnackBar(const SnackBar(content: Text('已删除该条运动记录')));
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
    final String calorieHint = _editing
        ? '编辑时不会自动重算热量，可手动修改；留空将按运动类型与时长估算'
        : _estimating
        ? '正在按类型与时长估算…'
        : _estimated
        ? '已按运动类型与时长自动估算，可手动修改'
        : _estimateMiss
        ? '该类型暂无估算参数，请手动填写消耗'
        : '选择类型并填写时长后自动估算，可手动修改';
    return DetailPageScaffold(
      title: _editing ? '编辑运动记录' : '新增运动记录',
      bottomBar: _editing
          ? AppActionRow(
              first: AppPrimaryButton(
                label: '保存',
                icon: Icons.save_outlined,
                loading: _saving,
                onPressed: _loading || _saving || _deleting ? null : _save,
              ),
              second: AppDangerButton(
                label: '删除',
                loading: _deleting,
                onPressed: _loading || _saving || _deleting ? null : _delete,
              ),
            )
          : AppPrimaryButton(
              label: '保存',
              icon: Icons.save_outlined,
              loading: _saving,
              onPressed: _loading || _saving ? null : _save,
            ),
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.only(bottom: 16),
                children: <Widget>[
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: 12,
                    children: <Widget>[
                      if (_error != null)
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.errorContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            _error!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onErrorContainer,
                            ),
                          ),
                        ),
                      SectionCard(
                        title: _editing ? '修改运动记录' : '运动信息',
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
                              label: '运动类型',
                              value: _type,
                              options: <AppSelectOption<String>>[
                                for (final String item
                                    in kFitnessExerciseOptions)
                                  AppSelectOption<String>(
                                    value: item,
                                    label: item,
                                  ),
                                // 历史数据可能是选项外的类型（如「登山」），
                                // 原样保留避免编辑时选中项丢失。
                                if (_type.isNotEmpty &&
                                    !kFitnessExerciseOptions.contains(_type))
                                  AppSelectOption<String>(
                                    value: _type,
                                    label: _type,
                                  ),
                              ],
                              hint: '请选择运动类型',
                              onChanged: (String value) {
                                setState(() => _type = value);
                                _scheduleEstimate();
                              },
                            ),
                            TextFormField(
                              controller: _duration,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: '时长（必填）',
                                hintText: '例如 30',
                                suffixText: '分钟',
                              ),
                              onChanged: (_) {
                                setState(() {});
                                _scheduleEstimate();
                              },
                              validator: (String? value) {
                                final int? parsed = int.tryParse(
                                  (value ?? '').trim(),
                                );
                                if (parsed == null || parsed <= 0) {
                                  return '请输入大于 0 的整数分钟';
                                }
                                return null;
                              },
                            ),
                            TextFormField(
                              controller: _calories,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: InputDecoration(
                                labelText: '消耗热量（可选）',
                                hintText: _estimating ? '推算中…' : '留空则不填',
                                suffixText: 'kcal',
                                helperText: calorieHint,
                                helperMaxLines: 2,
                              ),
                              validator: (String? value) =>
                                  _validateNonNegative(value, '消耗热量'),
                            ),
                            TextFormField(
                              controller: _distance,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: const InputDecoration(
                                labelText: '距离（可选）',
                                hintText: '留空则不填',
                                suffixText: 'km',
                              ),
                              validator: (String? value) =>
                                  _validateNonNegative(value, '距离'),
                            ),
                          ],
                        ),
                      ),
                      SectionCard(
                        title: '备注',
                        child: TextFormField(
                          controller: _note,
                          maxLines: 3,
                          decoration: const InputDecoration(
                            hintText: '可选，例如配速、器械、身体感受',
                          ),
                        ),
                      ),
                      Text(
                        _editing
                            ? '删除后区间汇总与按类型统计会同步更新。'
                            : '保存后列表与区间汇总会同步更新；热量留空时按运动类型与时长估算。',
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

  /// 可选数值校验：留空合法；填写必须是不小于 0 的数字。
  String? _validateNonNegative(String? value, String label) {
    final String text = (value ?? '').replaceAll(',', '').trim();
    if (text.isEmpty) {
      return null;
    }
    final double? parsed = double.tryParse(text);
    if (parsed == null || parsed < 0) {
      return '请输入不小于 0 的$label';
    }
    return null;
  }
}

/// 把数值转成不带多余尾零的输入文本（例如 320.0 → 320、12.50 → 12.5）。
String _plain(double value) {
  return value.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
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
