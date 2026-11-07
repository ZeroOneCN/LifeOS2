import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 下拉选择项：`value` 是提交给业务的值，`label` 是展示文案。
class AppSelectOption<T> {
  const AppSelectOption({required this.value, required this.label});

  final T value;
  final String label;
}

/// 全站统一的下拉选择控件（替代 DropdownButton / DropdownButtonFormField）。
///
/// 外观与 `TextFormField` 一致（主题填充色、12 圆角、`outline` 边框、聚焦主色），
/// 因此可以和输入框并排放在同一张表单里。
/// 点击后从屏幕底部向上展开选择层：高度不超过屏高 60%、内部可滚动、
/// 长文案单行省略不撑宽，支持外接键盘 ↑/↓ 移动高亮、Enter/Space 选中、Esc 关闭。
///
/// 受控组件：选中值由调用方持有，`onChanged` 回调后自行 `setState`。
class AppSelectField<T> extends StatelessWidget {
  const AppSelectField({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    this.hint = '请选择',
    this.helperText,
    this.enabled = true,
  });

  /// 字段名（浮动标签），与 InputDecoration.labelText 一致。
  final String label;

  /// 当前值；`T` 本身可以是可空类型（例如 `int?`），null 视为「未选择」。
  final T value;

  final List<AppSelectOption<T>> options;
  final ValueChanged<T> onChanged;
  final String hint;
  final String? helperText;
  final bool enabled;

  /// 当前值对应的展示文案；找不到时回退到 hint。
  String get _display {
    for (final AppSelectOption<T> item in options) {
      if (item.value == value) {
        return item.label;
      }
    }
    return hint;
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final bool empty = !options.any(
      (AppSelectOption<T> item) => item.value == value,
    );

    return Semantics(
      button: true,
      label: '$label：$_display',
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: enabled
            ? () async {
                final T? picked = await showAppSelectSheet<T>(
                  context: context,
                  title: label,
                  value: value,
                  options: options,
                );
                if (picked != null) {
                  onChanged(picked);
                }
              }
            : null,
        child: ExcludeSemantics(
          child: InputDecorator(
            isEmpty: false,
            decoration: InputDecoration(
              labelText: label,
              helperText: helperText,
              enabled: enabled,
              contentPadding: const EdgeInsets.fromLTRB(12, 16, 8, 16),
              suffixIcon: Icon(
                Icons.expand_more,
                size: 20,
                color: scheme.onSurfaceVariant,
              ),
            ),
            child: Text(
              _display,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: empty
                  ? theme.textTheme.bodyLarge?.copyWith(
                      color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                    )
                  : theme.textTheme.bodyLarge,
            ),
          ),
        ),
      ),
    );
  }
}

/// 弹层根组件的 Key，供测试测量弹层高度。
const Key appSelectSheetKey = ValueKey<String>('app-select-sheet');

/// 打开统一的选择层，返回选中的值；用户取消（点遮罩 / 返回键 / Esc）返回 null。
///
/// 自绘弹层而不用 `showModalBottomSheet`：后者的拖拽手柄与安全区会在
/// 60% 限高之外再叠高度，导致窄屏机型实际高度超出上限。
Future<T?> showAppSelectSheet<T>({
  required BuildContext context,
  required String title,
  required List<AppSelectOption<T>> options,
  T? value,
}) {
  // 用 View 的物理尺寸换算逻辑高度，避免个别机型 MediaQuery 口径不一致。
  final Size screen =
      View.of(context).physicalSize / View.of(context).devicePixelRatio;
  final double maxHeight = screen.height * 0.6;

  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '关闭选择',
    barrierColor: Colors.black.withValues(alpha: 0.35),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder:
        (
          BuildContext dialogContext,
          Animation<double> animation,
          Animation<double> secondaryAnimation,
        ) {
          return Align(
            alignment: Alignment.bottomCenter,
            child: _AppSelectSheet<T>(
              title: title,
              options: options,
              value: value,
              maxHeight: maxHeight,
            ),
          );
        },
    transitionBuilder:
        (
          BuildContext context,
          Animation<double> animation,
          Animation<double> secondaryAnimation,
          Widget child,
        ) {
          final Curve curve = Curves.easeOutCubic;
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.12),
                end: Offset.zero,
              ).animate(CurvedAnimation(parent: animation, curve: curve)),
              child: child,
            ),
          );
        },
  );
}

/// 弹层内部实现：限高 + 滚动 + 选中勾选 + 键盘导航。
class _AppSelectSheet<T> extends StatefulWidget {
  const _AppSelectSheet({
    required this.title,
    required this.options,
    required this.value,
    required this.maxHeight,
  });

  final String title;
  final List<AppSelectOption<T>> options;
  final T? value;

  /// 弹层整体高度上限（含标题与底部安全区）。
  final double maxHeight;

  @override
  State<_AppSelectSheet<T>> createState() => _AppSelectSheetState<T>();
}

class _AppSelectSheetState<T> extends State<_AppSelectSheet<T>> {
  static const double _itemExtent = 52;

  late int _highlight = math.max(
    0,
    widget.options.indexWhere(
      (AppSelectOption<T> item) => item.value == widget.value,
    ),
  );

  final ScrollController _controller = ScrollController();
  final FocusNode _focusNode = FocusNode(debugLabel: 'AppSelectSheet');

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  /// 上下移动高亮，并把高亮项滚动到可视区。
  void _move(int delta) {
    if (widget.options.isEmpty) {
      return;
    }
    final int next = (_highlight + delta).clamp(0, widget.options.length - 1);
    if (next == _highlight) {
      return;
    }
    setState(() => _highlight = next);
    if (!_controller.hasClients) {
      return;
    }
    final double viewport = _controller.position.viewportDimension;
    final double itemStart = next * _itemExtent;
    final double itemEnd = itemStart + _itemExtent;
    final double offset = _controller.offset;
    if (itemStart < offset) {
      _controller.jumpTo(itemStart);
    } else if (itemEnd > offset + viewport) {
      _controller.jumpTo(
        math.min(itemEnd - viewport, _controller.position.maxScrollExtent),
      );
    }
  }

  void _commit() {
    if (widget.options.isEmpty) {
      return;
    }
    Navigator.of(context).pop(widget.options[_highlight].value);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final double bottomInset = MediaQuery.paddingOf(context).bottom;

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.arrowDown): () => _move(1),
        const SingleActivator(LogicalKeyboardKey.arrowUp): () => _move(-1),
        const SingleActivator(LogicalKeyboardKey.enter): _commit,
        const SingleActivator(LogicalKeyboardKey.space): _commit,
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).pop(),
      },
      child: Focus(
        focusNode: _focusNode,
        autofocus: true,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: widget.maxHeight, minWidth: 0),
          child: Material(
            key: appSelectSheetKey,
            color: scheme.surface,
            clipBehavior: Clip.antiAlias,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                // 顶部拖拽提示条（视觉锚点，不可交互）。
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Center(
                    child: Container(
                      width: 32,
                      height: 4,
                      decoration: BoxDecoration(
                        color: scheme.onSurfaceVariant.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                  child: Text(
                    widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                Flexible(
                  child: ListView.builder(
                    controller: _controller,
                    // 选项少时按内容收缩，超过限高才滚动。
                    shrinkWrap: true,
                    itemExtent: _itemExtent,
                    padding: EdgeInsets.zero,
                    itemCount: widget.options.length,
                    itemBuilder: (BuildContext context, int index) {
                      final AppSelectOption<T> item = widget.options[index];
                      final bool selected = item.value == widget.value;
                      final bool highlighted = index == _highlight;
                      return InkWell(
                        onTap: () => Navigator.of(context).pop(item.value),
                        child: Container(
                          color: highlighted
                              ? scheme.primary.withValues(alpha: 0.08)
                              : null,
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Row(
                            children: <Widget>[
                              Expanded(
                                child: Text(
                                  item.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodyLarge?.copyWith(
                                    color: selected ? scheme.primary : null,
                                    fontWeight: selected
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                  ),
                                ),
                              ),
                              if (selected)
                                Icon(
                                  Icons.check,
                                  size: 20,
                                  color: scheme.primary,
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                // 底部安全区（手势条）留白。
                SizedBox(height: bottomInset),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
