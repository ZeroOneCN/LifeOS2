import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/finance_models.dart';
import '../../core/models/health_models.dart';
import '../../core/models/investment_models.dart';
import '../../core/models/lifestyle_models.dart';
import '../../core/models/report_models.dart';
import '../../features/auth/login_page.dart';
import '../../features/finance/finance_bill_form_page.dart';
import '../../features/finance/finance_bill_manage_page.dart';
import '../../features/finance/finance_bills_page.dart';
import '../../features/finance/finance_debt_detail_page.dart';
import '../../features/finance/finance_debt_form_page.dart';
import '../../features/finance/finance_debts_page.dart';
import '../../features/finance/finance_expense_create_page.dart';
import '../../features/finance/finance_page.dart';
import '../../features/finance/finance_planning_form_page.dart';
import '../../features/finance/finance_planning_page.dart';
import '../../features/finance/finance_shopping_form_page.dart';
import '../../features/finance/finance_shopping_page.dart';
import '../../features/finance/finance_travel_form_page.dart';
import '../../features/finance/finance_travel_manage_page.dart';
import '../../features/finance/finance_travel_page.dart';
import '../../features/finance/finance_transactions_page.dart';
import '../../features/health/health_body_ble_page.dart';
import '../../features/health/health_body_form_page.dart';
import '../../features/health/health_body_page.dart';
import '../../features/health/health_checkup_bulk_page.dart';
import '../../features/health/health_checkup_form_page.dart';
import '../../features/health/health_checkup_page.dart';
import '../../features/health/health_diet_form_page.dart';
import '../../features/health/health_diet_page.dart';
import '../../features/health/health_fitness_form_page.dart';
import '../../features/health/health_fitness_page.dart';
import '../../features/health/health_med_purchase_form_page.dart';
import '../../features/health/health_med_stock_form_page.dart';
import '../../features/health/health_medication_create_page.dart';
import '../../features/health/health_medication_detail_page.dart';
import '../../features/health/health_medication_page.dart';
import '../../features/health/health_page.dart';
import '../../features/health/health_sleep_form_page.dart';
import '../../features/health/health_sleep_page.dart';
import '../../features/health/health_steps_create_page.dart';
import '../../features/health/health_steps_page.dart';
import '../../features/invest/forex_detail_page.dart';
import '../../features/invest/forex_page.dart';
import '../../features/invest/fund_record_detail_page.dart';
import '../../features/invest/invest_analysis_page.dart';
import '../../features/invest/invest_calendar_page.dart';
import '../../features/invest/invest_page.dart';
import '../../features/life/card_form_page.dart';
import '../../features/life/life_page.dart';
import '../../features/life/lifestyle_cards_page.dart';
import '../../features/life/lifestyle_item_form_page.dart';
import '../../features/life/lifestyle_items_page.dart';
import '../../features/life/phone_card_ops_page.dart';
import '../../features/notifications/notification_center_page.dart';
import '../../features/reports/report_detail_page.dart';
import '../../features/reports/report_generate_page.dart';
import '../../features/reports/report_list_page.dart';
import '../../features/settings/about_page.dart';
import '../../features/settings/account_settings_page.dart';
import '../../features/settings/backup_export_page.dart';
import '../../features/settings/device_sessions_page.dart';
import '../../features/settings/server_config_page.dart';
import '../../features/settings/settings_page.dart';
import '../../features/shell/app_shell.dart';

/// 路由表：`StatefulShellRoute.indexedStack` + 5 个独立分支。
///
/// 选择理由见 docs/移动端可行性研究/P1_工程骨架.md：
/// 1. 分支内保留各自 Navigator 栈与滚动位置；
/// 2. 每个 Tab 的二级页返回只影响本分支；
/// 3. 顶栏、导航栏由 shell 统一，不侵入页面。
///
/// 各域二级路由与网页端 `frontend/src/config/routes.ts` 一一对应；
/// 业务列表页在 P2 先落占位页，保证每个入口都能到达并可返回。
///
/// 启动落点口径（唯一）：
/// 1. 冷启动固定落第一个 Tab「健康中心」（`initialLocation: '/health'`），
///    不恢复上次停留的 Tab，也不做任何 Tab 持久化读写；
/// 2. 进程未被杀、从后台返回时由 `StatefulShellRoute` 保留当前分支与页面，
///    不做任何 `go('/health')` 之类的强制跳转；
/// 3. 深链 / 通知跳转仍按目标 path 直达，不被上面的默认落点覆盖。
GoRouter createAppRouter() {
  final GlobalKey<NavigatorState> rootKey = GlobalKey<NavigatorState>(
    debugLabel: 'root',
  );
  final GlobalKey<NavigatorState> healthKey = GlobalKey<NavigatorState>(
    debugLabel: 'health',
  );
  final GlobalKey<NavigatorState> financeKey = GlobalKey<NavigatorState>(
    debugLabel: 'finance',
  );
  final GlobalKey<NavigatorState> lifeKey = GlobalKey<NavigatorState>(
    debugLabel: 'life',
  );
  final GlobalKey<NavigatorState> investKey = GlobalKey<NavigatorState>(
    debugLabel: 'invest',
  );
  final GlobalKey<NavigatorState> settingsKey = GlobalKey<NavigatorState>(
    debugLabel: 'settings',
  );

  return GoRouter(
    navigatorKey: rootKey,
    initialLocation: '/health',
    routes: <RouteBase>[
      StatefulShellRoute.indexedStack(
        builder:
            (
              BuildContext context,
              GoRouterState state,
              StatefulNavigationShell navigationShell,
            ) {
              return AppShell(navigationShell: navigationShell);
            },
        branches: <StatefulShellBranch>[
          StatefulShellBranch(
            navigatorKey: healthKey,
            routes: <RouteBase>[
              GoRoute(
                path: '/health',
                builder: (_, _) => const HealthPage(),
                routes: <RouteBase>[
                  GoRoute(
                    path: 'steps',
                    builder: (_, _) => const HealthStepsPage(),
                    routes: <RouteBase>[
                      GoRoute(
                        path: 'new',
                        builder: (_, _) => const HealthStepsCreatePage(),
                      ),
                      // 时段记录编辑：`extra` 带列表快照可直接预填，缺失时按 id 拉取。
                      GoRoute(
                        path: ':id',
                        builder: (_, GoRouterState state) =>
                            HealthStepsCreatePage(
                              recordId:
                                  int.tryParse(
                                    state.pathParameters['id'] ?? '',
                                  ) ??
                                  0,
                              initial: state.extra is StepRecord
                                  ? state.extra as StepRecord
                                  : null,
                            ),
                      ),
                    ],
                  ),
                  GoRoute(
                    path: 'medication',
                    builder: (_, _) => const HealthMedicationPage(),
                    routes: <RouteBase>[
                      // 静态段必须在 `:id` 之前，否则会被当成记录 id 解析。
                      GoRoute(
                        path: 'new',
                        builder: (_, _) => const HealthMedicationCreatePage(),
                      ),
                      GoRoute(
                        path: 'purchases/new',
                        builder: (_, _) => const HealthMedPurchaseFormPage(),
                      ),
                      GoRoute(
                        path: 'purchases/:id',
                        builder: (_, GoRouterState state) =>
                            HealthMedPurchaseFormPage(
                              purchaseId:
                                  int.tryParse(
                                    state.pathParameters['id'] ?? '',
                                  ) ??
                                  0,
                              initial: state.extra is MedPurchase
                                  ? state.extra as MedPurchase
                                  : null,
                            ),
                      ),
                      GoRoute(
                        path: 'stocks/new',
                        builder: (_, _) => const HealthMedStockFormPage(),
                      ),
                      GoRoute(
                        path: 'stocks/:sid/edit',
                        builder: (_, GoRouterState state) =>
                            HealthMedStockFormPage(
                              stockId:
                                  int.tryParse(
                                    state.pathParameters['sid'] ?? '',
                                  ) ??
                                  0,
                              initial: state.extra is MedStock
                                  ? state.extra as MedStock
                                  : null,
                            ),
                      ),
                      GoRoute(
                        path: ':id',
                        builder: (_, GoRouterState state) =>
                            HealthMedicationDetailPage(
                              recordId:
                                  int.tryParse(
                                    state.pathParameters['id'] ?? '',
                                  ) ??
                                  0,
                              // 列表页带过来的快照：断网时也能进入并打卡。
                              initial: state.extra is MedicationRecord
                                  ? state.extra as MedicationRecord
                                  : null,
                            ),
                      ),
                      GoRoute(
                        path: ':id/edit',
                        builder: (_, GoRouterState state) =>
                            HealthMedicationCreatePage(
                              recordId:
                                  int.tryParse(
                                    state.pathParameters['id'] ?? '',
                                  ) ??
                                  0,
                              initial: state.extra is MedicationRecord
                                  ? state.extra as MedicationRecord
                                  : null,
                            ),
                      ),
                    ],
                  ),
                  GoRoute(
                    path: 'vitals-sleep',
                    builder: (_, _) => const HealthSleepPage(),
                    routes: <RouteBase>[
                      GoRoute(
                        path: 'new',
                        builder: (_, _) => const HealthSleepFormPage(),
                      ),
                      // 编辑：列表带快照可直接预填，缺失时按 id 拉取。
                      GoRoute(
                        path: ':id',
                        builder: (_, GoRouterState state) =>
                            HealthSleepFormPage(
                              recordId:
                                  int.tryParse(
                                    state.pathParameters['id'] ?? '',
                                  ) ??
                                  0,
                              initial: state.extra is SleepRecord
                                  ? state.extra as SleepRecord
                                  : null,
                            ),
                      ),
                    ],
                  ),
                  // 体重记录：列表 + 趋势，录入/编辑与步数页同一套表单结构。
                  GoRoute(
                    path: 'body',
                    builder: (_, _) => const HealthBodyPage(),
                    routes: <RouteBase>[
                      // 静态段必须在 `:id` 之前，否则会被当成记录 id 解析。
                      GoRoute(
                        path: 'ble',
                        builder: (_, _) => const HealthBodyBlePage(),
                      ),
                      GoRoute(
                        path: 'new',
                        builder: (_, _) => const HealthBodyFormPage(),
                      ),
                      GoRoute(
                        path: ':id',
                        builder: (_, GoRouterState state) => HealthBodyFormPage(
                          recordId:
                              int.tryParse(state.pathParameters['id'] ?? '') ??
                              0,
                          initial: state.extra is BodyRecord
                              ? state.extra as BodyRecord
                              : null,
                        ),
                      ),
                    ],
                  ),
                  GoRoute(
                    path: 'fitness',
                    builder: (_, _) => const HealthFitnessPage(),
                    routes: <RouteBase>[
                      GoRoute(
                        path: 'new',
                        builder: (_, _) => const HealthFitnessFormPage(),
                      ),
                      GoRoute(
                        path: 'edit/:id',
                        builder: (_, GoRouterState state) =>
                            HealthFitnessFormPage(
                              recordId:
                                  int.tryParse(
                                    state.pathParameters['id'] ?? '',
                                  ) ??
                                  0,
                              initial: state.extra is FitnessRecord
                                  ? state.extra as FitnessRecord
                                  : null,
                            ),
                      ),
                    ],
                  ),
                  // 饮食记录：今日摄入汇总 + 按日期/餐次分组的记录列表。
                  GoRoute(
                    path: 'diet',
                    builder: (_, _) => const HealthDietPage(),
                    routes: <RouteBase>[
                      GoRoute(
                        path: 'new',
                        builder: (_, _) => const HealthDietFormPage(),
                      ),
                      GoRoute(
                        path: 'edit/:id',
                        builder: (_, GoRouterState state) => HealthDietFormPage(
                          recordId:
                              int.tryParse(state.pathParameters['id'] ?? '') ??
                              0,
                          initial: state.extra is DietRecord
                              ? state.extra as DietRecord
                              : null,
                        ),
                      ),
                    ],
                  ),
                  GoRoute(
                    path: 'checkup',
                    builder: (_, _) => const HealthCheckupPage(),
                    routes: <RouteBase>[
                      GoRoute(
                        path: 'new',
                        builder: (_, _) => const HealthCheckupBulkPage(),
                      ),
                      GoRoute(
                        path: ':id',
                        builder: (_, GoRouterState state) =>
                            HealthCheckupFormPage(
                              recordId:
                                  int.tryParse(
                                    state.pathParameters['id'] ?? '',
                                  ) ??
                                  0,
                              initial: state.extra is CheckupRecord
                                  ? state.extra as CheckupRecord
                                  : null,
                            ),
                      ),
                    ],
                  ),
                  GoRoute(
                    path: 'reports',
                    builder: (_, _) =>
                        const ReportListPage(source: ReportSource.health),
                    routes: <RouteBase>[
                      GoRoute(
                        path: 'generate',
                        builder: (_, _) => const ReportGeneratePage(
                          source: ReportSource.health,
                        ),
                      ),
                      GoRoute(
                        path: ':id',
                        builder: (_, GoRouterState state) => ReportDetailPage(
                          source: ReportSource.health,
                          reportId:
                              int.tryParse(state.pathParameters['id'] ?? '') ??
                              0,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: financeKey,
            routes: <RouteBase>[
              GoRoute(
                path: '/finance',
                builder: (_, _) => const FinancePage(),
                routes: <RouteBase>[
                  GoRoute(
                    path: 'bills',
                    builder: (_, _) => const FinanceBillsPage(),
                    routes: <RouteBase>[
                      GoRoute(
                        path: 'new',
                        builder: (_, GoRouterState state) =>
                            FinanceBillFormPage(
                              kind: billKindFromParam(
                                state.uri.queryParameters['kind'],
                              ),
                            ),
                      ),
                      GoRoute(
                        path: 'edit/:id',
                        builder: (_, GoRouterState state) =>
                            FinanceBillFormPage(
                              kind: billKindFromParam(
                                state.uri.queryParameters['kind'],
                              ),
                              id: int.tryParse(
                                state.pathParameters['id'] ?? '',
                              ),
                            ),
                      ),
                      // 配套字典维护：网贷平台 / 租房渠道 / 订阅分类。
                      GoRoute(
                        path: 'manage/:kind',
                        builder: (_, GoRouterState state) =>
                            FinanceBillManagePage(
                              kind: switch (state.pathParameters['kind']) {
                                'housing' => BillManageKind.rentChannel,
                                'subscription' =>
                                  BillManageKind.subscriptionCategory,
                                _ => BillManageKind.loanPlatform,
                              },
                            ),
                      ),
                    ],
                  ),
                  GoRoute(
                    path: 'debts',
                    builder: (_, _) => const FinanceDebtsPage(),
                    routes: <RouteBase>[
                      GoRoute(
                        path: 'new',
                        builder: (_, _) => const FinanceDebtFormPage(),
                      ),
                      GoRoute(
                        path: 'edit/:id',
                        builder: (_, GoRouterState state) =>
                            FinanceDebtFormPage(
                              debtId:
                                  int.tryParse(
                                    state.pathParameters['id'] ?? '',
                                  ) ??
                                  0,
                              initial: state.extra is DebtItem
                                  ? state.extra as DebtItem
                                  : null,
                            ),
                      ),
                      GoRoute(
                        path: ':id',
                        builder: (_, GoRouterState state) =>
                            FinanceDebtDetailPage(
                              debtId:
                                  int.tryParse(
                                    state.pathParameters['id'] ?? '',
                                  ) ??
                                  0,
                            ),
                      ),
                    ],
                  ),
                  GoRoute(
                    path: 'shopping',
                    builder: (_, _) => const FinanceShoppingPage(),
                    routes: <RouteBase>[
                      // 新增购物记录：复用编辑表单的空 ID 模式。
                      GoRoute(
                        path: 'new',
                        builder: (_, _) => const FinanceShoppingFormPage(),
                      ),
                      // 编辑购物记录：日期 / 商品 / 金额 / 平台 / 分类 / 备注。
                      GoRoute(
                        path: 'edit/:id',
                        builder: (_, GoRouterState state) =>
                            FinanceShoppingFormPage(
                              recordId:
                                  int.tryParse(
                                    state.pathParameters['id'] ?? '',
                                  ) ??
                                  0,
                              initial: state.extra is ShoppingRecord
                                  ? state.extra as ShoppingRecord
                                  : null,
                            ),
                      ),
                    ],
                  ),
                  GoRoute(
                    path: 'travel',
                    builder: (_, _) => const FinanceTravelPage(),
                    routes: <RouteBase>[
                      GoRoute(
                        path: 'new',
                        builder: (_, _) => const FinanceTravelFormPage(),
                      ),
                      GoRoute(
                        path: 'manage',
                        builder: (_, _) => const FinanceTravelManagePage(),
                      ),
                      // 编辑旅行明细：带起止时间 / 交通信息 / 支付方式。
                      GoRoute(
                        path: ':id',
                        builder: (_, GoRouterState state) =>
                            FinanceTravelFormPage(
                              recordId:
                                  int.tryParse(
                                    state.pathParameters['id'] ?? '',
                                  ) ??
                                  0,
                              initial: state.extra is TravelDetail
                                  ? state.extra as TravelDetail
                                  : null,
                            ),
                      ),
                    ],
                  ),
                  GoRoute(
                    path: 'planning',
                    builder: (_, _) => const FinancePlanningPage(),
                    routes: <RouteBase>[
                      GoRoute(
                        path: 'new',
                        builder: (_, _) => const FinancePlanningFormPage(),
                      ),
                      GoRoute(
                        path: ':id',
                        builder: (_, GoRouterState state) =>
                            FinancePlanningFormPage(
                              recordId:
                                  int.tryParse(
                                    state.pathParameters['id'] ?? '',
                                  ) ??
                                  0,
                              initial: state.extra is PlanItem
                                  ? state.extra as PlanItem
                                  : null,
                            ),
                      ),
                    ],
                  ),
                  GoRoute(
                    path: 'reports',
                    builder: (_, _) =>
                        const ReportListPage(source: ReportSource.finance),
                    routes: <RouteBase>[
                      GoRoute(
                        path: 'generate',
                        builder: (_, _) => const ReportGeneratePage(
                          source: ReportSource.finance,
                        ),
                      ),
                      GoRoute(
                        path: ':id',
                        builder: (_, GoRouterState state) => ReportDetailPage(
                          source: ReportSource.finance,
                          reportId:
                              int.tryParse(state.pathParameters['id'] ?? '') ??
                              0,
                        ),
                      ),
                    ],
                  ),
                  GoRoute(
                    path: 'transactions',
                    builder: (_, _) => const FinanceTransactionsPage(),
                  ),
                  GoRoute(
                    path: 'expense/new',
                    builder: (_, _) => const FinanceExpenseCreatePage(),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: lifeKey,
            routes: <RouteBase>[
              GoRoute(
                path: '/life',
                builder: (_, _) => const LifePage(),
                routes: <RouteBase>[
                  GoRoute(
                    path: 'items',
                    builder: (_, _) => const LifestyleItemsPage(),
                    routes: <RouteBase>[
                      GoRoute(
                        path: 'new',
                        builder: (_, GoRouterState state) {
                          final LifestyleItemFormArgs? args =
                              state.extra is LifestyleItemFormArgs
                              ? state.extra as LifestyleItemFormArgs
                              : null;
                          return LifestyleItemFormPage(
                            categories: args?.categories ?? const <String>[],
                          );
                        },
                      ),
                      GoRoute(
                        path: 'edit/:id',
                        builder: (_, GoRouterState state) {
                          final LifestyleItemFormArgs? args =
                              state.extra is LifestyleItemFormArgs
                              ? state.extra as LifestyleItemFormArgs
                              : null;
                          return LifestyleItemFormPage(
                            recordId:
                                int.tryParse(
                                  state.pathParameters['id'] ?? '',
                                ) ??
                                0,
                            initial: args?.item,
                            categories: args?.categories ?? const <String>[],
                          );
                        },
                      ),
                    ],
                  ),
                  GoRoute(
                    path: 'cards',
                    builder: (_, _) => const LifestyleCardsPage(),
                    routes: <RouteBase>[
                      // 新增 / 编辑卡片：kind 决定字段，id 作为 query 传入。
                      GoRoute(
                        path: 'form/:kind',
                        builder: (_, GoRouterState state) {
                          final CardKind kind = cardKindFromParam(
                            state.pathParameters['kind'],
                          );
                          final Object? extra = state.extra;
                          return CardFormPage(
                            kind: kind,
                            id: int.tryParse(
                              state.uri.queryParameters['id'] ?? '',
                            ),
                            phone: extra is PhoneCard ? extra : null,
                            bank: extra is BankCard ? extra : null,
                            carrier: extra is Carrier ? extra : null,
                            bill: extra is CardBill ? extra : null,
                          );
                        },
                      ),
                      GoRoute(
                        path: 'phone/:id/recharge',
                        builder: (_, GoRouterState state) => PhoneRechargePage(
                          cardId:
                              int.tryParse(state.pathParameters['id'] ?? '') ??
                              0,
                          initial: state.extra is PhoneCard
                              ? state.extra as PhoneCard
                              : null,
                        ),
                      ),
                      GoRoute(
                        path: 'phone/:id/adjust',
                        builder: (_, GoRouterState state) => PhoneAdjustPage(
                          cardId:
                              int.tryParse(state.pathParameters['id'] ?? '') ??
                              0,
                          initial: state.extra is PhoneCard
                              ? state.extra as PhoneCard
                              : null,
                        ),
                      ),
                    ],
                  ),
                  GoRoute(
                    path: 'reports',
                    builder: (_, _) =>
                        const ReportListPage(source: ReportSource.lifestyle),
                    routes: <RouteBase>[
                      GoRoute(
                        path: 'generate',
                        builder: (_, _) => const ReportGeneratePage(
                          source: ReportSource.lifestyle,
                        ),
                      ),
                      GoRoute(
                        path: ':id',
                        builder: (_, GoRouterState state) => ReportDetailPage(
                          source: ReportSource.lifestyle,
                          reportId:
                              int.tryParse(state.pathParameters['id'] ?? '') ??
                              0,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: investKey,
            routes: <RouteBase>[
              GoRoute(
                path: '/invest',
                builder: (_, _) => const InvestPage(),
                routes: <RouteBase>[
                  GoRoute(
                    path: 'forex',
                    builder: (_, _) => const ForexPage(),
                    routes: <RouteBase>[
                      // 交易详情（只读）：行情数据由网页端导入，移动端无写入入口。
                      GoRoute(
                        path: 'edit/:id',
                        builder: (_, GoRouterState state) => ForexDetailPage(
                          tradeId:
                              int.tryParse(state.pathParameters['id'] ?? '') ??
                              0,
                          initial: state.extra is ForexTrade
                              ? state.extra as ForexTrade
                              : null,
                        ),
                      ),
                      // 资金记录详情（只读）：后端无单条 GET，只能用列表快照。
                      GoRoute(
                        path: 'funds/edit/:id',
                        builder: (_, GoRouterState state) => FundRecordDetailPage(
                          recordId:
                              int.tryParse(state.pathParameters['id'] ?? '') ??
                              0,
                          record: state.extra is FundRecord
                              ? state.extra as FundRecord
                              : null,
                        ),
                      ),
                      // 投资分析：`GET /investment/forex/stats`（汇总口径为全部已平仓交易）。
                      GoRoute(
                        path: 'analysis',
                        builder: (_, _) => const InvestAnalysisPage(),
                      ),
                      // 交易日历：`GET /investment/forex/calendar?month=YYYY-MM`。
                      GoRoute(
                        path: 'calendar',
                        builder: (_, _) => const InvestCalendarPage(),
                      ),
                    ],
                  ),
                  GoRoute(
                    path: 'reports',
                    builder: (_, _) =>
                        const ReportListPage(source: ReportSource.investment),
                    routes: <RouteBase>[
                      GoRoute(
                        path: 'generate',
                        builder: (_, _) => const ReportGeneratePage(
                          source: ReportSource.investment,
                        ),
                      ),
                      GoRoute(
                        path: ':id',
                        builder: (_, GoRouterState state) => ReportDetailPage(
                          source: ReportSource.investment,
                          reportId:
                              int.tryParse(state.pathParameters['id'] ?? '') ??
                              0,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: settingsKey,
            routes: <RouteBase>[
              GoRoute(
                path: '/settings',
                builder: (_, _) => const SettingsPage(),
                routes: <RouteBase>[
                  GoRoute(
                    path: 'server',
                    builder: (_, _) => const ServerConfigPage(),
                  ),
                  GoRoute(
                    path: 'account',
                    builder: (_, _) => const AccountSettingsPage(),
                  ),
                  GoRoute(path: 'about', builder: (_, _) => const AboutPage()),
                  GoRoute(
                    path: 'devices',
                    builder: (_, _) => const DeviceSessionsPage(),
                  ),
                  GoRoute(
                    path: 'backup',
                    builder: (_, _) => const BackupExportPage(),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
      // 通知中心与登录页是全局目的地，不归属任何 Tab；
      // 从根页铃铛 / 状态条进入，返回时回到进入前的 Tab（shell 栈未受影响）。
      GoRoute(
        path: '/notifications',
        builder: (_, _) => const NotificationCenterPage(),
      ),
      GoRoute(path: '/login', builder: (_, _) => const LoginPage()),
    ],
  );
}
