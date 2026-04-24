package com.hissamuddin.eidos.ui

import androidx.compose.runtime.compositionLocalOf
import com.hissamuddin.eidos.AppContainer

/**
 * Composition local that hands the app-wide dependency container to any
 * Composable. Prefer this over `LocalContext.current.appContainer` so
 * previews can inject a fake.
 */
val LocalAppContainer = compositionLocalOf<AppContainer> {
    error("LocalAppContainer not provided — wrap your Composable in CompositionLocalProvider.")
}
