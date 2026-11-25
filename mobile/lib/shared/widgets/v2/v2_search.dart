import 'package:flutter/material.dart';

import '../../../theme/app_tokens.dart';
import 'v2_rows.dart';

/// 搜索入口：一条可跳转的功能/记录。
class V2SearchEntry {
  const V2SearchEntry({
    required this.title,
    required this.route,
    this.subtitle,
    this.icon,
    this.keywords = '',
  });

  final String title;
  final String route;
  final String? subtitle;
  final IconData? icon;

  /// 额外关键词（同义词、栏目短名等），参与匹配但不展示。
  final String keywords;

  bool matches(String query) {
    final String q = query.trim().toLowerCase();
    if (q.isEmpty) {
      return true;
    }
    final String? sub = subtitle;
    return title.toLowerCase().contains(q) ||
        keywords.toLowerCase().contains(q) ||
        (sub != null && sub.toLowerCase().contains(q));
  }
}

/// 搜索分组，例如「健康功能」。
class V2SearchSection {
  const V2SearchSection({required this.title, required this.entries});

  final String title;
  final List<V2SearchEntry> entries;
}

/// 打开 2.0 全屏搜索；用户选中条目时返回其路由，取消返回 null。
Future<String?> openV2Search(
  BuildContext context, {
  required String hint,
  required List<V2SearchSection> sections,
}) {
  return Navigator.of(context).push<String>(
    MaterialPageRoute<String>(
      fullscreenDialog: true,
      builder: (BuildContext context) =>
          _V2SearchPage(hint: hint, sections: sections),
    ),
  );
}

class _V2SearchPage extends StatefulWidget {
  const _V2SearchPage({required this.hint, required this.sections});

  final String hint;
  final List<V2SearchSection> sections;

  @override
  State<_V2SearchPage> createState() => _V2SearchPageState();
}

class _V2SearchPageState extends State<_V2SearchPage> {
  final TextEditingController _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 按关键词过滤后仍非空的分组。
  List<V2SearchSection> get _results {
    return widget.sections
        .map(
          (V2SearchSection section) => V2SearchSection(
            title: section.title,
            entries: section.entries
                .where((V2SearchEntry entry) => entry.matches(_query))
                .toList(growable: false),
          ),
        )
        .where((V2SearchSection section) => section.entries.isNotEmpty)
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    final List<V2SearchSection> results = _results;
    return Scaffold(
      backgroundColor: tokens.background,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      autofocus: true,
                      textInputAction: TextInputAction.search,
                      onChanged: (String value) =>
                          setState(() => _query = value),
                      cursorColor: tokens.accent,
                      style: AppType.rowTitle.copyWith(color: tokens.text),
                      decoration: InputDecoration(
                        hintText: widget.hint,
                        hintStyle: AppType.rowTitle.copyWith(
                          color: tokens.text3,
                        ),
                        prefixIcon: const Icon(Icons.search, size: 18),
                        prefixIconColor: tokens.text2,
                        filled: true,
                        fillColor: tokens.fill,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 10,
                        ),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(
                      foregroundColor: tokens.accent,
                      minimumSize: const Size(52, 44),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      textStyle: AppType.rowTitle,
                    ),
                    child: const Text('取消'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: results.isEmpty
                  ? _EmptyResult(tokens: tokens, query: _query)
                  : ListView(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                      children: <Widget>[
                        for (final V2SearchSection section in results) ...[
                          Padding(
                            padding: const EdgeInsets.fromLTRB(4, 16, 4, 7),
                            child: Text(
                              section.title,
                              style: AppType.section.copyWith(
                                color: tokens.text2,
                              ),
                            ),
                          ),
                          GroupCard(
                            children: <Widget>[
                              for (final V2SearchEntry entry in section.entries)
                                _SearchRow(entry: entry),
                            ],
                          ),
                        ],
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchRow extends StatelessWidget {
  const _SearchRow({required this.entry});

  final V2SearchEntry entry;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    final IconData? icon = entry.icon;
    final String? subtitle = entry.subtitle;
    return InkWell(
      onTap: () => Navigator.of(context).pop(entry.route),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 52),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: <Widget>[
              if (icon != null) ...<Widget>[
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: tokens.fill,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 17, color: tokens.accent),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      entry.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.rowTitle.copyWith(color: tokens.text),
                    ),
                    if (subtitle != null && subtitle.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.rowMeta.copyWith(color: tokens.text2),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right, size: 15, color: tokens.text3),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyResult extends StatelessWidget {
  const _EmptyResult({required this.tokens, required this.query});

  final AppTokens tokens;
  final String query;

  @override
  Widget build(BuildContext context) {
    final String q = query.trim();
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.search_off, size: 28, color: tokens.text3),
            const SizedBox(height: 10),
            Text(
              q.isEmpty ? '输入功能名开始搜索' : '没有找到「$q」',
              textAlign: TextAlign.center,
              style: AppType.rowMeta.copyWith(color: tokens.text2),
            ),
          ],
        ),
      ),
    );
  }
}
