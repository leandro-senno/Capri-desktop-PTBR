package com.leandrosenno.capri

import android.app.Notification
import android.os.Handler
import android.os.Looper
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification

/// Guarda as últimas notificações do aparelho (só na memória) para a Capri ler quando a pessoa pedir.
class CapriNotices : NotificationListenerService() {
    companion object {
        val recent = ArrayDeque<Map<String, Any>>()
        var listener: ((Map<String, Any>) -> Unit)? = null

        @Volatile
        var connected = false

        fun latest(): List<Map<String, Any>> = synchronized(recent) { recent.toList() }
    }

    override fun onListenerConnected() {
        connected = true
    }

    override fun onListenerDisconnected() {
        connected = false
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        if (sbn == null || sbn.packageName == packageName || sbn.isOngoing) return
        val notification = sbn.notification ?: return
        if (notification.flags and Notification.FLAG_GROUP_SUMMARY != 0) return
        val extras = notification.extras ?: return
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString()?.trim() ?: ""
        val text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString()?.trim() ?: ""
        if (title.isEmpty() && text.isEmpty()) return
        val app = try {
            packageManager.getApplicationLabel(packageManager.getApplicationInfo(sbn.packageName, 0)).toString()
        } catch (error: Exception) {
            sbn.packageName
        }
        val item = mapOf<String, Any>(
            "app" to app,
            "title" to title.take(120),
            "text" to text.take(300),
            "time" to sbn.postTime,
            "message" to (notification.category == Notification.CATEGORY_MESSAGE),
        )
        synchronized(recent) {
            recent.addLast(item)
            while (recent.size > 20) recent.removeFirst()
        }
        Handler(Looper.getMainLooper()).post { listener?.invoke(item) }
    }
}
