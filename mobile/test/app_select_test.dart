import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeos_mobile/shared/widgets/app_select.dart';

/// 下拉选择组件：选中回调、弹层限高、长文案单行、键盘导航。
void main() {
  /// 固定测试画布为 375x800（1x dpr），与真机逻辑尺寸一致。
  void usePhoneSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(375, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Widget harness(Widget child) {
    return MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(
          size: Size(375, 800),
          textScaler: TextScaler.linear(1.3),
        ),
        child: Scaffold(
          body: Center(child: SizedBox(width: 343, child: child)),
        ),
      ),
    );
  }

  const List<AppSelectOption<int?>> options = <AppSelectOption<int?>>[
    AppSelectOption<int?>(value: null, label: '未分类'),
    AppSelectOption<int?>(value: 1, label: '淘宝'),
    AppSelectOption<int?>(value: 2, label: '一个特别特别长的平台名称用于验证不会把弹层撑宽出屏'),
    AppSelectOption<int?>(value: 3, label: '京东'),
  ];

  testWidgets('选项超多时弹层限高屏高 60%，且长文案不撑宽出屏', (WidgetTester tester) async {
    usePhoneSurface(tester);
    final List<AppSelectOption<int?>> many = <AppSelectOption<int?>>[
      for (int i = 0; i < 40; i++)
        AppSelectOption<int?>(
          value: i,
          label: i == 2 ? '一个特别特别长的平台名称用于验证不会把弹层撑宽出屏' : '选项 $i',
        ),
    ];
    await tester.pumpWidget(
      harness(
        AppSelectField<int?>(
          label: '平台',
          value: null,
          hint: '请选择',
          options: many,
          onChanged: (int? value) {},
        ),
      ),
    );

    await tester.tap(find.byType(AppSelectField<int?>));
    await tester.pumpAndSettle();

    expect(find.text('选项 0'), findsOneWidget);
    final double sheetHeight = tester
        .getSize(find.byKey(appSelectSheetKey))
        .height;
    expect(sheetHeight, lessThanOrEqualTo(800 * 0.6 + 0.5));
    // 长文案单行 + 省略号，不会横向撑出屏幕。
    final Text longText = tester.widget<Text>(find.text(many[2].label));
    expect(longText.maxLines, 1);
    final Rect longRect = tester.getRect(find.text(many[2].label));
    expect(longRect.right, lessThanOrEqualTo(375));
    // 限高内可滚动：滚到底部仍可点选末项。
    await tester.scrollUntilVisible(
      find.text('选项 39'),
      200,
      scrollable: find.byType(Scrollable),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('选项 39'));
    await tester.pumpAndSettle();
    expect(find.byKey(appSelectSheetKey), findsNothing);
  });

  testWidgets('点选选项回传值并关闭弹层', (WidgetTester tester) async {
    usePhoneSurface(tester);
    int? picked;
    await tester.pumpWidget(
      harness(
        AppSelectField<int?>(
          label: '平台',
          value: null,
          options: options,
          onChanged: (int? value) => picked = value,
        ),
      ),
    );

    await tester.tap(find.byType(AppSelectField<int?>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('京东'));
    await tester.pumpAndSettle();

    expect(picked, 3);
    expect(find.byKey(appSelectSheetKey), findsNothing);
  });

  testWidgets('未选中时展示 hint，选中后回填选中文案', (WidgetTester tester) async {
    usePhoneSurface(tester);
    await tester.pumpWidget(
      harness(
        AppSelectField<int?>(
          label: '平台',
          value: 1,
          options: options,
          onChanged: (int? value) {},
        ),
      ),
    );
    expect(find.text('淘宝'), findsOneWidget);

    await tester.pumpWidget(
      harness(
        AppSelectField<int?>(
          label: '平台',
          value: null,
          hint: '未分类',
          options: options,
          onChanged: (int? value) {},
        ),
      ),
    );
    expect(find.text('未分类'), findsOneWidget);
  });

  testWidgets('外接键盘方向键移动高亮，Enter 选中', (WidgetTester tester) async {
    usePhoneSurface(tester);
    int? picked;
    await tester.pumpWidget(
      harness(
        AppSelectField<int?>(
          label: '平台',
          value: null,
          options: options,
          onChanged: (int? value) => picked = value,
        ),
      ),
    );

    await tester.tap(find.byType(AppSelectField<int?>));
    await tester.pumpAndSettle();

    // 默认高亮「未分类」（索引 0），下移一次到「淘宝」。
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(picked, 1);
  });
}
