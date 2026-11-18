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
import java.util.zip.ZipFile
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

        // Modelo de fala em português (32 MB). Vem dentro do app (pasta assets/vosk-pt, posta na compilação)
        // e é copiado uma vez para os arquivos do app. Se não vier, é baixado, de um destes endereços.
        private val MODEL_URLS = listOf(
            "https://huggingface.co/rhasspy/vosk-models/resolve/main/pt/vosk-model-small-pt-0.3.zip",
            "https://alphacephei.com/vosk/models/vosk-model-small-pt-0.3.zip",
        )
        private const val ASSET = "vosk-pt"
        private var model: Model? = null

        @Volatile
        var downloading = false

        @Volatile
        var percent = 0

        @Volatile
        var problem: String? = null

        fun folder(context: Context) = File(context.filesDir, "vosk-pt")

        /// O arquivo principal do modelo: solto na pasta (formato antigo, o deste modelo) ou dentro de am/ (formato novo).
        private fun hasModel(dir: File) = File(dir, "final.mdl").exists() || File(dir, "am/final.mdl").exists()

        /// Pronto só quando a instalação terminou inteira (o marcador é escrito por último).
        fun modelReady(context: Context) = File(folder(context), ".capri-ready").exists() && hasModel(folder(context))

        fun state(context: Context): Map<String, Any> = mapOf(
            "ready" to modelReady(context),
            "downloading" to downloading,
            "percent" to percent,
            "problem" to (problem ?: ""),
            "listening" to (instance?.speech != null),
        )

        /// Instala o modelo numa thread separada: copia de dentro do app ou, se não houver, baixa.
        fun prepare(context: Context) {
            if (downloading || modelReady(context)) return
            downloading = true
            percent = 0
            problem = null
            val app = context.applicationContext
            Thread {
                try {
                    val target = folder(app)
                    target.deleteRecursively() // tentativa anterior pela metade
                    if (!copyBundled(app, target)) download(app, target)
                    if (!hasModel(target)) throw IllegalStateException("modelo sem final.mdl")
                    File(target, ".capri-ready").writeText("ok")
                    percent = 100
                } catch (error: Exception) {
                    folder(app).deleteRecursively()
                    problem = "Não consegui instalar o ouvido offline (${error.javaClass.simpleName}: ${error.message ?: "sem detalhe"}). Confira a internet e tente de novo."
                } finally {
                    downloading = false
                    Handler(Looper.getMainLooper()).post { instance?.apply() }
                }
            }.start()
        }

        /// Copia o modelo que veio dentro do app. Devolve false se o app não trouxe o modelo.
        private fun copyBundled(context: Context, target: File): Boolean {
            val assets = context.assets
            val top = try {
                assets.list(ASSET)
            } catch (error: Exception) {
                null
            }
            if (top.isNullOrEmpty()) return false
            val files = ArrayList<String>()
            fun walk(path: String) {
                val inside = assets.list(path) ?: emptyArray()
                if (inside.isEmpty()) files.add(path) else inside.forEach { walk("$path/$it") }
            }
            walk(ASSET)
            files.forEachIndexed { index, path ->
                val out = File(target, path.removePrefix("$ASSET/"))
                out.parentFile?.mkdirs()
                assets.open(path).use { input -> FileOutputStream(out).use { input.copyTo(it) } }
                percent = (index + 1) * 99 / files.size
            }
            return true
        }

        /// Baixa o zip, retomando de onde parou se a conexão cair, confere se veio inteiro e descompacta.
        private fun download(context: Context, target: File) {
            val zip = File(context.cacheDir, "vosk-pt.zip")
            var last: Exception? = null
            try {
                for (address in MODEL_URLS) {
                    zip.delete()
                    var total = -1L
                    for (attempt in 1..6) {
                        try {
                            val got = zip.length()
                            val connection = URL(address).openConnection() as HttpURLConnection
                            connection.connectTimeout = 20000
                            connection.readTimeout = 30000
                            connection.instanceFollowRedirects = true
                            if (got > 0) connection.setRequestProperty("Range", "bytes=$got-")
                            val code = connection.responseCode
                            val resumed = code == 206
                            if (code != 200 && !resumed) throw IllegalStateException("HTTP $code")
                            if (!resumed) zip.delete()
                            val length = connection.contentLengthLong
                            if (length > 0) total = if (resumed) got + length else length
                            connection.inputStream.use { input ->
                                FileOutputStream(zip, resumed).use { output ->
                                    val buffer = ByteArray(64 * 1024)
                                    while (true) {
                                        val read = input.read(buffer)
                                        if (read < 0) break
                                        output.write(buffer, 0, read)
                                        if (total > 0) percent = (zip.length() * 90 / total).toInt()
                                    }
                                }
                            }
                            if (total > 0 && zip.length() < total) throw IllegalStateException("veio ${zip.length()} de $total bytes")
                            unzip(zip, target)
                            return
                        } catch (error: Exception) {
                            last = error
                            Thread.sleep(1500L * attempt)
                        }
                    }
                }
                throw last ?: IllegalStateException("download falhou")
            } finally {
                zip.delete()
            }
        }

        /// Descompacta e acha a pasta do modelo (a que tem am/final.mdl), seja qual for o nome dentro do zip.
        private fun unzip(zip: File, target: File) {
            ZipFile(zip).close() // falha aqui se o zip veio cortado
            val scratch = File(target.parentFile, "vosk-unzip")
            scratch.deleteRecursively()
            scratch.mkdirs()
            try {
                ZipInputStream(zip.inputStream()).use { unzip ->
                    while (true) {
                        val entry = unzip.nextEntry ?: break
                        val out = File(scratch, entry.name)
                        if (!out.canonicalPath.startsWith(scratch.canonicalPath)) continue
                        if (entry.isDirectory) {
                            out.mkdirs()
                        } else {
                            out.parentFile?.mkdirs()
                            FileOutputStream(out).use { unzip.copyTo(it) }
                        }
                    }
                }
                val mdl = scratch.walkTopDown().firstOrNull { it.name == "final.mdl" }
                    ?: throw IllegalStateException("modelo sem final.mdl")
                val folder = mdl.parentFile!!
                val root = if (folder.name == "am") folder.parentFile!! else folder
                target.deleteRecursively()
                if (!root.renameTo(target)) {
                    root.copyRecursively(target, overwrite = true)
                }
            } finally {
                scratch.deleteRecursively()
            }
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
