package com.hissamuddin.eidos.inference

import android.graphics.Bitmap
import com.hissamuddin.eidos.platform.diagnostics.FailureCategory
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow

/**
 * Abstract interface over a Gemma 4 session.
 *
 * A0 ships the stub only. Phase A2 drops in the real LiteRT-LM implementation
 * behind this same interface — every caller (RAGPipeline, DigestGenerator,
 * MemoryCrystallizer, BenchmarkRunner) depends on [GemmaSession] and never
 * on the concrete backing class.
 *
 * ## Multimodal
 *
 * [generate] accepts text messages, optional images, and optional audio in a
 * single call — Gemma 4 is natively multimodal and A2 wires all three day
 * one because that's the axis the hackathon judges score on.
 */
interface GemmaSession {
    /** Load the model into memory. Idempotent — safe to call multiple times. */
    suspend fun load(variant: GemmaVariant = GemmaVariant.E2B)

    /** Release GPU/NPU resources. Next [generate] call triggers a cold reload. */
    suspend fun unload()

    /**
     * Run inference. Emits [GenerationEvent.Token] for each streamed chunk,
     * terminated by exactly one [GenerationEvent.Complete] (on success) or
     * [GenerationEvent.Failed] (on error). Consumers should collect to the
     * first terminal event.
     *
     * @param messages role-tagged chat history. The last entry is the query.
     * @param images optional vision input. Empty list = text-only.
     * @param audio optional 16 kHz Int16 PCM. null = no audio.
     * @param reasoning when true, prepends a chain-of-thought instruction to
     *   the system prompt. Increases quality at a latency cost.
     */
    fun generate(
        messages: List<ChatMessage>,
        images: List<Bitmap> = emptyList(),
        audio: ShortArray? = null,
        reasoning: Boolean = false,
    ): Flow<GenerationEvent>
}

/** Available Gemma 4 variants. E4B requires 8 GB+ RAM; device-class gated. */
enum class GemmaVariant(val huggingFaceId: String, val sizeBytes: Long) {
    E2B(huggingFaceId = "google/gemma-4-e2b-it", sizeBytes = 3_580_000_000L),
    E4B(huggingFaceId = "google/gemma-4-e4b-it", sizeBytes = 7_200_000_000L),
}

/** Structured chat turn. Avoids stringly-typed role parsing downstream. */
data class ChatMessage(
    val role: Role,
    val content: String,
) {
    enum class Role { SYSTEM, USER, ASSISTANT, TOOL }
}

/** Events emitted during a single [GemmaSession.generate] call. */
sealed interface GenerationEvent {
    data class Token(val text: String) : GenerationEvent
    data class Complete(val totalTokens: Int) : GenerationEvent
    data class Failed(val category: FailureCategory, val message: String) : GenerationEvent
}

/**
 * Deterministic stub used during A0 so the Diagnostics benchmark harness is
 * callable end-to-end before LiteRT-LM lands in A2. Produces a canned reply
 * at ~20 tokens/second to exercise [com.hissamuddin.eidos.platform.diagnostics.MetricsRecorder.Probe.onToken].
 */
class StubGemmaSession : GemmaSession {

    override suspend fun load(variant: GemmaVariant) {
        // Pretend model load cost (keeps benchmark TTFT realistic).
        delay(STUB_LOAD_DELAY_MS)
    }

    override suspend fun unload() { /* no-op */ }

    override fun generate(
        messages: List<ChatMessage>,
        images: List<Bitmap>,
        audio: ShortArray?,
        reasoning: Boolean,
    ): Flow<GenerationEvent> = flow {
        // Canned reply. Real impl lands in A2 via LiteRT-LM.
        val replyTokens = "stub response — LiteRT-LM arrives in phase A2".split(" ")
        delay(STUB_FIRST_TOKEN_DELAY_MS)
        for (token in replyTokens) {
            emit(GenerationEvent.Token("$token "))
            delay(STUB_TOKEN_INTERVAL_MS)
        }
        emit(GenerationEvent.Complete(totalTokens = replyTokens.size))
    }

    private companion object {
        const val STUB_LOAD_DELAY_MS = 50L
        const val STUB_FIRST_TOKEN_DELAY_MS = 120L
        const val STUB_TOKEN_INTERVAL_MS = 50L
    }
}
