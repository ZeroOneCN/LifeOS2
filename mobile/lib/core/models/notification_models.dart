/// 内部事件键 → 可读来源名。
///
/// 后端 `source` 存的是 `feature_key:dedup`（如 `finance_loan_due:574:due`），
/// 直接展示会把表名/主键暴露给用户；这里只映射已知功能键，未知键一律隐藏。
const Map<String, String> _kNotificationSourceLabels = <String, String>{
  'finance_subscription_due': '服务订阅到期',
  'finance_utility_due': '水电燃气到期',
  'finance_rent_due': '房租应缴',
  'finance_loan_due': '网贷还款',
  'finance_reminder_due': '账单提醒',
  'finance_debt_due': '债务到期',
  'lifestyle_item_expire': '物品保质期',
  'lifestyle_phone_bill': '手机卡月租',
  'lifestyle_phone_low_balance': '话费余额不足',
  'lifestyle_bankcard_due': '银行卡还款',
  'lifestyle_card_expire': '银行卡有效期',
  'health_med_stock': '药品低库存',
  'health_checkup_due': '体检到期',
};

/// 通知中心模型（`GET /notifications` 列表项）。
class AppNotification {
  const AppNotification({
    required this.id,
    required this.title,
    this.content,
    required this.category,
    this.source,
    required this.read,
    required this.notifyDate,
    this.note,
  });

  final int id;
  final String title;
  final String? content;
  final String category;
  final String? source;
  final bool read;
  final String notifyDate;
  final String? note;

  /// 可读来源名；未知事件键返回 null（界面直接隐藏，不展示原始键）。
  String? get sourceLabel {
    final String raw = (source ?? '').trim();
    if (raw.isEmpty) {
      return null;
    }
    return _kNotificationSourceLabels[raw.split(':').first];
  }

  /// 正文转一行摘要：去掉换行与多余空白，供折叠态两行截断展示。
  String get summary {
    return (content ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// 标记已读后的本地副本（其他字段保持不变）。
  AppNotification copyWith({bool? read}) {
    return AppNotification(
      id: id,
      title: title,
      content: content,
      category: category,
      source: source,
      read: read ?? this.read,
      notifyDate: notifyDate,
      note: note,
    );
  }

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    return AppNotification(
      id: (json['id'] as num?)?.toInt() ?? 0,
      title: json['title'] as String? ?? '',
      content: json['content'] as String?,
      category: json['category'] as String? ?? '',
      source: json['source'] as String?,
      read: json['read'] as bool? ?? false,
      notifyDate: json['notify_date'] as String? ?? '',
      note: json['note'] as String?,
    );
  }
}
