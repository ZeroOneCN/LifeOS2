import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeos_mobile/shared/widgets/app_buttons.dart';

/// 按钮文字规范：单行 + 并列等宽等高（375 逻辑宽 + 1.3 倍字号）。
void main() {
  Widget harness(Widget child) {
    return MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(
          size: Size(375, 800),
          textScaler: TextScaler.linear(1.3),
        ),
        child: Scaffold(
          bottomNavigationBar: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: child,
            ),
          ),
        ),
      ),
    );
  }

  /// 收集按钮内所有文字，断言都强制单行。
  void expectSingleLineLabels() {
    final Iterable<Text> labels = find
        .descendant(
          of: find.byType(AppActionRow),
          matching: find.byType(Text),
        )
        .evaluate()
        .map((Element element) => element.widget as Text);
    expect(labels, isNotEmpty);
    for (final Text text in labels) {
      expect(text.maxLines, 1, reason: '按钮文字必须单行：${text.data}');
      expect(text.softWrap, isFalse, reason: '按钮文字禁止折行：${text.data}');
    }
  }

  testWidgets('结果页「返回体重 / 再称一次」等宽等高且单行', (WidgetTester tester) async {
    await tester.pumpWidget(
      harness(
        AppActionRow(
          first: AppPrimaryButton(
            label: '返回体重',
            onPressed: () {},
          ),
          second: AppSecondaryButton(
            label: '再称一次',
            icon: Icons.refresh,
            onPressed: () {},
          ),
        ),
      ),
    );

    final Size firstSize = tester.getSize(find.byType(AppPrimaryButton));
    final Size secondSize = tester.getSize(find.byType(AppSecondaryButton));

    // 两侧各占一半宽度（间距 12，可用宽度 375-32-12=331）。
    expect(firstSize.width, closeTo(secondSize.width, 1));
    expect(firstSize.width, greaterThan(150));
    // 等高：由 IntrinsicHeight 拉伸到同一高度。
    expect(firstSize.height, closeTo(secondSize.height, 0.5));
    expectSingleLineLabels();
  });

  testWidgets('长文案在 1.3 倍字号下仍单行且不溢出', (WidgetTester tester) async {
    await tester.pumpWidget(
      harness(
        AppActionRow(
          first: AppPrimaryButton(
            label: '同步到健康中心',
            onPressed: () {},
          ),
          second: AppDangerButton(
            label: '确认移除这条记录',
            onPressed: () {},
          ),
        ),
      ),
    );

    // 无 RenderFlex / 文本溢出异常即视为未折行、未溢出。
    expect(tester.takeException(), isNull);
    expectSingleLineLabels();
  });

  testWidgets('三按钮 1:1:1 等宽、等高，文字宽度不超出可用宽度（375 + 1.3x）', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      harness(
        AppActionRow(
          first: AppPrimaryButton(
            label: '开蓝牙',
            icon: null,
            compact: true,
            onPressed: () {},
          ),
          second: AppSecondaryButton(
            label: '重扫描',
            compact: true,
            onPressed: () {},
          ),
          third: AppSecondaryButton(
            label: '手动录入',
            compact: true,
            onPressed: () {},
          ),
        ),
      ),
    );

    final Size firstSize = tester.getSize(find.byType(AppPrimaryButton));
    final Size secondSize = tester.getSize(find.byType(AppSecondaryButton).first);
    final Size thirdSize = tester.getSize(find.byType(AppSecondaryButton).last);

    // 三槽等宽（375 - 32 - 12*2 = 319，各约 106.3）且等高。
    expect(firstSize.width, closeTo(secondSize.width, 1));
    expect(firstSize.width, closeTo(thirdSize.width, 1));
    expect(firstSize.height, closeTo(secondSize.height, 0.5));
    expect(firstSize.height, closeTo(thirdSize.height, 0.5));

    // 紧凑按钮左右内边距各 12：文字实际宽度必须放得下，才不会被 FittedBox 缩小。
    final List<String> labels = <String>['开蓝牙', '重扫描', '手动录入'];
    final List<Size> sizes = <Size>[firstSize, secondSize, thirdSize];
    for (int i = 0; i < labels.length; i++) {
      final double textWidth = tester.getSize(find.text(labels[i])).width;
      expect(
        textWidth,
        lessThanOrEqualTo(sizes[i].width - 24 + 0.5),
        reason: '「${labels[i]}」文字宽 $textWidth 超出可用宽 ${sizes[i].width - 24}',
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('取消 / 确认弹窗按钮单行', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(375, 800),
            textScaler: TextScaler.linear(1.3),
          ),
          child: Scaffold(
            body: AlertDialog(
              title: const Text('全部标记已读'),
              content: const Text('将把 12 条未读通知标记为已读，是否继续？'),
              actions: <Widget>[
                AppActionRow(
                  first: AppSecondaryButton(
                    label: '取消',
                    compact: true,
                    onPressed: () {},
                  ),
                  second: AppPrimaryButton(
                    label: '确定',
                    compact: true,
                    onPressed: () {},
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expectSingleLineLabels();
  });
}
