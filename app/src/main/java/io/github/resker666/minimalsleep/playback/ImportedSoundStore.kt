package io.github.resker666.minimalsleep.playback

import android.content.Context
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.provider.OpenableColumns
import android.webkit.MimeTypeMap
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.util.UUID
import org.json.JSONArray
import org.json.JSONObject

data class ImportedSound(val id: String, val label: String, val fileName: String)

class ImportedSoundStore(private val context: Context) {
    private val directory get() = File(context.filesDir, "imported-sounds")
    private val preferences get() = context.getSharedPreferences("imported-sounds", Context.MODE_PRIVATE)

    init {
        synchronized(metadataLock) {
            if (!cleanedThisProcess) {
                val referenced = list().map { it.fileName }.toSet()
                directory.listFiles()?.filterNot { it.name in referenced }?.forEach { it.delete() }
                cleanedThisProcess = true
            }
        }
    }

    fun list(): List<ImportedSound> = synchronized(metadataLock) {
        val stored = JSONArray(preferences.getString("items", "[]"))
        (0 until stored.length()).map { index ->
            val item = stored.getJSONObject(index)
            ImportedSound(item.getString("id"), item.getString("label"), item.getString("fileName"))
        }
    }

    fun file(id: String): File? = list().firstOrNull { it.id == id }?.let { File(directory, it.fileName) }

    fun import(uri: Uri): ImportedSound {
        val resolver = context.contentResolver
        val mime = resolver.getType(uri) ?: throw IOException("无法读取音频类型")
        if (!mime.startsWith("audio/")) throw IOException("请选择音频文件")
        if (list().size >= 10) throw IOException("最多保留 10 个导入声音，请先删除旧文件")
        val existingBytes = directory.listFiles()?.sumOf { it.length() } ?: 0L
        val extension = MimeTypeMap.getSingleton().getExtensionFromMimeType(mime)?.lowercase()
            ?.takeIf { it.matches(Regex("[a-z0-9]{1,8}")) } ?: "audio"
        val id = UUID.randomUUID().toString()
        val name = "$id.$extension"
        if (!directory.isDirectory && !directory.mkdirs()) throw IOException("无法创建导入目录")
        val temporary = File(directory, "$name.part")
        val target = File(directory, name)
        try {
            resolver.openInputStream(uri)?.use { source ->
                FileOutputStream(temporary).use { output ->
                    val buffer = ByteArray(8192)
                    var size = 0L
                    while (true) {
                        val count = source.read(buffer)
                        if (count < 0) break
                        size += count
                        if (size > 100L * 1024 * 1024) throw IOException("单个音频超过 100 MiB")
                        if (existingBytes + size > 300L * 1024 * 1024) throw IOException("导入音频总量超过 300 MiB")
                        if (context.filesDir.usableSpace < 200L * 1024 * 1024) throw IOException("设备剩余空间不足 200 MiB")
                        output.write(buffer, 0, count)
                    }
                    if (size == 0L) throw IOException("音频文件为空")
                    output.fd.sync()
                }
            } ?: throw IOException("无法打开音频文件")
            val retriever = MediaMetadataRetriever()
            try {
                retriever.setDataSource(temporary.absolutePath)
                val duration = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull()
                if (duration == null || duration < 1000L) throw IOException("无法解析或音频短于 1 秒")
            } finally {
                retriever.release()
            }
            val label = displayName(uri).take(60).ifBlank { "导入声音" }
            val sound = ImportedSound(id, label, name)
            synchronized(metadataLock) {
                val items = list()
                if (items.size >= 10) throw IOException("最多保留 10 个导入声音，请先删除旧文件")
                val used = directory.listFiles()?.filterNot { it.name.endsWith(".part") }?.sumOf { it.length() } ?: 0L
                if (used + temporary.length() > 300L * 1024 * 1024) throw IOException("导入音频总量超过 300 MiB")
                if (!temporary.renameTo(target)) throw IOException("无法保存音频文件")
                persist(items + sound)
            }
            return sound
        } catch (failure: Exception) {
            temporary.delete()
            target.delete()
            throw failure
        }
    }

    fun delete(id: String): Boolean = synchronized(metadataLock) {
        val items = list()
        val sound = items.firstOrNull { it.id == id } ?: return@synchronized false
        val file = File(directory, sound.fileName)
        persist(items.filterNot { it.id == id })
        if (file.exists() && !file.delete()) {
            persist(items)
            throw IOException("无法删除导入音频")
        }
        true
    }

    private fun persist(items: List<ImportedSound>) {
        val array = JSONArray()
        items.forEach { array.put(JSONObject().put("id", it.id).put("label", it.label).put("fileName", it.fileName)) }
        if (!preferences.edit().putString("items", array.toString()).commit()) throw IOException("无法保存导入列表")
    }

    private fun displayName(uri: Uri): String {
        return context.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
            if (cursor.moveToFirst()) cursor.getString(0) else null
        } ?: "导入声音"
    }

    companion object {
        private val metadataLock = Any()
        private var cleanedThisProcess = false
    }
}
