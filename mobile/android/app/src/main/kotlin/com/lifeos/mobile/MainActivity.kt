package com.lifeos.mobile

import android.Manifest
import android.content.ActivityNotFoundException
import android.content.ContentValues
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.provider.Settings
import androidx.core.content.FileProvider
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
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, UPDATER_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "canRequestInstall" -> result.success(canRequestPackageInstalls())
                    "openInstallSettings" -> openInstallSettings(result)
                    "installApk" -> {
                        val path = call.argument<String>("path")
                        if (path.isNullOrBlank()) {
                            result.error("file_unavailable", "安装包路径为空", null)
                        } else {
                            installApk(path, result)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * 是否允许本应用安装 APK。
     *
     * Android 8.0+ 起「安装未知来源」按应用授权，必须每次安装前查询，
     * 不能假设用户开过一次就一直有效（系统升级或安全软件会重置）。
     */
    private fun canRequestPackageInstalls(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            packageManager.canRequestPackageInstalls()
        } else {
            true
        }
    }

    /** 跳转「安装未知应用」授权页，直接定位到本应用。 */
    private fun openInstallSettings(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            result.success(false)
            return
        }
        try {
            startActivity(
                Intent(
                    Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                    Uri.parse("package:$packageName"),
                ),
            )
            result.success(true)
        } catch (error: ActivityNotFoundException) {
            result.success(false)
        }
    }

    /**
     * 用 FileProvider 的 content:// 地址拉起系统安装器。
     *
     * 失败按原因分码返回，界面据此给出「去授权 / 换手动安装」的不同提示：
     * - permission_denied：未授权「安装未知应用」
     * - file_unavailable：路径不在 FileProvider 声明范围内
     * - installer_missing：设备没有能处理 APK 的 Activity
     */
    private fun installApk(path: String, result: MethodChannel.Result) {
        if (!canRequestPackageInstalls()) {
            result.error("permission_denied", "未授予「安装未知应用」权限", null)
            return
        }
        val file = File(path)
        if (!file.isFile) {
            result.error("file_unavailable", "安装包不存在：$path", null)
            return
        }
        val uri = try {
            FileProvider.getUriForFile(this, "$packageName.fileprovider", file)
        } catch (error: IllegalArgumentException) {
            result.error("file_unavailable", "安装包路径不在共享范围内：$path", null)
            return
        }
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        try {
            startActivity(intent)
            result.success(true)
        } catch (error: ActivityNotFoundException) {
            result.error("installer_missing", "系统没有可用的安装器", null)
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
        private const val UPDATER_CHANNEL = "com.lifeos.mobile/updater"
        private const val REQUEST_WRITE_STORAGE = 4101
        private const val REQUEST_BLE_PERMISSIONS = 4102
    }
}
