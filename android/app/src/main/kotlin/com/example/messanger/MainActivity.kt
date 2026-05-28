package com.example.messanger

import android.app.KeyguardManager
import android.content.ContentResolver
import android.content.Context
import android.content.Intent
import android.database.Cursor
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

/**
 * MainActivity:
 *   1) Поведение «звонок»: просыпание поверх lockscreen для full-screen intent.
 *   2) Share-intent (action=SEND / SEND_MULTIPLE): сохраняем содержимое
 *      пересылки и отдаём Flutter через MethodChannel `app.channel.shared.data`.
 *
 * Поток шеринга:
 *   • Юзер из любого приложения нажимает «Поделиться» → выбирает наше.
 *   • Android запускает MainActivity с EXTRA_TEXT (для строк) или EXTRA_STREAM
 *     (для файлов, как Uri).
 *   • Мы копируем файлы из content:// URI в наш cache, чтобы Flutter мог
 *     прочитать их по обычному пути (system content URI могут быть
 *     недоступны после возврата из intent).
 *   • Flutter вызывает getSharedText / getSharedFiles → получает данные.
 */
class MainActivity : FlutterActivity() {

    private val CHANNEL = "app.channel.shared.data"

    /** Текст из последнего share-intent (или null). */
    private var pendingText: String? = null

    /** Список локальных путей к файлам из последнего share-intent. */
    private var pendingFiles: List<String> = emptyList()

    /** Канал для пуша «новый share-intent» в Flutter, если приложение уже работало. */
    private var channel: MethodChannel? = null

    /** ID профиля из deep link (если приложение открыто по ссылке /profile/xxx). */
    private var pendingProfileId: String? = null

    /** Код инвайта из deep link (/invite/xxx или talky://invite/xxx). */
    private var pendingInviteCode: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        applyCallWindowFlags(intent)
        handleShareIntent(intent)
        handleProfileDeepLink(intent)
        handleInviteDeepLink(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        applyCallWindowFlags(intent)
        handleShareIntent(intent)
        handleProfileDeepLink(intent)
        handleInviteDeepLink(intent)
        // Если Flutter уже подписан — пушим обновление сразу
        val payload = mutableMapOf<String, Any?>(
            "text" to pendingText,
            "files" to pendingFiles,
        )
        if (pendingProfileId != null) {
            payload["profileId"] = pendingProfileId
        }
        if (pendingInviteCode != null) {
            payload["inviteCode"] = pendingInviteCode
        }
        channel?.invokeMethod("onNewSharedData", payload)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).also { ch ->
            ch.setMethodCallHandler { call, result ->
                when (call.method) {
                    "getSharedText" -> {
                        val text = pendingText
                        pendingText = null
                        result.success(text)
                    }
                    "getSharedFiles" -> {
                        val files = pendingFiles
                        pendingFiles = emptyList()
                        result.success(files)
                    }
                    "consumeSharedData" -> {
                        // Атомарно забрать текст + файлы + profileId (для случая когда оба пришли вместе).
                        val payload = mutableMapOf<String, Any?>(
                            "text" to pendingText,
                            "files" to pendingFiles,
                        )
                        if (pendingProfileId != null) {
                            payload["profileId"] = pendingProfileId
                        }
                        if (pendingInviteCode != null) {
                            payload["inviteCode"] = pendingInviteCode
                        }
                        pendingText = null
                        pendingFiles = emptyList()
                        pendingProfileId = null
                        pendingInviteCode = null
                        result.success(payload)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    /** Достаём из intent текст и/или файлы и сохраняем в pending-поля. */
    private fun handleShareIntent(intent: Intent?) {
        if (intent == null) return
        val action = intent.action ?: return
        if (action != Intent.ACTION_SEND && action != Intent.ACTION_SEND_MULTIPLE) return

        val type = intent.type ?: ""

        // Текст ("text/plain") — берём прямо из EXTRA_TEXT.
        val sharedText = intent.getStringExtra(Intent.EXTRA_TEXT)
        if (!sharedText.isNullOrEmpty()) {
            pendingText = sharedText
        }

        // Файлы (любые медиа / документы) — копируем в cacheDir.
        val uris: List<Uri> = when {
            action == Intent.ACTION_SEND_MULTIPLE -> {
                @Suppress("UNCHECKED_CAST", "DEPRECATION")
                (intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM) as? ArrayList<Uri>)
                    ?: emptyList()
            }
            action == Intent.ACTION_SEND -> {
                @Suppress("DEPRECATION")
                val uri = intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
                if (uri != null) listOf(uri) else emptyList()
            }
            else -> emptyList()
        }

        if (uris.isNotEmpty()) {
            val saved = mutableListOf<String>()
            for (uri in uris) {
                copyUriToCache(uri)?.let { saved.add(it) }
            }
            pendingFiles = saved
        }

        // Если intent был text-only — type может быть "text/plain", файлов нет.
        // Если intent был file-only — sharedText может быть null. Это нормально.
        @Suppress("UNUSED_VARIABLE")
        val _t = type
    }

    /**
     * Копирует ресурс по URI (например content://...) во временный файл в cacheDir.
     * Возвращает абсолютный путь или null если не удалось.
     */
    private fun copyUriToCache(uri: Uri): String? {
        return try {
            val name = queryDisplayName(contentResolver, uri) ?: "shared_${System.currentTimeMillis()}"
            // Чистим имя от опасных символов
            val safeName = name.replace(Regex("[^A-Za-z0-9._-]"), "_")
            val outFile = File(cacheDir, "share_${System.currentTimeMillis()}_$safeName")
            contentResolver.openInputStream(uri)?.use { input ->
                FileOutputStream(outFile).use { output ->
                    input.copyTo(output)
                }
            } ?: return null
            outFile.absolutePath
        } catch (e: Throwable) {
            android.util.Log.e("MainActivity", "copyUriToCache failed", e)
            null
        }
    }

    private fun queryDisplayName(resolver: ContentResolver, uri: Uri): String? {
        return try {
            val cursor: Cursor? = resolver.query(uri, null, null, null, null)
            cursor?.use {
                val idx = it.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (idx >= 0 && it.moveToFirst()) it.getString(idx) else null
            }
        } catch (_: Throwable) { null }
    }

    /**
     * Извлекает ID профиля из deep-link URL.
     *
     * Поддерживает два формата:
     *   1) HTTP:    http://194.87.201.226/profile/abc123  → path=/profile/abc123
     *   2) Custom:  talky://profile/abc123                → host=profile, path=/abc123
     */
    private fun handleProfileDeepLink(intent: Intent?) {
        if (intent == null || intent.action != Intent.ACTION_VIEW) return
        val uri = intent.data ?: return
        val path = uri.path ?: ""

        val id: String? = when {
            // HTTP deep link: http(s)://host/profile/xxx
            path.startsWith("/profile/") -> path.removePrefix("/profile/").trim('/')
            // Custom scheme: talky://profile/xxx
            uri.scheme == "talky" && uri.host == "profile" -> path.trim('/')
            else -> null
        }

        if (!id.isNullOrEmpty()) {
            pendingProfileId = id
        }
    }

    /**
     * Извлекает код инвайта из deep-link URL.
     *
     * Поддерживает два формата:
     *   1) HTTP:    https://194.87.201.226/invite/abc123  → path=/invite/abc123
     *   2) Custom:  talky://invite/abc123                → host=invite, path=/abc123
     */
    private fun handleInviteDeepLink(intent: Intent?) {
        if (intent == null || intent.action != Intent.ACTION_VIEW) return
        val uri = intent.data ?: return
        val path = uri.path ?: ""

        val code: String? = when {
            // HTTP deep link: http(s)://host/invite/xxx
            path.startsWith("/invite/") -> path.removePrefix("/invite/").trim('/')
            // Custom scheme: talky://invite/xxx
            uri.scheme == "talky" && uri.host == "invite" -> path.trim('/')
            else -> null
        }

        if (!code.isNullOrEmpty()) {
            pendingInviteCode = code
        }
    }

    /**
     * Если intent — это намерение, связанное со звонком (full-screen intent от
     * notification), включаем все флаги, чтобы пройти сквозь lockscreen и
     * проснуться. Сами флаги обновлены под Android 8.1+, для старых версий —
     * через WindowManager.LayoutParams.
     */
    private fun applyCallWindowFlags(intent: Intent?) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
            val km = getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
            km.requestDismissKeyguard(this, null)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                android.view.WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                android.view.WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
                android.view.WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD
            )
        }
    }
}
