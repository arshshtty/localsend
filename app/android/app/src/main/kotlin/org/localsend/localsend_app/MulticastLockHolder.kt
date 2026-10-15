package org.localsend.localsend_app

import android.content.Context
import android.net.wifi.WifiManager
import android.util.Log

/// Holds a Wi-Fi MulticastLock while the app is in the foreground or a scan is
/// running. Without it, many devices filter incoming multicast packets, so
/// LocalSend announcements from other devices are dropped.
///
/// The lock is held iff `foreground || activeScans > 0`. Leaving the
/// foreground releases the foreground hold; a running scan keeps the lock only
/// until it ends (scans are short and bounded).
class MulticastLockHolder(context: Context) {
    private val lock: WifiManager.MulticastLock? =
        (context.applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager)
            ?.createMulticastLock("localsend")
            ?.apply { setReferenceCounted(false) }

    private var foreground = false
    private var activeScans = 0

    @Synchronized
    fun setForeground(value: Boolean) {
        foreground = value
        update()
    }

    @Synchronized
    fun scanStarted() {
        activeScans++
        update()
    }

    @Synchronized
    fun scanEnded() {
        if (activeScans > 0) activeScans--
        update()
    }

    @Synchronized
    fun isHeld(): Boolean = lock?.isHeld == true

    private fun update() {
        val lock = lock ?: return
        val want = foreground || activeScans > 0
        try {
            if (want && !lock.isHeld) {
                lock.acquire()
            } else if (!want && lock.isHeld) {
                lock.release()
            }
        } catch (e: RuntimeException) {
            // e.g. SecurityException when CHANGE_WIFI_MULTICAST_STATE is missing.
            Log.w("MulticastLockHolder", "Could not update multicast lock", e)
        }
    }
}
