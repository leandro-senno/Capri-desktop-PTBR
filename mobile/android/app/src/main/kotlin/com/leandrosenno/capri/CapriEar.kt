package com.leandrosenno.capri

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import org.json.JSONObject
import org.vosk.Model
import org.vosk.Recognizer
import org.vosk.android.RecognitionListener
import org.vosk.android.SpeechService
import java.io.File
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.util.zip.ZipInputStream

/// O ouvido da Capri em segundo plano.
///
/// 1. Mantém o microfone disponível enquanto ela flutua: o Android só deixa um app ouvir em segundo plano
///    se houver um serviço em primeiro plano do tipo "microfone", com aviso visível.
/// 2. Com a palavra de ativação ligada, fica ouvindo "Capri" com um reconhecedor offline (Vosk),
///    que roda inteiro no aparelho: nada do que ele ouve sai do celular nem é guardado.
class CapriEar : Service() {
    companion object {
        @Volatile
        var running = false

        /// A pessoa ligou a palavra de ativação.
        @Volatile
        var wantWake = false

        /// O app está usando o microfone (conversa, fala dela): a palavra de ativação espera.
        @Volatile
        var held = false

        /// Avisado quando ouve "Capri". Fica nulo quando o app não está aberto.
        var onWake: (() -> Unit)? = null

        private var instance: CapriEar? = null

        // Modelo de fala em português (31 MB), baixado uma vez.
        private const val MODEL_URL = "https://alphacephei.com/vosk/models/vosk-model-small-pt-0.3.zip"
        private var model: Model? = null

        @Volatile
        var downloading = false

        @Volatile
        var percent = 0

        @Volatile
        var problem: String? = null

        fun folder(context: Context) = File(context.filesDir, "vosk-pt")

        fun modelReady(context: Context) = File(folder(context), "conf/model.conf").exists() || File(folder(context), "am/final.mdl").exists()

        fun state(context: Context): Map<String, Any> = mapOf(
            "ready" to modelReady(context),
            "downloading" to downloading,
            "percent" to percent,
            "problem" to (problem ?: ""),
            "listening" to (instance?.speech != null),
        )

        /// Baixa e descompacta o modelo, numa thread separada.
        fun prepare(context: Context) {
            if (downloading || modelReady(context)) return
            downloading = true
            percent = 0
            problem = null
            val app = context.applicationContext
            Thread {
                val zip = File(app.cacheDir, "vosk-pt.zip")
                try {
                    val connection = URL(MODEL_URL).openConnection() as HttpURLConnection
                    connection.connectTimeout = 20000
                    connection.readTimeout = 30000
                    val total = connection.contentLengthLong
                    connection.inputStream.use { input ->
                        FileOutputStream(zip).use { output ->
                            val buffer = ByteArray(64 * 1024)
                            var got = 0L
                            while (true) {
                                val read = input.read(buffer)
                                if (read < 0) break
                                output.write(buffer, 0, read)
                                got += read
                                if (total > 0) percent = (got * 95 / total).toInt()
                            }
                        }
                    }
                    val target = folder(app)
                    target.deleteRecursively()
                    target.mkdirs()
                    ZipInputStream(zip.inputStream()).use { unzip ->
                        while (true) {
                            val entry = unzip.nextEntry ?: break
                            // Tira a pasta de cima do zip ("vosk-model-small-pt-0.3/...").
                            val inside = entry.name.substringAfter('/', "")
                            if (inside.isEmpty() || inside.contains("..")) continue
                            val out = File(target, inside)
                            if (entry.isDirectory) {
                                out.mkdirs()
                            } else {
                                out.parentFile?.mkdirs()
                                FileOutputStream(out).use { unzip.copyTo(it) }
                            }
                        }
                    }
                    percent = 100
                    if (!modelReady(app)) problem = "O modelo baixado veio incompleto."
                } catch (error: Exception) {
                    problem = "Não consegui baixar o ouvido offline. Confira a internet e tente de novo."
                } finally {
                    zip.delete()
                    downloading = false
                    Handler(Looper.getMainLooper()).post { instance?.apply() }
                }
            }.start()
        }

        /// Reaplica o estado (ligar ou pausar a escuta da palavra de ativação).
        fun refresh() {
            Handler(Looper.getMainLooper()).post { instance?.apply() }
        }
    }

    private var speech: SpeechService? = null
    private var loading = false
    private var lastWake = 0L

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        try {
            notifyUp()
            running = true
            instance = this
            apply()
        } catch (error: Exception) {
            running = false
            stopSelf()
        }
        return START_NOT_STICKY
    }

    private fun notifyUp() {
        val builder = if (Build.VERSION.SDK_INT >= 26) {
            getSystemService(NotificationManager::class.java)
                .createNotificationChannel(NotificationChannel("capri_ear", "Microfone da Capri", NotificationManager.IMPORTANCE_LOW))
            Notification.Builder(this, "capri_ear")
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        val words = if (wantWake) "Diga \"Capri\" para chamar. O que ela ouve não sai do celular." else "Microfone disponível para a janela flutuante"
        val notification = builder
            .setContentTitle("Capri")
            .setContentText(words)
            .setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .setOngoing(true)
            .build()
        if (Build.VERSION.SDK_INT >= 29) {
            startForeground(42, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE)
        } else {
            startForeground(42, notification)
        }
    }

    /// Liga a escuta da palavra quando faz sentido, e solta o microfone quando o app precisa dele.
    fun apply() {
        val should = wantWake && !held && modelReady(this)
        if (should && speech == null) begin() else if (!should) end()
        try {
            notifyUp()
        } catch (error: Exception) {
        }
    }

    private fun begin() {
        if (loading) return
        loading = true
        Thread {
            try {
                val loaded = model ?: Model(folder(this).absolutePath).also { model = it }
                Handler(Looper.getMainLooper()).post {
                    loading = false
                    if (!(wantWake && !held) || speech != null) return@post
                    try {
                        val service = SpeechService(Recognizer(loaded, 16000.0f), 16000.0f)
                        speech = service
                        service.startListening(listener)
                    } catch (error: Exception) {
                        speech = null
                        problem = "Não consegui abrir o microfone para a palavra de ativação."
                    }
                }
            } catch (error: Exception) {
                loading = false
                problem = "Não consegui carregar o ouvido offline."
            }
        }.start()
    }

    private fun end() {
        val service = speech ?: return
        speech = null
        try {
            service.stop()
            service.shutdown()
        } catch (error: Exception) {
        }
    }

    private val listener = object : RecognitionListener {
        override fun onPartialResult(hypothesis: String?) = check(hypothesis, "partial")
        override fun onResult(hypothesis: String?) = check(hypothesis, "text")
        override fun onFinalResult(hypothesis: String?) = check(hypothesis, "text")
        override fun onError(exception: Exception?) {
            end()
            Handler(Looper.getMainLooper()).postDelayed({ apply() }, 2000)
        }

        override fun onTimeout() {
            end()
            apply()
        }
    }

    private fun check(hypothesis: String?, field: String) {
        val heard = try {
            JSONObject(hypothesis ?: return).optString(field)
        } catch (error: Exception) {
            return
        }
        if (heard.isBlank() || !calls(heard)) return
        val now = System.currentTimeMillis()
        if (now - lastWake < 3000) return
        lastWake = now
        // Ouviu: solta o microfone para a conversa e chama o app.
        held = true
        end()
        val wake = onWake
        if (wake != null) {
            wake()
        } else {
            try {
                startActivity(Intent(this, MainActivity::class.java).putExtra("capri", "listen").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP))
            } catch (error: Exception) {
                held = false
                apply()
            }
        }
    }

    /// "Capri" e o que o reconhecedor costuma entender no lugar (cabri, capre...), também em duas palavras ("ca pri").
    private fun calls(text: String): Boolean {
        val words = CapriAccess.fold(text).split(' ').filter { it.isNotEmpty() }
        val tries = words + words.zipWithNext { a, b -> a + b }
        return tries.any { it.length in 4..7 && distance(it, "capri") <= 1 }
    }

    private fun distance(a: String, b: String): Int {
        val row = IntArray(b.length + 1) { it }
        for (i in 1..a.length) {
            var previous = row[0]
            row[0] = i
            for (j in 1..b.length) {
                val keep = row[j]
                row[j] = minOf(row[j] + 1, row[j - 1] + 1, previous + if (a[i - 1] == b[j - 1]) 0 else 1)
                previous = keep
            }
        }
        return row[b.length]
    }

    override fun onDestroy() {
        end()
        running = false
        instance = null
        super.onDestroy()
    }
}
