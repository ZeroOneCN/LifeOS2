import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_tokens.dart';

/// 声明下方二级页以内嵌方式渲染（作为根页栏目的内容，不压栈、不画导航栏）。
///
/// 根页把栏目页包进本组件后，[DetailPageScaffold] 会自动去掉导航栏、页面底色与
/// 状态栏声明，只保留内容区与底部操作区，从而与根页共用大标题和底栏导航。
class DetailPageEmbedded extends InheritedWidget {
  const DetailPageEmbedded({
    super.key,
    required super.child,
    this.embedded = true,
  });

  /// 是否以内嵌方式渲染。
  final bool embedded;

  /// 读取上层声明；没有声明时按独立页面处理。
  static bool of(BuildContext context) {
    final DetailPageEmbedded? scope = context
        .dependOnInheritedWidgetOfExactType<DetailPageEmbedded>();
    return scope?.embedded ?? false;
  }

  @override
  bool updateShouldNotify(DetailPageEmbedded oldWidget) =>
      embedded != oldWidget.embedded;
}

/// 二级页统一骨架（2.0）：紧凑导航栏 + 内容区 + 可选底部操作区。
///
/// - 导航栏高 44dp，左侧返回、标题绝对居中、右侧可选操作；底部 0.5dp 发丝线，
///   底色与页面一致，不再使用 Material `AppBar` 的 56dp 高度与独立底色。
/// - 内容区左右 [AppTokens.pagePadding]（20），与五个根页对齐。
/// - [bottomBar] 放在 body 的纵向布局里（内容区 `Expanded` + 底栏），而不是
///   `Scaffold.bottomNavigationBar`。这样底栏始终占位，内容只会在其上方滚动、
///   不会被压住；键盘弹起时 body 整体收缩，底栏随之上移到键盘上方，最末字段与
///   主操作同时可达。
/// - 被 [DetailPageEmbedded] 包裹时只渲染内容区与底栏，导航栏、底色、状态栏声明
///   全部交给根页，保证栏目内切换时页面骨架完全一致。
class DetailPageScaffold extends StatelessWidget {
  const DetailPageScaffold({
    super.key,
    required this.title,
    required this.child,
    this.floatingActionButton,
    this.actions,
    this.bottomBar,
  });

  final String title;
  final Widget child;
  final Widget? floatingActionButton;

  /// 导航栏右侧操作（通常是 `IconButton`）。
  final List<Widget>? actions;

  /// 底部常驻操作区；为空时页面保持无底栏。
  final Widget? bottomBar;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    // 内嵌模式：只保留内容区与底栏，导航栏/底色/状态栏由根页统一提供。
    if (DetailPageEmbedded.of(context)) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        // 键盘弹起由根页 Scaffold 统一收缩，内层不再重复处理。
        resizeToAvoidBottomInset: false,
        floatingActionButton: floatingActionButton,
        body: Column(
          children: <Widget>[
            Expanded(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  AppTokens.pagePadding,
                  6,
                  AppTokens.pagePadding,
                  bottomBar == null ? 0 : 12,
                ),
                child: child,
              ),
            ),
            // 底部安全区已由根页底栏导航占用，这里不再叠加 SafeArea。
            if (bottomBar != null)
              _buildBottomBar(tokens, applySafeArea: false),
          ],
        ),
      );
    }

    return AnnotatedRegion<SystemUiOverlayStyle>(
      // 骨架不再有 AppBar，状态栏样式需要在这里显式声明，避免沿用上一页。
      value: isDark
          ? SystemUiOverlayStyle.light
              .copyWith(statusBarColor: Colors.transparent)
          : SystemUiOverlayStyle.dark
              .copyWith(statusBarColor: Colors.transparent),
      child: Scaffold(
        backgroundColor: tokens.background,
        floatingActionButton: floatingActionButton,
        body: SafeArea(
          // 有底栏时底部安全区交给底栏自己处理，避免重复留白；
          // 无底栏时由外层 SafeArea 兜住手势条。
          bottom: bottomBar == null,
          child: Column(
            children: <Widget>[
              _DetailNavBar(title: title, actions: actions),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    AppTokens.pagePadding,
                    12,
                    AppTokens.pagePadding,
                    bottomBar == null ? 0 : 12,
                  ),
                  child: child,
                ),
              ),
              if (bottomBar != null)
                _buildBottomBar(tokens, applySafeArea: true),
            ],
          ),
        ),
      ),
    );
  }

  /// 底栏容器：surface 底色 + 顶部发丝线 + 铺满宽度的操作区。
  ///
  /// [applySafeArea] 为 false 时由外层（根页底栏导航）兜住手势条，避免重复留白。
  Widget _buildBottomBar(AppTokens tokens, {required bool applySafeArea}) {
    final Widget content = Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTokens.pagePadding,
        10,
        AppTokens.pagePadding,
        12,
      ),
      // 统一撑满宽度：单按钮底栏与双按钮底栏左右边界一致。
      child: SizedBox(width: double.infinity, child: bottomBar),
    );
    return Container(
      decoration: BoxDecoration(
        color: tokens.surface,
        border: Border(
          top: BorderSide(color: tokens.line, width: AppTokens.hairline),
        ),
      ),
      child: applySafeArea ? SafeArea(top: false, child: content) : content,
    );
  }
}

/// 44dp 紧凑导航栏：返回 + 居中标题 + 右侧操作。
///
/// 标题用 [Stack] 绝对居中：左右两侧宽度变化（无操作 / 一个操作）不会带动
/// 标题左右偏移；长标题按左右各 56dp 避让后省略。
class _DetailNavBar extends StatelessWidget {
  const _DetailNavBar({required this.title, this.actions});

  final String title;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    // 顶层页面（如冷启动直接落在 `/login`）没有上一页时不画无效返回箭头。
    final bool canPop = Navigator.of(context).canPop();
    final List<Widget>? actionWidgets = actions;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: tokens.line, width: AppTokens.hairline),
        ),
      ),
      child: SizedBox(
        height: 44,
        child: Stack(
          children: <Widget>[
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 56),
                child: Center(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.rowTitle.copyWith(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: tokens.text,
                    ),
                  ),
                ),
              ),
            ),
            if (canPop)
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  tooltip: '返回',
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.arrow_back_ios_new),
                  iconSize: 18,
                  color: tokens.text,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 44,
                    height: 44,
                  ),
                ),
              ),
            if (actionWidgets != null && actionWidgets.isNotEmpty)
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: IconButtonTheme(
                    // 覆盖 48dp 默认命中尺寸，避免右侧操作把 44dp 导航栏顶高。
                    data: IconButtonThemeData(
                      style: IconButton.styleFrom(
                        minimumSize: const Size(40, 40),
                        padding: EdgeInsets.zero,
                        foregroundColor: tokens.text,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: actionWidgets,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
