/// 投资域模型：外汇交易记录、交易资金记录（入金 / 出金 / 体验金）。
///
/// 字段口径与网页端 `pages/investment/forex.tsx` 一致：
/// - 列表来自 `GET /investment/forex?page=&page_size=`；
/// - 资金合计来自 `GET /investment/funds/stats`；
/// - 资金明细来自 `GET /investment/funds?page=&page_size=`。
library;

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

String _two(int value) => value < 10 ? '0$value' : '$value';

/// 资金类型标签：deposit 入金 / withdraw 出金 / experience 体验金。
String fundTypeLabel(String type) {
  switch (type) {
    case 'deposit':
      return '入金';
    case 'withdraw':
      return '出金';
    case 'experience':
      return '体验金';
    default:
      return type;
  }
}

/// 单条资金记录（`GET /investment/funds` 列表项）。
class FundRecord {
  const FundRecord({
    required this.id,
    required this.recordType,
    required this.amount,
    required this.recordDate,
    this.note,
  });

  final int id;
  final String recordType;
  final double amount;
  final String recordDate;
  final String? note;

  /// 类型文案。
  String get typeLabel => fundTypeLabel(recordType);

  /// 单号：`#id · 备注`，与网页端口径一致；备注为空时只留 `#id`。
  String get orderNo {
    final String? text = note?.trim();
    return (text == null || text.isEmpty) ? '#$id' : '#$id · $text';
  }

  factory FundRecord.fromJson(Map<String, dynamic> json) {
    return FundRecord(
      id: _toInt(json['id']),
      recordType: json['record_type'] as String? ?? '',
      amount: _toDouble(json['amount']),
      recordDate: json['record_date'] as String? ?? '',
      note: json['note'] as String?,
    );
  }
}

/// 资金合计（`GET /investment/funds/stats`）。
///
/// `net = 入金 - 出金 + 体验金`，与网页端四卡「净投入」同口径。
class FundStats {
  const FundStats({
    required this.deposit,
    required this.withdraw,
    required this.experience,
    required this.net,
  });

  final double deposit;
  final double withdraw;
  final double experience;
  final double net;

  factory FundStats.fromJson(Map<String, dynamic> json) {
    return FundStats(
      deposit: _toDouble(json['deposit']),
      withdraw: _toDouble(json['withdraw']),
      experience: _toDouble(json['experience']),
      net: _toDouble(json['net']),
    );
  }
}

/// 单笔外汇交易（`GET /investment/forex` 列表项）。
class ForexTrade {
  const ForexTrade({
    required this.id,
    required this.tradeDate,
    required this.symbol,
    required this.orderType,
    required this.openPrice,
    required this.lotSize,
    required this.commission,
    this.closePrice,
    this.pnl,
    required this.overnightFee,
    this.openTime,
    this.closeTime,
    this.holding,
    required this.status,
    this.note,
  });

  final int id;
  final String tradeDate;
  final String symbol;
  final String orderType;
  final double openPrice;
  final double lotSize;
  final double commission;
  final double? closePrice;
  final double? pnl;
  final double overnightFee;
  final String? openTime;
  final String? closeTime;
  final int? holding;
  final String status;
  final String? note;

  /// 是否持仓中（未平仓）。
  bool get isOpen => status == 'open';

  /// 方向文案：buy 做多 / sell 做空。
  String get orderTypeLabel => orderType == 'sell' ? '做空' : '做多';

  /// 净盈亏 = 盈亏 + 手续费 + 隔夜费（带符号），与后端汇总口径一致。
  double get netPnl => (pnl ?? 0) + commission + overnightFee;

  /// 列表时间：优先平仓时间，其次开仓时间，最后退回交易日。
  String get timeText {
    final String? iso = closeTime ?? openTime;
    if (iso == null || iso.isEmpty) {
      return tradeDate;
    }
    final DateTime? parsed = DateTime.tryParse(iso);
    if (parsed == null) {
      return iso;
    }
    final bool hasTime = iso.contains('T');
    return hasTime
        ? '${_two(parsed.month)}-${_two(parsed.day)} '
            '${_two(parsed.hour)}:${_two(parsed.minute)}'
        : tradeDate;
  }

  factory ForexTrade.fromJson(Map<String, dynamic> json) {
    return ForexTrade(
      id: _toInt(json['id']),
      tradeDate: json['trade_date'] as String? ?? '',
      symbol: json['symbol'] as String? ?? '',
      orderType: json['order_type'] as String? ?? 'buy',
      openPrice: _toDouble(json['open_price']),
      lotSize: _toDouble(json['lot_size']),
      commission: _toDouble(json['commission']),
      closePrice:
          json['close_price'] == null ? null : _toDouble(json['close_price']),
      pnl: json['pnl'] == null ? null : _toDouble(json['pnl']),
      overnightFee: _toDouble(json['overnight_fee']),
      openTime: json['open_time'] as String?,
      closeTime: json['close_time'] as String?,
      holding: json['holding'] == null ? null : _toInt(json['holding']),
      status: json['status'] as String? ?? 'closed',
      note: json['note'] as String?,
    );
  }
}
