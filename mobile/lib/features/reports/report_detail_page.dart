import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/data/overview_controller.dart';
import '../../core/models/report_models.dart';
import '../../core/network/api_exception.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/root_page_scaffold.dart';
import '../../shared/widgets/section_card.dart';
import '../../shared/widgets/section_status.dart';
import '../../theme/app_theme.dart';

/// 报告明细页：财务报告 / 投资报告共用。
///
/// 接口：`GET {source.apiPath}/{id}`。
/// 标题只显示报告名（AppBar），统计区间作为副标题只出现一次；
/// 明细按后端区块（h2 + table）分组，宽表改为「首列标题 + 两列字段网格」，
/// 不做横向滚动。
class ReportDetailPage extends StatefulWidget {
  const ReportDetailPage({
    super.key,
    required this.source,
    required this.reportId,
  });

  final ReportSource source;
  final int reportId;

  @override
  State<ReportDetailPage> createState() => _ReportDetailPageState();
}

class _ReportDetailPageState extends State<ReportDetailPage> {
  ReportDetail? _detail;
  LoadStatus _status = LoadStatus.loading;
  String? _message;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _refresh();
      }
    });
  }

  /// 拉取单份报告明细。
  Future<void> _refresh() async {
    final AppScope scope = AppScope.of(context);
    if (!scope.auth.isLoggedIn) {
      setState(() {
        _status = scope.auth.connectionFailed
            ? LoadStatus.connectionFailed
            : LoadStatus.unauthenticated;
        _message = scope.auth.restoreError;
      });
      return;
    }
    setState(() {
      _status = _detail == null ? LoadStatus.loading : LoadStatus.ready;
      _message = null;
    });
    try {
      final Map<String, dynamic>? data = (await scope.apiClient
              .get<Map<String, dynamic>>(
            '${widget.source.apiPath}/${widget.reportId}',
          ))
          .data;
      if (data == null) {
        throw const ApiException(
          kind: ApiErrorKind.badResponse,
          message: '报告详情返回数据为空',
        );
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _detail = ReportDetail.fromJson(data);
        _status = LoadStatus.ready;
      });
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _status = _errorStatus(scope, error);
        _message = error.message;
      });
    }
  }

  /// 错误分流：未登录 / 已保留登录态的连接失败 / 普通失败。
  LoadStatus _errorStatus(AppScope scope, ApiException error) {
    if (error.isUnauthorized) {
      return LoadStatus.unauthenticated;
    }
    final bool offline = scope.auth.hasLocalSession &&
        (error.kind == ApiErrorKind.network ||
            error.kind == ApiErrorKind.timeout);
    return offline ? LoadStatus.connectionFailed : LoadStatus.failed;
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color muted = theme.colorScheme.onSurfaceVariant;
    final ReportDetail? detail = _detail;
    final String title = detail == null || detail.displayTitle.isEmpty
        ? widget.source.pageTitle
        : detail.displayTitle;

    return DetailPageScaffold(
      title: title,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: <Widget>[
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 12,
            children: <Widget>[
              ListStatusView(
                status: _status,
                message: _message,
                onRetry: _refresh,
              ),
              if (_status == LoadStatus.ready && detail != null) ...<Widget>[
                SectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 6,
                    children: <Widget>[
                      if (detail.rangeText.isNotEmpty)
                        Row(
                          spacing: 6,
                          children: <Widget>[
                            Icon(Icons.calendar_month_outlined,
                                size: 16, color: muted),
                            Flexible(
                              child: Text(
                                detail.rangeText,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: muted,
                                  fontFeatures: const <FontFeature>[
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      if (detail.createdText.isNotEmpty)
                        Text(
                          detail.createdText,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: muted,
                          ),
                        ),
                      if (detail.displaySummary.isNotEmpty)
                        Text(
                          detail.displaySummary,
                          style: theme.textTheme.bodyMedium,
                        ),
                    ],
                  ),
                ),
                ..._buildSections(context, detail.content),
                if (detail.content.isEmpty)
                  const SectionCard(
                    child: EmptyState(
                      icon: Icons.description_outlined,
                      title: '报告暂无明细',
                      description: '该报告未包含可展示的区块',
                      compact: true,
                    ),
                  ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  /// 把 h2 / table 区块收拢成「标题 + 内容」的分组卡片。
  List<Widget> _buildSections(BuildContext context, List<ReportBlock> blocks) {
    final List<Widget> result = <Widget>[];
    String? sectionTitle;
    final List<Widget> body = <Widget>[];

    void flush() {
      if (body.isEmpty) {
        return;
      }
      result.add(
        SectionCard(
          title: sectionTitle,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 8,
            children: List<Widget>.of(body),
          ),
        ),
      );
      body.clear();
      sectionTitle = null;
    }

    for (final ReportBlock block in blocks) {
      if (block.isHeading) {
        flush();
        sectionTitle = block.text;
      } else if (block.isTable) {
        body.add(
          _ReportTable(
            header: block.header,
            rows: block.rows,
            caption: block.caption,
          ),
        );
      } else if (block.isKv) {
        body.add(
          _ReportTable(
            header: const <String>[],
            rows: block.rows,
            caption: block.caption,
          ),
        );
      } else if ((block.text ?? '').isNotEmpty) {
        body.add(
          Text(block.text!, style: Theme.of(context).textTheme.bodyMedium),
        );
      }
    }
    flush();
    return result;
  }
}

/// 报告表格渲染：两列走「标签 / 数值」行，多列按首列分组成字段网格。
class _ReportTable extends StatelessWidget {
  const _ReportTable({
    required this.header,
    required this.rows,
    this.caption = '',
  });

  final List<String> header;
  final List<List<String>> rows;

  /// 表格小标题（后端 `name`）/ 键值对分组标签（后端 `label`）。
  final String caption;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color muted = theme.colorScheme.onSurfaceVariant;
    final Widget table;
    if (rows.isEmpty) {
      table = Text(
        '暂无数据',
        style: theme.textTheme.bodySmall?.copyWith(color: muted),
      );
    } else if (header.length <= 2) {
      table = Column(
        children: <Widget>[
          for (final List<String> row in rows)
            _KvRow(header: header, row: row),
        ],
      );
    } else {
      table = Column(
        children: <Widget>[
          for (int index = 0; index < rows.length; index++) ...<Widget>[
            if (index > 0) const Divider(),
            _GroupedRow(header: header, row: rows[index]),
          ],
        ],
      );
    }
    if (caption.isEmpty) {
      return table;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 6,
      children: <Widget>[
        Text(
          caption,
          style: theme.textTheme.bodySmall?.copyWith(
            color: muted,
            fontWeight: FontWeight.w600,
          ),
        ),
        table,
      ],
    );
  }
}

/// 两列表格的一行：左标签、右数值（等宽、正负分色）。
class _KvRow extends StatelessWidget {
  const _KvRow({required this.header, required this.row});

  final List<String> header;
  final List<String> row;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color muted = theme.colorScheme.onSurfaceVariant;
    final AppSemanticColors colors = context.semanticColors;
    final String label = row.isNotEmpty ? row[0] : '';
    final String value = row.length > 1 ? row[1] : '';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 12,
        children: <Widget>[
          Expanded(
            flex: 4,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(color: muted),
            ),
          ),
          Expanded(
            flex: 5,
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: _signColor(value, colors),
                fontWeight: FontWeight.w600,
                fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 多列表格的一行：首列当标题，其余列按两列网格分组展示（不横向滚动）。
class _GroupedRow extends StatelessWidget {
  const _GroupedRow({required this.header, required this.row});

  final List<String> header;
  final List<String> row;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color muted = theme.colorScheme.onSurfaceVariant;
    final AppSemanticColors colors = context.semanticColors;
    final String title = row.isNotEmpty ? row[0] : '';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 4,
        children: <Widget>[
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final double itemWidth = (constraints.maxWidth - 12) / 2;
              return Wrap(
                spacing: 12,
                runSpacing: 6,
                children: <Widget>[
                  for (int i = 1; i < header.length; i++)
                    SizedBox(
                      width: itemWidth,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        spacing: 1,
                        children: <Widget>[
                          Text(
                            header[i],
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: muted),
                          ),
                          Text(
                            i < row.length ? row[i] : '',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: _signColor(
                                i < row.length ? row[i] : '',
                                colors,
                              ),
                              fontWeight: FontWeight.w600,
                              fontFeatures: const <FontFeature>[
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// 数值正负色：`+` 开头用 success，`-` 开头用 danger，其余保持默认色。
///
/// 只在「符号后紧跟数字或货币符号」时生效，避免把日期等文本误判成负数。
Color? _signColor(String value, AppSemanticColors colors) {
  final String text = value.trim();
  if (text.isEmpty) {
    return null;
  }
  if (RegExp(r'^[+＋]\s*(?:¥|￥|\d)').hasMatch(text)) {
    return colors.success;
  }
  if (RegExp(r'^[-−]\s*(?:¥|￥|\d)').hasMatch(text)) {
    return colors.danger;
  }
  return null;
}
