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
import android.util.Log

/**
 * 前台服务：应用退到后台时保持进程活跃（持续接收 ChatPush 推送），并承载消息通知。
 *
 * 与旧实现的三点关键区别：
 * 1. **只在后台运行**：由 Dart 侧在应用退到后台时 start、回到前台时 stop ——
 *    所以常驻通知只在后台出现，启动应用时通知栏是干净的。旧实现一进主界面就挂
 *    常驻通知（keepAlive 默认 true），用户反馈「哪个聊天软件会这样干」。
 * 2. **消息通知按会话区分**：通知 id 用 `sessionKey.hashCode()`，不同会话可以并存，
 *    不再全部挤在 id=1 上互相覆盖（旧实现永远只留最后一条）。
 * 3. **两个通知渠道**：消息走 [CHANNEL_MESSAGES]（HIGH，有提示音），常驻走
 *    [CHANNEL_SERVICE]（MIN，无声、无角标）—— 常驻不会像消息那样打扰。
 *
 * 所有对外方法自带 try/catch：Android 12+ 从后台启动前台服务会抛
 * `ForegroundServiceStartNotAllowedException`，此处降级为「启动失败」而绝不崩溃。
 */
class ChatBackgroundService : Service() {
    companion object {
        const val ACTION_START = "me.yuey1ng.mnchat.action.START"
        const val ACTION_STOP = "me.yuey1ng.mnchat.action.STOP"

        /** 消息通知渠道（有提示音）。 */
        const val CHANNEL_MESSAGES = "mnchat_messages"

        /** 常驻服务渠道（无声、无角标、最低优先级）。 */
        const val CHANNEL_SERVICE = "mnchat_service"

        /** 常驻通知 id；消息通知用 sessionKey.hashCode()，需避开它。 */
        const val SERVICE_NOTIFICATION_ID = 1

        /** 通知点击时随 Intent 带回的会话 key（供 Dart 侧跳转到对应会话）。 */
        const val EXTRA_SESSION_KEY = "mnchat_session_key"

        private const val TAG = "MnChat"

        /** 消息通知的聚合组名（同组的多会话通知在通知栏折叠成一堆）。 */
        private const val GROUP_KEY = "mnchat.messages"

        /** 已弹出的消息通知 id（用于「全部清除」；不含常驻通知）。 */
        private val messageIds = mutableSetOf<Int>()

        /** 通知大图标缓存（asset:xx / url:xx → Bitmap），避免同一好友反复下载。 */
        private val iconCache = mutableMapOf<String, android.graphics.Bitmap>()

        var isRunning = false
            private set

        /**
         * 已下单 `startForegroundService()`、但服务尚未执行到 `startForeground()` 的窗口。
         *
         * 该窗口内**绝不能**调用 `stopService()`：AMS 的 `stopServiceLocked()` 在记录
         * 处于 delayed / pending / isServiceNeeded 时会提前返回，既不清 `fgRequired`
         * 也不撤 `SERVICE_FOREGROUND_TIMEOUT_MSG`，超时一到就抛
         * `ForegroundServiceDidNotStartInTimeException` 崩进程（前台服务契约泄漏）。
         */
        @Volatile
        private var startRequested = false

        /** 由 sessionKey 推导通知 id，并避开常驻通知 id（避免互相顶掉）。 */
        fun messageIdFor(sessionKey: String): Int {
            val id = sessionKey.hashCode()
            return if (id == SERVICE_NOTIFICATION_ID) id + 1 else id
        }

        /**
         * 启动前台服务。
         *
         * @return 是否成功。Android 12+ 在后台启动可能被系统拒绝（返回 false），
         *   此时不崩，退化为「进程活着就能收消息」。
         */
        fun start(context: Context): Boolean {
            return try {
                val intent = Intent(context, ChatBackgroundService::class.java)
                    .setAction(ACTION_START)
                startRequested = true
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
                true
            } catch (e: Exception) {
                startRequested = false
                Log.w(TAG, "启动前台服务失败: $e")
                false
            }
        }

        /**
         * 停止前台服务（常驻通知随之移除）。
         *
         * **不用 `stopService()`**：若 `startForegroundService()` 的前台契约尚未履行
         * （见 [startRequested]），`stopServiceLocked()` 会在 delayed / pending /
         * isServiceNeeded 时提前返回，从而泄漏 `fgRequired` 与超时消息，最终导致
         * `ForegroundServiceDidNotStartInTimeException` 崩溃。
         * 改为投递 [ACTION_STOP]，由 `onStartCommand()` 先 `ensureForeground()` 兑现
         * 契约、再自停 —— 任何时刻都不会留下未兑现的前台契约。
         */
        fun stop(context: Context) {
            // 既没在跑、也没有未兑现的启动请求：没有可停的东西。
            if (!isRunning && !startRequested) return
            try {
                val intent = Intent(context, ChatBackgroundService::class.java)
                    .setAction(ACTION_STOP)
                context.startService(intent)
            } catch (e: Exception) {
                // 后台限制拒绝 startService：**不**降级到 stopService（会重现竞态）。
                // 服务稍后 startForeground() 兑现契约，回前台时再次 stop 即可。
                Log.w(TAG, "停止前台服务失败: $e")
            }
        }

        /** 建好两个渠道（幂等；API < 26 无渠道概念）。 */
        fun createChannels(context: Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
            try {
                val nm = context.getSystemService(Context.NOTIFICATION_SERVICE)
                    as NotificationManager
                nm.createNotificationChannel(
                    NotificationChannel(
                        CHANNEL_MESSAGES,
                        "聊天消息",
                        NotificationManager.IMPORTANCE_HIGH
                    ).apply { description = "好友 / 群聊新消息" }
                )
                nm.createNotificationChannel(
                    NotificationChannel(
                        CHANNEL_SERVICE,
                        "后台运行",
                        NotificationManager.IMPORTANCE_MIN
                    ).apply {
                        description = "退到后台时保持连接（常驻通知）"
                        setShowBadge(false)
                    }
                )
            } catch (e: Exception) {
                Log.w(TAG, "创建通知渠道失败: $e")
            }
        }

        /** 兼容 API < 26 的通知构造（带 channel 的构造在低版本会崩）。 */
        private fun builder(context: Context, channelId: String): Notification.Builder =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Notification.Builder(context, channelId)
            } else {
                @Suppress("DEPRECATION")
                Notification.Builder(context)
            }

        /**
         * 消息渠道 id —— 按「提示音 / 震动」的组合取对应渠道。
         *
         * Android 8+ 的声音与震动是**渠道级**属性，单条通知改不了，所以只能这么分；
         * 且只在真正用到时才创建，用户的通知设置里不会平白多出用不到的条目。
         *
         * 两者都开时直接用默认消息渠道，保持与旧版本完全一致的行为。
         */
        private fun messageChannel(
            context: Context,
            sound: Boolean,
            vibrate: Boolean
        ): String {
            if (sound && vibrate) return CHANNEL_MESSAGES
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return CHANNEL_MESSAGES
            val id = when {
                !sound && !vibrate -> "${CHANNEL_MESSAGES}_silent"
                !sound -> "${CHANNEL_MESSAGES}_nosound"
                else -> "${CHANNEL_MESSAGES}_novibrate"
            }
            try {
                val nm = context.getSystemService(Context.NOTIFICATION_SERVICE)
                    as NotificationManager
                if (nm.getNotificationChannel(id) == null) {
                    val name = when {
                        !sound && !vibrate -> "聊天消息（静音）"
                        !sound -> "聊天消息（无声）"
                        else -> "聊天消息（不震动）"
                    }
                    val ch = NotificationChannel(
                        id,
                        name,
                        NotificationManager.IMPORTANCE_HIGH
                    ).apply {
                        description = "好友 / 群聊新消息"
                        if (!sound) setSound(null, null)
                        enableVibration(vibrate)
                    }
                    nm.createNotificationChannel(ch)
                }
            } catch (e: Exception) {
                Log.w(TAG, "创建消息渠道失败: $e")
                return CHANNEL_MESSAGES
            }
            return id
        }

        /** 构造「点击后带着 sessionKey 打开应用」的 PendingIntent。 */
        private fun launchPending(
            context: Context,
            sessionKey: String,
            requestCode: Int
        ): PendingIntent? {
            val intent = context.packageManager
                .getLaunchIntentForPackage(context.packageName) ?: return null
            intent.putExtra(EXTRA_SESSION_KEY, sessionKey)
            // singleTop + 该 flag：应用已在运行时点通知走 onNewIntent（热启动），
            // 未运行时由启动 Intent 带回（冷启动）。
            intent.addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
            return PendingIntent.getActivity(
                context,
                requestCode,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        }

        /**
         * 弹出一条会话消息通知。
         *
         * 同一会话重复收到时原地更新那一条；不同会话各自一条、并存不覆盖。
         *
         * @param lines 该会话最近若干条正文，用 InboxStyle 展开显示（最多 5 条）。
         */
        fun showMessageNotification(
            context: Context,
            sessionKey: String,
            title: String,
            text: String,
            lines: List<String>,
            group: Boolean,
            avatarUrl: String?,
            avatarAsset: String?,
            sound: Boolean,
            vibrate: Boolean
        ) {
            // 先立刻弹出（不等头像下载完成），再在后台线程把大图标补上原地更新。
            postMessageNotification(context, sessionKey, title, text, lines, group, null, sound, vibrate)
            if (avatarAsset.isNullOrEmpty() && avatarUrl.isNullOrEmpty()) return
            val app = context.applicationContext
            Thread {
                val icon = loadLargeIcon(app, avatarAsset, avatarUrl) ?: return@Thread
                postMessageNotification(app, sessionKey, title, text, lines, group, icon, sound, vibrate)
            }.start()
        }

        /** 真正构建并发出消息通知（[icon] 为空则不带大图标）。 */
        private fun postMessageNotification(
            context: Context,
            sessionKey: String,
            title: String,
            text: String,
            lines: List<String>,
            group: Boolean,
            icon: android.graphics.Bitmap?,
            sound: Boolean,
            vibrate: Boolean
        ) {
            try {
                createChannels(context)
                val nm = context.getSystemService(Context.NOTIFICATION_SERVICE)
                    as NotificationManager
                val id = messageIdFor(sessionKey)
                val nb = builder(context, messageChannel(context, sound, vibrate))
                    .setSmallIcon(android.R.drawable.stat_notify_chat)
                    .setContentTitle(title)
                    .setContentText(text)
                    .setAutoCancel(true)
                    .setGroup(GROUP_KEY)
                if (icon != null) nb.setLargeIcon(icon)
                launchPending(context, sessionKey, id)?.let { nb.setContentIntent(it) }
                if (lines.size > 1) {
                    val style = Notification.InboxStyle().setBigContentTitle(title)
                    lines.take(5).forEach { style.addLine(it.take(80)) }
                    nb.setStyle(style)
                } else {
                    nb.setStyle(Notification.BigTextStyle().bigText(text))
                }
                nm.notify(id, nb.build())
                synchronized(messageIds) { messageIds.add(id) }
                if (group) {
                    // 群聊与好友分开成两个通知栏小组，便于折叠（失败不影响通知本身）
                    nm.createNotificationChannelGroup(
                        android.app.NotificationChannelGroup("mnchat.groups", "群聊")
                    )
                }
            } catch (e: Exception) {
                Log.w(TAG, "弹出通知失败: $e")
            }
        }

        /**
         * 加载通知大图标：优先 Flutter 资源里的本地头像图标（APK 内路径为
         * `assets/flutter_assets/<asset>`），其次按 URL 下载。结果进小缓存。
         */
        private fun loadLargeIcon(
            context: Context,
            asset: String?,
            url: String?
        ): android.graphics.Bitmap? {
            val assetKey = asset?.takeIf { it.isNotEmpty() }
            val urlText = url?.takeIf { it.isNotEmpty() }
            val key = when {
                assetKey != null -> "asset:$assetKey"
                urlText != null -> "url:$urlText"
                else -> return null
            }
            synchronized(iconCache) { iconCache[key]?.let { return it } }
            val bitmap: android.graphics.Bitmap? = try {
                if (assetKey != null) {
                    context.assets.open("flutter_assets/$assetKey").use {
                        android.graphics.BitmapFactory.decodeStream(it)
                    }
                } else if (urlText != null) {
                    val conn = java.net.URL(urlText).openConnection()
                            as java.net.HttpURLConnection
                    conn.connectTimeout = 4000
                    conn.readTimeout = 4000
                    conn.instanceFollowRedirects = true
                    conn.inputStream.use {
                        android.graphics.BitmapFactory.decodeStream(it)
                    }
                } else {
                    null
                }
            } catch (e: Exception) {
                Log.w(TAG, "加载通知头像失败: $e")
                null
            }
            if (bitmap != null) {
                synchronized(iconCache) {
                    if (iconCache.size > 32) iconCache.clear()
                    iconCache[key] = bitmap
                }
            }
            return bitmap
        }

        /** 取消某个会话的通知。 */
        fun cancelMessageNotification(context: Context, sessionKey: String) {
            try {
                val nm = context.getSystemService(Context.NOTIFICATION_SERVICE)
                    as NotificationManager
                val id = messageIdFor(sessionKey)
                nm.cancel(id)
                synchronized(messageIds) { messageIds.remove(id) }
            } catch (e: Exception) {
                Log.w(TAG, "取消通知失败: $e")
            }
        }

        /** 取消全部消息通知（**不动**常驻通知）。 */
        fun cancelAllMessageNotifications(context: Context) {
            try {
                val nm = context.getSystemService(Context.NOTIFICATION_SERVICE)
                    as NotificationManager
                synchronized(messageIds) {
                    messageIds.forEach { nm.cancel(it) }
                    messageIds.clear()
                }
            } catch (e: Exception) {
                Log.w(TAG, "清空通知失败: $e")
            }
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        // 一被创建就立即兑现前台契约：无论随后 intent 是 START 还是 STOP，
        // 都必须在系统超时内调用 startForeground()，否则系统抛
        // ForegroundServiceDidNotStartInTimeException（进程级崩溃，无法捕获）。
        ensureForeground()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // 幂等兜底：服务已存在、onCreate 不再执行时，仍保证契约已履行。
        ensureForeground()
        if (intent?.action == ACTION_STOP) {
            removeForeground()
            stopSelf()
            return START_NOT_STICKY
        }
        return START_STICKY
    }

    /**
     * 幂等地进入前台。
     *
     * 任何一次 `startForegroundService()` 都会给本服务记一笔「必须尽快
     * startForeground()」的账（AMS 的 `fgRequired` + 超时消息）。把它收敛到唯一
     * 入口，保证只要服务被启动、无论带着什么 action，这笔账都会被还清。
     */
    private fun ensureForeground() {
        if (isRunning) return
        try {
            startInForeground()
        } catch (e: Exception) {
            // 前台服务启动被拒（Android 12+ 后台限制）/ 通知渠道异常：
            // 收起服务，不影响应用本体运行。
            Log.w(TAG, "前台服务启动失败: $e")
            removeForeground()
            stopSelf()
        }
    }

    /** 常驻通知：低优先级渠道、Ongoing、文案中性。 */
    private fun startInForeground() {
        createChannels(this)
        val nb = builder(this, CHANNEL_SERVICE)
            .setSmallIcon(android.R.drawable.stat_notify_chat)
            .setContentTitle("MnChat 后台运行中")
            .setContentText("保持连接以接收消息")
            .setOngoing(true)
        launchPending(this, "", SERVICE_NOTIFICATION_ID)?.let { nb.setContentIntent(it) }
        startForeground(SERVICE_NOTIFICATION_ID, nb.build())
        isRunning = true
        startRequested = false
    }

    /** 移除前台状态与常驻通知（兼容 API < 24）。 */
    private fun removeForeground() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                stopForeground(STOP_FOREGROUND_REMOVE)
            } else {
                @Suppress("DEPRECATION")
                stopForeground(true)
            }
        } catch (e: Exception) {
            Log.w(TAG, "移除前台通知失败: $e")
        }
        isRunning = false
    }

    override fun onDestroy() {
        isRunning = false
        startRequested = false
        super.onDestroy()
    }
}
