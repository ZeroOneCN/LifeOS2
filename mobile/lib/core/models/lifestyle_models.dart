/// 生活域模型：物品追踪与卡片管理（只读列表所需字段）。
///
/// 卡号按用户要求完整展示（每 4 位分组），不提供任何脱敏输出。
library;

import '../utils/formatters.dart';

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

/// 物品状态下拉选项：取值与后端 `ItemCreate` pattern 一致，文案沿用列表既有口径。
const List<({String value, String label})> kItemStatuses =
    <({String value, String label})>[
      (value: 'in_use', label: '使用中'),
      (value: 'loaned', label: '已借出'),
      (value: 'lost', label: '已丢失'),
      (value: 'recycled', label: '已回收'),
    ];

/// 物品来源下拉选项：manual 手动录入 / shopping 购物同步。
const List<({String value, String label})> kItemSources =
    <({String value, String label})>[
      (value: 'manual', label: '手动'),
      (value: 'shopping', label: '购物同步'),
    ];

/// 物品分类预设：与网页端 `pages/lifestyle/items.tsx` 的固定分类一致。
///
/// 统计接口的 `by_category` 只覆盖已有数据，新建时若只依赖它会出现「无选项」，
/// 因此以这组预设为底、再并入历史分类。
const List<String> kItemCategories = <String>[
  '电子',
  '服饰',
  '书籍',
  '家居',
  '数码配件',
  '购物',
  '其他',
];

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
    required this.byCategory,
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

  /// 按分类统计；新增/编辑物品时作为分类下拉的可选项（与网页端同源）。
  final List<LabelCount> byCategory;

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
      byCategory: parse('by_category', 'category'),
    );
  }
}

/// 完整卡号展示：每 4 位用空格分组，方便在窄屏上一眼核对。
///
/// 用户明确要求不再脱敏，因此这里不做任何遮挡；长号码只分组、不截断，
/// 由界面按可用宽度自然换行。
String formatCardNumber(String? raw) {
  final String value = (raw ?? '').trim().replaceAll(RegExp(r'\s+'), '');
  if (value.isEmpty) {
    return '未填卡号';
  }
  if (value.length <= 12) {
    return value;
  }
  final StringBuffer buffer = StringBuffer();
  for (int i = 0; i < value.length; i++) {
    if (i > 0 && i % 4 == 0) {
      buffer.write(' ');
    }
    buffer.write(value[i]);
  }
  return buffer.toString();
}

/// 复制用纯号码：去掉空格与分隔符；缺号时返回 null。
String? copyableCardNumber(String? raw) {
  final String value = (raw ?? '').trim();
  if (value.isEmpty) {
    return null;
  }
  final String digits = value.replaceAll(RegExp(r'[^0-9]'), '');
  return digits.isEmpty ? value : digits;
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
/// 完整卡号直接展示：列表用 [displayNumber]（分组不截断），
/// 复制用 [copyableNumber]（纯数字、无空格）。
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

  /// 完整卡号展示：每 4 位分组，不脱敏、不截断。
  String get displayNumber => formatCardNumber(cardNumber);

  /// 复制用纯号码；缺号时返回 null。
  String? get copyableNumber => copyableCardNumber(cardNumber);

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

/// 单张手机号卡（`GET /lifestyle/phone-cards` 列表项，只读）。
///
/// 号码按用户要求完整展示，复制时提交纯数字。
class PhoneCard {
  const PhoneCard({
    required this.id,
    required this.phoneNumber,
    required this.operator,
    this.region,
    this.balance,
    this.openingBalance,
    this.monthlyFee,
    this.billDay,
    this.dataPlan,
    this.callPlan,
    this.smsPlan,
    required this.status,
    this.note,
    this.billingType = 'monthly',
    this.chargeMode = 'monthly',
    this.autoCharge = true,
    this.billPaidThisMonth = false,
    this.monthCharged = 0,
    this.monthExpected = 0,
  });

  final int id;
  final String phoneNumber;
  final String operator;
  final String? region;
  final double? balance;

  /// 起始余额（`opening_balance`）：接口 `balance`（`balance` 字段）是
  /// 「起始余额 + Σ流水」的派生值，起始余额为 0 且无流水时 0 只是默认值。
  final double? openingBalance;
  final double? monthlyFee;
  final int? billDay;
  final String? dataPlan;
  final String? callPlan;
  final String? smsPlan;
  final String status;
  final String? note;

  /// 资费口径（后端派生字段）：`monthly` 月租 / `yearly` 年费；扣费方式同名字段。
  final String billingType;
  final String chargeMode;
  final bool autoCharge;

  /// 本月是否已扣账、已扣金额与应扣金额（后端按当月流水派生）。
  final bool billPaidThisMonth;
  final double monthCharged;
  final double monthExpected;

  /// 完整号码展示：与银行卡同一口径（长号码分组，不脱敏、不截断）。
  String get displayNumber => formatCardNumber(phoneNumber);

  /// 已采集的余额；未采集（返回 null，或起始余额为 0 且流水净额为 0）返回 null。
  ///
  /// 与 [balanceText] 使用同一判定，合计口径据此只累加「已采集部分」。
  double? get collectedBalance {
    final double? value = balance;
    if (value == null) {
      return null;
    }
    if (value == 0 && (openingBalance ?? 0) == 0) {
      return null;
    }
    return value;
  }

  /// 话费余额文案。
  ///
  /// 后端 `balance` 恒为派生值（起始余额 + Σ流水），没有单独的「是否已采集」标记；
  /// 因此按「返回 null，或起始余额 0（默认值）且流水净额 0」判定为未采集，显示「—」，
  /// 其余按金额展示（真 0 显示 `¥0.00`）。
  String get balanceText {
    final double? value = collectedBalance;
    return value == null ? '—' : formatMoney(value);
  }

  /// 复制用纯号码；缺号时返回 null。
  String? get copyableNumber => copyableCardNumber(phoneNumber);

  /// 套餐文案：流量 / 通话 / 短信三项中有值的拼在一起；全空返回「未设置套餐」。
  ///
  /// 后端未配置的通话/短信项存的是 `"0"`，直接拼接会出现 `0 · 30 · 0`
  /// 这类噪音，因此跳过数值为 0 的项（带单位的 `200MB/月` 仍保留）。
  String get planText {
    bool meaningful(String? raw) {
      final String value = (raw ?? '').trim();
      if (value.isEmpty) {
        return false;
      }
      final double? number = double.tryParse(value);
      return number == null || number > 0;
    }

    final List<String> parts = <String>[
      if (meaningful(dataPlan)) dataPlan!.trim(),
      if (meaningful(callPlan)) callPlan!.trim(),
      if (meaningful(smsPlan)) smsPlan!.trim(),
    ];
    return parts.isEmpty ? '未设置套餐' : parts.join(' · ');
  }

  /// 本月扣费文案；无需扣费的卡返回 null。
  ///
  /// 用于「扣费」按钮旁说明当前账期状态，同时为「补齐本月应扣」提供上下文。
  String? get monthBillText {
    if (monthExpected <= 0 && monthCharged <= 0) {
      return null;
    }
    if (billPaidThisMonth) {
      return '本月已扣 ${formatMoney(monthCharged)}';
    }
    return '本月应扣 ${formatMoney(monthExpected)} · 待扣';
  }

  factory PhoneCard.fromJson(Map<String, dynamic> json) {
    return PhoneCard(
      id: (json['id'] as num?)?.toInt() ?? 0,
      phoneNumber: json['phone_number'] as String? ?? '',
      operator: json['operator'] as String? ?? '',
      region: json['region'] as String?,
      balance: json['balance'] == null
          ? null
          : (json['balance'] as num).toDouble(),
      openingBalance: json['opening_balance'] == null
          ? null
          : (json['opening_balance'] as num).toDouble(),
      monthlyFee: json['monthly_fee'] == null
          ? null
          : (json['monthly_fee'] as num).toDouble(),
      billDay: (json['bill_day'] as num?)?.toInt(),
      dataPlan: json['data_plan'] as String?,
      callPlan: json['call_plan'] as String?,
      smsPlan: json['sms_plan'] as String?,
      status: json['status'] as String? ?? 'active',
      note: json['note'] as String?,
      billingType: json['billing_type'] as String? ?? 'monthly',
      chargeMode: json['charge_mode'] as String? ?? 'monthly',
      autoCharge: json['auto_charge'] as bool? ?? true,
      billPaidThisMonth: json['bill_paid_this_month'] as bool? ?? false,
      monthCharged: (json['month_charged'] as num?)?.toDouble() ?? 0,
      monthExpected: (json['month_expected'] as num?)?.toDouble() ?? 0,
    );
  }
}

/// 手机号卡资金流水（`GET /lifestyle/phone-cards/{id}/ledger`）。
///
/// amount 有符号：充值与余额上调为正，扣费与下调为负。
class PhoneLedgerEntry {
  const PhoneLedgerEntry({
    required this.id,
    required this.entryType,
    required this.entryDate,
    required this.amount,
    this.note,
  });

  final int id;
  final String entryType;
  final String entryDate;
  final double amount;
  final String? note;

  /// 充值 / 扣费 / 校准。
  String get typeLabel {
    switch (entryType) {
      case 'recharge':
        return '充值';
      case 'charge':
        return '扣费';
      case 'adjust':
        return '校准';
      default:
        return entryType;
    }
  }

  /// 带符号金额文案：正数补 `+`，负数由 [formatMoney] 自带减号。
  String get amountText => amount > 0
      ? '+${formatMoney(amount)}'
      : formatMoney(amount);

  factory PhoneLedgerEntry.fromJson(Map<String, dynamic> json) {
    return PhoneLedgerEntry(
      id: (json['id'] as num?)?.toInt() ?? 0,
      entryType: json['entry_type'] as String? ?? '',
      entryDate: json['entry_date'] as String? ?? '',
      amount: (json['amount'] as num?)?.toDouble() ?? 0,
      note: json['note'] as String?,
    );
  }
}
