/// 财务域业务模型：账单（网贷/房租等分期账单）、债务（借入/借出）、
/// 购物记录、旅行开支与财务规划。
///
/// 只映射移动端列表与明细需要的字段；时间字段保留后端 `yyyy-MM-dd` 文本，
/// 不在客户端做时区转换（避免跨时区把「到期日」挪一天）。
library;

/// 账单状态：pending 待还 / partial 部分还款 / cleared 已结清。
String billStatusLabel(String status) {
  switch (status) {
    case 'pending':
      return '待还';
    case 'partial':
      return '部分还款';
    case 'cleared':
      return '已结清';
    default:
      return status;
  }
}

/// 债务方向：borrow 借入 / lend 借出。
String debtDirectionLabel(String direction) {
  return direction == 'lend' ? '借出' : '借入';
}

/// 债务状态：active 进行中 / settled 已结清。
String debtStatusLabel(String status) {
  return status == 'settled' ? '已结清' : '进行中';
}

double _toDouble(Object? value) {
  if (value is num) {
    return value.toDouble();
  }
  if (value is String) {
    return double.tryParse(value) ?? 0;
  }
  return 0;
}

int _toInt(Object? value) {
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value) ?? 0;
  }
  return 0;
}

/// 单条账单（`GET /finance/loan-bills` 列表项）。
class BillItem {
  const BillItem({
    required this.id,
    required this.platformId,
    required this.billMonth,
    this.dueDate,
    required this.amount,
    required this.interest,
    required this.paidAmount,
    required this.status,
    this.overdue = false,
    this.graceApplied = false,
    this.note,
  });

  final int id;
  final int platformId;
  final String billMonth;
  final String? dueDate;
  final double amount;
  final double interest;
  final double paidAmount;
  final String status;
  final bool overdue;

  /// 该账单是否已申请容时服务（固定顺延 3 天）。
  final bool graceApplied;
  final String? note;

  /// 待还金额 = 应还金额 - 已还金额（后端 `upcoming.remaining` 同口径）。
  double get remaining {
    final double value = amount - paidAmount;
    return value < 0 ? 0 : value;
  }

  factory BillItem.fromJson(Map<String, dynamic> json) {
    return BillItem(
      id: _toInt(json['id']),
      platformId: _toInt(json['platform_id']),
      billMonth: json['bill_month'] as String? ?? '',
      dueDate: json['due_date'] as String?,
      amount: _toDouble(json['amount']),
      interest: _toDouble(json['interest']),
      paidAmount: _toDouble(json['paid_amount']),
      status: json['status'] as String? ?? 'pending',
      overdue: json['overdue'] as bool? ?? false,
      graceApplied: json['grace_applied'] as bool? ?? false,
      note: json['note'] as String?,
    );
  }
}

/// 账单汇总（`GET /finance/loan-bills/stats?days=0`）。
class BillStats {
  const BillStats({
    required this.total,
    required this.paid,
    required this.remaining,
    required this.totalInterest,
    required this.pendingCount,
    required this.partialCount,
    required this.clearedCount,
    required this.upcoming,
  });

  final double total;
  final double paid;
  final double remaining;
  final double totalInterest;
  final int pendingCount;
  final int partialCount;
  final int clearedCount;
  final List<BillItem> upcoming;

  factory BillStats.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> status =
        (json['status'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{};
    return BillStats(
      total: _toDouble(json['total']),
      paid: _toDouble(json['paid']),
      remaining: _toDouble(json['remaining']),
      totalInterest: _toDouble(json['total_interest']),
      pendingCount: _toInt(status['pending']),
      partialCount: _toInt(status['partial']),
      clearedCount: _toInt(status['cleared']),
      upcoming: ((json['upcoming'] as List?) ?? const <dynamic>[])
          .whereType<Map>()
          .map((Map item) => BillItem.fromJson(item.cast<String, dynamic>()))
          .toList(growable: false),
    );
  }
}

/// 账单还款记录（`GET /finance/repayments?bill_id=`）。
class BillRepayment {
  const BillRepayment({
    required this.id,
    required this.repayDate,
    required this.amount,
    required this.discount,
    this.method,
    this.note,
  });

  final int id;
  final String repayDate;
  final double amount;
  final double discount;
  final String? method;
  final String? note;

  /// 实付金额：网贷还款接口的 `amount` 本身就是实付（优惠另存在 `discount`）。
  double get actual => amount;

  factory BillRepayment.fromJson(Map<String, dynamic> json) {
    return BillRepayment(
      id: _toInt(json['id']),
      repayDate: json['repay_date'] as String? ?? '',
      amount: _toDouble(json['amount']),
      discount: _toDouble(json['discount']),
      method: json['method'] as String?,
      note: json['note'] as String?,
    );
  }
}

/// 单条债务（`GET /finance/debts` 列表项）。
class DebtItem {
  const DebtItem({
    required this.id,
    required this.debtDate,
    required this.name,
    required this.direction,
    this.counterparty,
    required this.amount,
    this.remaining,
    this.interestRate,
    required this.interestTotal,
    this.channel,
    this.dueDate,
    required this.status,
    this.note,
  });

  final int id;
  final String debtDate;
  final String name;
  final String direction;
  final String? counterparty;
  final double amount;
  final double? remaining;
  final double? interestRate;
  final double interestTotal;
  final String? channel;
  final String? dueDate;
  final String status;
  final String? note;

  bool get isLend => direction == 'lend';

  /// 未还金额：后端未给 `remaining` 时按本金计算。
  double get outstanding => remaining ?? amount;

  factory DebtItem.fromJson(Map<String, dynamic> json) {
    return DebtItem(
      id: _toInt(json['id']),
      debtDate: json['debt_date'] as String? ?? '',
      name: json['name'] as String? ?? '',
      direction: json['direction'] as String? ?? 'borrow',
      counterparty: json['counterparty'] as String?,
      amount: _toDouble(json['amount']),
      remaining:
          json['remaining'] == null ? null : _toDouble(json['remaining']),
      interestRate: json['interest_rate'] == null
          ? null
          : _toDouble(json['interest_rate']),
      interestTotal: _toDouble(json['interest_total']),
      channel: json['channel'] as String?,
      dueDate: json['due_date'] as String?,
      status: json['status'] as String? ?? 'active',
      note: json['note'] as String?,
    );
  }
}

/// 债务汇总（`GET /finance/debts/stats?days=0`）。
class DebtStats {
  const DebtStats({
    required this.total,
    required this.active,
    required this.settled,
    required this.borrowTotal,
    required this.lendTotal,
    required this.outstanding,
    required this.overdue,
  });

  final int total;
  final int active;
  final int settled;
  final double borrowTotal;
  final double lendTotal;
  final double outstanding;
  final int overdue;

  factory DebtStats.fromJson(Map<String, dynamic> json) {
    return DebtStats(
      total: _toInt(json['total']),
      active: _toInt(json['active']),
      settled: _toInt(json['settled']),
      borrowTotal: _toDouble(json['borrow_total']),
      lendTotal: _toDouble(json['lend_total']),
      outstanding: _toDouble(json['outstanding']),
      overdue: _toInt(json['overdue']),
    );
  }
}

/// 债务还款记录（`GET /finance/debts/{id}/payments`，返回数组）。
class DebtPayment {
  const DebtPayment({
    required this.id,
    required this.repayDate,
    required this.amount,
    required this.discount,
    required this.actual,
    this.note,
  });

  final int id;
  final String repayDate;
  final double amount;
  final double discount;
  final double actual;
  final String? note;

  factory DebtPayment.fromJson(Map<String, dynamic> json) {
    final double amount = _toDouble(json['amount']);
    final double discount = _toDouble(json['discount']);
    return DebtPayment(
      id: _toInt(json['id']),
      repayDate: json['repay_date'] as String? ?? '',
      amount: amount,
      discount: discount,
      actual: json['actual'] == null
          ? (amount - discount < 0 ? 0 : amount - discount)
          : _toDouble(json['actual']),
      note: json['note'] as String?,
    );
  }
}

/// 购物记录（`GET /finance/shopping/records` 列表项）。
///
/// 后端列表只返回 `platform_id` / `category_id`，页面用字典做 id → 名称映射。
class ShoppingRecord {
  const ShoppingRecord({
    required this.id,
    required this.recordDate,
    required this.productName,
    this.platformId,
    this.spec,
    required this.totalPrice,
    this.unitPrice,
    this.orderNo,
    this.ledgerId,
    this.categoryId,
    this.note,
  });

  final int id;
  final String recordDate;
  final String productName;
  final int? platformId;
  final String? spec;
  final double totalPrice;
  final double? unitPrice;
  final String? orderNo;
  final int? ledgerId;
  final int? categoryId;
  final String? note;

  /// 平台名：字典缺失时退化为「平台 id」，未设置平台时为「未分类」。
  String platformLabel(Map<int, String> platforms) {
    final int? id = platformId;
    if (id == null) {
      return '未分类';
    }
    final String? name = platforms[id];
    return (name == null || name.isEmpty) ? '平台 $id' : name;
  }

  factory ShoppingRecord.fromJson(Map<String, dynamic> json) {
    return ShoppingRecord(
      id: _toInt(json['id']),
      recordDate: json['record_date'] as String? ?? '',
      productName: json['product_name'] as String? ?? '',
      platformId: json['platform_id'] == null
          ? null
          : _toInt(json['platform_id']),
      spec: json['spec'] as String?,
      totalPrice: _toDouble(json['total_price']),
      unitPrice:
          json['unit_price'] == null ? null : _toDouble(json['unit_price']),
      orderNo: json['order_no'] as String?,
      ledgerId: json['ledger_id'] == null ? null : _toInt(json['ledger_id']),
      categoryId:
          json['category_id'] == null ? null : _toInt(json['category_id']),
      note: json['note'] as String?,
    );
  }
}

/// 汇总条目：按平台 / 账本 / 分类聚合后的名称与金额。
class NameAmount {
  const NameAmount({
    required this.id,
    required this.name,
    required this.amount,
  });

  final int id;
  final String name;
  final double amount;

  /// 从 `{platform_id, platform, amount}` 这类结构解析，键名由调用方指定。
  factory NameAmount.fromJson(
    Map<String, dynamic> json, {
    required String idKey,
    required String nameKey,
  }) {
    return NameAmount(
      id: _toInt(json[idKey]),
      name: json[nameKey] as String? ?? '未分类',
      amount: _toDouble(json['amount']),
    );
  }
}

/// 购物汇总（`GET /finance/shopping/records/stats?days=`）。
class ShoppingStats {
  const ShoppingStats({
    required this.total,
    required this.count,
    required this.byPlatform,
    required this.byLedger,
    required this.byCategory,
  });

  final double total;
  final int count;
  final List<NameAmount> byPlatform;
  final List<NameAmount> byLedger;
  final List<NameAmount> byCategory;

  /// 平均单笔；无记录时为 0。
  double get average => count == 0 ? 0 : total / count;

  factory ShoppingStats.fromJson(Map<String, dynamic> json) {
    List<NameAmount> parseList(String key, String idKey, String nameKey) {
      return ((json[key] as List?) ?? const <dynamic>[])
          .whereType<Map>()
          .map((Map item) => NameAmount.fromJson(
                item.cast<String, dynamic>(),
                idKey: idKey,
                nameKey: nameKey,
              ))
          .toList(growable: false);
    }

    return ShoppingStats(
      total: _toDouble(json['total']),
      count: _toInt(json['count']),
      byPlatform: parseList('by_platform', 'platform_id', 'platform'),
      byLedger: parseList('by_ledger', 'ledger_id', 'ledger'),
      byCategory: parseList('by_category', 'category_id', 'category'),
    );
  }
}

/// 购物平台 / 账本字典项（`GET /finance/shopping/platforms|ledgers`）。
class NamedOption {
  const NamedOption({required this.id, required this.name});

  final int id;
  final String name;

  factory NamedOption.fromJson(Map<String, dynamic> json) {
    return NamedOption(
      id: _toInt(json['id']),
      name: json['name'] as String? ?? '',
    );
  }
}

/// 行程账本（`GET /finance/travel/ledgers` 列表项）。
class TravelLedger {
  const TravelLedger({
    required this.id,
    required this.name,
    this.startDate,
    this.endDate,
    this.note,
  });

  final int id;
  final String name;
  final String? startDate;
  final String? endDate;
  final String? note;

  /// 起止日期文案：任一端缺失时退化展示已有内容。
  String get periodText {
    final String? start = startDate;
    final String? end = endDate;
    if (start == null && end == null) {
      return '未设置行程日期';
    }
    return '${start ?? '—'} ~ ${end ?? '进行中'}';
  }

  factory TravelLedger.fromJson(Map<String, dynamic> json) {
    return TravelLedger(
      id: _toInt(json['id']),
      name: json['name'] as String? ?? '',
      startDate: json['start_date'] as String?,
      endDate: json['end_date'] as String?,
      note: json['note'] as String?,
    );
  }
}

/// 行程明细（`GET /finance/travel/details` 列表项）。
///
/// 后端时间字段是 `HH:MM:SS` 文本，展示时截到分钟。
class TravelDetail {
  const TravelDetail({
    required this.id,
    this.ledgerId,
    required this.detailDate,
    this.beginTime,
    this.endTime,
    required this.category,
    required this.item,
    required this.originalPrice,
    required this.discount,
    required this.actualPrice,
    this.transportInfo,
    this.paymentMethod,
    this.note,
  });

  final int id;
  final int? ledgerId;
  final String detailDate;
  final String? beginTime;
  final String? endTime;
  final String category;
  final String item;
  final double originalPrice;
  final double discount;
  final double actualPrice;
  final String? transportInfo;
  final String? paymentMethod;
  final String? note;

  /// 时间段文案：任一端缺失时为「—」。
  String get timeRange {
    if (beginTime == null || endTime == null) {
      return '—';
    }
    return '${_clock(beginTime)}-${_clock(endTime)}';
  }

  /// 时长（分钟）：跨零点按加一天计算，与网页端口径一致。
  int? get durationMinutes {
    if (beginTime == null || endTime == null) {
      return null;
    }
    final int? begin = _minutesOfDay(beginTime);
    final int? end = _minutesOfDay(endTime);
    if (begin == null || end == null) {
      return null;
    }
    return end >= begin ? end - begin : end + 1440 - begin;
  }

  /// 时长文案：`X 小时 Y 分钟` / `Y 分钟`。
  String get durationText {
    final int? minutes = durationMinutes;
    if (minutes == null) {
      return '—';
    }
    final int hour = minutes ~/ 60;
    final int minute = minutes % 60;
    if (hour == 0) {
      return '$minute 分钟';
    }
    return minute == 0 ? '$hour 小时' : '$hour 小时 $minute 分钟';
  }

  factory TravelDetail.fromJson(Map<String, dynamic> json) {
    return TravelDetail(
      id: _toInt(json['id']),
      ledgerId: json['ledger_id'] == null ? null : _toInt(json['ledger_id']),
      detailDate: json['detail_date'] as String? ?? '',
      beginTime: json['begin_time'] as String?,
      endTime: json['end_time'] as String?,
      category: json['category'] as String? ?? '其他',
      item: json['item'] as String? ?? '',
      originalPrice: _toDouble(json['original_price']),
      discount: _toDouble(json['discount']),
      actualPrice: _toDouble(json['actual_price']),
      transportInfo: json['transport_info'] as String?,
      paymentMethod: json['payment_method'] as String?,
      note: json['note'] as String?,
    );
  }
}

/// 旅行汇总（`GET /finance/travel/details/stats?days=`）。
class TravelStats {
  const TravelStats({
    required this.totalActual,
    required this.totalOriginal,
    required this.totalDiscount,
    required this.count,
    required this.byCategory,
  });

  final double totalActual;
  final double totalOriginal;
  final double totalDiscount;
  final int count;
  final List<NameAmount> byCategory;

  factory TravelStats.fromJson(Map<String, dynamic> json) {
    return TravelStats(
      totalActual: _toDouble(json['total_actual']),
      totalOriginal: _toDouble(json['total_original']),
      totalDiscount: _toDouble(json['total_discount']),
      count: _toInt(json['count']),
      byCategory: ((json['by_category'] as List?) ?? const <dynamic>[])
          .whereType<Map>()
          .map((Map item) => NameAmount(
                id: -1,
                name: item['category'] as String? ?? '其他',
                amount: _toDouble(item['amount']),
              ))
          .toList(growable: false),
    );
  }
}

/// 财务规划状态：active 进行中 / done 已完成 / abandoned 已放弃。
String planStatusLabel(String status) {
  switch (status) {
    case 'done':
      return '已完成';
    case 'abandoned':
      return '已放弃';
    default:
      return '进行中';
  }
}

/// 单条财务规划（`GET /finance/planning` 列表项）。
class PlanItem {
  const PlanItem({
    required this.id,
    required this.planDate,
    required this.planType,
    required this.title,
    this.targetAmount,
    this.savedAmount,
    required this.status,
    this.note,
  });

  final int id;
  final String planDate;
  final String planType;
  final String title;
  final double? targetAmount;
  final double? savedAmount;
  final String status;
  final String? note;

  /// 达成进度：0–1；缺少目标或目标为 0 时返回 null。
  double? get progress {
    final double? target = targetAmount;
    final double? saved = savedAmount;
    if (target == null || saved == null || target <= 0) {
      return null;
    }
    final double value = saved / target;
    return value < 0 ? 0 : (value > 1 ? 1 : value);
  }

  factory PlanItem.fromJson(Map<String, dynamic> json) {
    return PlanItem(
      id: _toInt(json['id']),
      planDate: json['plan_date'] as String? ?? '',
      planType: json['plan_type'] as String? ?? '',
      title: json['title'] as String? ?? '',
      targetAmount: json['target_amount'] == null
          ? null
          : _toDouble(json['target_amount']),
      savedAmount: json['saved_amount'] == null
          ? null
          : _toDouble(json['saved_amount']),
      status: json['status'] as String? ?? 'active',
      note: json['note'] as String?,
    );
  }
}

/// 某类型规划的条数与已存金额。
class PlanTypeStat {
  const PlanTypeStat({
    required this.planType,
    required this.count,
    required this.amount,
  });

  final String planType;
  final int count;
  final double amount;
}

/// 财务规划汇总（`GET /finance/planning/stats?days=0`）。
class PlanStats {
  const PlanStats({
    required this.total,
    required this.active,
    required this.done,
    required this.targetTotal,
    required this.savedTotal,
    required this.byType,
  });

  final int total;
  final int active;
  final int done;
  final double targetTotal;
  final double savedTotal;
  final List<PlanTypeStat> byType;

  factory PlanStats.fromJson(Map<String, dynamic> json) {
    return PlanStats(
      total: _toInt(json['total']),
      active: _toInt(json['active']),
      done: _toInt(json['done']),
      targetTotal: _toDouble(json['target_total']),
      savedTotal: _toDouble(json['saved_total']),
      byType: ((json['by_type'] as List?) ?? const <dynamic>[])
          .whereType<Map>()
          .map((Map item) => PlanTypeStat(
                planType: item['plan_type'] as String? ?? '',
                count: _toInt(item['count']),
                amount: _toDouble(item['amount']),
              ))
          .toList(growable: false),
    );
  }
}

/// `HH:MM:SS` → `HH:MM`。
String _clock(String? value) {
  if (value == null || value.isEmpty) {
    return '—';
  }
  return value.length >= 5 ? value.substring(0, 5) : value;
}

/// `HH:MM:SS` → 当天第几分钟；无法解析时返回 null。
int? _minutesOfDay(String? value) {
  if (value == null || value.isEmpty) {
    return null;
  }
  final List<String> parts = value.split(':');
  if (parts.length < 2) {
    return null;
  }
  final int? hour = int.tryParse(parts[0]);
  final int? minute = int.tryParse(parts[1]);
  if (hour == null || minute == null) {
    return null;
  }
  return hour * 60 + minute;
}

/// 住房记录（`/finance/housing`），字段与网页端「房租水电 → 租房」一致。
class HousingItem {
  const HousingItem({
    required this.id,
    required this.name,
    required this.shortName,
    required this.channel,
    required this.orientation,
    required this.moveInDate,
    required this.moveOutDate,
    required this.rentTerm,
    required this.actualMonthlyRent,
    required this.deposit,
    required this.depositRefunded,
    required this.depositRefundChannel,
    required this.agentFee,
    required this.cleanFee,
    required this.serviceFee,
    required this.laundryFee,
    required this.note,
  });

  final int id;
  final String name;
  final String? shortName;
  final String? channel;
  final String? orientation;
  final String? moveInDate;
  final String? moveOutDate;
  final String rentTerm;
  final double actualMonthlyRent;
  final double deposit;
  final double depositRefunded;
  final String? depositRefundChannel;
  final double agentFee;
  final double cleanFee;
  final double serviceFee;
  final double laundryFee;
  final String? note;

  /// 租期文案：月付 / 季付 / 一次性。
  String get rentTermLabel {
    switch (rentTerm) {
      case 'quarterly':
        return '季付';
      case 'one_time':
        return '一次性';
      default:
        return '月付';
    }
  }

  factory HousingItem.fromJson(Map<String, dynamic> json) {
    return HousingItem(
      id: _toInt(json['id']),
      name: json['name'] as String? ?? '',
      shortName: json['short_name'] as String?,
      channel: json['channel'] as String?,
      orientation: json['orientation'] as String?,
      moveInDate: json['move_in_date'] as String?,
      moveOutDate: json['move_out_date'] as String?,
      rentTerm: json['rent_term'] as String? ?? 'monthly',
      actualMonthlyRent: _toDouble(json['actual_monthly_rent']),
      deposit: _toDouble(json['deposit']),
      depositRefunded: _toDouble(json['deposit_refunded']),
      depositRefundChannel: json['deposit_refund_channel'] as String?,
      agentFee: _toDouble(json['agent_fee']),
      cleanFee: _toDouble(json['clean_fee']),
      serviceFee: _toDouble(json['service_fee']),
      laundryFee: _toDouble(json['laundry_fee']),
      note: json['note'] as String?,
    );
  }
}

/// 水电缴费记录（`/finance/utilities`），字段与网页端一致。
class UtilityItem {
  const UtilityItem({
    required this.id,
    required this.housingId,
    required this.billMonth,
    required this.feeType,
    required this.amount,
    required this.dueDate,
    required this.paid,
    required this.note,
  });

  final int id;
  final int? housingId;
  final String billMonth;
  final String feeType;
  final double amount;
  final String? dueDate;
  final bool paid;
  final String? note;

  factory UtilityItem.fromJson(Map<String, dynamic> json) {
    return UtilityItem(
      id: _toInt(json['id']),
      housingId: json['housing_id'] == null ? null : _toInt(json['housing_id']),
      billMonth: json['bill_month'] as String? ?? '',
      feeType: json['fee_type'] as String? ?? 'electricity',
      amount: _toDouble(json['amount']),
      dueDate: json['due_date'] as String?,
      paid: json['paid'] as bool? ?? false,
      note: json['note'] as String?,
    );
  }
}

/// 服务订阅记录（`/finance/subscriptions`），字段与网页端一致。
class SubscriptionItem {
  const SubscriptionItem({
    required this.id,
    required this.name,
    required this.planName,
    required this.category,
    required this.billingCycle,
    required this.amount,
    required this.startDate,
    required this.endDate,
    required this.autoRenew,
    required this.status,
    required this.note,
  });

  final int id;
  final String name;
  final String? planName;
  final String category;
  final String billingCycle;
  final double amount;
  final String startDate;
  final String? endDate;
  final bool autoRenew;
  final String status;
  final String? note;

  /// 计费周期文案。
  String get billingCycleLabel {
    switch (billingCycle) {
      case 'quarter':
        return '季付';
      case 'year':
        return '年付';
      default:
        return '月付';
    }
  }

  /// 状态文案。
  String get statusLabel {
    switch (status) {
      case 'expired':
        return '已过期';
      case 'cancelled':
        return '已取消';
      default:
        return '生效中';
    }
  }

  factory SubscriptionItem.fromJson(Map<String, dynamic> json) {
    return SubscriptionItem(
      id: _toInt(json['id']),
      name: json['name'] as String? ?? '',
      planName: json['plan_name'] as String?,
      category: json['category'] as String? ?? '会员',
      billingCycle: json['billing_cycle'] as String? ?? 'month',
      amount: _toDouble(json['amount']),
      startDate: json['start_date'] as String? ?? '',
      endDate: json['end_date'] as String?,
      autoRenew: json['auto_renew'] as bool? ?? false,
      status: json['status'] as String? ?? 'active',
      note: json['note'] as String?,
    );
  }
}

