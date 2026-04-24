package com.hissamuddin.eidos.platform.diagnostics

/**
 * Typed taxonomy of failures that can occur in Eidos. Used by [EidosLogger]
 * and [MetricsRecorder] so every error site carries a category that can be
 * filtered in Diagnostics and compared across sessions.
 *
 * Schema is stable — adding a case is safe, reordering is not (the string
 * name is what ends up in the JSONL log). Remove a case only with a
 * migration plan for historical logs that reference it.
 */
enum class FailureCategory {
    // --- Model / inference ---------------------------------------------------
    MODEL_LOAD,
    MODEL_GENERATE,
    MODEL_THERMAL,
    MODEL_OOM,
    MODEL_VISION_FAILED,
    MODEL_AUDIO_FAILED,

    // --- RAG -----------------------------------------------------------------
    RAG_EMBED,
    RAG_RETRIEVE,

    // --- Memory --------------------------------------------------------------
    MEMORY_WRITE,
    MEMORY_READ,
    MEMORY_CRYSTALLIZE,

    // --- Model download ------------------------------------------------------
    DOWNLOAD_NETWORK,
    DOWNLOAD_CHECKSUM,
    DOWNLOAD_DISK_FULL,

    // --- OS / permissions ----------------------------------------------------
    PERMISSION_DENIED,
    AUDIO_SESSION_FAILED,
    CAMERA_ACCESS_FAILED,

    // --- App actions / skills ------------------------------------------------
    INTENT_EXECUTE,
    SKILL_EXECUTE,
    PERSONA_ROUTE_FAILED,

    // --- Fallback ------------------------------------------------------------
    UNKNOWN,
}
