package io.github.resker666.minimalsleep.detection

import android.content.Context
import java.io.Closeable
import java.nio.ByteBuffer
import java.nio.ByteOrder
import org.tensorflow.lite.Interpreter

/** Consumes PCM already captured by RecordingService; never opens another microphone. */
internal class YamnetClassifier(context: Context) : Closeable {
    private val labels = context.assets.open("yamnet-labels-v1.txt").bufferedReader().use { it.readLines() }
    private val model = context.assets.open("yamnet-v1.tflite").use { it.readBytes() }
    private val interpreter: Interpreter

    init {
        require(labels.size == 521 && labels[0] == "Speech" && labels[38] == "Snoring" && labels[42] == "Cough")
        val buffer = ByteBuffer.allocateDirect(model.size).order(ByteOrder.nativeOrder())
        buffer.put(model)
        buffer.rewind()
        interpreter = Interpreter(buffer, Interpreter.Options().setNumThreads(2))
        require(interpreter.getInputTensor(0).shape().contentEquals(intArrayOf(ClassificationPolicy.WINDOW_SAMPLES)))
        require(interpreter.getOutputTensor(0).shape().contentEquals(intArrayOf(1, labels.size)))
    }

    fun classify(samples: ShortArray): ClassificationPolicy.Result {
        val input = FloatArray(ClassificationPolicy.WINDOW_SAMPLES)
        val output = Array(1) { FloatArray(labels.size) }
        val scores = ArrayList<FloatArray>()
        var offset = 0
        while (offset < samples.size) {
            input.fill(0f)
            val count = minOf(input.size, samples.size - offset)
            for (i in 0 until count) input[i] = samples[offset + i] / 32768f
            interpreter.run(input, output)
            scores += output[0].copyOf()
            offset += input.size
        }
        return ClassificationPolicy.classify(labels, scores)
    }

    override fun close() = interpreter.close()
}
