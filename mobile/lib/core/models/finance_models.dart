/// 财务域业务模型：账单（网贷/房租等分期账单）与债务（借入/借出）。
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
    this.note,
  });

  final int id;
  final String repayDate;
  final double amount;
  final double discount;
  final String? note;

  /// 实付 = 还款金额 - 优惠。
  double get actual {
    final double value = amount - discount;
    return value < 0 ? 0 : value;
  }

  factory BillRepayment.fromJson(Map<String, dynamic> json) {
    return BillRepayment(
      id: _toInt(json['id']),
      repayDate: json['repay_date'] as String? ?? '',
      amount: _toDouble(json['amount']),
      discount: _toDouble(json['discount']),
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
