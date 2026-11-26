package com.example.music_player

import android.os.Handler
import android.os.Looper
import com.ryanheise.audioservice.AudioServiceActivity
import com.yausername.ffmpeg.FFmpeg
import com.yausername.youtubedl_android.YoutubeDL
import com.yausername.youtubedl_android.YoutubeDLRequest
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.util.concurrent.Executors

class MainActivity : AudioServiceActivity() {
    private val executor = Executors.newCachedThreadPool()
    private val main = Handler(Looper.getMainLooper())
    private var sink: EventChannel.EventSink? = null
    private var initialized = false

    private fun emit(data: Map<String, Any?>) = main.post { sink?.success(data) }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        EventChannel(messenger, "seal_player/ytdlp_events").setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, events: EventChannel.EventSink?) { sink = events }
                override fun onCancel(args: Any?) { sink = null }
            })

        MethodChannel(messenger, "seal_player/ytdlp").setMethodCallHandler { call, result ->
            when (call.method) {
                "init" -> executor.execute {
                    try {
                        if (!initialized) {
                            YoutubeDL.getInstance().init(applicationContext)
                            FFmpeg.getInstance().init(applicationContext)
                            initialized = true
                        }
                        main.post { result.success(true) }
                    } catch (e: Throwable) { // also catches Errors such as ExceptionInInitializerError
                        main.post { result.error("INIT", e.message ?: e.toString(), null) }
                    }
                }

                "download" -> {
                    val id = call.argument<String>("id")!!
                    val url = call.argument<String>("url")!!
                    val audioOnly = call.argument<Boolean>("audioOnly") ?: true
                    val format = call.argument<String>("format") ?: "mp3"
                    val outDir = call.argument<String>("outDir")!!
                    result.success(null)

                    executor.execute {
                        try {
                            // Title lookup so the UI can show something nicer than the URL.
                            try {
                                val info = YoutubeDL.getInstance().getInfo(url)
                                emit(mapOf("id" to id, "type" to "title", "title" to (info.title ?: url)))
                            } catch (_: Exception) {}

                            fun buildRequest(withThumbnail: Boolean): YoutubeDLRequest {
                                val req = YoutubeDLRequest(url)
                                req.addOption("--no-playlist")
                                req.addOption("--no-mtime")
                                req.addOption("-o", "$outDir/%(title).150B.%(ext)s")
                                req.addOption("--embed-metadata")
                                if (withThumbnail) {
                                    // Cover art inside the file, cropped to a square.
                                    req.addOption("--embed-thumbnail")
                                    req.addOption("--convert-thumbnails", "jpg")
                                    req.addOption(
                                        "--ppa",
                                        "ThumbnailsConvertor+ffmpeg_o:-c:v mjpeg -vf crop=\"'if(gt(ih,iw),iw,ih)':'if(gt(iw,ih),ih,iw)'\""
                                    )
                                }
                                if (audioOnly) {
                                    req.addOption("-f", "bestaudio/best")
                                    req.addOption("-x")
                                    req.addOption("--audio-format", format)
                                } else {
                                    req.addOption("-f", "bv*[height<=1080]+ba/b")
                                    req.addOption("--merge-output-format", "mp4")
                                }
                                return req
                            }

                            val onProgress: (Float, Long, String) -> Unit = { progress, eta, _ ->
                                emit(mapOf("id" to id, "type" to "progress",
                                    "progress" to progress.toDouble(), "eta" to eta))
                            }

                            try {
                                YoutubeDL.getInstance().execute(buildRequest(true), id, onProgress)
                            } catch (e: YoutubeDL.CanceledException) {
                                throw e
                            } catch (e: Exception) {
                                // Thumbnail step can fail for some formats; the song is
                                // still worth having, so retry without cover art.
                                YoutubeDL.getInstance().execute(buildRequest(false), id, onProgress)
                            }
                            emit(mapOf("id" to id, "type" to "done"))
                        } catch (e: Exception) {
                            emit(mapOf("id" to id, "type" to "error", "message" to (e.message ?: "Download failed")))
                        }
                    }
                }

                "search" -> {
                    val query = call.argument<String>("query")!!
                    val count = call.argument<Int>("count") ?: 15
                    executor.execute {
                        try {
                            // ytsearchN: is yt-dlp's built-in YouTube search. --flat-playlist
                            // keeps it fast: one JSON line per result, no per-video lookups.
                            val req = YoutubeDLRequest("ytsearch$count:$query")
                            req.addOption("--flat-playlist")
                            req.addOption("--dump-json")
                            req.addOption("--no-warnings")
                            val out = YoutubeDL.getInstance().execute(req).out

                            fun str(o: JSONObject, key: String) =
                                if (o.isNull(key)) "" else o.optString(key)

                            val items = ArrayList<Map<String, Any?>>()
                            for (line in out.lineSequence()) {
                                val s = line.trim()
                                if (!s.startsWith("{")) continue
                                try {
                                    val o = JSONObject(s)
                                    val vid = str(o, "id")
                                    if (vid.isEmpty()) continue
                                    val channel = str(o, "channel").ifEmpty { str(o, "uploader") }
                                    items.add(mapOf(
                                        "id" to vid,
                                        "title" to str(o, "title"),
                                        "channel" to channel,
                                        "duration" to (if (o.isNull("duration")) null else o.optDouble("duration")),
                                        "url" to str(o, "url").ifEmpty { "https://www.youtube.com/watch?v=$vid" },
                                    ))
                                } catch (_: Exception) {}
                            }
                            main.post { result.success(items) }
                        } catch (e: Exception) {
                            main.post { result.error("SEARCH", e.message, null) }
                        }
                    }
                }

                "update" -> executor.execute {
                    try {
                        val status = YoutubeDL.getInstance()
                            .updateYoutubeDL(applicationContext, YoutubeDL.UpdateChannel.NIGHTLY)
                        main.post { result.success(status?.toString() ?: "UNKNOWN") }
                    } catch (e: Exception) {
                        main.post { result.error("UPDATE", e.message, null) }
                    }
                }

                "cancel" -> {
                    YoutubeDL.getInstance().destroyProcessById(call.argument<String>("id")!!)
                    result.success(null)
                }

                else -> result.notImplemented()
            }
        }
    }
}