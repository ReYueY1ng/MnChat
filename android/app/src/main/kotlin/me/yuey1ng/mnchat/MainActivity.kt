package me.yuey1ng.mnchat

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * 原生桥接：前台服务 / 系统通知 / 运行时通知权限 / 通知点击跳转 / 隐藏到后台。
 *
 * 协议（与 Dart 侧 lib/core/services/native_bridge.dart 一一对应）：
 * Dart → native：startBackgroundService / stopBackgroundService /
 *   isBackgroundServiceRunning / requestNotificationPermission /
 *   showMessageNotification / cancelMessageNotification /
 *   cancelAllMessageNotifications / getInitialNotificationSessionKey / moveTaskToBack
 * native → Dart：onNotificationTap({sessionKey})
 */
class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "mnchat/native"
        private const val REQ_POST_NOTIFICATIONS = 1001
    }

    private var channel: MethodChannel? = null

    /** 冷启动时带进来的会话 key（点通知拉起应用）；读取一次后清空。 */
    private var initialSessionKey: String? = null

    /** 正在等待结果的权限请求（同一时间只允许一个）。 */
    private var permissionResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // 冷启动：启动 Intent 里可能带着「点通知进来」的会话 key
        initialSessionKey = intent?.getStringExtra(ChatBackgroundService.EXTRA_SESSION_KEY)

        val ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        channel = ch
        ch.setMethodCallHandler { call, result ->
            when (call.method) {
                "startBackgroundService" ->
                    result.success(ChatBackgroundService.start(this))

                "stopBackgroundService" -> {
                    ChatBackgroundService.stop(this)
                    result.success(true)
                }

                "isBackgroundServiceRunning" ->
                    result.success(ChatBackgroundService.isRunning)

                "requestNotificationPermission" -> requestNotificationPermission(result)

                "showMessageNotification" -> {
                    ChatBackgroundService.showMessageNotification(
                        this,
                        call.argument<String>("sessionKey") ?: "",
                        call.argument<String>("title") ?: "",
                        call.argument<String>("text") ?: "",
                        call.argument<List<String>>("lines") ?: emptyList(),
                        call.argument<Boolean>("group") ?: false,
                        call.argument<String>("avatarUrl"),
                        call.argument<String>("avatarAsset"),
                        call.argument<Boolean>("sound") ?: true,
                        call.argument<Boolean>("vibrate") ?: true
                    )
                    result.success(true)
                }

                "cancelMessageNotification" -> {
                    ChatBackgroundService.cancelMessageNotification(
                        this,
                        call.argument<String>("sessionKey") ?: ""
                    )
                    result.success(true)
                }

                "cancelAllMessageNotifications" -> {
                    ChatBackgroundService.cancelAllMessageNotifications(this)
                    result.success(true)
                }

                "getInitialNotificationSessionKey" -> {
                    val key = initialSessionKey
                    initialSessionKey = null // 只交付一次
                    result.success(key)
                }

                "moveTaskToBack" -> {
                    // 返回键 → 隐藏到后台（前台服务继续收推送）
                    moveTaskToBack(true)
                    result.success(true)
                }

                else -> result.notImplemented()
            }
        }
    }

    /**
     * Android 13(API 33)+ 运行时申请 POST_NOTIFICATIONS。
     *
     * 低于 33 直接返回 true（无需申请）；已授权直接返回 true。
     * 用系统 `requestPermissions` 而不是 androidx 的 `registerForActivityResult`，
     * 避免依赖 androidx.activity 的可用性。
     */
    private fun requestNotificationPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            result.success(true)
            return
        }
        val granted = checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
        if (granted) {
            result.success(true)
            return
        }
        if (permissionResult != null) {
            // 已有一个请求在飞：不重复弹窗，先按当前状态回复
            result.success(false)
            return
        }
        permissionResult = result
        requestPermissions(
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            REQ_POST_NOTIFICATIONS
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != REQ_POST_NOTIFICATIONS) return
        val granted = grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        permissionResult?.success(granted)
        permissionResult = null
    }

    /**
     * 热启动：应用已在运行时点击通知，系统复用该 Activity 并回调这里。
     * 把会话 key 直接推给 Dart（Dart 侧跳转到对应会话）。
     */
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val key = intent.getStringExtra(ChatBackgroundService.EXTRA_SESSION_KEY)
        if (!key.isNullOrEmpty()) {
            channel?.invokeMethod("onNotificationTap", mapOf("sessionKey" to key))
        }
    }
}
