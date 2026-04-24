package com.hissamuddin.eidos.platform.diagnostics

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.preferencesDataStore
import com.hissamuddin.eidos.BuildConfig
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

/**
 * Runtime-toggleable capability flags backed by DataStore. Diagnostics exposes
 * every flag; nothing branches on `BuildConfig.DEBUG` except the defaults.
 *
 * ## Contract
 *
 *  - Reading a flag yields a cold [Flow] that emits the current value + all
 *    subsequent changes. Collect in a ViewModel; don't call on the main path
 *    of inference.
 *  - `safetyGateEnabled` is special: in RELEASE the setter is a no-op so the
 *    gate cannot be disabled by accident or by a malicious DataStore edit.
 *  - Adding a flag is free. Removing a flag requires a DataStore migration
 *    or the app silently drops the unknown key on next write.
 *
 * ## Flag catalog
 *
 * See `plan.md` for which phase owns each flag. Defaults below reflect the
 * A0 baseline: features not yet shipped are OFF; always-on safeties are ON.
 */
class EidosFeatureFlags internal constructor(
    private val store: DataStore<Preferences>,
) {
    val visionEnabled: Flow<Boolean> = flag(KEY_VISION, DEFAULT_VISION)
    val audioViaGemmaEnabled: Flow<Boolean> = flag(KEY_AUDIO_VIA_GEMMA, DEFAULT_AUDIO_VIA_GEMMA)
    val audioEnabled: Flow<Boolean> = flag(KEY_AUDIO, DEFAULT_AUDIO)
    val reasoningEnabled: Flow<Boolean> = flag(KEY_REASONING, DEFAULT_REASONING)
    val personasEnabled: Flow<Boolean> = flag(KEY_PERSONAS, DEFAULT_PERSONAS)
    val diagnosticsUiEnabled: Flow<Boolean> = flag(KEY_DIAG_UI, DEFAULT_DIAG_UI)
    val longContextPackingEnabled: Flow<Boolean> = flag(KEY_LONG_CTX, DEFAULT_LONG_CTX)
    val safetyGateEnabled: Flow<Boolean> = flag(KEY_SAFETY, DEFAULT_SAFETY)
    val notificationListenerEnabled: Flow<Boolean> = flag(KEY_NOTIF_LISTENER, DEFAULT_NOTIF_LISTENER)
    val foregroundServiceEnabled: Flow<Boolean> = flag(KEY_FGS, DEFAULT_FGS)

    suspend fun setVisionEnabled(v: Boolean) = write(KEY_VISION, v)
    suspend fun setAudioViaGemmaEnabled(v: Boolean) = write(KEY_AUDIO_VIA_GEMMA, v)
    suspend fun setAudioEnabled(v: Boolean) = write(KEY_AUDIO, v)
    suspend fun setReasoningEnabled(v: Boolean) = write(KEY_REASONING, v)
    suspend fun setPersonasEnabled(v: Boolean) = write(KEY_PERSONAS, v)
    suspend fun setDiagnosticsUiEnabled(v: Boolean) = write(KEY_DIAG_UI, v)
    suspend fun setLongContextPackingEnabled(v: Boolean) = write(KEY_LONG_CTX, v)
    suspend fun setNotificationListenerEnabled(v: Boolean) = write(KEY_NOTIF_LISTENER, v)
    suspend fun setForegroundServiceEnabled(v: Boolean) = write(KEY_FGS, v)

    /**
     * SafetyGate setter. No-op in RELEASE builds — the gate cannot be turned
     * off by a bad user action, a corrupt DataStore, or an overzealous
     * engineer. DEBUG can toggle for unit tests.
     */
    suspend fun setSafetyGateEnabled(v: Boolean) {
        if (!BuildConfig.DEBUG) return
        write(KEY_SAFETY, v)
    }

    private fun flag(key: Preferences.Key<Boolean>, default: Boolean): Flow<Boolean> =
        store.data.map { prefs -> prefs[key] ?: default }

    private suspend fun write(key: Preferences.Key<Boolean>, value: Boolean) {
        store.edit { it[key] = value }
    }

    companion object {
        // --- Keys ------------------------------------------------------------
        private val KEY_VISION = booleanPreferencesKey("vision_enabled")
        private val KEY_AUDIO_VIA_GEMMA = booleanPreferencesKey("audio_via_gemma_enabled")
        private val KEY_AUDIO = booleanPreferencesKey("audio_enabled")
        private val KEY_REASONING = booleanPreferencesKey("reasoning_enabled")
        private val KEY_PERSONAS = booleanPreferencesKey("personas_enabled")
        private val KEY_DIAG_UI = booleanPreferencesKey("diagnostics_ui_enabled")
        private val KEY_LONG_CTX = booleanPreferencesKey("long_context_packing_enabled")
        private val KEY_SAFETY = booleanPreferencesKey("safety_gate_enabled")
        private val KEY_NOTIF_LISTENER = booleanPreferencesKey("notification_listener_enabled")
        private val KEY_FGS = booleanPreferencesKey("foreground_service_enabled")

        // --- Defaults (A0 baseline) -----------------------------------------
        private const val DEFAULT_VISION = false            // wired in A2b
        private const val DEFAULT_AUDIO_VIA_GEMMA = false   // wired in A2b
        private const val DEFAULT_AUDIO = true              // AudioRecord path available early
        private const val DEFAULT_REASONING = true          // CoT on by default
        private const val DEFAULT_PERSONAS = false          // Phase A9
        private val DEFAULT_DIAG_UI = BuildConfig.DEBUG     // hidden in release by default
        private const val DEFAULT_LONG_CTX = false          // memory budget matters on mid-range
        private const val DEFAULT_SAFETY = true             // always-on in release
        private const val DEFAULT_NOTIF_LISTENER = false    // opt-in (A8.1)
        private const val DEFAULT_FGS = false               // user-toggled (A6)

        /**
         * Standard factory. Uses the app's own DataStore so flags survive
         * process restarts but are wiped on data clear / uninstall.
         */
        fun create(context: Context): EidosFeatureFlags =
            EidosFeatureFlags(context.flagsStore)
    }
}

// Per Google's recommendation: top-level `preferencesDataStore` delegate so
// DataStore stays a singleton for the process.
private val Context.flagsStore: DataStore<Preferences> by preferencesDataStore(name = "eidos_flags")
