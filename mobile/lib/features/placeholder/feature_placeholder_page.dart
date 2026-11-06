import 'package:flutter/material.dart';

import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/root_page_scaffold.dart';

/// 二级占位页：真实路由已注册、可返回；业务列表留给后续批次。
class FeaturePlaceholderPage extends StatelessWidget {
  const FeaturePlaceholderPage({
    super.key,
    required this.title,
    this.description = '该页面的真实数据与交互将在后续批次接入。',
  });

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return DetailPageScaffold(
      title: title,
      child: EmptyState(
        icon: Icons.construction_outlined,
        title: title,
        description: description,
      ),
    );
  }
}
