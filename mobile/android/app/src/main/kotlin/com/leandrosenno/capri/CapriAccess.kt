package com.leandrosenno.capri

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Path
import android.os.Build
import android.os.Bundle
import android.view.Display
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import android.view.accessibility.AccessibilityWindowInfo
import java.io.ByteArrayOutputStream
import java.text.Normalizer

/// Os olhos e as mãos da Capri em outros apps: lê o texto da tela e toca, rola e digita.
/// Só age quando o app pede (a pedido da pessoa na conversa); não observa nada sozinho.
class CapriAccess : AccessibilityService() {
    companion object {
        @Volatile
        var instance: CapriAccess? = null

        fun fold(text: String): String =
            Normalizer.normalize(text.lowercase(), Normalizer.Form.NFD).replace(Regex("\\p{Mn}+"), "").replace(Regex("\\s+"), " ").trim()
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
    }

    override fun onUnbind(intent: Intent?): Boolean {
        instance = null
        return super.onUnbind(intent)
    }

    override fun onDestroy() {
        instance = null
        super.onDestroy()
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {}

    override fun onInterrupt() {}

    /// As janelas de outros apps na tela (a janela flutuante da própria Capri fica de fora).
    private fun roots(): List<AccessibilityNodeInfo> {
        val found = ArrayList<AccessibilityNodeInfo>()
        try {
            for (window in windows) {
                if (window.type != AccessibilityWindowInfo.TYPE_APPLICATION) continue
                val root = window.root ?: continue
                if (root.packageName == packageName) continue
                found.add(root)
            }
        } catch (error: Exception) {
        }
        if (found.isEmpty()) rootInActiveWindow?.let { if (it.packageName != packageName) found.add(it) }
        return found
    }

    private fun label(node: AccessibilityNodeInfo): String {
        val text = node.text?.toString()?.trim()
        if (!text.isNullOrEmpty()) return text
        return node.contentDescription?.toString()?.trim() ?: ""
    }

    private fun walk(node: AccessibilityNodeInfo, lines: MutableList<String>) {
        if (lines.size >= 150 || !node.isVisibleToUser) return
        val shown = label(node)
        if (shown.isNotEmpty()) {
            val kind = if (node.isEditable) "[campo] " else if (node.isClickable) "[botão] " else ""
            val line = kind + shown.take(200)
            if (lines.isEmpty() || lines.last() != line) lines.add(line)
        }
        for (i in 0 until node.childCount) node.getChild(i)?.let { walk(it, lines) }
    }

    private fun buttons(node: AccessibilityNodeInfo, found: MutableList<String>) {
        if (found.size >= 40 || !node.isVisibleToUser) return
        val shown = label(node)
        if (shown.isNotEmpty() && shown.length <= 40 && (node.isClickable || node.isEditable) && !found.contains(shown)) found.add(shown)
        for (i in 0 until node.childCount) node.getChild(i)?.let { buttons(it, found) }
    }

    /// Os nomes dos itens tocáveis na tela, para o cérebro escolher onde tocar.
    fun tappable(): List<String> {
        val found = ArrayList<String>()
        for (root in roots()) buttons(root, found)
        return found
    }

    /// O texto visível na tela, de cima para baixo, e o app que está aberto.
    fun read(): Map<String, Any> {
        val lines = ArrayList<String>()
        var app = ""
        for (root in roots()) {
            if (app.isEmpty()) app = root.packageName?.toString() ?: ""
            walk(root, lines)
        }
        val name = try {
            packageManager.getApplicationLabel(packageManager.getApplicationInfo(app, 0)).toString()
        } catch (error: Exception) {
            app
        }
        return mapOf("app" to name, "lines" to lines)
    }

    private fun find(node: AccessibilityNodeInfo, wanted: String, best: Array<AccessibilityNodeInfo?>, score: IntArray) {
        if (!node.isVisibleToUser) return
        val shown = fold(label(node))
        if (shown.isNotEmpty()) {
            val now = if (shown == wanted) 3 else if (shown.startsWith(wanted)) 2 else if (shown.contains(wanted)) 1 else 0
            if (now > score[0]) {
                score[0] = now
                best[0] = node
            }
        }
        for (i in 0 until node.childCount) node.getChild(i)?.let { find(it, wanted, best, score) }
    }

    /// O nome do item na tela que combina com o texto pedido, sem tocar nele.
    fun locate(wanted: String): String? {
        val best = arrayOfNulls<AccessibilityNodeInfo>(1)
        val score = IntArray(1)
        val name = fold(wanted)
        if (name.isEmpty()) return null
        for (root in roots()) find(root, name, best, score)
        return best[0]?.let { label(it) }
    }

    /// Toca no item que combina com o texto. Devolve o nome do item tocado, ou null se não achou.
    fun click(wanted: String): String? {
        val best = arrayOfNulls<AccessibilityNodeInfo>(1)
        val score = IntArray(1)
        val name = fold(wanted)
        if (name.isEmpty()) return null
        for (root in roots()) find(root, name, best, score)
        val target = best[0] ?: return null
        var node: AccessibilityNodeInfo? = target
        while (node != null && !node.isClickable) node = node.parent
        val done = (node ?: target).performAction(AccessibilityNodeInfo.ACTION_CLICK)
        return if (done) label(target) else null
    }

    private fun editable(node: AccessibilityNodeInfo): AccessibilityNodeInfo? {
        if (node.isEditable && node.isVisibleToUser) return node
        for (i in 0 until node.childCount) node.getChild(i)?.let { child -> editable(child)?.let { return it } }
        return null
    }

    /// Escreve no campo de texto em foco (ou no primeiro campo da tela).
    fun type(text: String): Boolean {
        for (root in roots()) {
            val field = root.findFocus(AccessibilityNodeInfo.FOCUS_INPUT)?.takeIf { it.isEditable } ?: editable(root) ?: continue
            val arguments = Bundle()
            arguments.putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, text)
            return field.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, arguments)
        }
        return false
    }

    /// Rola a tela com um gesto de arrastar.
    /// Tira uma foto da tela e entrega em JPEG reduzido (lado maior de 1024 px), ou null se não der.
    /// Só no Android 11 ou mais novo. Telas protegidas (banco, senha) saem pretas, por decisão do sistema.
    fun shot(done: (ByteArray?) -> Unit) {
        if (Build.VERSION.SDK_INT < 30) {
            done(null)
            return
        }
        try {
            takeScreenshot(Display.DEFAULT_DISPLAY, mainExecutor, object : TakeScreenshotCallback {
                override fun onSuccess(result: ScreenshotResult) {
                    var bytes: ByteArray? = null
                    try {
                        val hard = Bitmap.wrapHardwareBuffer(result.hardwareBuffer, result.colorSpace)
                        val soft = hard?.copy(Bitmap.Config.ARGB_8888, false)
                        result.hardwareBuffer.close()
                        if (soft != null) {
                            val ratio = 1024f / maxOf(soft.width, soft.height)
                            val small = if (ratio < 1f) Bitmap.createScaledBitmap(soft, (soft.width * ratio).toInt(), (soft.height * ratio).toInt(), true) else soft
                            val out = ByteArrayOutputStream()
                            small.compress(Bitmap.CompressFormat.JPEG, 72, out)
                            bytes = out.toByteArray()
                        }
                    } catch (error: Exception) {
                        bytes = null
                    }
                    done(bytes)
                }

                override fun onFailure(errorCode: Int) {
                    done(null)
                }
            })
        } catch (error: Exception) {
            done(null)
        }
    }

    /// O app que está na frente agora (fora a própria Capri).
    fun front(): String = roots().firstOrNull()?.packageName?.toString() ?: ""

    /// [across] é onde arrastar, de 0 (esquerda) a 1 (direita), para desviar da janela flutuante.
    fun scroll(down: Boolean, across: Float): Boolean {
        val metrics = resources.displayMetrics
        val x = metrics.widthPixels * across.coerceIn(0.05f, 0.95f)
        val from = metrics.heightPixels * (if (down) 0.7f else 0.3f)
        val to = metrics.heightPixels * (if (down) 0.3f else 0.7f)
        val path = Path()
        path.moveTo(x, from)
        path.lineTo(x, to)
        val gesture = GestureDescription.Builder().addStroke(GestureDescription.StrokeDescription(path, 0, 300)).build()
        return dispatchGesture(gesture, null, null)
    }

    fun global(action: String): Boolean {
        val code = when (action) {
            "back" -> GLOBAL_ACTION_BACK
            "home" -> GLOBAL_ACTION_HOME
            "recents" -> GLOBAL_ACTION_RECENTS
            "notifications" -> GLOBAL_ACTION_NOTIFICATIONS
            else -> return false
        }
        return performGlobalAction(code)
    }
}
