import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../theme/app_tokens.dart';

/// 2.0 域内栏目条。
///
/// 规则（与效果稿一致）：
/// - 所有栏目统一 2 个汉字，不多不少；
/// - 一屏严格 6 等分：每项占 1/6 宽，只露出 6 个完整栏目，不出现半个字；
/// - 超过 6 项时横滑并吸附到栏目边界，右侧 6% 渐隐提示「还有更多」；
/// - 不足 6 项时等分铺满；
/// - 选中态为居中的 2px System Blue 短下划线。
class DomainTabs extends StatefulWidget {
  const DomainTabs({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onSelected,
    this.fadeColor,
  });

  /// 栏目文字，必须全部为 2 个汉字。
  final List<String> labels;

  /// 当前选中项（域概览固定为 0）。
  final int selectedIndex;

  /// 点击栏目回调。
  final ValueChanged<int> onSelected;

  /// 右侧渐隐的终色，默认取页面底色。
  final Color? fadeColor;

  @override
  State<DomainTabs> createState() => _DomainTabsState();
}

class _DomainTabsState extends State<DomainTabs> {
  final ScrollController _controller = ScrollController();

  /// 每项宽度（= 可视宽度 / 6），用于吸附计算。
  double _itemWidth = 0;

  /// 是否已滑到最右端；到端点后不再绘制渐隐。
  bool _atEnd = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 横滑结束吸附到最近的栏目边界，并维护右侧渐隐的显隐。
  bool _onScroll(ScrollNotification notification) {
    if (!_controller.hasClients) {
      return false;
    }
    final ScrollMetrics metrics = notification.metrics;
    final bool atEnd = metrics.extentAfter <= 0.5;
    if (atEnd != _atEnd) {
      setState(() => _atEnd = atEnd);
    }
    if (notification is ScrollEndNotification && _itemWidth > 0) {
      final double raw = _controller.offset;
      final double target = (raw / _itemWidth).round() * _itemWidth;
      final double clamped = target.clamp(
        metrics.minScrollExtent,
        metrics.maxScrollExtent,
      );
      if ((clamped - raw).abs() > 0.5) {
        _controller.animateTo(
          clamped,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        );
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    assert(
      widget.labels.every((String label) => label.runes.length == 2),
      '域内栏目必须统一 2 个汉字',
    );
    final AppTokens tokens = AppTokens.of(context);
    final Color fadeColor = widget.fadeColor ?? tokens.background;
    // 横向 ListView 必须有确定高度：字号 × 行高（1.0）+ 上下内边距 24。
    final double tabHeight =
        MediaQuery.textScalerOf(context).scale(AppType.segment.fontSize ?? 14) +
        24;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double itemWidth = constraints.maxWidth / 6;
        _itemWidth = itemWidth;
        final bool scrollable = widget.labels.length > 6;

        final Widget content = SizedBox(
          height: tabHeight,
          child: scrollable
              ? Material(
                  type: MaterialType.transparency,
                  child: NotificationListener<ScrollNotification>(
                    onNotification: _onScroll,
                    child: ListView.builder(
                      controller: _controller,
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      itemExtent: itemWidth,
                      itemCount: widget.labels.length,
                      itemBuilder: (BuildContext context, int index) =>
                          _buildTab(context, index, itemWidth),
                    ),
                  ),
                )
              : Material(
                  type: MaterialType.transparency,
                  child: Row(
                    children: <Widget>[
                      for (int i = 0; i < widget.labels.length; i++)
                        Expanded(child: _buildTab(context, i, itemWidth)),
                    ],
                  ),
                ),
        );

        return Container(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: tokens.line, width: AppTokens.hairline),
            ),
          ),
          child: Stack(
            children: <Widget>[
              content,
              if (scrollable && !_atEnd)
                Positioned(
                  top: 0,
                  bottom: 0,
                  right: 0,
                  // 设计稿是右侧 6% 渐隐；真机上 6% 会压到第 6 个栏目的文字。
                  // 这里按 6% 与 10dp 取小值，只渐隐右侧留白，保证 6 个字完整。
                  width: math.min(constraints.maxWidth * 0.06, 10),
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: <Color>[
                            fadeColor.withValues(alpha: 0),
                            fadeColor,
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  /// 单个栏目：文字 + 选中下划线，整块可点。
  Widget _buildTab(BuildContext context, int index, double width) {
    final AppTokens tokens = AppTokens.of(context);
    final bool selected = index == widget.selectedIndex;
    return SizedBox(
      width: width,
      child: InkWell(
        onTap: () => widget.onSelected(index),
        child: Semantics(
          selected: selected,
          child: Stack(
            alignment: Alignment.bottomCenter,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.only(top: 11, bottom: 13),
                child: Text(
                  widget.labels[index],
                  maxLines: 1,
                  softWrap: false,
                  textAlign: TextAlign.center,
                  style: AppType.segment.copyWith(
                    color: selected ? tokens.text : tokens.text2,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
              if (selected)
                Container(
                  width: 22,
                  height: 2,
                  decoration: BoxDecoration(
                    color: tokens.accent,
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
