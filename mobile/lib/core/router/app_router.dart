import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/health_models.dart';
import '../../core/models/report_models.dart';
import '../../features/auth/login_page.dart';
import '../../features/finance/finance_bill_detail_page.dart';
import '../../features/finance/finance_bills_page.dart';
import '../../features/finance/finance_debt_detail_page.dart';
import '../../features/finance/finance_debts_page.dart';
import '../../features/finance/finance_expense_create_page.dart';
import '../../features/finance/finance_page.dart';
import '../../features/finance/finance_planning_page.dart';
import '../../features/finance/finance_shopping_page.dart';
import '../../features/finance/finance_travel_page.dart';
import '../../features/finance/finance_transactions_page.dart';
import '../../features/health/health_medication_detail_page.dart';
import '../../features/health/health_medication_page.dart';
import '../../features/health/health_page.dart';
import '../../features/health/health_steps_page.dart';
import '../../features/invest/forex_create_page.dart';
import '../../features/invest/forex_page.dart';
import '../../features/invest/invest_page.dart';
import '../../features/life/life_page.dart';
import '../../features/life/lifestyle_cards_page.dart';
import '../../features/life/lifestyle_items_page.dart';
import '../../features/notifications/notification_center_page.dart';
import '../../features/placeholder/feature_placeholder_page.dart';
import '../../features/reports/report_detail_page.dart';
import '../../features/reports/report_list_page.dart';
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
    initialLocation: '/finance',
    routes: <RouteBase>[
      StatefulShellRoute.indexedStack(
        builder: (
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
                  ),
                  GoRoute(
                    path: 'medication',
                    builder: (_, _) => const HealthMedicationPage(),
                    routes: <RouteBase>[
                      GoRoute(
                        path: ':id',
                        builder: (_, GoRouterState state) =>
                            HealthMedicationDetailPage(
                          recordId:
                              int.tryParse(state.pathParameters['id'] ?? '') ??
                                  0,
                          // 列表页带过来的快照：断网时也能进入并打卡。
                          initial: state.extra is MedicationRecord
                              ? state.extra as MedicationRecord
                              : null,
                        ),
                      ),
                    ],
                  ),
                  GoRoute(
                    path: 'vitals-sleep',
                    builder: (_, _) =>
                        const FeaturePlaceholderPage(title: '睡眠体征'),
                  ),
                  GoRoute(
                    path: 'fitness',
                    builder: (_, _) =>
                        const FeaturePlaceholderPage(title: '健身运动'),
                  ),
                  GoRoute(
                    path: 'checkup',
                    builder: (_, _) =>
                        const FeaturePlaceholderPage(title: '体检指标'),
                  ),
                  GoRoute(
                    path: 'reports',
                    builder: (_, _) =>
                        const ReportListPage(source: ReportSource.health),
                    routes: <RouteBase>[
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
                        path: ':id',
                        builder: (_, GoRouterState state) =>
                            FinanceBillDetailPage(
                          billId: int.tryParse(state.pathParameters['id'] ?? '') ??
                              0,
                          platformName:
                              state.uri.queryParameters['platform'] ?? '',
                        ),
                      ),
                    ],
                  ),
                  GoRoute(
                    path: 'debts',
                    builder: (_, _) => const FinanceDebtsPage(),
                    routes: <RouteBase>[
                      GoRoute(
                        path: ':id',
                        builder: (_, GoRouterState state) =>
                            FinanceDebtDetailPage(
                          debtId: int.tryParse(state.pathParameters['id'] ?? '') ??
                              0,
                        ),
                      ),
                    ],
                  ),
                  GoRoute(
                    path: 'shopping',
                    builder: (_, _) => const FinanceShoppingPage(),
                  ),
                  GoRoute(
                    path: 'travel',
                    builder: (_, _) => const FinanceTravelPage(),
                  ),
                  GoRoute(
                    path: 'planning',
                    builder: (_, _) => const FinancePlanningPage(),
                  ),
                  GoRoute(
                    path: 'reports',
                    builder: (_, _) =>
                        const ReportListPage(source: ReportSource.finance),
                    routes: <RouteBase>[
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
                  ),
                  GoRoute(
                    path: 'cards',
                    builder: (_, _) => const LifestyleCardsPage(),
                  ),
                  GoRoute(
                    path: 'reports',
                    builder: (_, _) =>
                        const ReportListPage(source: ReportSource.lifestyle),
                    routes: <RouteBase>[
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
                      GoRoute(
                        path: 'new',
                        builder: (_, _) => const ForexCreatePage(),
                      ),
                    ],
                  ),
                  GoRoute(
                    path: 'reports',
                    builder: (_, _) =>
                        const ReportListPage(source: ReportSource.investment),
                    routes: <RouteBase>[
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
                    builder: (_, _) =>
                        const FeaturePlaceholderPage(title: '账户设置'),
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
      GoRoute(
        path: '/login',
        builder: (_, _) => const LoginPage(),
      ),
    ],
  );
}
