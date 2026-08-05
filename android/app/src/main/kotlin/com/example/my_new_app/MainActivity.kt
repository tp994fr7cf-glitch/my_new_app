package com.example.my_new_app

import android.util.Log
import io.agora.rtc2.ChannelMediaOptions
import io.agora.rtc2.ClientRoleOptions
import io.agora.rtc2.Constants
import io.agora.rtc2.DataStreamConfig
import io.agora.rtc2.IAudioFrameObserver
import io.agora.rtc2.IRtcEngineEventHandler
import io.agora.rtc2.RtcEngine
import io.agora.rtc2.RtcEngineConfig
import io.agora.rtc2.audio.AudioParams
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.nio.ByteBuffer

class MainActivity : FlutterActivity() {
    private var nativeRtcEngine: RtcEngine? = null
    private var nativeRtcAppId: String? = null
    private lateinit var liveAudioRtcChannel: MethodChannel
    @Volatile
    private var audioCaptureStartedAtNtpMs: Long? = null
    @Volatile
    private var awaitingAudioCaptureStart = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        liveAudioRtcChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            LIVE_AUDIO_RTC_CHANNEL,
        )
        liveAudioRtcChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "initialize" -> {
                    val appId = call.argument<String>("appId")
                    if (appId.isNullOrBlank()) {
                        result.error("invalid_app_id", "Agora appId is required.", null)
                        return@setMethodCallHandler
                    }

                    try {
                        val existing = nativeRtcEngine
                        if (existing != null) {
                            check(nativeRtcAppId == appId) {
                                "A native Agora engine already exists for another appId."
                            }
                            result.success(null)
                            return@setMethodCallHandler
                        }

                        Log.i(LOG_TAG, "Creating the direct native Agora engine.")
                        val engine = RtcEngine.create(
                            RtcEngineConfig().apply {
                                mAppId = appId
                                mContext = applicationContext
                                mEventHandler = createRtcEventHandler()
                            },
                        )
                        nativeRtcEngine = engine
                        nativeRtcAppId = appId
                        Log.i(LOG_TAG, "Direct native Agora engine created.")
                        result.success(null)
                    } catch (error: Throwable) {
                        Log.e(LOG_TAG, "Unable to create the direct native Agora engine.", error)
                        result.error(
                            "native_engine_create_failed",
                            error.message ?: error.javaClass.simpleName,
                            null,
                        )
                    }
                }

                "enableAudio" -> withEngine(result, call.method) {
                    it.enableAudio()
                }

                "setClientRole" -> withEngine(result, call.method) {
                    val canPublish = call.argument<Boolean>("canPublish") == true
                    it.setClientRole(
                        if (canPublish) {
                            Constants.CLIENT_ROLE_BROADCASTER
                        } else {
                            Constants.CLIENT_ROLE_AUDIENCE
                        },
                        ClientRoleOptions().apply {
                            audienceLatencyLevel =
                                Constants.AUDIENCE_LATENCY_LEVEL_ULTRA_LOW_LATENCY
                        },
                    )
                }

                "join" -> withEngine(result, call.method) {
                    val token = requireNotNull(call.argument<String>("token"))
                    val channelName =
                        requireNotNull(call.argument<String>("channelName"))
                    val uid = requireNotNull(call.argument<Number>("uid")).toInt()
                    val canPublish = call.argument<Boolean>("canPublish") == true
                    if (canPublish) {
                        startAudioCaptureTimingObservation(it)
                    } else {
                        stopAudioCaptureTimingObservation(it)
                    }
                    it.joinChannel(
                        token,
                        channelName,
                        uid,
                        mediaOptions(canPublish),
                    )
                }

                "isConnected" -> {
                    val engine = nativeRtcEngine
                    result.success(
                        engine?.connectionState ==
                            Constants.CONNECTION_STATE_CONNECTED,
                    )
                }

                "getNtpWallTimeInMs" -> {
                    val engine = nativeRtcEngine
                    if (engine == null) {
                        result.error(
                            "rtc_not_initialized",
                            "Agora engine is not initialized.",
                            null,
                        )
                    } else {
                        result.success(engine.ntpWallTimeInMs)
                    }
                }

                "getAudioCaptureStartNtpTimeInMs" -> {
                    result.success(audioCaptureStartedAtNtpMs)
                }

                "renewToken" -> withEngine(result, call.method) {
                    it.renewToken(requireNotNull(call.argument<String>("token")))
                }

                "updateMediaOptions" -> withEngine(result, call.method) {
                    val canPublish = call.argument<Boolean>("canPublish") == true
                    if (canPublish && audioCaptureStartedAtNtpMs == null) {
                        startAudioCaptureTimingObservation(it)
                    } else if (!canPublish) {
                        stopAudioCaptureTimingObservation(it)
                    }
                    it.updateChannelMediaOptions(mediaOptions(canPublish))
                }

                "muteLocalAudioStream" -> withEngine(result, call.method) {
                    it.muteLocalAudioStream(
                        call.argument<Boolean>("muted") == true,
                    )
                }

                "adjustPlaybackSignalVolume" -> withEngine(result, call.method) {
                    it.adjustPlaybackSignalVolume(
                        requireNotNull(call.argument<Number>("volume")).toInt(),
                    )
                }

                "createDataStream" -> {
                    val engine = nativeRtcEngine
                    if (engine == null) {
                        result.error(
                            "rtc_not_initialized",
                            "Agora engine is not initialized.",
                            null,
                        )
                        return@setMethodCallHandler
                    }
                    try {
                        val streamId = engine.createDataStream(
                            DataStreamConfig().apply {
                                syncWithAudio = true
                                ordered = true
                            },
                        )
                        if (streamId < 0) {
                            result.error(
                                "agora_createDataStream_failed",
                                "Agora createDataStream failed: $streamId",
                                streamId,
                            )
                        } else {
                            result.success(streamId)
                        }
                    } catch (error: Throwable) {
                        reportNativeError(result, call.method, error)
                    }
                }

                "sendStreamMessage" -> withEngine(result, call.method) {
                    val streamId =
                        requireNotNull(call.argument<Number>("streamId")).toInt()
                    val data = requireNotNull(call.argument<ByteArray>("data"))
                    it.sendStreamMessage(streamId, data)
                }

                "leave" -> {
                    val engine = nativeRtcEngine
                    if (engine == null) {
                        result.success(null)
                    } else {
                        completeAgoraCall(result, call.method, engine.leaveChannel())
                    }
                }

                "release" -> {
                    try {
                        destroyNativeRtcEngine()
                        result.success(null)
                    } catch (error: Throwable) {
                        reportNativeError(result, call.method, error)
                    }
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun createRtcEventHandler(): IRtcEngineEventHandler {
        return object : IRtcEngineEventHandler() {
            override fun onJoinChannelSuccess(channel: String?, uid: Int, elapsed: Int) {
                sendEvent("joined")
            }

            override fun onConnectionStateChanged(state: Int, reason: Int) {
                if (state == Constants.CONNECTION_STATE_CONNECTED) {
                    sendEvent("joined")
                }
            }

            override fun onRejoinChannelSuccess(channel: String?, uid: Int, elapsed: Int) {
                sendEvent("rejoined")
            }

            override fun onConnectionInterrupted() {
                sendEvent("connectionInterrupted")
            }

            override fun onConnectionLost() {
                sendEvent("connectionLost")
            }

            override fun onLeaveChannel(stats: RtcStats?) {
                sendEvent("left")
            }

            override fun onClientRoleChanged(
                oldRole: Int,
                newRole: Int,
                newRoleOptions: ClientRoleOptions?,
            ) {
                sendEvent(
                    "clientRoleChanged",
                    mapOf(
                        "canPublish" to
                            (newRole == Constants.CLIENT_ROLE_BROADCASTER),
                    ),
                )
            }

            override fun onClientRoleChangeFailed(reason: Int, currentRole: Int) {
                sendEvent(
                    "clientRoleChangeFailed",
                    mapOf(
                        "reason" to reason,
                        "currentCanPublish" to
                            (currentRole == Constants.CLIENT_ROLE_BROADCASTER),
                    ),
                )
            }

            override fun onError(err: Int) {
                sendEvent(
                    "error",
                    mapOf(
                        "code" to err,
                        "message" to RtcEngine.getErrorDescription(err),
                    ),
                )
            }

            override fun onStreamMessage(uid: Int, streamId: Int, data: ByteArray?) {
                if (data != null) {
                    sendEvent("streamMessage", mapOf("data" to data))
                }
            }

            override fun onStreamMessageError(
                uid: Int,
                streamId: Int,
                error: Int,
                missed: Int,
                cached: Int,
            ) {
                sendEvent(
                    "streamMessageError",
                    mapOf("code" to error, "missed" to missed),
                )
            }

            override fun onTokenPrivilegeWillExpire(token: String?) {
                sendEvent("tokenRefreshRequired")
            }

            override fun onRequestToken() {
                sendEvent("tokenRefreshRequired")
            }
        }
    }

    private val audioFrameObserver = object : IAudioFrameObserver {
        override fun onRecordAudioFrame(
            channelId: String?,
            type: Int,
            samplesPerChannel: Int,
            bytesPerSample: Int,
            channels: Int,
            samplesPerSec: Int,
            buffer: ByteBuffer?,
            renderTimeMs: Long,
            avsyncType: Int,
        ): Boolean {
            if (!awaitingAudioCaptureStart || renderTimeMs <= 0) {
                return true
            }
            val engine = nativeRtcEngine ?: return true
            val monotonicNowMs = engine.currentMonotonicTimeInMs
            val ntpNowMs = engine.ntpWallTimeInMs
            // renderTimeMs may already be a wall-clock value or may use Agora's
            // monotonic clock, depending on SDK/platform behavior. Convert the
            // latter to NTP and keep the first outgoing frame as the session's
            // capture anchor. Do not replace this with callback arrival time:
            // that includes variable thread/encoding delay. This baseline may
            // still be revised if a reproduced device issue proves the SDK
            // timestamp semantics differ.
            val candidateNtpMs = when {
                renderTimeMs >= 1_000_000_000_000L -> renderTimeMs
                monotonicNowMs >= renderTimeMs && ntpNowMs > 0 ->
                    ntpNowMs - (monotonicNowMs - renderTimeMs)
                else -> return true
            }
            if (candidateNtpMs <= 0) {
                return true
            }
            synchronized(this@MainActivity) {
                if (awaitingAudioCaptureStart && audioCaptureStartedAtNtpMs == null) {
                    audioCaptureStartedAtNtpMs = candidateNtpMs
                    awaitingAudioCaptureStart = false
                    Log.i(
                        LOG_TAG,
                        "Captured Agora audio timeline start at $candidateNtpMs.",
                    )
                    runOnUiThread {
                        nativeRtcEngine?.registerAudioFrameObserver(null)
                    }
                }
            }
            return true
        }

        override fun onPlaybackAudioFrame(
            channelId: String?,
            type: Int,
            samplesPerChannel: Int,
            bytesPerSample: Int,
            channels: Int,
            samplesPerSec: Int,
            buffer: ByteBuffer?,
            renderTimeMs: Long,
            avsyncType: Int,
        ) = false

        override fun onMixedAudioFrame(
            channelId: String?,
            type: Int,
            samplesPerChannel: Int,
            bytesPerSample: Int,
            channels: Int,
            samplesPerSec: Int,
            buffer: ByteBuffer?,
            renderTimeMs: Long,
            avsyncType: Int,
        ) = false

        override fun onEarMonitoringAudioFrame(
            type: Int,
            samplesPerChannel: Int,
            bytesPerSample: Int,
            channels: Int,
            samplesPerSec: Int,
            buffer: ByteBuffer?,
            renderTimeMs: Long,
            avsyncType: Int,
        ) = false

        override fun onPlaybackAudioFrameBeforeMixing(
            channelId: String?,
            uid: Int,
            type: Int,
            samplesPerChannel: Int,
            bytesPerSample: Int,
            channels: Int,
            samplesPerSec: Int,
            buffer: ByteBuffer?,
            renderTimeMs: Long,
            avsyncType: Int,
            rtpTimestamp: Int,
            presentationMs: Long,
        ) = false

        override fun getObservedAudioFramePosition() = 0

        override fun getRecordAudioParams(): AudioParams? = null

        override fun getPlaybackAudioParams(): AudioParams? = null

        override fun getMixedAudioParams(): AudioParams? = null

        override fun getEarMonitoringAudioParams(): AudioParams? = null
    }

    private fun startAudioCaptureTimingObservation(engine: RtcEngine) {
        audioCaptureStartedAtNtpMs = null
        awaitingAudioCaptureStart = true
        val observerResult = engine.registerAudioFrameObserver(audioFrameObserver)
        val formatResult = engine.setRecordingAudioFrameParameters(
            AUDIO_FRAME_SAMPLE_RATE,
            AUDIO_FRAME_CHANNELS,
            Constants.RAW_AUDIO_FRAME_OP_MODE_READ_ONLY,
            AUDIO_FRAME_SAMPLES_PER_CALL,
        )
        if (observerResult < 0 || formatResult < 0) {
            awaitingAudioCaptureStart = false
            engine.registerAudioFrameObserver(null)
            Log.w(
                LOG_TAG,
                "Audio timing observer unavailable: observer=$observerResult, " +
                    "format=$formatResult",
            )
        }
    }

    private fun stopAudioCaptureTimingObservation(engine: RtcEngine) {
        awaitingAudioCaptureStart = false
        engine.registerAudioFrameObserver(null)
    }

    private fun mediaOptions(canPublish: Boolean): ChannelMediaOptions {
        return ChannelMediaOptions().apply {
            channelProfile = Constants.CHANNEL_PROFILE_LIVE_BROADCASTING
            clientRoleType =
                if (canPublish) {
                    Constants.CLIENT_ROLE_BROADCASTER
                } else {
                    Constants.CLIENT_ROLE_AUDIENCE
                }
            audienceLatencyLevel =
                Constants.AUDIENCE_LATENCY_LEVEL_ULTRA_LOW_LATENCY
            publishMicrophoneTrack = canPublish
            publishCameraTrack = false
            autoSubscribeAudio = true
            autoSubscribeVideo = false
            enableAudioRecordingOrPlayout = true
        }
    }

    private fun withEngine(
        result: MethodChannel.Result,
        method: String,
        operation: (RtcEngine) -> Int,
    ) {
        val engine = nativeRtcEngine
        if (engine == null) {
            result.error(
                "rtc_not_initialized",
                "Agora engine is not initialized.",
                null,
            )
            return
        }
        try {
            completeAgoraCall(result, method, operation(engine))
        } catch (error: Throwable) {
            reportNativeError(result, method, error)
        }
    }

    private fun completeAgoraCall(
        result: MethodChannel.Result,
        method: String,
        returnCode: Int,
    ) {
        if (returnCode < 0) {
            result.error(
                "agora_${method}_failed",
                "Agora $method failed: $returnCode",
                returnCode,
            )
        } else {
            result.success(null)
        }
    }

    private fun reportNativeError(
        result: MethodChannel.Result,
        method: String,
        error: Throwable,
    ) {
        Log.e(LOG_TAG, "Native Agora $method failed.", error)
        result.error(
            "native_${method}_failed",
            error.message ?: error.javaClass.simpleName,
            null,
        )
    }

    private fun sendEvent(
        type: String,
        details: Map<String, Any?> = emptyMap(),
    ) {
        runOnUiThread {
            liveAudioRtcChannel.invokeMethod(
                "event",
                mapOf("type" to type) + details,
            )
        }
    }

    private fun destroyNativeRtcEngine() {
        if (nativeRtcEngine == null) {
            return
        }

        Log.i(LOG_TAG, "Destroying the direct native Agora engine.")
        nativeRtcEngine?.registerAudioFrameObserver(null)
        RtcEngine.destroy()
        nativeRtcEngine = null
        nativeRtcAppId = null
        audioCaptureStartedAtNtpMs = null
        awaitingAudioCaptureStart = false
        Log.i(LOG_TAG, "Direct native Agora engine destroyed.")
    }

    companion object {
        private const val LIVE_AUDIO_RTC_CHANNEL =
            "com.example.my_new_app/live_audio_native_rtc"
        private const val LOG_TAG = "LiveAudioNativeRtc"
        private const val AUDIO_FRAME_SAMPLE_RATE = 48000
        private const val AUDIO_FRAME_CHANNELS = 1
        private const val AUDIO_FRAME_SAMPLES_PER_CALL = 480
    }
}
