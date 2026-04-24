package com.hissamuddin.eidos.ui

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Chat
import androidx.compose.material.icons.filled.Book
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Memory
import androidx.compose.material.icons.filled.Settings
import androidx.compose.ui.graphics.vector.ImageVector

/**
 * Top-level navigation destinations. Bottom-bar order matches this enum's
 * declaration order.
 */
enum class Destination(
    val route: String,
    val labelRes: Int,
    val icon: ImageVector,
) {
    HOME("home", com.hissamuddin.eidos.R.string.nav_home, Icons.Filled.Home),
    CHAT("chat", com.hissamuddin.eidos.R.string.nav_chat, Icons.AutoMirrored.Filled.Chat),
    MEMORY("memory", com.hissamuddin.eidos.R.string.nav_memory, Icons.Filled.Memory),
    KB("kb", com.hissamuddin.eidos.R.string.nav_kb, Icons.Filled.Book),
    SETTINGS("settings", com.hissamuddin.eidos.R.string.nav_settings, Icons.Filled.Settings),
    ;

    companion object {
        const val ROUTE_DIAGNOSTICS = "settings/diagnostics"
    }
}
