package com.leandrosenno.capri

import android.Manifest
import android.app.ActivityManager
import android.app.SearchManager
import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioManager
import android.media.MediaMetadata
import android.media.session.MediaSessionManager
import android.media.session.PlaybackState
import android.net.Uri
import android.os.Bundle
import android.os.BatteryManager
import android.provider.AlarmClock
import android.provider.CalendarContract
import android.provider.ContactsContract
import android.provider.MediaStore
import android.provider.Settings
import android.view.KeyEvent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/// As "mãos" da Capri no Android: apps, links, música, alarmes, contatos, bateria,
/// e a ponte para os serviços de acessibilidade (tela) e de notificações.
class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null

    /// Por que o app foi aberto (widget, atalho, assistente, palavra de ativação, ao ligar), até o Dart perguntar.
    private var pending: String? = null

    /// O que o pedido de abertura quer: "listen" (conversar), "toggle" (soltar ou guardar) ou "float" (soltar).
    private fun reason(intent: Intent?): String? {
        if (intent == null) return null
        intent.getStringExtra("capri")?.let { return it }
        return when (intent.action) {
            Intent.ACTION_ASSIST, Intent.ACTION_VOICE_COMMAND, "android.intent.action.SEARCH_LONG_PRESS" -> "listen"
            else -> null
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        pending = reason(intent)
        super.onCreate(savedInstanceState)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        val why = reason(intent) ?: return
        val talk = channel
        if (talk != null) talk.invokeMethod("launched", why) else pending = why
    }

    override fun onDestroy() {
        CapriEar.onWake = null
        channel = null
        super.onDestroy()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val hands = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "capri/hands")
        channel = hands
        // A palavra de ativação ouviu "Capri" com o app aberto: avisa o Dart, que decide o que mostrar.
        CapriEar.onWake = { runOnUiThread { channel?.invokeMethod("wake", null) } }
        hands.setMethodCallHandler { call, result ->
            if (call.method == "shot") {
                // A foto da tela chega depois, por isso responde fora do fluxo comum.
                val access = CapriAccess.instance
                if (access == null) result.success(null) else access.shot { bytes -> result.success(bytes) }
                return@setMethodCallHandler
            }
            try {
                result.success(handle(call))
            } catch (error: NotImplementedError) {
                result.notImplemented()
            } catch (error: Exception) {
                result.success(if (call.method == "apps" || call.method == "notices" || call.method == "tappable") emptyList<Map<String, Any>>() else if (call.method == "screen" || call.method == "contact" || call.method == "battery" || call.method == "playing" || call.method == "launch" || call.method == "wakeState" || call.method == "events") null else false)
            }
        }
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "capri/notices").setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                CapriNotices.listener = { item -> events?.success(item) }
            }

            override fun onCancel(arguments: Any?) {
                CapriNotices.listener = null
            }
        })
    }

    private fun text(call: MethodCall, name: String): String = call.argument<String>(name) ?: ""

    private fun handle(call: MethodCall): Any? {
        return when (call.method) {
            "apps" -> {
                val launcher = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
                packageManager.queryIntentActivities(launcher, 0).map {
                    mapOf("name" to it.loadLabel(packageManager).toString(), "package" to it.activityInfo.packageName)
                }
            }
            "launch" -> {
                val intent = packageManager.getLaunchIntentForPackage(text(call, "package"))
                intent != null && start(intent)
            }
            "view" -> start(Intent(Intent.ACTION_VIEW, Uri.parse(text(call, "url"))))
            // Pede ao app de música para tocar o que foi buscado (Spotify e YouTube Music aceitam).
            "play" -> start(
                Intent(MediaStore.INTENT_ACTION_MEDIA_PLAY_FROM_SEARCH)
                    .setPackage(call.argument<String>("package"))
                    .putExtra(MediaStore.EXTRA_MEDIA_FOCUS, "vnd.android.cursor.item/*")
                    .putExtra(SearchManager.QUERY, text(call, "query"))
            )
            // Abre a busca dentro de um app (o YouTube aceita).
            "search" -> start(Intent(Intent.ACTION_SEARCH).setPackage(call.argument<String>("package")).putExtra(SearchManager.QUERY, text(call, "query")))
            // Manda um texto para um app (o WhatsApp abre a lista de conversas para escolher).
            "share" -> start(Intent(Intent.ACTION_SEND).setType("text/plain").setPackage(call.argument<String>("package")).putExtra(Intent.EXTRA_TEXT, text(call, "text")))
            "alarm" -> start(
                Intent(AlarmClock.ACTION_SET_ALARM)
                    .putExtra(AlarmClock.EXTRA_HOUR, call.argument<Int>("hour") ?: 0)
                    .putExtra(AlarmClock.EXTRA_MINUTES, call.argument<Int>("minute") ?: 0)
                    .putExtra(AlarmClock.EXTRA_MESSAGE, text(call, "label"))
                    .putExtra(AlarmClock.EXTRA_SKIP_UI, true)
            )
            "timer" -> start(
                Intent(AlarmClock.ACTION_SET_TIMER)
                    .putExtra(AlarmClock.EXTRA_LENGTH, call.argument<Int>("seconds") ?: 60)
                    .putExtra(AlarmClock.EXTRA_MESSAGE, text(call, "label"))
                    .putExtra(AlarmClock.EXTRA_SKIP_UI, true)
            )
            "battery" -> {
                val battery = getSystemService(BATTERY_SERVICE) as BatteryManager
                mapOf("level" to battery.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY), "charging" to battery.isCharging)
            }
            "contact" -> contact(text(call, "name"))
            "access" -> CapriAccess.instance != null
            "accessSettings" -> start(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
            "appSettings" -> start(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName")))
            "screen" -> CapriAccess.instance?.read()
            "locate" -> CapriAccess.instance?.locate(text(call, "text"))
            "tappable" -> CapriAccess.instance?.tappable() ?: emptyList<String>()
            "click" -> CapriAccess.instance?.click(text(call, "text"))
            "type" -> CapriAccess.instance?.type(text(call, "text")) ?: false
            "scroll" -> CapriAccess.instance?.scroll(call.argument<Boolean>("down") ?: true, (call.argument<Double>("x") ?: 0.5).toFloat()) ?: false
            // Botões de mídia: valem para o que estiver tocando (Spotify, YouTube, TikTok...).
            "media" -> {
                val audio = getSystemService(AUDIO_SERVICE) as AudioManager
                val code = when (text(call, "key")) {
                    "next" -> KeyEvent.KEYCODE_MEDIA_NEXT
                    "previous" -> KeyEvent.KEYCODE_MEDIA_PREVIOUS
                    "pause" -> KeyEvent.KEYCODE_MEDIA_PAUSE
                    "play" -> KeyEvent.KEYCODE_MEDIA_PLAY
                    else -> KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE
                }
                audio.dispatchMediaKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, code))
                audio.dispatchMediaKeyEvent(KeyEvent(KeyEvent.ACTION_UP, code))
                true
            }
            "volume" -> {
                val audio = getSystemService(AUDIO_SERVICE) as AudioManager
                val way = if (call.argument<Boolean>("up") == true) AudioManager.ADJUST_RAISE else AudioManager.ADJUST_LOWER
                repeat(2) { audio.adjustStreamVolume(AudioManager.STREAM_MUSIC, way, AudioManager.FLAG_SHOW_UI) }
                true
            }
            // Liga ou desliga o serviço que mantém o microfone disponível com ela flutuando.
            "ear" -> {
                val intent = Intent(this, CapriEar::class.java)
                if (call.argument<Boolean>("on") != true) {
                    stopService(intent)
                    false
                } else if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
                    requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), 8)
                    false
                } else {
                    if (android.os.Build.VERSION.SDK_INT >= 26) startForegroundService(intent) else startService(intent)
                    true
                }
            }
            "earOn" -> CapriEar.running
            "global" -> CapriAccess.instance?.global(text(call, "action")) ?: false
            "playing" -> playing()
            // Fechar um app: vai para a tela inicial se ele estiver na frente e encerra o que ficou em segundo plano.
            "close" -> {
                val target = text(call, "package")
                if (CapriAccess.instance?.front() == target) CapriAccess.instance?.global("home")
                android.os.Handler(mainLooper).postDelayed({
                    try {
                        (getSystemService(ACTIVITY_SERVICE) as ActivityManager).killBackgroundProcesses(target)
                    } catch (error: Exception) {
                    }
                }, 900)
                true
            }
            "front" -> CapriAccess.instance?.front() ?: ""
            "launch" -> pending.also { pending = null }
            // Some com o app (vai para trás), deixando só a janela flutuante.
            "hide" -> moveTaskToBack(true)
            // Abre o app por cima (a partir da palavra de ativação, com o app em segundo plano).
            "summon" -> start(Intent(this, MainActivity::class.java).putExtra("capri", text(call, "why")).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP))
            "wakeState" -> CapriEar.state(this)
            "wakePrepare" -> {
                CapriEar.prepare(this)
                true
            }
            "wakeSet" -> {
                CapriEar.wantWake = call.argument<Boolean>("on") == true
                CapriEar.refresh()
                true
            }
            "wakeHold" -> {
                CapriEar.held = call.argument<Boolean>("hold") == true
                CapriEar.refresh()
                true
            }
            "assistantSettings" -> start(Intent(Settings.ACTION_MANAGE_DEFAULT_APPS_SETTINGS)) || start(Intent(Settings.ACTION_VOICE_INPUT_SETTINGS))
            "events" -> events(call.argument<Number>("from")?.toLong() ?: 0L, call.argument<Number>("to")?.toLong() ?: 0L)
            // Abre o calendário com o compromisso preenchido; a pessoa confere e salva.
            "newEvent" -> start(
                Intent(Intent.ACTION_INSERT)
                    .setData(CalendarContract.Events.CONTENT_URI)
                    .putExtra(CalendarContract.Events.TITLE, text(call, "title"))
                    .putExtra(CalendarContract.EXTRA_EVENT_BEGIN_TIME, call.argument<Number>("begin")?.toLong() ?: 0L)
                    .putExtra(CalendarContract.EXTRA_EVENT_END_TIME, call.argument<Number>("end")?.toLong() ?: 0L)
                    .putExtra(CalendarContract.EXTRA_EVENT_ALL_DAY, call.argument<Boolean>("allDay") == true)
            )
            "reply" -> CapriNotices.reply(this, text(call, "key"), text(call, "text"))
            "noticesOn" -> CapriNotices.connected
            "noticeSettings" -> start(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
            "notices" -> CapriNotices.latest()
            else -> throw NotImplementedError()
        }
    }

    /// Os compromissos entre [from] e [to] (milissegundos). Sem a permissão, pede e devolve {"granted": false}.
    private fun events(from: Long, to: Long): Map<String, Any> {
        if (checkSelfPermission(Manifest.permission.READ_CALENDAR) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(arrayOf(Manifest.permission.READ_CALENDAR), 9)
            return mapOf("granted" to false)
        }
        val found = ArrayList<Map<String, Any>>()
        val fields = arrayOf(
            CalendarContract.Instances.TITLE,
            CalendarContract.Instances.BEGIN,
            CalendarContract.Instances.END,
            CalendarContract.Instances.ALL_DAY,
            CalendarContract.Instances.EVENT_LOCATION,
        )
        CalendarContract.Instances.query(contentResolver, fields, from, to)?.use { cursor ->
            while (cursor.moveToNext() && found.size < 30) {
                found.add(
                    mapOf(
                        "title" to (cursor.getString(0) ?: "(sem título)"),
                        "begin" to cursor.getLong(1),
                        "end" to cursor.getLong(2),
                        "allDay" to (cursor.getInt(3) == 1),
                        "place" to (cursor.getString(4) ?: ""),
                    )
                )
            }
        }
        found.sortBy { it["begin"] as Long }
        return mapOf("granted" to true, "events" to found)
    }

    /// O que está tocando agora, lido das sessões de mídia. Precisa do acesso às notificações.
    private fun playing(): Map<String, Any>? {
        val manager = getSystemService(MEDIA_SESSION_SERVICE) as MediaSessionManager
        val sessions = manager.getActiveSessions(ComponentName(this, CapriNotices::class.java))
        var found: Map<String, Any>? = null
        for (session in sessions) {
            val title = session.metadata?.getString(MediaMetadata.METADATA_KEY_TITLE) ?: continue
            val artist = session.metadata?.getString(MediaMetadata.METADATA_KEY_ARTIST) ?: ""
            val live = session.playbackState?.state == PlaybackState.STATE_PLAYING
            val app = try {
                packageManager.getApplicationLabel(packageManager.getApplicationInfo(session.packageName, 0)).toString()
            } catch (error: Exception) {
                session.packageName
            }
            val item = mapOf<String, Any>("title" to title, "artist" to artist, "app" to app, "playing" to live)
            if (live) return item
            if (found == null) found = item
        }
        return found
    }

    /// Procura um contato pelo nome. Sem a permissão, pede e devolve {"granted": false}.
    private fun contact(name: String): Map<String, Any>? {
        if (checkSelfPermission(Manifest.permission.READ_CONTACTS) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(arrayOf(Manifest.permission.READ_CONTACTS), 7)
            return mapOf("granted" to false)
        }
        val wanted = CapriAccess.fold(name)
        var best: Map<String, Any>? = null
        var bestScore = 0
        contentResolver.query(
            ContactsContract.CommonDataKinds.Phone.CONTENT_URI,
            arrayOf(ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME, ContactsContract.CommonDataKinds.Phone.NUMBER),
            null, null, null
        )?.use { cursor ->
            while (cursor.moveToNext()) {
                val shown = cursor.getString(0) ?: continue
                val number = cursor.getString(1) ?: continue
                val folded = CapriAccess.fold(shown)
                val score = if (folded == wanted) 3 else if (folded.startsWith("$wanted ")) 2 else if (folded.contains(wanted)) 1 else 0
                if (score > bestScore) {
                    bestScore = score
                    best = mapOf("granted" to true, "name" to shown, "number" to number)
                }
            }
        }
        return best ?: mapOf("granted" to true)
    }

    private fun start(intent: Intent): Boolean {
        return try {
            applicationContext.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            true
        } catch (error: Exception) {
            false
        }
    }
}
