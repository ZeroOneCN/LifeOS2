import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/models/lifestyle_models.dart';
import '../../core/network/api_exception.dart';
import '../../core/utils/formatters.dart';
import '../../shared/widgets/app_buttons.dart';
import '../../shared/widgets/root_page_scaffold.dart';
import '../../shared/widgets/section_card.dart';

/// 手机号卡充值与校准的共用地基：取卡信息、日期选择、金额输入与提交。
///
/// 两个写操作的字段与规则对齐网页端 `pages/lifestyle/cards.tsx`：
/// - 充值 `POST /lifestyle/phone-cards/{id}/recharge`：金额必填 > 0，
///   充值日期可空（默认今天），备注可空；写入一条正数流水，余额派生更新。
/// - 校准 `POST /lifestyle/phone-cards/{id}/adjust`：真实余额必填（可为负），
///   后端按「真实余额 - 账面余额」生成一条差额流水；差额为 0 时不落账。
class PhoneRechargePage extends StatefulWidget {
  const PhoneRechargePage({super.key, required this.cardId, this.initial});

  final int cardId;

  /// 列表带进来的快照；为空时按 [cardId] 取最新卡片。
  final PhoneCard? initial;

  @override
  State<PhoneRechargePage> createState() => _PhoneRechargePageState();
}

class _PhoneRechargePageState extends State<PhoneRechargePage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _amount = TextEditingController();
  final TextEditingController _note = TextEditingController();

  PhoneCard? _card;
  DateTime _date = DateTime.now();
  bool _loading = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _card = widget.initial;
    if (_card == null) {
      _loading = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _loadCard();
        }
      });
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  /// 兜底拉取卡片；只用于展示号码与当前余额。
  Future<void> _loadCard() async {
    final AppScope scope = AppScope.of(context);
    try {
      final Map<String, dynamic>? json =
          (await scope.apiClient.get<Map<String, dynamic>>(
            '/lifestyle/phone-cards/${widget.cardId}',
          )).data;
      if (!mounted) {
        return;
      }
      setState(() {
        _card = json == null ? null : PhoneCard.fromJson(json);
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

  /// `yyyy-MM-dd`（后端充值日期口径）。
  String get _dateText {
    String two(int value) => value < 10 ? '0$value' : '$value';
    return '${_date.year}-${two(_date.month)}-${two(_date.day)}';
  }

  /// 选择充值日期。
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

  /// 提交充值：成功后余额由后端刷新，返回列表并重拉。
  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    final AppScope scope = AppScope.of(context);
    final NavigatorState navigator = Navigator.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    if (!scope.outbox.isOnline) {
      setState(() => _error = '当前无网络：充值需要联网，请恢复网络后重试');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final Map<String, dynamic>? json =
          (await scope.apiClient.post<Map<String, dynamic>>(
            '/lifestyle/phone-cards/${widget.cardId}/recharge',
            data: <String, dynamic>{
              'amount': double.parse(_amount.text.replaceAll(',', '').trim()),
              'recharge_date': _dateText,
              'note': _note.text.trim().isEmpty ? null : _note.text.trim(),
            },
          )).data;
      final PhoneCard? updated = json == null ? null : PhoneCard.fromJson(json);
      if (!mounted) {
        return;
      }
      navigator.pop(true);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            updated == null
                ? '充值成功，余额已刷新'
                : '已充值，余额 ${updated.balanceText}',
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

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final PhoneCard? card = _card;
    return DetailPageScaffold(
      title: '手机号卡充值',
      bottomBar: AppPrimaryButton(
        label: '确认充值',
        loading: _saving,
        onPressed: _saving ? null : _submit,
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
                        _ErrorBanner(message: _error!, theme: theme),
                      if (card != null)
                        SectionCard(
                          title: '当前卡片',
                          child: _CardSummary(card: card),
                        ),
                      SectionCard(
                        title: '充值信息',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          spacing: 12,
                          children: <Widget>[
                            TextFormField(
                              controller: _amount,
                              autofocus: true,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              textAlign: TextAlign.right,
                              decoration: const InputDecoration(
                                labelText: '充值金额（必填）',
                                hintText: '例如 50',
                                prefixText: '¥ ',
                              ),
                              validator: (String? value) {
                                final double? parsed = double.tryParse(
                                  (value ?? '').replaceAll(',', '').trim(),
                                );
                                if (parsed == null || parsed <= 0) {
                                  return '请输入大于 0 的金额';
                                }
                                return null;
                              },
                            ),
                            _DateField(
                              label: '充值日期',
                              value: _dateText,
                              onTap: _pickDate,
                            ),
                            TextFormField(
                              controller: _note,
                              maxLines: 2,
                              decoration: const InputDecoration(
                                hintText: '可选，例如充值渠道、优惠说明',
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '充值后余额由后端流水重新求和，返回列表会自动刷新。',
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

/// 手机号卡余额校准页：输入运营商显示的真实余额，后端生成差额流水。
class PhoneAdjustPage extends StatefulWidget {
  const PhoneAdjustPage({super.key, required this.cardId, this.initial});

  final int cardId;
  final PhoneCard? initial;

  @override
  State<PhoneAdjustPage> createState() => _PhoneAdjustPageState();
}

class _PhoneAdjustPageState extends State<PhoneAdjustPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _target = TextEditingController();
  final TextEditingController _note = TextEditingController();

  PhoneCard? _card;
  DateTime _date = DateTime.now();
  bool _loading = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _card = widget.initial;
    if (_card == null) {
      _loading = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _loadCard();
        }
      });
    }
  }

  @override
  void dispose() {
    _target.dispose();
    _note.dispose();
    super.dispose();
  }

  /// 兜底拉取卡片；校准需要展示当前账面余额作为参照。
  Future<void> _loadCard() async {
    final AppScope scope = AppScope.of(context);
    try {
      final Map<String, dynamic>? json =
          (await scope.apiClient.get<Map<String, dynamic>>(
            '/lifestyle/phone-cards/${widget.cardId}',
          )).data;
      if (!mounted) {
        return;
      }
      setState(() {
        _card = json == null ? null : PhoneCard.fromJson(json);
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

  /// `yyyy-MM-dd`（后端校准日期口径）。
  String get _dateText {
    String two(int value) => value < 10 ? '0$value' : '$value';
    return '${_date.year}-${two(_date.month)}-${two(_date.day)}';
  }

  /// 选择校准日期。
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

  /// 提交校准：后端按差额生成流水，余额为 0 差额时不落账。
  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    final AppScope scope = AppScope.of(context);
    final NavigatorState navigator = Navigator.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    if (!scope.outbox.isOnline) {
      setState(() => _error = '当前无网络：校准需要联网，请恢复网络后重试');
      return;
    }
    final double target = double.parse(_target.text.replaceAll(',', '').trim());
    final String? before = _card?.balanceText;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final Map<String, dynamic>? json =
          (await scope.apiClient.post<Map<String, dynamic>>(
            '/lifestyle/phone-cards/${widget.cardId}/adjust',
            data: <String, dynamic>{
              'target_balance': target,
              'adjust_date': _dateText,
              'note': _note.text.trim().isEmpty ? null : _note.text.trim(),
            },
          )).data;
      final PhoneCard? updated = json == null ? null : PhoneCard.fromJson(json);
      if (!mounted) {
        return;
      }
      navigator.pop(true);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            updated == null
                ? '校准成功，余额已刷新'
                : '已校准到 ${formatMoney(target)}'
                    '${before == null ? '' : '（原 $before）'}',
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

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final PhoneCard? card = _card;
    return DetailPageScaffold(
      title: '手机号卡校准',
      bottomBar: AppPrimaryButton(
        label: '确认校准',
        loading: _saving,
        onPressed: _saving ? null : _submit,
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
                        _ErrorBanner(message: _error!, theme: theme),
                      if (card != null)
                        SectionCard(
                          title: '当前卡片',
                          child: _CardSummary(card: card),
                        ),
                      SectionCard(
                        title: '校准信息',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          spacing: 12,
                          children: <Widget>[
                            TextFormField(
                              controller: _target,
                              autofocus: true,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                    signed: true,
                                  ),
                              textAlign: TextAlign.right,
                              decoration: const InputDecoration(
                                labelText: '真实余额（必填）',
                                hintText: '运营商 App 显示的实际话费',
                                prefixText: '¥ ',
                              ),
                              validator: (String? value) {
                                final String text =
                                    (value ?? '').replaceAll(',', '').trim();
                                if (text.isEmpty) {
                                  return '请输入真实余额';
                                }
                                if (double.tryParse(text) == null) {
                                  return '请输入有效数字（可为负数）';
                                }
                                return null;
                              },
                            ),
                            _DateField(
                              label: '校准日期',
                              value: _dateText,
                              onTap: _pickDate,
                            ),
                            TextFormField(
                              controller: _note,
                              maxLines: 2,
                              decoration: const InputDecoration(
                                hintText: '可选，例如核对渠道、差异原因',
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '后端按「真实余额 − 账面余额」生成一条差额流水；差额为 0 不会落账。',
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

/// 卡片摘要：号码 + 运营商 + 当前余额（余额为空显示「—」）。
class _CardSummary extends StatelessWidget {
  const _CardSummary({required this.card});

  final PhoneCard card;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color muted = theme.colorScheme.onSurfaceVariant;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 4,
      children: <Widget>[
        Text(
          card.displayNumber,
          maxLines: 2,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
            fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
          ),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 2,
          children: <Widget>[
            Text(
              card.operator,
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
            Text(
              '余额 ${card.balanceText}',
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
          ],
        ),
      ],
    );
  }
}

/// 只读日期行。
class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
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

/// 顶部错误提示条。
class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.theme});

  final String message;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        message,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onErrorContainer,
        ),
      ),
    );
  }
}
