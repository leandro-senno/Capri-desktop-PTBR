package com.leandrosenno.capri

import android.Manifest
import android.app.SearchManager
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioManager
import android.net.Uri
import android.os.BatteryManager
import android.provider.AlarmClock
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
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "capri/hands").setMethodCallHandler { call, result ->
            try {
                result.success(handle(call))
            } catch (error: NotImplementedError) {
                result.notImplemented()
            } catch (error: Exception) {
                result.success(if (call.method == "apps" || call.method == "notices" || call.method == "tappable") emptyList<Map<String, Any>>() else if (call.method == "screen" || call.method == "contact" || call.method == "battery") null else false)
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
            "noticesOn" -> CapriNotices.connected
            "noticeSettings" -> start(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
            "notices" -> CapriNotices.latest()
            else -> throw NotImplementedError()
        }
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
