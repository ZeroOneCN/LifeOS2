import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// 全局分段 Tab：财务中心账单页与生活中心卡片页共用同一组件。
///
/// 视觉规范：外层 `surfaceContainerHigh` 圆角 8、内边距 3；选中项用
/// `primary` 实心 + `onPrimary` 文字，圆角 8；未选中为透明底 + 次要文字。
/// 文案支持带数量（如「手机号卡 9」），单行不截断。
class AppTabSelector extends StatelessWidget {
  const AppTabSelector({
    super.key,
    required this.labels,
    required this.value,
    required this.onChanged,
  });

  final List<String> labels;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppRadii.control),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.7),
        ),
      ),
      child: Row(
        children: <Widget>[
          for (int index = 0; index < labels.length; index++)
            Expanded(
              child: Semantics(
                button: true,
                selected: index == value,
                child: InkWell(
                  onTap: () => onChanged(index),
                  borderRadius: BorderRadius.circular(AppRadii.control),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: index == value ? scheme.primary : Colors.transparent,
                      borderRadius: BorderRadius.circular(AppRadii.control),
                    ),
                    child: Text(
                      labels[index],
                      maxLines: 1,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: index == value
                            ? scheme.onPrimary
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
