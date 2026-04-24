package com.hissamuddin.eidos.ui.theme

import android.os.Build
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.dynamicDarkColorScheme
import androidx.compose.material3.dynamicLightColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.platform.LocalContext

private val DarkColors = darkColorScheme(
    primary = BrandBlue,
    onPrimary = Ink,
    background = Ink,
    surface = Slate,
)

private val LightColors = lightColorScheme(
    primary = BrandBlueDark,
    onPrimary = Fog,
    background = Fog,
    surface = Fog,
)

/**
 * Material 3 theme wrapper. Uses dynamic color on Android 12+ so the
 * palette matches the user's wallpaper — a small but real "feels native"
 * detail. Falls back to the brand palette below on older devices.
 */
@Composable
fun EidosTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    dynamicColor: Boolean = true,
    content: @Composable () -> Unit,
) {
    val colors = when {
        dynamicColor && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S -> {
            val ctx = LocalContext.current
            if (darkTheme) dynamicDarkColorScheme(ctx) else dynamicLightColorScheme(ctx)
        }
        darkTheme -> DarkColors
        else -> LightColors
    }

    MaterialTheme(
        colorScheme = colors,
        typography = EidosTypography,
        content = content,
    )
}
