package com.lifeos.mobile

import android.Manifest
import android.content.ContentValues
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.provider.Settings
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
    private var blePermissionResult: MethodChannel.Result? = null

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
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BLE_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "requestBlePermissions" -> requestBlePermissions(result)
                    "openAppSettings" -> {
                        val intent = Intent(
                            Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                            Uri.parse("package:$packageName"),
                        )
                        startActivity(intent)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * 申请蓝牙扫描 / 连接权限。
     *
     * Android 12+ 使用 BLUETOOTH_SCAN / BLUETOOTH_CONNECT；
     * Android 11 及以下扫描 BLE 需要定位权限。
     * 返回 granted / denied / permanently_denied，供界面决定是否引导去设置。
     */
    private fun requestBlePermissions(result: MethodChannel.Result) {
        val required = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            arrayOf(
                Manifest.permission.BLUETOOTH_SCAN,
                Manifest.permission.BLUETOOTH_CONNECT,
            )
        } else {
            arrayOf(Manifest.permission.ACCESS_FINE_LOCATION)
        }
        val missing = required.filter {
            checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED
        }
        if (missing.isEmpty()) {
            result.success("granted")
            return
        }
        blePermissionResult = result
        requestPermissions(missing.toTypedArray(), REQUEST_BLE_PERMISSIONS)
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
        if (requestCode == REQUEST_BLE_PERMISSIONS) {
            val result = blePermissionResult
            blePermissionResult = null
            val allGranted = permissions.indices.all {
                grantResults.getOrNull(it) == PackageManager.PERMISSION_GRANTED
            }
            if (allGranted) {
                result?.success("granted")
            } else {
                // 没有任何权限可再次弹窗时，视为永久拒绝，界面引导去系统设置。
                val canAskAgain = permissions.any {
                    shouldShowRequestPermissionRationale(it)
                }
                result?.success(
                    if (canAskAgain) "denied" else "permanently_denied",
                )
            }
            return
        }
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
        private const val BLE_CHANNEL = "com.lifeos.mobile/ble"
        private const val REQUEST_WRITE_STORAGE = 4101
        private const val REQUEST_BLE_PERMISSIONS = 4102
    }
}
