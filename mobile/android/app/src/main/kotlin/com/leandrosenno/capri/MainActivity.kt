package com.leandrosenno.capri

import android.app.SearchManager
import android.content.Intent
import android.net.Uri
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/// As "mãos" da Capri no Android: listar e abrir apps, abrir links e pedir música.
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "capri/hands").setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "apps" -> {
                        val launcher = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
                        val found = packageManager.queryIntentActivities(launcher, 0)
                        result.success(found.map {
                            mapOf("name" to it.loadLabel(packageManager).toString(), "package" to it.activityInfo.packageName)
                        })
                    }
                    "launch" -> {
                        val intent = packageManager.getLaunchIntentForPackage(call.argument<String>("package") ?: "")
                        result.success(intent != null && start(intent))
                    }
                    "view" -> result.success(start(Intent(Intent.ACTION_VIEW, Uri.parse(call.argument<String>("url") ?: ""))))
                    "play" -> {
                        // Pede ao app de música para tocar o que foi buscado (Spotify e YouTube Music aceitam).
                        val intent = Intent(MediaStore.INTENT_ACTION_MEDIA_PLAY_FROM_SEARCH)
                            .setPackage(call.argument<String>("package"))
                            .putExtra(MediaStore.EXTRA_MEDIA_FOCUS, "vnd.android.cursor.item/*")
                            .putExtra(SearchManager.QUERY, call.argument<String>("query") ?: "")
                        result.success(start(intent))
                    }
                    "search" -> {
                        // Abre a busca dentro de um app (o YouTube aceita).
                        val intent = Intent(Intent.ACTION_SEARCH)
                            .setPackage(call.argument<String>("package"))
                            .putExtra(SearchManager.QUERY, call.argument<String>("query") ?: "")
                        result.success(start(intent))
                    }
                    else -> result.notImplemented()
                }
            } catch (error: Exception) {
                result.success(if (call.method == "apps") emptyList<Map<String, String>>() else false)
            }
        }
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
