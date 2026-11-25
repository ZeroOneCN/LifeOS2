import 'package:flutter/material.dart';

import '../../../theme/app_tokens.dart';

/// 横向等宽分段的一项。
class V2SegmentedOption<T> {
  const V2SegmentedOption({required this.label, required this.value});

  final String label;
  final T value;
}

/// 2.0 横向等宽分段控件：灰色轨道 + 白色选中块。
///
/// 用于外观 / 字体档位 / 投资曲线区间；切换只重建控件，不重建页面数据。
class V2Segmented<T> extends StatelessWidget {
  const V2Segmented({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
    this.compact = false,
  });

  final List<V2SegmentedOption<T>> options;
  final T selected;
  final ValueChanged<T> onChanged;

  /// 紧凑模式：用于图表右上角等空间有限的场景。
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    final double height = compact ? 30 : 40;
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: tokens.fill2,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: <Widget>[
          for (final V2SegmentedOption<T> option in options)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Material(
                  color: option.value == selected
                      ? tokens.surface
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => onChanged(option.value),
                    child: SizedBox(
                      height: height,
                      child: Center(
                        child: Text(
                          option.label,
                          maxLines: 1,
                          softWrap: false,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: compact ? 12 : 14,
                            height: 1,
                            fontWeight: option.value == selected
                                ? FontWeight.w600
                                : FontWeight.w500,
                            color: option.value == selected
                                ? tokens.text
                                : tokens.text2,
                          ),
                        ),
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
