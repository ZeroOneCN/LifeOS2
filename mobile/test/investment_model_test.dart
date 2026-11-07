import 'package:flutter_test/flutter_test.dart';
import 'package:lifeos_mobile/core/models/investment_models.dart';

/// 投资域模型：资金记录与合计、统计汇总与派生文案、交易日历。
void main() {
  test('资金类型选项与未知类型兜底', () {
    expect(kFundTypes.map((e) => e.value), <String>[
      'deposit',
      'withdraw',
      'experience',
    ]);
    expect(kFundTypes.map((e) => e.label), <String>['入金', '出金', '体验金']);
    expect(fundTypeLabel('deposit'), '入金');
    // 后端新增类型时原样显示，不丢记录。
    expect(fundTypeLabel('bonus'), 'bonus');
  });

  test('资金记录解析：体验金可为负数，备注为空时单号只留 #id', () {
    final FundRecord negative = FundRecord.fromJson(<String, dynamic>{
      'id': 184,
      'record_type': 'experience',
      'amount': -2.76,
      'record_date': '2026-07-02',
      'note': '体验金亏损',
    });
    expect(negative.amount, -2.76);
    expect(negative.typeLabel, '体验金');
    expect(negative.orderNo, '#184 · 体验金亏损');

    final FundRecord plain = FundRecord.fromJson(<String, dynamic>{
      'id': 7,
      'record_type': 'deposit',
      'amount': 1000,
      'record_date': '2026-05-13',
      'note': '   ',
    });
    expect(plain.amount, 1000.0);
    expect(plain.orderNo, '#7');
  });

  test('资金合计解析：字段缺失按 0，不做本地重算', () {
    final FundStats stats = FundStats.fromJson(<String, dynamic>{
      'deposit': 12000.5,
      'withdraw': 3000,
      'experience': -52.78,
      'net': 8947.72,
    });
    expect(stats.deposit, 12000.5);
    expect(stats.withdraw, 3000.0);
    expect(stats.experience, -52.78);
    expect(stats.net, 8947.72);

    final FundStats empty = FundStats.fromJson(<String, dynamic>{});
    expect(empty.deposit, 0);
    expect(empty.net, 0);
  });

  test('外汇统计解析：summary / by_symbol / analysis 与时段文案', () {
    final ForexStats stats = ForexStats.fromJson(<String, dynamic>{
      'summary': <String, dynamic>{
        'account_value': 28947.72,
        'net_profit': 1200.35,
        'gross_pnl': 1600.5,
        'total_commission': -300.15,
        'total_overnight': -100.0,
        'trade_count': 4277,
        'open_count': 3,
        'win_rate': 56.4,
        'profit_loss_ratio': 1.35,
        'profit_factor': 1.58,
        'total_deposit': 12000.5,
        'total_withdraw': 3000,
        'total_experience': -52.78,
        'symbol_count': 12,
      },
      'by_symbol': <dynamic>[
        <String, dynamic>{
          'symbol': 'XAUUSD',
          'count': 1200,
          'win_rate': 58.2,
          'pnl': 860.4,
        },
        <String, dynamic>{
          'symbol': 'EURUSD',
          'count': 980,
          'win_rate': 51.0,
          'pnl': -120.6,
        },
      ],
      'analysis': <String, dynamic>{
        'avg_win': 42.1,
        // 无亏损交易时后端给 null，页面必须显示「—」而不是 0。
        'avg_loss': null,
        'max_drawdown': -320.75,
        'max_drawdown_pct': -8.4,
        'profit_factor': 1.58,
        'longest_win_streak': 9,
        'longest_loss_streak': 5,
        'avg_holding_minutes': 85,
        'hour_dist': <dynamic>[
          <String, dynamic>{'hour': 8, 'count': 120},
          <String, dynamic>{'hour': 21, 'count': 96},
        ],
      },
    });

    expect(stats.summary.accountValue, 28947.72);
    expect(stats.summary.tradeCount, 4277);
    expect(stats.summary.winRate, 56.4);
    expect(stats.summary.symbolCount, 12);
    expect(stats.bySymbol.length, 2);
    expect(stats.bySymbol.first.symbol, 'XAUUSD');
    expect(stats.bySymbol.last.pnl, -120.6);
    expect(stats.analysis.avgWin, 42.1);
    expect(stats.analysis.avgLoss, isNull);
    expect(stats.analysis.maxDrawdown, -320.75);
    expect(stats.analysis.longestWinStreak, 9);
    expect(stats.analysis.hourDist.length, 2);
    expect(stats.analysis.hourDist.first.label, '08:00');
    expect(stats.analysis.hourDist.last.label, '21:00');
    expect(stats.analysis.avgHoldingText, '1 小时 25 分');
  });

  test('平均持仓文案：分钟 / 整小时 / 缺失三档', () {
    ForexAnalysis base({int? minutes}) => ForexAnalysis.fromJson(
      <String, dynamic>{'avg_holding_minutes': minutes},
    );
    expect(base(minutes: 45).avgHoldingText, '45 分钟');
    expect(base(minutes: 120).avgHoldingText, '2 小时');
    expect(base().avgHoldingText, '—');
    expect(base(minutes: 0).avgHoldingText, '—');
  });

  test('外汇统计空响应：给空列表与零值，页面不崩', () {
    final ForexStats stats = ForexStats.fromJson(<String, dynamic>{});
    expect(stats.summary.tradeCount, 0);
    expect(stats.summary.accountValue, 0);
    expect(stats.bySymbol, isEmpty);
    expect(stats.analysis.hourDist, isEmpty);
    expect(stats.analysis.avgHoldingText, '—');
  });

  test('交易日历解析：monthKey 补零、active 只认 count', () {
    final ForexCalendar calendar = ForexCalendar.fromJson(<String, dynamic>{
      'year': 2026,
      'month': 9,
      'days': <dynamic>[
        <String, dynamic>{
          'day': 3,
          'pnl': 128.4,
          'count': 6,
          'win': 4,
          'loss': 2,
          'position': false,
        },
        <String, dynamic>{
          'day': 4,
          'pnl': 0,
          'count': 0,
          'win': 0,
          'loss': 0,
          'position': false,
        },
      ],
      'summary': <String, dynamic>{
        'month_pnl': 128.4,
        'trading_days': 1,
        'win_days': 1,
        'loss_days': 0,
        'return_rate': 0.4,
      },
    });
    expect(calendar.monthKey, '2026-09');
    expect(calendar.days.length, 2);
    expect(calendar.days.first.active, isTrue);
    expect(calendar.days.first.win, 4);
    expect(calendar.days.last.active, isFalse);
    expect(calendar.summary.monthPnl, 128.4);
    expect(calendar.summary.returnRate, 0.4);

    final ForexCalendar november = ForexCalendar.fromJson(<String, dynamic>{
      'year': 2026,
      'month': 11,
      'days': <dynamic>[],
    });
    expect(november.monthKey, '2026-11');
    expect(november.days, isEmpty);
    expect(november.summary.tradingDays, 0);
  });
}
