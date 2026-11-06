/// 生活域模型：物品追踪与卡片管理（只读列表所需字段）。
///
/// 卡号只在客户端做脱敏展示，模型不提供任何完整卡号的格式化输出。
library;

/// 物品状态标签：in_use / lost / loaned / recycled。
String itemStatusLabel(String status) {
  switch (status) {
    case 'lost':
      return '已丢失';
    case 'loaned':
      return '已借出';
    case 'recycled':
      return '已回收';
    default:
      return '使用中';
  }
}

/// 物品到期提示：`daysLeft` 为负表示已过期，为 0 表示今天到期。
///
/// 仅当 `expire_date` 有值时才生成；没填到期日的物品返回 null，
/// 不参与「临期 / 过期」判定。
class ItemExpiry {
  const ItemExpiry({required this.daysLeft, required this.isExpired});

  final int daysLeft;
  final bool isExpired;
}

/// 单件物品（`GET /lifestyle/items` 列表项）。
class LifestyleItem {
  const LifestyleItem({
    required this.id,
    required this.itemName,
    required this.category,
    this.location,
    required this.status,
    this.purchaseDate,
    this.price,
    this.expireDate,
    this.endDate,
    required this.source,
    this.note,
  });

  final int id;
  final String itemName;
  final String category;
  final String? location;
  final String status;
  final String? purchaseDate;
  final double? price;
  final String? expireDate;
  final String? endDate;
  final String source;
  final String? note;

  /// 到期提示：到期日为空或无法解析时返回 null（视为「未填到期日」）。
  ItemExpiry? expiryInfo({DateTime? today}) {
    final String? raw = expireDate;
    if (raw == null || raw.isEmpty) {
      return null;
    }
    final DateTime? date = DateTime.tryParse(raw);
    if (date == null) {
      return null;
    }
    final DateTime base = today ?? DateTime.now();
    final DateTime expire = DateTime(date.year, date.month, date.day);
    final DateTime now = DateTime(base.year, base.month, base.day);
    final int left = expire.difference(now).inDays;
    return ItemExpiry(daysLeft: left, isExpired: left < 0);
  }

  factory LifestyleItem.fromJson(Map<String, dynamic> json) {
    return LifestyleItem(
      id: (json['id'] as num?)?.toInt() ?? 0,
      itemName: json['item_name'] as String? ?? '',
      category: json['category'] as String? ?? '',
      location: json['location'] as String?,
      status: json['status'] as String? ?? 'in_use',
      purchaseDate: json['purchase_date'] as String?,
      price: json['price'] == null ? null : (json['price'] as num).toDouble(),
      expireDate: json['expire_date'] as String?,
      endDate: json['end_date'] as String?,
      source: json['source'] as String? ?? 'manual',
      note: json['note'] as String?,
    );
  }
}

/// 名称 + 数量的聚合项（按状态 / 分类 / 银行）。
class LabelCount {
  const LabelCount({required this.label, required this.count});

  final String label;
  final int count;
}

/// 物品汇总（`GET /lifestyle/items/stats?days=`）。
class ItemStats {
  const ItemStats({
    required this.total,
    required this.inUse,
    required this.totalValue,
    required this.totalUsageDays,
    required this.avgDailyCost,
    required this.expiring,
    required this.expired,
    required this.byStatus,
  });

  final int total;
  final int inUse;
  final double totalValue;
  final int totalUsageDays;
  final double avgDailyCost;

  /// 临期数：后端按 `days` 窗口计算，只有填了到期日的物品会计入。
  final int expiring;

  /// 过期数：只有填了到期日且早于今天才会计入。
  final int expired;

  final List<LabelCount> byStatus;

  factory ItemStats.fromJson(Map<String, dynamic> json) {
    List<LabelCount> parse(String key, String labelKey) {
      return ((json[key] as List?) ?? const <dynamic>[])
          .whereType<Map>()
          .map((Map item) => LabelCount(
                label: item[labelKey] as String? ?? '',
                count: (item['count'] as num?)?.toInt() ?? 0,
              ))
          .toList(growable: false);
    }

    return ItemStats(
      total: (json['total'] as num?)?.toInt() ?? 0,
      inUse: (json['in_use'] as num?)?.toInt() ?? 0,
      totalValue: (json['total_value'] as num?)?.toDouble() ?? 0,
      totalUsageDays: (json['total_usage_days'] as num?)?.toInt() ?? 0,
      avgDailyCost: (json['avg_daily_cost'] as num?)?.toDouble() ?? 0,
      expiring: (json['expiring'] as num?)?.toInt() ?? 0,
      expired: (json['expired'] as num?)?.toInt() ?? 0,
      byStatus: parse('by_status', 'status'),
    );
  }
}

/// 卡号脱敏：只保留后四位，其余一律用 `••••` 代替。
///
/// 卡号为空或不足四位时返回 `未填卡号` / 原文短尾，绝不完整展示。
String maskCardNumber(String? raw) {
  final String digits =
      (raw ?? '').replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) {
    return '未填卡号';
  }
  if (digits.length <= 4) {
    return '•••• $digits';
  }
  return '•••• ${digits.substring(digits.length - 4)}';
}

/// 银行卡类型：credit / debit。
String cardCategoryLabel(String value) =>
    value == 'credit' ? '信用卡' : '借记卡';

/// 银行卡形态：physical / virtual。
String cardFormLabel(String value) => value == 'virtual' ? '虚拟' : '实体';

/// 银行卡状态：active / frozen / expired / closed。
String cardStatusLabel(String value) {
  switch (value) {
    case 'frozen':
      return '已冻结';
    case 'expired':
      return '已过期';
    case 'closed':
      return '已销户';
    default:
      return '正常';
  }
}

/// 单张银行卡（`GET /lifestyle/bank-cards` 列表项）。
///
/// 完整卡号只保存在 [cardNumber] 供脱敏计算，界面必须使用 [maskedNumber]。
class BankCard {
  const BankCard({
    required this.id,
    required this.cardName,
    this.cardHolder,
    required this.bank,
    required this.cardCategory,
    required this.cardForm,
    this.cardNumber,
    this.balance,
    this.creditLimit,
    this.billingDay,
    this.dueDay,
    this.expireDate,
    required this.status,
    this.note,
  });

  final int id;
  final String cardName;
  final String? cardHolder;
  final String bank;
  final String cardCategory;
  final String cardForm;
  final String? cardNumber;
  final double? balance;
  final double? creditLimit;
  final int? billingDay;
  final int? dueDay;
  final String? expireDate;
  final String status;
  final String? note;

  bool get isCredit => cardCategory == 'credit';

  /// 脱敏卡号（只留后四位），列表与详情只允许展示这个值。
  String get maskedNumber => maskCardNumber(cardNumber);

  /// 账单日 / 还款日文案；未设置时返回 null。
  String? get billingText {
    if (!isCredit || billingDay == null || dueDay == null) {
      return null;
    }
    return '账单日 $billingDay · 还款日 $dueDay';
  }

  factory BankCard.fromJson(Map<String, dynamic> json) {
    return BankCard(
      id: (json['id'] as num?)?.toInt() ?? 0,
      cardName: json['card_name'] as String? ?? '',
      cardHolder: json['card_holder'] as String?,
      bank: json['bank'] as String? ?? '',
      cardCategory: json['card_category'] as String? ?? 'debit',
      cardForm: json['card_form'] as String? ?? 'physical',
      cardNumber: json['card_number'] as String?,
      balance: json['balance'] == null
          ? null
          : (json['balance'] as num).toDouble(),
      creditLimit: json['credit_limit'] == null
          ? null
          : (json['credit_limit'] as num).toDouble(),
      billingDay: (json['billing_day'] as num?)?.toInt(),
      dueDay: (json['due_day'] as num?)?.toInt(),
      expireDate: json['expire_date'] as String?,
      status: json['status'] as String? ?? 'active',
      note: json['note'] as String?,
    );
  }
}

/// 银行卡汇总（`GET /lifestyle/bank-cards/stats?days=`）。
class BankStats {
  const BankStats({
    required this.total,
    required this.active,
    required this.balanceTotal,
    required this.creditTotal,
    required this.byBank,
    required this.byCategory,
  });

  final int total;
  final int active;
  final double balanceTotal;
  final double creditTotal;
  final List<LabelCount> byBank;
  final List<LabelCount> byCategory;

  /// 指定卡类型的数量（如 credit / debit）。
  int countOfCategory(String category) {
    for (final LabelCount item in byCategory) {
      if (item.label == category) {
        return item.count;
      }
    }
    return 0;
  }

  factory BankStats.fromJson(Map<String, dynamic> json) {
    List<LabelCount> parse(String key, String labelKey) {
      return ((json[key] as List?) ?? const <dynamic>[])
          .whereType<Map>()
          .map((Map item) => LabelCount(
                label: item[labelKey] as String? ?? '',
                count: (item['count'] as num?)?.toInt() ?? 0,
              ))
          .toList(growable: false);
    }

    return BankStats(
      total: (json['total'] as num?)?.toInt() ?? 0,
      active: (json['active'] as num?)?.toInt() ?? 0,
      balanceTotal: (json['balance_total'] as num?)?.toDouble() ?? 0,
      creditTotal: (json['credit_total'] as num?)?.toDouble() ?? 0,
      byBank: parse('by_bank', 'bank'),
      byCategory: parse('by_category', 'card_category'),
    );
  }
}
