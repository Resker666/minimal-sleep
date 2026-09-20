package io.github.resker666.minimalsleep.data

import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.util.UUID

class AudioFileStore(private val directory: File) {
    fun write(samples: ShortArray, sampleRate: Int): String {
        require(sampleRate > 0 && samples.isNotEmpty())
        if (!directory.isDirectory && !directory.mkdirs()) throw IOException("无法创建录音目录")
        val name = "${UUID.randomUUID()}.wav"
        val temporary = File(directory, "$name.part")
        val target = path(name)
        val byteCount = samples.size * 2
        try {
            FileOutputStream(temporary).use { out ->
                fun ascii(value: String) = out.write(value.toByteArray(Charsets.US_ASCII))
                fun u16(value: Int) {
                    out.write(value and 0xff)
                    out.write((value ushr 8) and 0xff)
                }
                fun u32(value: Int) {
                    u16(value and 0xffff)
                    u16(value ushr 16)
                }
                ascii("RIFF")
                u32(36 + byteCount)
                ascii("WAVEfmt ")
                u32(16)
                u16(1)
                u16(1)
                u32(sampleRate)
                u32(sampleRate * 2)
                u16(2)
                u16(16)
                ascii("data")
                u32(byteCount)
                val block = ByteArray(8192)
                var offset = 0
                while (offset < samples.size) {
                    val count = minOf(samples.size - offset, block.size / 2)
                    for (index in 0 until count) {
                        val sample = samples[offset + index].toInt()
                        block[index * 2] = sample.toByte()
                        block[index * 2 + 1] = (sample ushr 8).toByte()
                    }
                    out.write(block, 0, count * 2)
                    offset += count
                }
                out.fd.sync()
            }
            if (!temporary.renameTo(target)) throw IOException("无法完成录音文件")
            return name
        } catch (error: Exception) {
            temporary.delete()
            throw error
        }
    }

    fun path(name: String): File {
        require(Regex("[0-9a-f-]{36}\\.wav").matches(name))
        return File(directory, name)
    }
}
