import 'package:flutter/material.dart';

import '../../theme/app_tokens.dart';

/// 静态区块卡片：标题 + 内容，二级页的统一容器（2.0 样式）。
///
/// 与 [GroupCard] 同一视觉口径：surface 底色、14dp 圆角、0.5dp 发丝线描边、
/// 16dp 内边距；标题用 16/600 主文字，右侧可选操作与原卡片保持同一行。
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    this.title,
    required this.child,
    this.trailing,
  });

  final String? title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    return Material(
      color: tokens.surface,
      borderRadius: BorderRadius.circular(AppTokens.cardRadius),
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppTokens.cardRadius),
          border: Border.all(
            color: tokens.line,
            width: AppTokens.hairline,
          ),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 12,
          children: <Widget>[
            if (title != null)
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      title!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.rowTitle.copyWith(
                        fontWeight: FontWeight.w600,
                        color: tokens.text,
                      ),
                    ),
                  ),
                  ?trailing,
                ],
              ),
            child,
          ],
        ),
      ),
    );
  }
}
