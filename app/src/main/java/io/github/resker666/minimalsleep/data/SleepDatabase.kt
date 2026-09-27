package io.github.resker666.minimalsleep.data

import android.content.Context
import androidx.room.Dao
import androidx.room.Database
import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.Insert
import androidx.room.PrimaryKey
import androidx.room.Query
import androidx.room.Room
import androidx.room.RoomDatabase
import androidx.room.migration.Migration
import androidx.sqlite.db.SupportSQLiteDatabase

@Entity(tableName = "sessions")
data class SleepSession(
    @PrimaryKey val id: String,
    val startedAtEpochMs: Long,
    val startTimeZone: String,
    val endedAtEpochMs: Long? = null,
    val durationSamples: Long = 0,
    val status: String = "RECORDING",
    val endReason: String? = null
)

@Entity(tableName = "events")
data class SoundEvent(
    @PrimaryKey val id: String,
    val sessionId: String,
    val groupId: String,
    val startSample: Long,
    val durationSamples: Long,
    val label: String = "普通声音",
    val fileName: String,
    val playbackAffected: Boolean,
    val modelVersion: String? = null,
    val modelScore: Float? = null,
    val modelSourceLabel: String? = null,
    val userLabel: String? = null,
    @ColumnInfo(defaultValue = "'LEGACY'") val classificationStatus: String = "PENDING"
)

fun SoundEvent.effectiveLabel(): String {
    userLabel?.let { return it }
    if (playbackAffected && classificationStatus == "READY" &&
        label in setOf("人声/疑似梦话", "疑似鼾声", "疑似咳嗽")
    ) return "未确定（播放干扰）"
    return label
}

@Entity(tableName = "playback_intervals")
data class PlaybackInterval(
    @PrimaryKey val id: String,
    val sessionId: String,
    val soundId: String,
    val appVolume: Float,
    val startSample: Long,
    val endSample: Long
)

@Entity(tableName = "recording_gaps")
data class RecordingGap(
    @PrimaryKey val id: String,
    val sessionId: String,
    val startSample: Long,
    val reason: String
)

@Entity(tableName = "capture_hours", primaryKeys = ["sessionId", "hourIndex"])
data class CaptureHour(
    val sessionId: String,
    val hourIndex: Int,
    val sensitivity: String,
    val frameCount: Int,
    val below3Count: Int,
    val below6Count: Int,
    val below12Count: Int,
    val atLeast12Count: Int,
    val candidateCount: Int,
    val maxRms: Float
)

@Dao
interface SleepDao {
    @Insert fun insertSession(session: SleepSession)
    @Insert fun insertEvent(event: SoundEvent)
    @Insert fun insertPlaybackInterval(interval: PlaybackInterval)
    @Insert fun insertGap(gap: RecordingGap)
    @Insert fun insertCaptureHour(hour: CaptureHour)
    @Query("UPDATE sessions SET endedAtEpochMs = :endedAt, durationSamples = :samples, status = :status, endReason = :reason WHERE id = :id")
    fun endSession(id: String, endedAt: Long, samples: Long, status: String, reason: String?)
    @Query("UPDATE sessions SET status = 'INTERRUPTED', endedAtEpochMs = :now, endReason = '进程中断' WHERE status = 'RECORDING'")
    fun markStaleInterrupted(now: Long)
    @Query("SELECT * FROM sessions ORDER BY startedAtEpochMs DESC")
    fun sessions(): List<SleepSession>
    @Query("SELECT * FROM events WHERE sessionId = :id ORDER BY startSample")
    fun events(id: String): List<SoundEvent>
    @Query("UPDATE events SET label = :label, modelVersion = :version, modelScore = :score, modelSourceLabel = :sourceLabel, classificationStatus = :status WHERE id = :id")
    fun classifyEvent(id: String, label: String, version: String?, score: Float?, sourceLabel: String?, status: String)
    @Query("UPDATE events SET userLabel = :label WHERE id = :id")
    fun setUserLabel(id: String, label: String?)
    @Query("UPDATE events SET classificationStatus = 'SKIPPED' WHERE sessionId = :sessionId AND classificationStatus = 'PENDING'")
    fun markPendingSkipped(sessionId: String)
    @Query("UPDATE events SET classificationStatus = 'SKIPPED' WHERE classificationStatus = 'PENDING' AND sessionId IN (SELECT id FROM sessions WHERE status != 'RECORDING')")
    fun markStaleClassificationSkipped()
    @Query("SELECT * FROM playback_intervals WHERE sessionId = :id ORDER BY startSample")
    fun playbackIntervals(id: String): List<PlaybackInterval>
    @Query("SELECT * FROM recording_gaps WHERE sessionId = :id")
    fun gaps(id: String): List<RecordingGap>
    @Query("SELECT * FROM capture_hours WHERE sessionId = :id ORDER BY hourIndex")
    fun captureHours(id: String): List<CaptureHour>
    @Query("DELETE FROM events WHERE id = :id")
    fun deleteEvent(id: String)
    @Query("DELETE FROM events WHERE sessionId = :id")
    fun deleteEventsForSession(id: String)
    @Query("DELETE FROM playback_intervals WHERE sessionId = :id")
    fun deletePlaybackIntervalsForSession(id: String)
    @Query("DELETE FROM recording_gaps WHERE sessionId = :id")
    fun deleteGapsForSession(id: String)
    @Query("DELETE FROM capture_hours WHERE sessionId = :id")
    fun deleteCaptureHoursForSession(id: String)
    @Query("DELETE FROM sessions WHERE id = :id")
    fun deleteSession(id: String)
}

@Database(
    entities = [SleepSession::class, SoundEvent::class, PlaybackInterval::class, RecordingGap::class, CaptureHour::class],
    version = 3,
    exportSchema = true
)
abstract class SleepDatabase : RoomDatabase() {
    abstract fun dao(): SleepDao

    companion object {
        @Volatile private var instance: SleepDatabase? = null
        private val MIGRATION_1_2 = object : Migration(1, 2) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL("ALTER TABLE events ADD COLUMN modelVersion TEXT")
                db.execSQL("ALTER TABLE events ADD COLUMN modelScore REAL")
                db.execSQL("ALTER TABLE events ADD COLUMN modelSourceLabel TEXT")
                db.execSQL("ALTER TABLE events ADD COLUMN userLabel TEXT")
                db.execSQL("ALTER TABLE events ADD COLUMN classificationStatus TEXT NOT NULL DEFAULT 'LEGACY'")
            }
        }
        private val MIGRATION_2_3 = object : Migration(2, 3) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL("""CREATE TABLE IF NOT EXISTS capture_hours (
                    sessionId TEXT NOT NULL, hourIndex INTEGER NOT NULL, sensitivity TEXT NOT NULL,
                    frameCount INTEGER NOT NULL, below3Count INTEGER NOT NULL,
                    below6Count INTEGER NOT NULL, below12Count INTEGER NOT NULL,
                    atLeast12Count INTEGER NOT NULL, candidateCount INTEGER NOT NULL,
                    maxRms REAL NOT NULL, PRIMARY KEY(sessionId, hourIndex)
                )""".trimIndent())
            }
        }

        fun get(context: Context): SleepDatabase = instance ?: synchronized(this) {
            instance ?: Room.databaseBuilder(
                context.applicationContext,
                SleepDatabase::class.java,
                "minimal-sleep.db"
            ).addMigrations(MIGRATION_1_2, MIGRATION_2_3).build().also { instance = it }
        }
    }
}
