package io.github.resker666.minimalsleep.detection

import android.content.Context
import io.github.resker666.minimalsleep.capture.RecordingUiState
import io.github.resker666.minimalsleep.data.SleepDao
import java.io.Closeable
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit

/** Fixed queue limits retained PCM to one running segment and four waiting segments. */
class EventClassificationWorker(private val context: Context, private val dao: SleepDao) : Closeable {
    private val executor = ThreadPoolExecutor(
        1, 1, 0, TimeUnit.MILLISECONDS, ArrayBlockingQueue(4),
        { task -> Thread(task, "minimal-sleep-classifier") }
    )
    private var classifier: YamnetClassifier? = null
    private var loadFailed = false

    fun submit(eventId: String, samples: ShortArray) {
        try {
            executor.execute {
                try {
                    if (classifier == null && !loadFailed) {
                        try {
                            classifier = YamnetClassifier(context)
                            RecordingUiState.classifierStatus = "READY"
                        } catch (error: Exception) {
                            loadFailed = true
                            RecordingUiState.classifierStatus = "UNAVAILABLE"
                        }
                    }
                    val active = classifier
                    if (active == null) {
                        dao.classifyEvent(eventId, "普通声音", null, null, null, "UNAVAILABLE")
                    } else {
                        val result = active.classify(samples)
                        dao.classifyEvent(
                            eventId, result.label, ClassificationPolicy.MODEL_VERSION,
                            result.score, result.sourceLabel, "READY"
                        )
                    }
                } catch (error: Exception) {
                    dao.classifyEvent(eventId, "普通声音", null, null, null, "ERROR")
                    RecordingUiState.classifierStatus = "UNAVAILABLE"
                }
            }
        } catch (_: RejectedExecutionException) {
            dao.classifyEvent(eventId, "普通声音", null, null, null, "SKIPPED")
        }
    }

    override fun close() {
        executor.shutdown()
        val stopped = if (executor.awaitTermination(60, TimeUnit.SECONDS)) true else {
            executor.shutdownNow()
            executor.awaitTermination(5, TimeUnit.SECONDS)
        }
        if (stopped) classifier?.close()
    }
}
