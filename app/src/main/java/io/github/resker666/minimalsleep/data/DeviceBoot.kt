package io.github.resker666.minimalsleep.data

import android.content.Context
import android.provider.Settings

object DeviceBoot {
    fun count(context: Context): Int? = try {
        Settings.Global.getInt(context.contentResolver, Settings.Global.BOOT_COUNT, -1).takeIf { it >= 0 }
    } catch (_: SecurityException) {
        null
    }
}
