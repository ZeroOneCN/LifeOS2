package com.lifeos.mobile

import android.Manifest
import android.content.ContentValues
import android.content.pm.PackageManager
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * 平台通道：把头像原图写入系统相册。
 *
 * - Android 10+（API 29）：MediaStore，无需存储权限。
 * - Android 9 及以下：写入 Pictures/LifeOS，需要 WRITE_EXTERNAL_STORAGE，
 *   权限被拒时向 Flutter 返回 `permission_denied`，由界面给出可读提示。
 */
class MainActivity : FlutterActivity() {
    private var pendingBytes: ByteArray? = null
    private var pendingName: String? = null
    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method == "saveImageToGallery") {
                    val bytes = call.argument<ByteArray>("bytes")
                    val name = call.argument<String>("name") ?: "lifeos-avatar.jpg"
                    if (bytes == null || bytes.isEmpty()) {
                        result.error("invalid_args", "图片数据为空", null)
                    } else {
                        persistImage(bytes, name, result)
                    }
                } else {
                    result.notImplemented()
                }
            }
    }

    /** 按系统版本选择 MediaStore 或公共 Pictures 目录写入。 */
    private fun persistImage(bytes: ByteArray, name: String, result: MethodChannel.Result) {
        val needsLegacyPermission = Build.VERSION.SDK_INT < Build.VERSION_CODES.Q &&
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.M &&
            checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) !=
            PackageManager.PERMISSION_GRANTED
        if (needsLegacyPermission) {
            pendingBytes = bytes
            pendingName = name
            pendingResult = result
            requestPermissions(
                arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE),
                REQUEST_WRITE_STORAGE,
            )
            return
        }

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val values = ContentValues().apply {
                    put(MediaStore.Images.Media.DISPLAY_NAME, name)
                    put(MediaStore.Images.Media.MIME_TYPE, "image/jpeg")
                    put(
                        MediaStore.Images.Media.RELATIVE_PATH,
                        Environment.DIRECTORY_PICTURES + "/LifeOS",
                    )
                    put(MediaStore.Images.Media.IS_PENDING, 1)
                }
                val uri = contentResolver.insert(
                    MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                    values,
                ) ?: throw IllegalStateException("无法创建相册文件")
                val output = contentResolver.openOutputStream(uri)
                    ?: throw IllegalStateException("无法写入相册文件")
                output.use { it.write(bytes) }
                values.clear()
                values.put(MediaStore.Images.Media.IS_PENDING, 0)
                contentResolver.update(uri, values, null, null)
            } else {
                @Suppress("DEPRECATION")
                val pictures = Environment.getExternalStoragePublicDirectory(
                    Environment.DIRECTORY_PICTURES,
                )
                val dir = File(pictures, "LifeOS")
                if (!dir.exists()) {
                    dir.mkdirs()
                }
                File(dir, name).writeBytes(bytes)
            }
            result.success(true)
        } catch (error: Exception) {
            result.error("save_failed", error.message ?: "保存失败", null)
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != REQUEST_WRITE_STORAGE) {
            return
        }
        val bytes = pendingBytes
        val name = pendingName
        val result = pendingResult
        pendingBytes = null
        pendingName = null
        pendingResult = null
        if (grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED &&
            bytes != null &&
            result != null
        ) {
            persistImage(bytes, name ?: "lifeos-avatar.jpg", result)
        } else {
            result?.error("permission_denied", "没有相册写入权限", null)
        }
    }

    companion object {
        private const val CHANNEL = "com.lifeos.mobile/media"
        private const val REQUEST_WRITE_STORAGE = 4101
    }
}
