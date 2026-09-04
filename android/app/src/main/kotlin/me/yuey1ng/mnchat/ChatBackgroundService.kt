package me.yuey1ng.mnchat

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder

/**
 * 前台服务：后台保持进程活跃（接收 ChatPush 推送），并承载新消息通知。
 *
 * 由 MainActivity 通过 MethodChannel 启动/停止。Flutter 侧推送到达时调用
 * showNotification() 弹出系统通知（即使应用在后台也能收到）。
 */
class ChatBackgroundService : Service() {
    companion object {
        const val ACTION_START = "me.yuey1ng.mnchat.action.START"
        const val ACTION_STOP = "me.yuey1ng.mnchat.action.STOP"
        const val CHANNEL_ID = "mnchat_messages"
        const val NOTIFICATION_ID = 1

        /** 是否已启动 */
        var isRunning = false
            private set

        fun start(context: Context) {
            if (isRunning) return
            val intent = Intent(context, ChatBackgroundService::class.java).setAction(ACTION_START)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            if (!isRunning) return
            context.stopService(Intent(context, ChatBackgroundService::class.java))
        }

        /** 弹出新消息通知（应用前台时也会发，由 Dart 侧控制是否需要）。 */
        fun showNotification(context: Context, title: String, text: String, sessionKey: String) {
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            createChannel(context, nm)
            val intent = context.packageManager.getLaunchIntentForPackage(context.packageName)
            val pending = PendingIntent.getActivity(
                context,
                sessionKey.hashCode(),
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            val notification = Notification.Builder(context, CHANNEL_ID)
                .setSmallIcon(android.R.drawable.stat_notify_chat)
                .setContentTitle(title)
                .setContentText(text)
                .setContentIntent(pending)
                .setAutoCancel(true)
                .build()
            nm.notify(NOTIFICATION_ID, notification)
        }

        private fun createChannel(context: Context, nm: NotificationManager) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val channel = NotificationChannel(
                    CHANNEL_ID,
                    "聊天消息",
                    NotificationManager.IMPORTANCE_DEFAULT
                )
                nm.createNotificationChannel(channel)
            }
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action
        if (action == ACTION_STOP) {
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            return START_NOT_STICKY
        }
        startInForeground()
        return START_STICKY
    }

    private fun startInForeground() {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        ChatBackgroundService.createChannel(this, nm)
        val launch = packageManager.getLaunchIntentForPackage(packageName)
        val pending = PendingIntent.getActivity(
            this,
            0,
            launch,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val notification = Notification.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_notify_chat)
            .setContentTitle("MnChat 运行中")
            .setContentText("正在后台接收聊天消息")
            .setContentIntent(pending)
            .setOngoing(true)
            .build()
        startForeground(NOTIFICATION_ID, notification)
        isRunning = true
    }

    override fun onDestroy() {
        isRunning = false
        super.onDestroy()
    }
}