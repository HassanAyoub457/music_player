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
                    } catch (e: Exception) {
                        main.post { result.error("INIT", e.message, null) }
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

                            val req = YoutubeDLRequest(url)
                            req.addOption("--no-playlist")
                            req.addOption("--no-mtime")
                            req.addOption("-o", "$outDir/%(title).150B.%(ext)s")
                            if (audioOnly) {
                                req.addOption("-f", "bestaudio/best")
                                req.addOption("-x")
                                req.addOption("--audio-format", format)
                                req.addOption("--embed-metadata")
                            } else {
                                req.addOption("-f", "bv*[height<=1080]+ba/b")
                                req.addOption("--merge-output-format", "mp4")
                            }

                            YoutubeDL.getInstance().execute(req, id) { progress, eta, _ ->
                                emit(mapOf("id" to id, "type" to "progress",
                                    "progress" to progress.toDouble(), "eta" to eta))
                            }
                            emit(mapOf("id" to id, "type" to "done"))
                        } catch (e: Exception) {
                            emit(mapOf("id" to id, "type" to "error", "message" to (e.message ?: "Download failed")))
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
