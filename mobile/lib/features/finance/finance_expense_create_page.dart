import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_scope.dart';
import '../../core/network/api_exception.dart';
import '../../shared/widgets/app_buttons.dart';
import '../../shared/widgets/app_select.dart';
import '../../shared/widgets/root_page_scaffold.dart';
import '../../shared/widgets/section_card.dart';

/// 记一笔支出（离线队列的第一个端到端写入样本）。
///
/// 走网页端的购物记录接口：`POST /finance/shopping/records`
/// （字段：`record_date` / `product_name` / `total_price` / `category_id` / `note`）。
///
/// 与外汇新增不同，这里**先写本地队列再提示**：联网时立刻触发后台同步，
/// 断网时直接提示「已存本地，联网后自动同步」，不再等 HTTP 超时。
class FinanceExpenseCreatePage extends StatefulWidget {
  const FinanceExpenseCreatePage({super.key});

  @override
  State<FinanceExpenseCreatePage> createState() =>
      _FinanceExpenseCreatePageState();
}

class _FinanceExpenseCreatePageState extends State<FinanceExpenseCreatePage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _amount = TextEditingController();
  final TextEditingController _description = TextEditingController();
  final TextEditingController _note = TextEditingController();

  DateTime _date = DateTime.now();
  int? _categoryId;
  final Map<int, String> _categories = <int, String>{};
  bool _loadingCategories = false;
  String? _categoryError;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _loadCategories();
      }
    });
  }

  @override
  void dispose() {
    _amount.dispose();
    _description.dispose();
    _note.dispose();
    super.dispose();
  }

  /// 加载分类字典（`GET /finance/shopping/categories`）。
  ///
  /// 失败不阻塞记支出：分类是可选字段，离线时留空提示即可。
  Future<void> _loadCategories() async {
    final AppScope scope = AppScope.of(context);
    if (!scope.auth.isLoggedIn || !scope.outbox.isOnline) {
      setState(() => _categoryError = '离线状态，分类可留空，同步时不影响');
      return;
    }
    setState(() {
      _loadingCategories = true;
      _categoryError = null;
    });
    try {
      final List<dynamic>? data = (await scope.apiClient
              .get<List<dynamic>>('/finance/shopping/categories'))
          .data;
      if (!mounted) {
        return;
      }
      setState(() {
        _categories
          ..clear()
          ..addAll(
            Map<int, String>.fromEntries(
              (data ?? <dynamic>[]).whereType<Map>().map((Map item) {
                final Map<String, dynamic> json = item.cast<String, dynamic>();
                return MapEntry<int, String>(
                  (json['id'] as num?)?.toInt() ?? -1,
                  json['name'] as String? ?? '',
                );
              }),
            ),
          );
        _loadingCategories = false;
      });
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadingCategories = false;
        _categoryError = '分类加载失败：${error.message}';
      });
    }
  }

  /// `yyyy-MM-dd`（后端 `record_date` 口径）。
  String get _dateText {
    String two(int value) => value < 10 ? '0$value' : '$value';
    return '${_date.year}-${two(_date.month)}-${two(_date.day)}';
  }

  /// 选择消费日期。
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

  /// 保存：先落本地队列，再返回；同步由队列后台完成。
  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    final AppScope scope = AppScope.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final bool online = scope.outbox.isOnline;
    setState(() => _saving = true);
    final double amount =
        double.parse(_amount.text.replaceAll(',', '').trim());
    final entry = await scope.outbox.enqueueExpense(<String, dynamic>{
      'record_date': _dateText,
      'product_name': _description.text.trim(),
      'total_price': amount,
      if (_categoryId != null) 'category_id': _categoryId,
      if (_note.text.trim().isNotEmpty) 'note': _note.text.trim(),
    });
    if (!mounted) {
      return;
    }
    setState(() => _saving = false);
    if (entry == null) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('待同步已达上限（200 条），请先联网同步后再记一笔'),
        ),
      );
      return;
    }
    context.pop(true);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          online ? '已保存，正在同步到服务器' : '已存本地，联网后自动同步',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppScope scope = AppScope.of(context);
    final ThemeData theme = Theme.of(context);
    final bool online = scope.outbox.isOnline;
    return DetailPageScaffold(
      title: '记一笔支出',
      bottomBar: SizedBox(
        height: kAppButtonHeight,
        width: double.infinity,
        child: AppPrimaryButton(
          label: online ? '保存' : '保存到本地',
          loading: _saving,
          onPressed: _saving ? null : _save,
        ),
      ),
      child: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: <Widget>[
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 12,
              children: <Widget>[
                if (!online) _offlineBanner(theme),
                SectionCard(
                  title: '支出信息',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: 12,
                    children: <Widget>[
                      TextFormField(
                        controller: _amount,
                        autofocus: true,
                        textAlign: TextAlign.end,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: '金额（元）',
                          hintText: '0.00',
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
                      TextFormField(
                        controller: _description,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: '说明',
                          hintText: '例如：午餐、加油、日用品',
                        ),
                        validator: (String? value) {
                          if (value == null || value.trim().isEmpty) {
                            return '请填写这笔支出的说明';
                          }
                          return null;
                        },
                      ),
                      _FieldTile(
                        label: '消费日期',
                        value: _dateText,
                        icon: Icons.calendar_today_outlined,
                        onTap: _pickDate,
                      ),
                      _CategorySelector(
                        categories: _categories,
                        value: _categoryId,
                        loading: _loadingCategories,
                        onChanged: (int? value) =>
                            setState(() => _categoryId = value),
                      ),
                      if (_categoryError != null)
                        Text(
                          _categoryError!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
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
                      hintText: '可选，例如商户、用途',
                    ),
                  ),
                ),
                Text(
                  '保存后先进入本地队列；联网时自动按顺序同步，成功即从队列移除。',
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

  /// 离线提示：说明保存会进本地队列，避免用户以为没保存成功。
  Widget _offlineBanner(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        spacing: 8,
        children: <Widget>[
          Icon(
            Icons.cloud_off_outlined,
            size: 18,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          Expanded(
            child: Text(
              '当前无网络：保存后进入本地队列，联网后自动同步',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 分类选择器：可选，未选择时按「未分类」提交。
class _CategorySelector extends StatelessWidget {
  const _CategorySelector({
    required this.categories,
    required this.value,
    required this.loading,
    required this.onChanged,
  });

  final Map<int, String> categories;
  final int? value;
  final bool loading;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    return AppSelectField<int?>(
      label: '分类',
      value: value,
      helperText: loading ? '分类加载中…' : null,
      options: <AppSelectOption<int?>>[
        const AppSelectOption<int?>(value: null, label: '未分类'),
        for (final MapEntry<int, String> item in categories.entries)
          AppSelectOption<int?>(value: item.key, label: item.value),
      ],
      onChanged: onChanged,
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
