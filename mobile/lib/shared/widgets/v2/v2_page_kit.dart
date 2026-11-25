import 'package:flutter/material.dart';

import '../../../core/data/overview_controller.dart';
import '../../../theme/app_tokens.dart';
import '../section_status.dart';
import 'stat_rail.dart';

/// 列表页统一骨架：状态占位 → 内容块 → 加载更多页脚。
///
/// 统一各列表页的首屏顺序：数据未就绪时只显示状态条（加载中 / 失败 / 未登录），
/// 就绪后按 [children] 顺序渲染「摘要 → 分组标题 → 分组卡 → 页脚」。
/// 页面只负责提供内容，不再各自拼 `ListView` 与 `ListStatusView`。
class ListPageBody extends StatelessWidget {
  const ListPageBody({
    super.key,
    required this.status,
    required this.onRetry,
    this.message,
    this.blocks = const <Widget>[],
    this.footer,
  });

  /// 当前数据状态；[LoadStatus.ready] / [LoadStatus.idle] 时渲染内容。
  final LoadStatus status;

  /// 失败状态下的重试回调。
  final VoidCallback onRetry;

  /// 失败状态下的补充说明（接口报文 / 恢复登录时的错误）。
  final String? message;

  /// 内容块，按传入顺序纵向排列。
  final List<Widget> blocks;

  /// 列表尾部（通常是加载更多页脚），只在就绪后渲染。
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final bool ready = status == LoadStatus.ready || status == LoadStatus.idle;
    return ListView(
      // 左右与顶部由二级页骨架统一提供，这里只留滚动尾部留白。
      padding: const EdgeInsets.only(bottom: 24),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: <Widget>[
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          // 内容块之间统一 12dp，页面不再各自写 SizedBox。
          spacing: 12,
          children: <Widget>[
            if (!ready)
              ListStatusView(status: status, message: message, onRetry: onRetry)
            else ...<Widget>[
              ...blocks,
              ?footer,
            ],
          ],
        ),
      ],
    );
  }
}

/// 列表页首屏摘要：一句概览 + 三格指标轨。
///
/// 先给「有多少、最要紧的是什么」，再进入明细列表；[caption] 为空时只渲染指标轨。
class SummaryStrip extends StatelessWidget {
  const SummaryStrip({super.key, this.caption, required this.items});

  /// 概览句（如「最近一份 11-20 · 覆盖近 30 天」）。
  final String? caption;

  /// 指标项，数量与 [StatRail] 一致（2~4 项）。
  final List<StatRailItem> items;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    final String? text = caption;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 8,
      children: <Widget>[
        if (text != null && text.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppType.rowMeta.copyWith(color: tokens.text2),
            ),
          ),
        StatRail(items: items),
      ],
    );
  }
}

/// 2.0 搜索框：单行输入 + 搜索图标 + 有内容时可一键清空。
///
/// 输入框本身的底色、圆角、聚焦描边由全局 `inputDecorationTheme` 统一提供，
/// 这里只收敛图标、内边距与清空行为，避免各页各写一套。
class V2SearchField extends StatelessWidget {
  const V2SearchField({
    super.key,
    required this.controller,
    required this.hint,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    return TextField(
      controller: controller,
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      cursorColor: tokens.accent,
      style: AppType.rowTitle.copyWith(color: tokens.text),
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: const Icon(Icons.search, size: 18),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                tooltip: '清空搜索',
                icon: const Icon(Icons.close, size: 16),
                onPressed: () {
                  controller.clear();
                  onChanged('');
                },
              ),
      ),
    );
  }
}
