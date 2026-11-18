package io.github.yyyy530.tokenworks_go

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.media.AudioManager
import android.os.Bundle
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.Locale

class VoiceChannel(
    private val activity: FlutterActivity,
    messenger: BinaryMessenger
) : MethodChannel.MethodCallHandler, RecognitionListener {
    private val channel = MethodChannel(messenger, "tokenworks_go/voice")
    private val audioManager = activity.getSystemService(AudioManager::class.java)
    private var recognizer: SpeechRecognizer? = null
    private var tts: TextToSpeech? = null
    private var ttsReady = false
    private var listening = false
    private var permissionResult: MethodChannel.Result? = null
    private val pendingSpeech = ArrayDeque<Pair<String, String>>()

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "startListening" -> startListening(result)
            "stopListening" -> {
                stopListening()
                result.success(null)
            }
            "speak" -> {
                val id = call.argument<String>("id")
                val text = call.argument<String>("text")
                if (id.isNullOrBlank() || text.isNullOrBlank()) {
                    result.error("invalid-utterance", "Utterance id and text are required", null)
                } else {
                    pendingSpeech.addLast(id to text)
                    drainSpeech()
                    result.success(null)
                }
            }
            "stopSpeaking" -> {
                pendingSpeech.clear()
                tts?.stop()
                result.success(null)
            }
            "setSpeakerphone" -> {
                val enabled = call.arguments as? Boolean ?: true
                audioManager.mode = AudioManager.MODE_IN_COMMUNICATION
                audioManager.isSpeakerphoneOn = enabled
                result.success(null)
            }
            "shutdown" -> {
                shutdown()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun startListening(result: MethodChannel.Result) {
        if (listening) {
            result.success(null)
            return
        }
        if (ContextCompat.checkSelfPermission(activity, Manifest.permission.RECORD_AUDIO) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            permissionResult = result
            ActivityCompat.requestPermissions(activity, arrayOf(Manifest.permission.RECORD_AUDIO), audioPermissionRequest)
            return
        }
        if (!SpeechRecognizer.isRecognitionAvailable(activity)) {
            result.error("stt-unavailable", "System speech recognition is unavailable", null)
            return
        }
        if (recognizer == null) {
            recognizer = SpeechRecognizer.createSpeechRecognizer(activity).also {
                it.setRecognitionListener(this)
            }
        }
        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, Locale.getDefault().toLanguageTag())
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
        }
        listening = true
        recognizer?.startListening(intent)
        result.success(null)
    }

    fun onPermissionResult(granted: Boolean) {
        val result = permissionResult ?: return
        permissionResult = null
        if (granted) {
            startListening(result)
        } else {
            result.error("microphone-permission", "Microphone permission was denied", null)
        }
    }

    private fun stopListening() {
        listening = false
        recognizer?.stopListening()
    }

    private fun drainSpeech() {
        if (!ttsReady || pendingSpeech.isEmpty()) {
            if (tts == null && pendingSpeech.isNotEmpty()) initializeTts()
            return
        }
        while (pendingSpeech.isNotEmpty()) {
            val (id, text) = pendingSpeech.removeFirst()
            tts?.speak(text, TextToSpeech.QUEUE_ADD, null, id)
        }
    }

    private fun initializeTts() {
        tts = TextToSpeech(activity) { status ->
            if (status != TextToSpeech.SUCCESS) {
                channel.invokeMethod("playbackError", "系统朗读服务初始化失败")
                return@TextToSpeech
            }
            val engine = tts ?: return@TextToSpeech
            val language = engine.setLanguage(Locale.getDefault())
            if (language == TextToSpeech.LANG_MISSING_DATA || language == TextToSpeech.LANG_NOT_SUPPORTED) {
                channel.invokeMethod("playbackError", "系统朗读服务不支持当前语言")
                return@TextToSpeech
            }
            engine.setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                    .build()
            )
            engine.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                override fun onStart(id: String) {
                    channel.invokeMethod("utterance", mapOf("id" to id, "started" to true))
                }

                override fun onDone(id: String) {
                    channel.invokeMethod("utterance", mapOf("id" to id, "started" to false))
                }

                override fun onError(id: String) {
                    channel.invokeMethod("playbackError", "系统朗读服务播放失败")
                }
            })
            ttsReady = true
            drainSpeech()
        }
    }

    fun shutdown() {
        listening = false
        recognizer?.stopListening()
        recognizer?.destroy()
        recognizer = null
        pendingSpeech.clear()
        tts?.stop()
        tts?.shutdown()
        tts = null
        ttsReady = false
        audioManager.isSpeakerphoneOn = false
        audioManager.mode = AudioManager.MODE_NORMAL
    }

    private fun recognitionText(bundle: Bundle): String =
        bundle.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull().orEmpty()

    override fun onPartialResults(results: Bundle) {
        channel.invokeMethod("recognition", mapOf("text" to recognitionText(results), "final" to false))
    }

    override fun onResults(results: Bundle) {
        listening = false
        channel.invokeMethod("recognition", mapOf("text" to recognitionText(results), "final" to true))
    }

    override fun onError(error: Int) {
        listening = false
        channel.invokeMethod("listeningError", error)
    }

    override fun onReadyForSpeech(params: Bundle?) = Unit
    override fun onBeginningOfSpeech() = Unit
    override fun onRmsChanged(rmsdB: Float) = Unit
    override fun onBufferReceived(buffer: ByteArray?) = Unit
    override fun onEndOfSpeech() = Unit
    override fun onEvent(eventType: Int, params: Bundle?) = Unit

    private companion object {
        const val audioPermissionRequest = 7319
    }
}
