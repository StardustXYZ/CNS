package it.stardustxyz.cns

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createChannels()
    }

    /**
     * The two kinds of notification sent by GitHub (app/services/fcm.py): "uscite" with the
     * phone's sound, "notte" (23-8) without sound. Android 8+ needs them before they arrive;
     * the person can change each one in the phone's settings.
     */
    private fun createChannels() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java) ?: return
        manager.createNotificationChannel(
            NotificationChannel("uscite", "Uscite nuove", NotificationManager.IMPORTANCE_DEFAULT).apply {
                description = "Le uscite nuove degli artisti in Controllare"
            },
        )
        manager.createNotificationChannel(
            NotificationChannel("notte", "Di notte, senza suono", NotificationManager.IMPORTANCE_LOW).apply {
                description = "Le uscite trovate tra le 23 e le 8"
            },
        )
    }
}
