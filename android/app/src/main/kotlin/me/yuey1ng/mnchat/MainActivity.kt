package me.yuey1ng.mnchat

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "mnchat/native").setMethodCallHandler { call, result ->
            when (call.method) {
                "startBackgroundService" -> {
                    ChatBackgroundService.start(this)
                    result.success(true)
                }
                "stopBackgroundService" -> {
                    ChatBackgroundService.stop(this)
                    result.success(true)
                }
                "isBackgroundServiceRunning" -> {
                    result.success(ChatBackgroundService.isRunning)
                }
                "showNotification" -> {
                    val title = call.argument<String>("title") ?: ""
                    val text = call.argument<String>("text") ?: ""
                    val sessionKey = call.argument<String>("sessionKey") ?: ""
                    ChatBackgroundService.showNotification(this, title, text, sessionKey)
                    result.success(true)
                }
                "moveTaskToBack" -> {
                    // 返回键 → 隐藏到后台（进程保活，前台服务继续收推送）
                    moveTaskToBack(true)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }
}
