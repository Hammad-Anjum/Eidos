# ============================================================================
# Eidos — R8 / ProGuard rules
# ============================================================================
# Keep rules for release builds. Debug is not minified.
# Verify each block still matches reality if you change the corresponding
# library version. Order goes: platform → framework → project-specific.

# ----------------------------------------------------------------------------
# Kotlin metadata (keep @Metadata for reflection + serialization)
# ----------------------------------------------------------------------------
-keep class kotlin.Metadata { *; }
-keepattributes *Annotation*, Signature, InnerClasses, EnclosingMethod

# ----------------------------------------------------------------------------
# Coroutines — keep internals used by reflection in `kotlinx.coroutines.debug`
# ----------------------------------------------------------------------------
-keepnames class kotlinx.coroutines.internal.MainDispatcherFactory { }
-keepnames class kotlinx.coroutines.CoroutineExceptionHandler { }
-keepclassmembers class kotlinx.coroutines.** { volatile <fields>; }

# ----------------------------------------------------------------------------
# kotlinx.serialization — keep @Serializable classes + synthetic serializers
# ----------------------------------------------------------------------------
-keepattributes *Annotation*
-keep,includedescriptorclasses class com.hissamuddin.eidos.**$$serializer { *; }
-keepclassmembers class com.hissamuddin.eidos.** {
    *** Companion;
}
-keepclasseswithmembers class com.hissamuddin.eidos.** {
    kotlinx.serialization.KSerializer serializer(...);
}

# ----------------------------------------------------------------------------
# Room — keep @Entity / @Dao / @Database generated implementations
# ----------------------------------------------------------------------------
-keep class * extends androidx.room.RoomDatabase
-keep @androidx.room.Entity class *
-keep class androidx.room.paging.** { *; }
-dontwarn androidx.room.paging.**

# ----------------------------------------------------------------------------
# OkHttp — strip unused optional integrations
# ----------------------------------------------------------------------------
-dontwarn okhttp3.internal.platform.**
-dontwarn org.conscrypt.**
-dontwarn org.bouncycastle.**
-dontwarn org.openjsse.**

# ----------------------------------------------------------------------------
# Compose — preserve @Composable + runtime reflection targets
# ----------------------------------------------------------------------------
-keep class androidx.compose.runtime.** { *; }

# ----------------------------------------------------------------------------
# LiteRT-LM / MediaPipe / native inference (placeholder — fill in A2)
# Native JNI methods must not be obfuscated. These libs use reflection to
# resolve their JNI entrypoints.
# ----------------------------------------------------------------------------
# -keep class com.google.mediapipe.** { *; }
# -keep class com.google.ai.edge.** { *; }

# ----------------------------------------------------------------------------
# Eidos — keep entry points
# ----------------------------------------------------------------------------
-keep class com.hissamuddin.eidos.App { *; }
-keep class com.hissamuddin.eidos.ui.MainActivity { *; }

# Diagnostics logger model classes serialize to JSONL — keep their fields.
-keep class com.hissamuddin.eidos.platform.diagnostics.LogRecord { *; }
-keep class com.hissamuddin.eidos.platform.diagnostics.MetricRecord { *; }
