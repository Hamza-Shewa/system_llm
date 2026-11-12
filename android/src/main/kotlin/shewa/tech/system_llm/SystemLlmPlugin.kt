package shewa.tech.system_llm

import android.Manifest
import android.app.Activity
import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.StatFs
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import com.google.mlkit.genai.common.FeatureStatus
import com.google.mlkit.genai.prompt.Generation
import com.google.mlkit.genai.prompt.PromptPrefix
import com.google.mlkit.genai.prompt.TextPart
import com.google.mlkit.genai.prompt.generateContentRequest
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import org.json.JSONObject
import java.io.File

/** Bridges only AICore's installed model and explicitly on-device recognition. */
class SystemLlmPlugin :
    FlutterPlugin,
    ActivityAware,
    MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler,
    PluginRegistry.RequestPermissionsResultListener {
    private var channel: MethodChannel? = null
    private var streamChannel: EventChannel? = null
    private var generationIsStream = false
    private var context: Context? = null
    private var activity: Activity? = null
    private var activityBinding: ActivityPluginBinding? = null
    private var scope: CoroutineScope? = null
    private val model by lazy { Generation.getClient() }
    private var modelCreated = false
    private var generation: Job? = null
    private var recognizer: SpeechRecognizer? = null
    private var speechResult: MethodChannel.Result? = null
    private var speechLocale = "en"
    private var partialTranscript = ""
    private val handler = Handler(Looper.getMainLooper())
    private val speechTimeout = Runnable { finishSpeech(partialTranscript) }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
        channel = MethodChannel(binding.binaryMessenger, "system_llm").also {
            it.setMethodCallHandler(this)
        }
        streamChannel = EventChannel(binding.binaryMessenger, "system_llm/stream").also {
            it.setStreamHandler(this)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        streamChannel?.setStreamHandler(null)
        streamChannel = null
        generation?.cancel()
        finishSpeech("")
        scope?.cancel()
        scope = null
        if (modelCreated) model.close()
        modelCreated = false
        context = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        activityBinding = binding
        binding.addRequestPermissionsResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() = onDetachedFromActivity()

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) =
        onAttachedToActivity(binding)

    override fun onDetachedFromActivity() {
        activityBinding?.removeRequestPermissionsResultListener(this)
        activityBinding = null
        activity = null
    }

    private suspend fun modelStatus(): String {
        modelCreated = true
        return when (model.checkStatus()) {
            // Structured output is prompted for and validated here, so ML Kit's
            // own structured-output feature is not required.
            FeatureStatus.AVAILABLE -> "available"
            FeatureStatus.DOWNLOADING, FeatureStatus.DOWNLOADABLE -> "model_not_ready"
            else -> "unsupported"
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "environment" -> environment(call.argument<List<String>>("directories") ?: emptyList(), result)
            "availability" -> {
                val activeScope = scope
                if (activeScope == null) result.success("unsupported")
                else activeScope.launch {
                    try { result.success(modelStatus()) }
                    catch (_: Exception) { result.success("unsupported") }
                }
            }
            "speechAvailable" -> result.success(speechAvailable())
            "generateObject" -> generate(call, result)
            "listen" -> listen(call.argument<String>("locale") ?: "en", result)
            "stopListening" -> {
                recognizer?.stopListening()
                // Providers that omit a final callback still settle the request.
                handler.removeCallbacks(speechTimeout)
                handler.postDelayed(speechTimeout, 3000)
                result.success(null)
            }
            "cancel" -> {
                generation?.cancel()
                finishSpeech("")
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        val args = arguments as? Map<*, *> ?: emptyMap<String, Any>()
        fun fail(code: String) { events.error(code, null, null); events.endOfStream() }
        if (generation?.isActive == true) { fail("busy"); return }
        val activeScope = scope ?: run { fail("unsupported"); return }
        val instructions = args["instructions"] as? String ?: ""
        val input = args["input"] as? String ?: ""
        val maxTokens = (args["maxTokens"] as? Number)?.toInt() ?: 512
        generationIsStream = true
        // Lazy, so `generation` is set before Main.immediate runs the body.
        val job = activeScope.launch(start = CoroutineStart.LAZY) {
            try {
                val status = modelStatus()
                if (status != "available") { fail(status); return@launch }
                val caching = model.isCachingFeatureAvailable()
                val request = generateContentRequest(TextPart(if (caching) input else "$instructions\n$input")) {
                    temperature = 0.0f
                    maxOutputTokens = maxTokens
                    if (caching) promptPrefix = PromptPrefix(instructions)
                }
                if (model.countTokens(request).totalTokens + maxTokens > minOf(4000, model.getTokenLimit())) {
                    fail("context_too_long"); return@launch
                }
                // Each response carries the text produced since the previous one.
                model.generateContentStream(request).collect { response ->
                    val chunk = response.candidates.firstOrNull()?.text
                    if (!chunk.isNullOrEmpty()) events.success(chunk)
                }
                events.endOfStream()
            } catch (_: CancellationException) {
                events.endOfStream()
            } catch (_: Exception) {
                // Do not forward provider error text: it may include private input.
                fail("generation_failed")
            } finally {
                // A cancelled job may unwind after a newer request started.
                if (generation === coroutineContext[Job]) generationIsStream = false
            }
        }
        generation = job
        job.start()
    }

    override fun onCancel(arguments: Any?) {
        // A late cancel after the stream ended must not stop a newer request.
        if (generationIsStream) generation?.cancel()
    }

    /** Creates app-private directories that Auto Backup never copies. */
    private fun environment(names: List<String>, result: MethodChannel.Result) {
        val app = context ?: run { result.error("storage_error", null, null); return }
        try {
            val base = app.noBackupFilesDir
            val paths = mutableMapOf<String, String>()
            for (name in names) {
                if (name.isEmpty() || name.contains('/') || name.contains("..")) throw IllegalArgumentException()
                val directory = File(base, name)
                if (!directory.isDirectory && !directory.mkdirs()) throw IllegalStateException()
                paths[name] = directory.absolutePath
            }
            val memory = ActivityManager.MemoryInfo()
            (app.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager).getMemoryInfo(memory)
            // Match the running process ABI, not only the phone's supported ABIs.
            val supported = android.os.Process.is64Bit() &&
                Build.SUPPORTED_64_BIT_ABIS.any { it == "arm64-v8a" || it == "x86_64" }
            result.success(mapOf(
                "supported" to supported,
                "directories" to paths,
                "freeBytes" to StatFs(base.absolutePath).availableBytes,
                "memoryBytes" to memory.totalMem
            ))
        } catch (_: Exception) { result.error("storage_error", null, null) }
    }

    private fun generate(call: MethodCall, result: MethodChannel.Result) {
        if (generation?.isActive == true) { result.error("busy", null, null); return }
        val schemaMap = call.argument<Map<String, Any?>>("schema")
        val schema = try { schemaMap?.let { JSONObject(it) } } catch (_: Exception) { null }
        if (schema == null || schema.optString("type") != "object") {
            result.error("invalid_request", null, null); return
        }
        val instructions = StructuredOutput.instructions(call.argument<String>("instructions") ?: "", schema)
        val input IsStream = false
        generation= call.argument<String>("input") ?: ""
        val maxTokens = call.argument<Int>("maxTokens") ?: 512
        val activeScope = scope ?: run { result.error("unsupported", null, null); return }
        generation = activeScope.launch {
            try {
                val status = modelStatus()
                if (status != "available") { result.error(status, null, null); return@launch }
                val caching = model.isCachingFeatureAvailable()
                var correction = ""
                // Greedy decoding repeats itself, so the retry changes the prompt.
                repeat(2) { attempt ->
                    val text = if (caching) input + correction else "$instructions\n$input$correction"
                    val request = generateContentRequest(TextPart(text)) {
                        temperature = 0.0f
                        maxOutputTokens = maxTokens
                        if (caching) promptPrefix = PromptPrefix(instructions)
                    }
                    if (model.countTokens(request).totalTokens + maxTokens > minOf(4000, model.getTokenLimit())) {
                        result.error("context_too_long", null, null); return@launch
                    }
                    val answer = model.generateContent(request).candidates.firstOrNull()?.text
                    val valid = answer?.let { StructuredOutput.validated(schema, it) }
                    if (valid != null) { result.success(valid); return@launch }
                    if (attempt == 0) correction = "\n\nYour previous answer was not valid. Reply with only the JSON object."
                }
                result.error("invalid_response", null, null)
            } catch (_: CancellationException) {
                result.error("cancelled", null, null)
            } catch (_: Exception) {
                // Do not forward provider error text: it may include private input.
                result.error("generation_failed", null, null)
            }
        }
    }

    private fun speechAvailable(): Boolean {
        val app = context ?: return false
        return Build.VERSION.SDK_INT >= 31 && SpeechRecognizer.isOnDeviceRecognitionAvailable(app)
    }

    private fun listen(locale: String, result: MethodChannel.Result) {
        val current = activity
        if (current == null || !speechAvailable()) { result.error("speech_unavailable", null, null); return }
        if (speechResult != null) { result.error("busy", null, null); return }
        speechLocale = locale
        speechResult = result
        partialTranscript = ""
        if (current.checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            current.requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), REQUEST_RECORD_AUDIO)
        } else startSpeech()
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ): Boolean {
        if (requestCode != REQUEST_RECORD_AUDIO) return false
        if (speechResult == null) return true
        if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) startSpeech()
        else finishSpeech(error = "permission_denied")
        return true
    }

    private fun startSpeech() {
        val app = context
        if (app == null || Build.VERSION.SDK_INT < 31) { finishSpeech(error = "speech_unavailable"); return }
        try {
            // Never use createSpeechRecognizer: it may send audio to a server.
            recognizer = SpeechRecognizer.createOnDeviceSpeechRecognizer(app)
            recognizer?.setRecognitionListener(object : RecognitionListener {
                override fun onReadyForSpeech(params: Bundle?) {}
                override fun onBeginningOfSpeech() {}
                override fun onRmsChanged(rmsdB: Float) {}
                override fun onBufferReceived(buffer: ByteArray?) {}
                override fun onEndOfSpeech() {}
                override fun onEvent(eventType: Int, params: Bundle?) {}
                override fun onPartialResults(partialResults: Bundle?) {
                    partialTranscript = partialResults?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull() ?: ""
                }
                override fun onResults(results: Bundle?) {
                    finishSpeech(results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull() ?: partialTranscript)
                }
                override fun onError(error: Int) {
                    finishSpeech(error = when (error) {
                        SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> "permission_denied"
                        SpeechRecognizer.ERROR_NO_MATCH, SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> "no_speech"
                        else -> "speech_unavailable"
                    })
                }
            })
            val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                putExtra(RecognizerIntent.EXTRA_LANGUAGE, speechLocale)
                putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
                putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, true)
            }
            recognizer?.startListening(intent)
            handler.postDelayed(speechTimeout, 45000)
        } catch (_: Exception) { finishSpeech(error = "speech_unavailable") }
    }

    private fun finishSpeech(text: String = "", error: String? = null) {
        val pending = speechResult
        speechResult = null
        handler.removeCallbacks(speechTimeout)
        val previous = recognizer
        recognizer = null
        previous?.destroy()
        if (error == null) pending?.success(text.take(1000))
        else pending?.error(error, null, null)
    }

    private companion object {
        const val REQUEST_RECORD_AUDIO = 4107
    }
}
