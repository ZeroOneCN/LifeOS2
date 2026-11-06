import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_scope.dart';
import '../../core/network/api_exception.dart';
import '../../shared/widgets/root_page_scaffold.dart';
import '../../shared/widgets/section_card.dart';

/// 新增一笔外汇交易（`POST /investment/forex`）。
///
/// 字段与网页端 `pages/investment/forex.tsx` 的 `tradeFields` 对齐：
/// 交易日期、品种、订单类型、手数、开仓价、平仓价、开/平仓时间、
/// 手续费、隔夜费、盈亏金额、备注。
///
/// 写操作先做在线提交；失败时**保留表单内容**并在页内给出「重试」，
/// 不丢数据。离线排队留给批次 C。
class ForexCreatePage extends StatefulWidget {
  const ForexCreatePage({super.key});

  @override
  State<ForexCreatePage> createState() => _ForexCreatePageState();
}

class _ForexCreatePageState extends State<ForexCreatePage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _symbol = TextEditingController();
  final TextEditingController _lotSize = TextEditingController();
  final TextEditingController _openPrice = TextEditingController();
  final TextEditingController _closePrice = TextEditingController();
  final TextEditingController _commission = TextEditingController();
  final TextEditingController _overnightFee = TextEditingController();
  final TextEditingController _pnl = TextEditingController();
  final TextEditingController _note = TextEditingController();

  String _orderType = 'buy';
  DateTime _tradeDate = DateTime.now();
  DateTime? _openTime;
  DateTime? _closeTime;

  bool _submitting = false;
  String? _submitError;

  @override
  void dispose() {
    _symbol.dispose();
    _lotSize.dispose();
    _openPrice.dispose();
    _closePrice.dispose();
    _commission.dispose();
    _overnightFee.dispose();
    _pnl.dispose();
    _note.dispose();
    super.dispose();
  }

  /// 解析输入框数字：空串返回 null，去掉千分位后解析。
  double? _num(String raw) {
    final String text = raw.replaceAll(',', '').trim();
    if (text.isEmpty) {
      return null;
    }
    return double.tryParse(text);
  }

  /// `yyyy-MM-dd`（后端 `trade_date` 口径）。
  String _dateText(DateTime value) {
    String two(int v) => v < 10 ? '0$v' : '$v';
    return '${value.year}-${two(value.month)}-${two(value.day)}';
  }

  /// `yyyy-MM-dd HH:mm`（仅展示用）。
  String _timeText(DateTime value) {
    String two(int v) => v < 10 ? '0$v' : '$v';
    return '${_dateText(value)} ${two(value.hour)}:${two(value.minute)}';
  }

  /// ISO 时间（后端 `open_time` / `close_time` 口径）。
  String _isoText(DateTime value) {
    String two(int v) => v < 10 ? '0$v' : '$v';
    return '${_dateText(value)}T${two(value.hour)}:${two(value.minute)}:00';
  }

  /// 选择交易日期。
  Future<void> _pickTradeDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _tradeDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(DateTime.now().year + 1, 12, 31),
    );
    if (picked == null || !mounted) {
      return;
    }
    setState(() => _tradeDate = picked);
  }

  /// 选择开仓 / 平仓时间（先日期再时间，可清除）。
  Future<void> _pickDateTime({required bool open}) async {
    final DateTime initial = (open ? _openTime : _closeTime) ?? DateTime.now();
    final DateTime? day = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(DateTime.now().year + 1, 12, 31),
    );
    if (day == null || !mounted) {
      return;
    }
    final TimeOfDay? time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null || !mounted) {
      return;
    }
    final DateTime value =
        DateTime(day.year, day.month, day.day, time.hour, time.minute);
    setState(() {
      if (open) {
        _openTime = value;
      } else {
        _closeTime = value;
      }
    });
  }

  /// 组装提交体；空值字段不发送（后端有默认值）。
  Map<String, dynamic> _buildPayload() {
    final String note = _note.text.trim();
    final double? closePrice = _num(_closePrice.text);
    final double? pnl = _num(_pnl.text);
    final String? openTime = _openTime == null ? null : _isoText(_openTime!);
    final String? closeTime =
        _closeTime == null ? null : _isoText(_closeTime!);
    return <String, dynamic>{
      'trade_date': _dateText(_tradeDate),
      'symbol': _symbol.text.trim(),
      'order_type': _orderType,
      'open_price': _num(_openPrice.text) ?? 0,
      'lot_size': _num(_lotSize.text) ?? 0,
      'commission': _num(_commission.text) ?? 0,
      'overnight_fee': _num(_overnightFee.text) ?? 0,
      'close_price': ?closePrice,
      'pnl': ?pnl,
      'open_time': ?openTime,
      'close_time': ?closeTime,
      if (note.isNotEmpty) 'note': note,
    };
  }

  /// 提交：成功后返回列表（`true` 触发刷新）；失败保留表单并可重试。
  Future<void> _submit() async {
    if (_submitting) {
      return;
    }
    final FormState? form = _formKey.currentState;
    if (form == null || !form.validate()) {
      return;
    }
    final Map<String, dynamic> payload = _buildPayload();
    setState(() {
      _submitting = true;
      _submitError = null;
    });
    try {
      await AppScope.of(context).apiClient.post<Map<String, dynamic>>(
            '/investment/forex',
            data: payload,
          );
      if (!mounted) {
        return;
      }
      context.pop(true);
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _submitting = false;
        _submitError = error.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return DetailPageScaffold(
      title: '新增交易',
      child: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: <Widget>[
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 12,
              children: <Widget>[
                if (_submitError != null) _submitErrorBanner(theme),
                SectionCard(
                  title: '基础信息',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: 12,
                    children: <Widget>[
                      _FieldTile(
                        label: '交易日期',
                        value: _dateText(_tradeDate),
                        icon: Icons.calendar_today_outlined,
                        onTap: _pickTradeDate,
                      ),
                      TextFormField(
                        controller: _symbol,
                        textCapitalization: TextCapitalization.characters,
                        decoration: const InputDecoration(
                          labelText: '交易品种',
                          hintText: 'EUR/USD',
                        ),
                        validator: (String? value) {
                          if (value == null || value.trim().isEmpty) {
                            return '请填写交易品种';
                          }
                          return null;
                        },
                      ),
                      _OrderTypeSelector(
                        value: _orderType,
                        onChanged: (String value) =>
                            setState(() => _orderType = value),
                      ),
                      TextFormField(
                        controller: _lotSize,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: '手数',
                          hintText: '0.10',
                        ),
                        validator: (String? value) {
                          final double? parsed = _num(value ?? '');
                          if (parsed == null || parsed <= 0) {
                            return '请输入大于 0 的手数';
                          }
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
                SectionCard(
                  title: '价格与时间',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: 12,
                    children: <Widget>[
                      Row(
                        spacing: 12,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Expanded(
                            child: TextFormField(
                              controller: _openPrice,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                              decoration: const InputDecoration(
                                labelText: '开仓价格',
                                hintText: '1.0800',
                              ),
                              validator: (String? value) {
                                final double? parsed = _num(value ?? '');
                                if (parsed == null || parsed <= 0) {
                                  return '请输入有效价格';
                                }
                                return null;
                              },
                            ),
                          ),
                          Expanded(
                            child: TextFormField(
                              controller: _closePrice,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                              decoration: const InputDecoration(
                                labelText: '平仓价格',
                                hintText: '可不填',
                              ),
                              validator: (String? value) {
                                if (value == null || value.trim().isEmpty) {
                                  return null;
                                }
                                return _num(value) == null ? '请输入有效数字' : null;
                              },
                            ),
                          ),
                        ],
                      ),
                      _FieldTile(
                        label: '开仓时间',
                        value: _openTime == null ? '未设置' : _timeText(_openTime!),
                        icon: Icons.schedule_outlined,
                        onTap: () => _pickDateTime(open: true),
                        onClear: _openTime == null
                            ? null
                            : () => setState(() => _openTime = null),
                      ),
                      _FieldTile(
                        label: '平仓时间',
                        value:
                            _closeTime == null ? '未设置' : _timeText(_closeTime!),
                        icon: Icons.schedule_outlined,
                        onTap: () => _pickDateTime(open: false),
                        onClear: _closeTime == null
                            ? null
                            : () => setState(() => _closeTime = null),
                      ),
                    ],
                  ),
                ),
                SectionCard(
                  title: '费用与盈亏',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: 12,
                    children: <Widget>[
                      Row(
                        spacing: 12,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Expanded(
                            child: TextFormField(
                              controller: _commission,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                decimal: true,
                                signed: true,
                              ),
                              decoration: const InputDecoration(
                                labelText: '手续费',
                                hintText: '0',
                              ),
                              validator: _optionalNumber,
                            ),
                          ),
                          Expanded(
                            child: TextFormField(
                              controller: _overnightFee,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                decimal: true,
                                signed: true,
                              ),
                              decoration: const InputDecoration(
                                labelText: '隔夜费',
                                hintText: '0',
                              ),
                              validator: _optionalNumber,
                            ),
                          ),
                        ],
                      ),
                      TextFormField(
                        controller: _pnl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                          signed: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: '盈亏金额',
                          hintText: '亏损填负数，未平仓可不填',
                        ),
                        validator: _optionalNumber,
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
                      hintText: '可选，例如策略、复盘结论',
                    ),
                  ),
                ),
                SizedBox(
                  height: 48,
                  child: FilledButton(
                    onPressed: _submitting ? null : _submit,
                    child: _submitting
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            spacing: 8,
                            children: <Widget>[
                              SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: theme.colorScheme.onPrimary,
                                ),
                              ),
                              const Text('提交中…'),
                            ],
                          )
                        : Text(_submitError == null ? '保存交易' : '重新提交'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 可选数字校验：允许空；非空必须是合法数字。
  String? _optionalNumber(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }
    return _num(value) == null ? '请输入有效数字' : null;
  }

  /// 提交失败提示：失败不清空表单，提供「重试」。
  Widget _submitErrorBanner(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        spacing: 8,
        children: <Widget>[
          Icon(
            Icons.error_outline,
            size: 18,
            color: theme.colorScheme.onErrorContainer,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 2,
              children: <Widget>[
                Text(
                  '提交失败：$_submitError',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onErrorContainer,
                  ),
                ),
                Text(
                  '表单内容已保留，点击「重试」重新提交',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onErrorContainer
                        .withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: _submitting ? null : _submit,
            child: const Text('重试'),
          ),
        ],
      ),
    );
  }
}

/// 订单类型：做多 Buy / 做空 Sell。
class _OrderTypeSelector extends StatelessWidget {
  const _OrderTypeSelector({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<String>(
      segments: const <ButtonSegment<String>>[
        ButtonSegment<String>(value: 'buy', label: Text('做多 Buy')),
        ButtonSegment<String>(value: 'sell', label: Text('做空 Sell')),
      ],
      selected: <String>{value},
      onSelectionChanged: (Set<String> selection) =>
          onChanged(selection.first),
    );
  }
}

/// 行内选择项：标签 + 当前值 + 图标；有值时给「清除」。
class _FieldTile extends StatelessWidget {
  const _FieldTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
    this.onClear,
  });

  final String label;
  final String value;
  final IconData icon;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color muted = theme.colorScheme.onSurfaceVariant;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          spacing: 8,
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 2,
                children: <Widget>[
                  Text(
                    label,
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  ),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
            if (onClear != null)
              TextButton(
                onPressed: onClear,
                child: const Text('清除'),
              ),
            Icon(icon, size: 18, color: muted),
          ],
        ),
      ),
    );
  }
}
