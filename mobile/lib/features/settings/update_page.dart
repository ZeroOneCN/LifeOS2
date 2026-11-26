import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/app_scope.dart';
import '../../core/update/install_bridge.dart';
import '../../core/update/release_info.dart';
import '../../core/update/update_controller.dart';
import '../../core/update/update_service.dart';
import '../../shared/widgets/app_buttons.dart';
import '../../shared/widgets/root_page_scaffold.dart';
import '../../shared/widgets/section_card.dart';
import '../../shared/widgets/v2/stat_rail.dart';
import '../../shared/widgets/v2/v2_page_kit.dart';
import '../../theme/app_tokens.dart';

/// 检查更新页：展示当前/最新版本，下载带进度，校验 SHA-256 后拉起系统安装器。
///
/// 安装是系统界面行为，完成后当前 App 会被杀掉，所以这里不设计「装完回原页」。
class UpdatePage extends StatefulWidget {
  const UpdatePage({super.key});

  @override
  State<UpdatePage> createState() => _UpdatePageState();
}

class _UpdatePageState extends State<UpdatePage> with WidgetsBindingObserver {
  final InstallBridge _bridge = const InstallBridge();

  UpdateCheckResult? _result;
  bool _downloading = false;
  int _received = 0;
  int _total = 0;
  UpdateFailure? _failure;
  File? _readyFile;
  CancelToken? _cancelToken;

  /// 正在等待用户从「安装未知应用」设置页返回，返回后自动重试安装。
  bool _awaitingPermission = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _check();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cancelToken?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 从系统设置页返回：重新检查权限，已授权就直接拉起安装器。
    if (state == AppLifecycleState.resumed && _awaitingPermission) {
      _awaitingPermission = false;
      _install(_readyFile);
    }
  }

  /// 手动检查更新；结果决定展示「已是最新」还是「有新版本」。
  Future<void> _check() async {
    if (_downloading) {
      return;
    }
    final UpdateController update = AppScope.of(context).update;
    final UpdateCheckResult result = await update.check();
    if (!mounted) {
      return;
    }
    setState(() {
      _result = result;
      _failure = result == UpdateCheckResult.failed ? update.lastFailure : null;
      _readyFile = null;
    });
  }

  /// 下载并校验安装包；校验通过后直接进入安装流程。
  Future<void> _download() async {
    final UpdateController update = AppScope.of(context).update;
    final ReleaseInfo? release = update.latest;
    if (release == null || _downloading) {
      return;
    }
    setState(() {
      _downloading = true;
      _received = 0;
      _total = release.size;
      _failure = null;
      _readyFile = null;
    });
    final CancelToken token = CancelToken();
    _cancelToken = token;
    try {
      final Directory? base = await getExternalStorageDirectory();
      if (base == null) {
        throw const UpdateFailure(
          UpdateFailureKind.storage,
          '系统未提供应用外部目录',
          hint: '无法写入安装包，请检查存储状态',
        );
      }
      final File file = await update.service.downloadApk(
        serverBase: update.serverBase,
        release: release,
        baseDir: base,
        cancelToken: token,
        onProgress: (int received, int total) {
          if (!mounted) {
            return;
          }
          setState(() {
            _received = received;
            _total = total > 0 ? total : release.size;
          });
        },
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _downloading = false;
        _readyFile = file;
      });
      await _install(file);
    } on UpdateFailure catch (failure) {
      if (!mounted) {
        return;
      }
      setState(() {
        _downloading = false;
        _failure = failure;
      });
    } finally {
      _cancelToken = null;
    }
  }

  /// 校验通过后拉起系统安装器；未授权时先引导去「安装未知应用」。
  ///
  /// Args:
  ///   file: 已通过大小与哈希校验的 APK。
  Future<void> _install(File? file) async {
    if (file == null || !file.existsSync()) {
      return;
    }
    final bool allowed = await _bridge.canRequestInstall();
    if (!mounted) {
      return;
    }
    if (!allowed) {
      await _askInstallPermission();
      return;
    }
    try {
      await _bridge.installApk(file.path);
      // 安装界面已经拉起，当前 App 随后会被系统杀掉，这里不再更新界面
    } on InstallBridgeException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _failure = UpdateFailure(
          error.error == InstallBridgeError.permissionDenied
              ? UpdateFailureKind.installPermission
              : UpdateFailureKind.installerMissing,
          error.message,
          hint: error.error == InstallBridgeError.permissionDenied
              ? '在系统设置里允许本应用安装应用后，回到本页重试'
              : '可改用文件管理器手动安装下载目录中的 APK',
        );
      });
    }
  }

  /// 未授权「安装未知应用」时的引导弹窗。
  ///
  /// 用户确认后跳系统授权页；返回时由 [didChangeAppLifecycleState] 接手重试。
  Future<void> _askInstallPermission() async {
    final bool? go = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('需要安装权限'),
          content: const Text(
            '系统要求单独允许「安装未知应用」才能升级。'
            '确认后会打开本应用的授权页，打开开关再返回即可继续安装。',
          ),
          actions: <Widget>[
            AppActionRow(
              first: AppSecondaryButton(
                label: '取消',
                compact: true,
                onPressed: () => Navigator.of(dialogContext).pop(false),
              ),
              second: AppPrimaryButton(
                label: '去授权',
                icon: Icons.open_in_new,
                compact: true,
                onPressed: () => Navigator.of(dialogContext).pop(true),
              ),
            ),
          ],
        );
      },
    );
    if (go != true || !mounted) {
      setState(() {
        _failure = const UpdateFailure(
          UpdateFailureKind.installPermission,
          '未开启「安装未知应用」权限，安装已取消',
          hint: '可在本页重新点击安装，或到系统设置中允许本应用安装应用',
        );
      });
      return;
    }
    _awaitingPermission = true;
    final bool opened = await _bridge.openInstallSettings();
    if (!opened && mounted) {
      _awaitingPermission = false;
      setState(() {
        _failure = const UpdateFailure(
          UpdateFailureKind.installPermission,
          '无法打开安装权限设置页',
          hint: '请手动进入「设置 → 应用 → 特殊权限 → 安装未知应用」开启',
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    final AppScope scope = AppScope.of(context);
    return ListenableBuilder(
      listenable: scope.update,
      builder: (BuildContext context, _) {
        final UpdateController update = scope.update;
        final ReleaseInfo? release = update.latest;
        final bool available = update.hasUpdate && release != null;
        final String? status = _statusText(update);

        // 主操作常驻底栏：有更新时是「下载并安装」，下载中是「取消下载」，
        // 无更新时退回「重新检查」，三种状态位置不变。
        final Widget bottomBar;
        if (_downloading) {
          bottomBar = AppSecondaryButton(
            label: '取消下载',
            icon: Icons.close,
            onPressed: () => _cancelToken?.cancel(),
          );
        } else if (available) {
          bottomBar = AppPrimaryButton(
            label: _readyFile == null ? '下载并安装' : '重新安装',
            icon: Icons.system_update_alt,
            onPressed: _readyFile == null
                ? _download
                : () => _install(_readyFile),
          );
        } else {
          bottomBar = AppSecondaryButton(
            label: '重新检查',
            icon: Icons.refresh,
            onPressed: _check,
          );
        }

        return DetailPageScaffold(
          title: '检查更新',
          bottomBar: bottomBar,
          child: ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: <Widget>[
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 12,
                children: <Widget>[
                  SummaryStrip(
                    items: <StatRailItem>[
                      StatRailItem(
                        label: '当前版本',
                        value: update.currentVersionName.isEmpty
                            ? '—'
                            : update.currentVersionName,
                      ),
                      StatRailItem(
                        label: '最新版本',
                        value: release?.versionName ?? '—',
                      ),
                    ],
                  ),
                  if (status != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text(
                        status,
                        style: AppType.rowMeta.copyWith(color: tokens.text2),
                      ),
                    ),
                  SectionCard(
                    title: '版本信息',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        _InfoRow(
                          label: '当前版本',
                          value: _versionText(
                            update.currentVersionName,
                            update.currentVersionCode,
                          ),
                        ),
                        const Divider(height: 16),
                        _InfoRow(
                          label: '最新版本',
                          value: release == null
                              ? '未知'
                              : _versionText(
                                  release.versionName,
                                  release.versionCode,
                                ),
                        ),
                        if (release != null) ...<Widget>[
                          const Divider(height: 16),
                          _InfoRow(
                            label: '安装包大小',
                            value: formatBytes(release.size),
                          ),
                          if (release.publishedAt.isNotEmpty) ...<Widget>[
                            const Divider(height: 16),
                            _InfoRow(
                              label: '发布时间',
                              value: _dateText(release.publishedAt),
                            ),
                          ],
                        ],
                        const Divider(height: 16),
                        _InfoRow(
                          label: '更新来源',
                          value: update.latestFromStore
                              ? '应用仓库 apps.01iot.top'
                              : '${update.serverBase}/api/v1'
                                    '${UpdateService.manifestPath}',
                          small: true,
                        ),
                      ],
                    ),
                  ),
                  if (available && release.releaseNotes.isNotEmpty)
                    SectionCard(
                      title: '更新说明',
                      child: Text(
                        release.releaseNotes,
                        style: AppType.rowMeta.copyWith(color: tokens.text),
                      ),
                    ),
                  if (_failure != null) _FailureCard(failure: _failure!),
                  if (_downloading) _progressCard(),
                  Text(
                    '安装由系统安装器完成：需要手动点「安装」，部分手机会额外提示'
                    '「风险应用」或要求关闭纯净模式；安装过程中当前 App 会退出，'
                    '不会自动回到本页。',
                    style: AppType.rowMeta.copyWith(color: tokens.text3),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  /// ISO 时间 → `yyyy-MM-dd HH:mm`，去掉秒与时区，避免一行挤满数字。
  String _dateText(String value) {
    final String text = value.replaceFirst('T', ' ');
    return text.length >= 16 ? text.substring(0, 16) : text;
  }

  /// 下载进度卡：百分比 + 已传/总量。
  Widget _progressCard() {
    final AppTokens tokens = AppTokens.of(context);
    final double ratio = _total > 0 ? (_received / _total).clamp(0.0, 1.0) : 0;
    return SectionCard(
      title: '下载中',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 8,
        children: <Widget>[
          LinearProgressIndicator(value: ratio > 0 ? ratio : null),
          Text(
            '${(ratio * 100).toStringAsFixed(0)}%  '
            '${formatBytes(_received)} / ${formatBytes(_total)}',
            style: AppType.rowMeta.copyWith(color: tokens.text2),
          ),
        ],
      ),
    );
  }

  /// 状态行文案：检查中 / 已是最新 / 有新版本。
  String? _statusText(UpdateController update) {
    if (update.checking) {
      return '正在检查…';
    }
    if (_result == UpdateCheckResult.upToDate) {
      return '已是最新版本';
    }
    if (update.hasUpdate) {
      return '发现新版本 ${update.latest!.versionName}';
    }
    return null;
  }

  /// `1.0.0（2008）` 形式的版本文案。
  String _versionText(String name, int code) {
    if (name.isEmpty) {
      return '读取中…';
    }
    return code > 0 ? '$name（$code）' : name;
  }
}

/// 失败原因卡：主提示 + 建议动作，按失败类型不混用文案。
class _FailureCard extends StatelessWidget {
  const _FailureCard({required this.failure});

  final UpdateFailure failure;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tokens.fill2,
        borderRadius: BorderRadius.circular(AppTokens.controlRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 6,
        children: <Widget>[
          Row(
            spacing: 8,
            children: <Widget>[
              Icon(
                _iconFor(failure.kind),
                size: 18,
                color: tokens.red,
              ),
              Expanded(
                child: Text(
                  failure.message,
                  style: AppType.rowMeta.copyWith(
                    color: tokens.text,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          if (failure.hint.isNotEmpty)
            Text(
              failure.hint,
              style: AppType.rowMeta.copyWith(color: tokens.text2),
            ),
        ],
      ),
    );
  }

  /// 按失败类型选图标，让「权限」和「网络」一眼可分。
  IconData _iconFor(UpdateFailureKind kind) {
    switch (kind) {
      case UpdateFailureKind.network:
        return Icons.wifi_off;
      case UpdateFailureKind.notPublished:
        return Icons.cloud_off;
      case UpdateFailureKind.manifestInvalid:
        return Icons.description_outlined;
      case UpdateFailureKind.sizeMismatch:
      case UpdateFailureKind.hashMismatch:
        return Icons.gpp_bad_outlined;
      case UpdateFailureKind.storage:
        return Icons.sd_card_alert_outlined;
      case UpdateFailureKind.installPermission:
        return Icons.lock_outline;
      case UpdateFailureKind.installerMissing:
        return Icons.android_outlined;
      case UpdateFailureKind.cancelled:
        return Icons.cancel_outlined;
      case UpdateFailureKind.downloadFailed:
      case UpdateFailureKind.unknown:
        return Icons.error_outline;
    }
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    this.small = false,
  });

  final String label;
  final String value;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          width: 88,
          child: Text(
            label,
            style: AppType.rowMeta.copyWith(color: tokens.text2),
          ),
        ),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: small
                ? AppType.statLabel.copyWith(color: tokens.text3)
                : AppType.rowTitle.copyWith(color: tokens.text),
          ),
        ),
      ],
    );
  }
}
