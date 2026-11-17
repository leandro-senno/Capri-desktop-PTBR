package com.leandrosenno.capri

import android.app.Notification
import android.app.RemoteInput
import android.content.Context
import android.content.Intent
import android.os.Bundle
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

        /// O botão "responder" de cada notificação recente, pela chave dela.
        private val replies = LinkedHashMap<String, Notification.Action>()

        /// Responde a uma notificação pelo próprio botão de resposta dela (como responder pela cortina).
        /// Só é chamado depois que a pessoa confirmou o texto na conversa.
        fun reply(context: Context, key: String, text: String): Boolean {
            val action = synchronized(replies) { replies[key] } ?: return false
            val inputs = action.remoteInputs ?: return false
            return try {
                val intent = Intent()
                val results = Bundle()
                for (input in inputs) results.putCharSequence(input.resultKey, text)
                RemoteInput.addResultsToIntent(inputs, intent, results)
                action.actionIntent.send(context, 0, intent)
                true
            } catch (error: Exception) {
                false
            }
        }
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
        val answer = notification.actions?.firstOrNull { action ->
            action.remoteInputs?.any { it.allowFreeFormInput } == true
        }
        if (answer != null) {
            synchronized(replies) {
                replies[sbn.key] = answer
                while (replies.size > 30) replies.remove(replies.keys.first())
            }
        }
        val item = mapOf<String, Any>(
            "key" to sbn.key,
            "canReply" to (answer != null),
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
