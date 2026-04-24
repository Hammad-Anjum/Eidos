package com.hissamuddin.eidos.ui

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.CompositionLocalProvider
import com.hissamuddin.eidos.appContainer
import com.hissamuddin.eidos.ui.theme.EidosTheme

/**
 * The one and only Activity. We host Compose directly and use Navigation
 * Compose for screen routing (see [EidosApp]).
 *
 * Why single-activity: simpler lifecycle, simpler back-stack, simpler
 * Compose state. No fragment bridging.
 */
class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        val container = appContainer
        setContent {
            CompositionLocalProvider(LocalAppContainer provides container) {
                EidosTheme {
                    EidosApp()
                }
            }
        }
    }
}
