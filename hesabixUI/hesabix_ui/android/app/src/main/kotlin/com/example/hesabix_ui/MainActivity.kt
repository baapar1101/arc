package ir.hsxn.hesabix_ui

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import ir.hsxn.hesabix_ui.smsbank.SmsBankPlugin
import java.io.File

/// local_auth requires FragmentActivity (BiometricPrompt).
/// Also hosts APK install MethodChannel for sideloaded updates.
class MainActivity : FlutterFragmentActivity() {
    private val apkInstallerChannel = "ir.hsxn.hesabix_ui/apk_installer"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        SmsBankPlugin.register(flutterEngine, this)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            apkInstallerChannel,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "canRequestPackageInstalls" -> {
                    result.success(
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            packageManager.canRequestPackageInstalls()
                        } else {
                            true
                        },
                    )
                }
                "openInstallPermissionSettings" -> {
                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            val intent = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES).apply {
                                data = Uri.parse("package:$packageName")
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            startActivity(intent)
                        }
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("SETTINGS", e.message, null)
                    }
                }
                "installApk" -> {
                    val path = call.argument<String>("filePath")
                    if (path.isNullOrBlank()) {
                        result.error("ARG", "filePath required", null)
                        return@setMethodCallHandler
                    }
                    try {
                        installApk(path)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("INSTALL", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        SmsBankPlugin.consumeIntent(applicationContext, intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        SmsBankPlugin.consumeIntent(applicationContext, intent)
    }

    private fun installApk(path: String) {
        val file = File(path)
        if (!file.exists()) {
            throw IllegalArgumentException("APK file not found: $path")
        }
        // APKs may live under Flutter's app_flutter documents dir, which is
        // outside the default FileProvider roots (files/ / cache/). Prefer the
        // original path when configured; otherwise stage into cache.
        val shareFile = fileForProvider(file)
        val uri = FileProvider.getUriForFile(
            this,
            "$packageName.fileprovider",
            shareFile,
        )
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        startActivity(intent)
    }

    private fun fileForProvider(file: File): File {
        return try {
            FileProvider.getUriForFile(this, "$packageName.fileprovider", file)
            file
        } catch (_: IllegalArgumentException) {
            val staged = File(cacheDir, "apk_install/${file.name}")
            staged.parentFile?.mkdirs()
            file.copyTo(staged, overwrite = true)
            staged
        }
    }
}
