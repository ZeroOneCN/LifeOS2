import 'package:flutter_test/flutter_test.dart';
import 'package:lifeos_mobile/core/models/lifestyle_models.dart';

/// 生活域模型：物品统计解析、到期标记口径、手机号卡派生文案与流水符号。
void main() {
  test('物品统计解析：by_status / by_category 可缺失，计数按原值', () {
    final ItemStats stats = ItemStats.fromJson(<String, dynamic>{
      'total': 426,
      'in_use': 401,
      'total_value': 12800.5,
      'total_usage_days': 21000,
      'avg_daily_cost': 1.2,
      'expiring': 2,
      'expired': 1,
      'by_status': <dynamic>[
        <String, dynamic>{'status': 'in_use', 'count': 401},
        <String, dynamic>{'status': 'recycled', 'count': 25},
      ],
      'by_category': <dynamic>[
        <String, dynamic>{'category': '电子', 'count': 120},
        <String, dynamic>{'category': '', 'count': 3},
      ],
    });
    expect(stats.total, 426);
    expect(stats.inUse, 401);
    expect(stats.totalValue, 12800.5);
    expect(stats.avgDailyCost, 1.2);
    expect(stats.byStatus.length, 2);
    expect(stats.byStatus.last.label, 'recycled');
    expect(stats.byCategory.first.label, '电子');
    expect(stats.byCategory.last.label, '');

    // 后端未返回分组时给空列表，页面不应因此崩溃。
    final ItemStats empty = ItemStats.fromJson(<String, dynamic>{});
    expect(empty.total, 0);
    expect(empty.byStatus, isEmpty);
    expect(empty.byCategory, isEmpty);
  });

  test('物品到期：expire_date 为空或无法解析时不产生临期/过期标记', () {
    const LifestyleItem noExpire = LifestyleItem(
      id: 1,
      itemName: '机械键盘',
      category: '电子',
      status: 'in_use',
      source: 'manual',
    );
    expect(noExpire.expiryInfo(today: DateTime(2026, 11, 7)), isNull);

    final LifestyleItem emptyExpire = LifestyleItem.fromJson(<String, dynamic>{
      'id': 2,
      'item_name': '空气滤芯',
      'category': '家居',
      'status': 'in_use',
      'source': 'manual',
      'expire_date': '',
    });
    expect(emptyExpire.expiryInfo(today: DateTime(2026, 11, 7)), isNull);

    final LifestyleItem expired = LifestyleItem.fromJson(<String, dynamic>{
      'id': 3,
      'item_name': '牛奶',
      'category': '其他',
      'status': 'in_use',
      'source': 'manual',
      'expire_date': '2026-11-01',
    });
    final ItemExpiry? expiry =
        expired.expiryInfo(today: DateTime(2026, 11, 7));
    expect(expiry, isNotNull);
    expect(expiry!.daysLeft, -6);
    expect(expiry.isExpired, isTrue);
  });

  test('物品状态与来源选项覆盖后端取值，历史未知值可原样展示', () {
    expect(kItemStatuses.map((item) => item.value).toSet(),
        <String>{'in_use', 'loaned', 'lost', 'recycled'});
    expect(itemStatusLabel('recycled'), '已回收');
    expect(itemStatusLabel('unknown'), '使用中');
    expect(kItemSources.map((item) => item.value).toSet(),
        <String>{'manual', 'shopping'});
    // 分类预设与网页端一致，新建时始终有可选项。
    expect(kItemCategories, contains('电子'));
    expect(kItemCategories.length, 7);
  });

  test('手机号卡派生字段：本月已扣 / 应扣文案与余额空值显示「—」', () {
    final PhoneCard paid = PhoneCard.fromJson(<String, dynamic>{
      'id': 8,
      'phone_number': '13800000000',
      'operator': '中国移动',
      'balance': 20.5,
      'opening_balance': 0,
      'billing_type': 'monthly',
      'charge_mode': 'monthly',
      'auto_charge': false,
      'bill_paid_this_month': true,
      'month_charged': 20,
      'month_expected': 20,
      'status': 'active',
    });
    expect(paid.billingType, 'monthly');
    expect(paid.autoCharge, isFalse);
    expect(paid.billPaidThisMonth, isTrue);
    expect(paid.monthBillText, '本月已扣 ¥20.00');
    expect(paid.balanceText, '¥20.50');

    final PhoneCard pending = PhoneCard.fromJson(<String, dynamic>{
      'id': 9,
      'phone_number': '13900000000',
      'operator': '中国联通',
      'balance': 0,
      'opening_balance': 0,
      'status': 'active',
      'bill_paid_this_month': false,
      'month_expected': 10,
    });
    expect(pending.monthBillText, '本月应扣 ¥10.00 · 待扣');
    // 起始余额 0 且无流水：视为未采集。
    expect(pending.balanceText, '—');

    final PhoneCard noBill = PhoneCard.fromJson(<String, dynamic>{
      'id': 10,
      'phone_number': '13700000000',
      'operator': '中国电信',
      'opening_balance': 100,
      'balance': 100,
      'status': 'active',
      'month_expected': 0,
      'month_charged': 0,
    });
    expect(noBill.monthBillText, isNull);
    expect(noBill.balanceText, '¥100.00');
  });

  test('手机号卡流水：类型中文与带符号金额', () {
    final PhoneLedgerEntry recharge =
        PhoneLedgerEntry.fromJson(<String, dynamic>{
      'id': 1,
      'entry_type': 'recharge',
      'entry_date': '2026-11-07',
      'amount': 50,
      'note': '话费充值',
    });
    expect(recharge.typeLabel, '充值');
    expect(recharge.amountText, '+¥50.00');
    expect(recharge.note, '话费充值');

    final PhoneLedgerEntry charge = PhoneLedgerEntry.fromJson(<String, dynamic>{
      'id': 2,
      'entry_type': 'charge',
      'entry_date': '2026-11-01',
      'amount': -20,
    });
    expect(charge.typeLabel, '扣费');
    expect(charge.amountText, '-¥20.00');
    expect(charge.note, isNull);

    final PhoneLedgerEntry adjust = PhoneLedgerEntry.fromJson(<String, dynamic>{
      'id': 3,
      'entry_type': 'adjust',
      'entry_date': '2026-11-07',
      'amount': -3.2,
    });
    expect(adjust.typeLabel, '校准');
    expect(adjust.amountText, '-¥3.20');
  });
}
