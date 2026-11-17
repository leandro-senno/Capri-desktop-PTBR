package com.leandrosenno.capri

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/// Quando o celular liga, solta a Capri flutuando (se a pessoa ligou essa opção).
class CapriBoot : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED && intent.action != "android.intent.action.QUICKBOOT_POWERON") return
        // As preferências do app ficam no arquivo do shared_preferences do Flutter, com o prefixo "flutter.".
        val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        if (!prefs.getBoolean("flutter.boot_float", false)) return
        try {
            context.startActivity(Intent(context, MainActivity::class.java).putExtra("capri", "float").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        } catch (error: Exception) {
            // Sem a permissão de aparecer sobre outros apps, o Android não deixa abrir ao ligar.
        }
    }
}
