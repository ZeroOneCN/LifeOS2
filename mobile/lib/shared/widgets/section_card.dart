import 'package:flutter/material.dart';

/// 静态区块卡片：标题 + 内容，P1 骨架的统一容器。
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
    final TextTheme textTheme = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 12,
          children: <Widget>[
            if (title != null)
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(title!, style: textTheme.titleMedium),
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
