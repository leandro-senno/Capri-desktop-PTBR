package com.leandrosenno.capri

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder

/// Mantém o microfone disponível enquanto a Capri está flutuando: o Android só deixa um app
/// ouvir em segundo plano se houver um serviço em primeiro plano do tipo "microfone" com aviso visível.
/// O serviço não grava nada; quem escuta é o reconhecimento de fala, só quando o microfone é ligado.
class CapriEar : Service() {
    companion object {
        @Volatile
        var running = false
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        try {
            val builder = if (Build.VERSION.SDK_INT >= 26) {
                getSystemService(NotificationManager::class.java)
                    .createNotificationChannel(NotificationChannel("capri_ear", "Microfone da Capri", NotificationManager.IMPORTANCE_LOW))
                Notification.Builder(this, "capri_ear")
            } else {
                @Suppress("DEPRECATION")
                Notification.Builder(this)
            }
            val notification = builder
                .setContentTitle("Capri")
                .setContentText("Microfone disponível para a janela flutuante")
                .setSmallIcon(android.R.drawable.ic_btn_speak_now)
                .setOngoing(true)
                .build()
            if (Build.VERSION.SDK_INT >= 29) {
                startForeground(42, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE)
            } else {
                startForeground(42, notification)
            }
            running = true
        } catch (error: Exception) {
            running = false
            stopSelf()
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        running = false
        super.onDestroy()
    }
}
