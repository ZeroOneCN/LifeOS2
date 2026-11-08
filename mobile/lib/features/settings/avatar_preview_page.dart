import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';

/// 大图页返回给设置页的动作：关闭大图后打开头像更换面板。
enum AvatarPreviewAction {
  /// 更换 / 移除头像：两条入口都回到原来的三条路径（上传 / 地址 / 移除）。
  edit,
}

/// 头像大图预览：深色背景、双指缩放、长按保存到系统相册。
///
/// 更换头像的入口收在头像自身交互里：点头像进大图，大图底部再提供
/// 「更换头像 / 移除头像」，关闭大图后回到设置页并弹出原三条路径面板，
/// 避免在设置页额外摆一个按钮影响版面。
///
/// 保存走平台通道（`com.lifeos.mobile/media`），Android 10+ 用 MediaStore，
/// 更低版本请求 WRITE_EXTERNAL_STORAGE；权限被拒会返回可读提示。
class AvatarPreviewPage extends StatefulWidget {
  const AvatarPreviewPage({
    super.key,
    required this.url,
  });

  /// 已解析后的完整头像地址（http/https）。
  final String url;

  @override
  State<AvatarPreviewPage> createState() => _AvatarPreviewPageState();
}

class _AvatarPreviewPageState extends State<AvatarPreviewPage> {
  static const MethodChannel _channel =
      MethodChannel('com.lifeos.mobile/media');

  bool _saving = false;

  /// 下载头像原图字节（不走缓存，保证保存的是最新图）。
  Future<Uint8List> _download() async {
    final HttpClient client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final HttpClientRequest request =
          await client.getUrl(Uri.parse(widget.url));
      final HttpClientResponse response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('图片请求失败（HTTP ${response.statusCode}）');
      }
      final List<int> bytes = <int>[];
      await for (final List<int> chunk in response) {
        bytes.addAll(chunk);
      }
      if (bytes.isEmpty) {
        throw const HttpException('图片内容为空');
      }
      return Uint8List.fromList(bytes);
    } finally {
      client.close(force: true);
    }
  }

  /// 长按保存：成功 / 权限被拒 / 其他失败都给出可读提示，不静默。
  Future<void> _save() async {
    if (_saving) {
      return;
    }
    setState(() => _saving = true);
    _toast('正在保存…');
    try {
      final Uint8List bytes = await _download();
      await _channel.invokeMethod<void>('saveImageToGallery', <String, dynamic>{
        'bytes': bytes,
        'name': 'lifeos-avatar-${DateTime.now().millisecondsSinceEpoch}.jpg',
      });
      if (!mounted) {
        return;
      }
      _toast('已保存到相册');
    } on PlatformException catch (error) {
      if (!mounted) {
        return;
      }
      if (error.code == 'permission_denied') {
        _toast('没有相册写入权限：请在系统设置中允许后重试');
      } else {
        _toast('保存失败：${error.message ?? error.code}');
      }
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      _toast('保存失败：$error');
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  /// 长按不再直接落盘：先弹出与微信一致的「保存图片」选项，
  /// 用户明确点「保存到相册」后才执行写入，避免误触把图片存进相册。
  Future<void> _showSaveOptions() async {
    if (_saving) {
      return;
    }
    final bool? confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: const Color(0xFF1C1C1E),
      showDragHandle: true,
      builder: (BuildContext sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            spacing: 8,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Text(
                  '长按操作',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.65),
                    fontSize: 12,
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.download_outlined, color: Colors.white),
                title: const Text(
                  '保存到相册',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () => Navigator.of(sheetContext).pop(true),
              ),
              ListTile(
                leading: const Icon(Icons.close, color: Colors.white70),
                title: const Text(
                  '取消',
                  style: TextStyle(color: Colors.white70),
                ),
                onTap: () => Navigator.of(sheetContext).pop(false),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
    if (confirmed == true && mounted) {
      await _save();
    }
  }

  /// 大图页用浅色浮条提示，避免默认深色 SnackBar 在黑底上看不清。
  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          backgroundColor: Colors.white,
          content: Text(message, style: const TextStyle(color: Colors.black)),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('头像预览'),
      ),
      body: SafeArea(
        child: Stack(
          children: <Widget>[
            Positioned.fill(
              child: GestureDetector(
                onLongPress: _saving ? null : _showSaveOptions,
                behavior: HitTestBehavior.opaque,
                child: InteractiveViewer(
                  minScale: 1,
                  maxScale: 5,
                  child: Center(
                    child: Image.network(
                      widget.url,
                      fit: BoxFit.contain,
                      loadingBuilder: (BuildContext context, Widget child,
                          ImageChunkEvent? progress) {
                        if (progress == null) {
                          return child;
                        }
                        return const Center(
                          child: CircularProgressIndicator(color: Colors.white),
                        );
                      },
                      errorBuilder: (BuildContext context, Object error,
                          StackTrace? stackTrace) {
                        return const Padding(
                          padding: EdgeInsets.all(32),
                          child: Text(
                            '头像加载失败，请返回重试',
                            style: TextStyle(color: Colors.white70),
                            textAlign: TextAlign.center,
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 20,
              right: 20,
              bottom: 16,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                spacing: 12,
                children: <Widget>[
                  Row(
                    spacing: 12,
                    children: <Widget>[
                      Expanded(
                        child: _DarkAction(
                          label: '更换头像',
                          icon: Icons.photo_library_outlined,
                          onPressed: () => Navigator.of(context)
                              .pop(AvatarPreviewAction.edit),
                        ),
                      ),
                      Expanded(
                        child: _DarkAction(
                          label: '移除头像',
                          icon: Icons.delete_outline,
                          danger: true,
                          onPressed: () => Navigator.of(context)
                              .pop(AvatarPreviewAction.edit),
                        ),
                      ),
                    ],
                  ),
                  Text(
                    '双指缩放 · 长按图片可保存到相册',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.65),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 深色大图页专用操作按钮：白底主操作 / 危险色描边次操作。
///
/// 尺寸与全 App 按钮规范一致（高 48、圆角 `AppRadii.control`、图标 18），
/// 仅颜色按黑底做反色处理，避免主题浅色按钮在黑底上不可见。
class _DarkAction extends StatelessWidget {
  const _DarkAction({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.danger = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final RoundedRectangleBorder shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadii.control),
    );
    const TextStyle textStyle = TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w600,
    );
    const EdgeInsets padding = EdgeInsets.symmetric(horizontal: 12);
    if (!danger) {
      return SizedBox(
        height: 48,
        child: FilledButton.icon(
          onPressed: onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: Colors.black,
            minimumSize: const Size(0, 48),
            padding: padding,
            shape: shape,
            iconSize: 18,
          ),
          icon: Icon(icon),
          label: Text(label, style: textStyle),
        ),
      );
    }
    return SizedBox(
      height: 48,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.dangerLight,
          minimumSize: const Size(0, 48),
          padding: padding,
          shape: shape,
          iconSize: 18,
          side: BorderSide(
            color: AppColors.dangerLight.withValues(alpha: 0.8),
          ),
        ),
        icon: Icon(icon),
        label: Text(label, style: textStyle),
      ),
    );
  }
}
