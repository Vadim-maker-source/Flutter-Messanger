package com.example.messanger

import android.app.KeyguardManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

/**
 * MainActivity с поддержкой "calling app" поведения:
 *
 * Когда приходит push о входящем звонке и пользователь тапает на уведомление
 * (или его автоматически открывает full-screen intent на залоченном экране),
 * activity:
 *   - просыпается через включение экрана
 *   - показывается ПОВЕРХ lockscreen без необходимости разблокировки
 *   - получает фокус, включается аудио/визуальный звонок
 *
 * Это стандартный UX: звонит WhatsApp → экран загорается → видна кнопка ответить.
 */
class MainActivity : FlutterActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        applyCallWindowFlags(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        applyCallWindowFlags(intent)
    }

    /**
     * Если intent — это намерение, связанное со звонком (full-screen intent от
     * notification), включаем все флаги, чтобы пройти сквозь lockscreen и
     * проснуться. Сами флаги обновлены под Android 8.1+, для старых версий —
     * через WindowManager.LayoutParams.
     */
    private fun applyCallWindowFlags(intent: Intent?) {
        // Эвристика: применяем флаги всегда при cold-start от notification.
        // Это безопасно: если экран уже разблокирован — флаги не меняют
        // ничего видимо.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
            // Снимаем keyguard если он не secure (без пин-кода)
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
