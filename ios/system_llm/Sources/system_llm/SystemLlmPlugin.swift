import AVFoundation
import Flutter
import Speech
import UIKit
#if canImport(FoundationModels)
import FoundationModels
#endif

private enum SchemaError: Error { case invalid }

#if canImport(FoundationModels)
/// Converts the Dart `AiSchema` JSON into a runtime generation schema, because
/// `@Generable` structs only exist at compile time.
@available(iOS 26.0, *)
private func dynamicSchema(_ json: [String: Any], name: String) throws -> DynamicGenerationSchema {
  switch json["type"] as? String {
  case "object":
    let entries = json["properties"] as? [[String: Any]] ?? []
    let properties = try entries.map { entry -> DynamicGenerationSchema.Property in
      guard let propertyName = entry["name"] as? String, !propertyName.isEmpty else { throw SchemaError.invalid }
      return DynamicGenerationSchema.Property(
        name: propertyName,
        description: entry["description"] as? String,
        schema: try dynamicSchema(entry, name: propertyName)
      )
    }
    return DynamicGenerationSchema(name: name, description: json["description"] as? String, properties: properties)
  case "array":
    guard let items = json["items"] as? [String: Any] else { throw SchemaError.invalid }
    return DynamicGenerationSchema(
      arrayOf: try dynamicSchema(items, name: name + "Item"),
      minimumElements: nil,
      maximumElements: (json["maxItems"] as? NSNumber)?.intValue
    )
  case "string": return DynamicGenerationSchema(type: String.self)
  case "integer": return DynamicGenerationSchema(type: Int.self)
  case "boolean": return DynamicGenerationSchema(type: Bool.self)
  default: throw SchemaError.invalid
  }
}
#endif

/// Receives Flutter stream requests on the platform thread and forwards them
/// to the main-actor plugin.
private final class StreamHandler: NSObject, FlutterStreamHandler {
  weak var plugin: SystemLlmPlugin?

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    let args = arguments as? [String: Any] ?? [:]
    Task { @MainActor [weak plugin] in plugin?.startStream(args, sink: events) }
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    Task { @MainActor [weak plugin] in plugin?.cancelStream() }
    return nil
  }
}

#if canImport(FoundationModels)
/// Maps a Foundation Models failure to the plugin's stable error codes.
@available(iOS 26.0, *)
private func errorCode(for error: LanguageModelSession.GenerationError) -> String {
  switch error {
  case .exceededContextWindowSize: return "context_too_long"
  case .unsupportedLanguageOrLocale: return "unsupported_language"
  default: return "generation_failed"
  }
}
#endif

/// Bridges the system language model and on-device speech recognition.
@MainActor
public final class SystemLlmPlugin: NSObject, FlutterPlugin {
  private var generation: Task<Void, Never>?
  private var generationIsStream = false
  private let streamHandler = StreamHandler()
  private let audioEngine = AVAudioEngine()
  private var speechTask: SFSpeechRecognitionTask?
  private var speechRequest: SFSpeechAudioBufferRecognitionRequest?
  private var speechResult: FlutterResult?
  private var speechTimer: Timer?
  private var transcript = ""
  private var hasAudioTap = false
  private var speechID = UUID()

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "system_llm", binaryMessenger: registrar.messenger())
    let instance = SystemLlmPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
    let events = FlutterEventChannel(name: "system_llm/stream", binaryMessenger: registrar.messenger())
    instance.streamHandler.plugin = instance
    events.setStreamHandler(instance.streamHandler)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    let locale = args["locale"] as? String ?? "en"
    switch call.method {
    case "environment": environment(args["directories"] as? [String] ?? [], result: result)
    case "availability": result(availability(locale))
    case "speechAvailable":
      let recognizer = SFSpeechRecognizer(locale: Locale(identifier: locale))
      result(recognizer?.supportsOnDeviceRecognition == true && recognizer?.isAvailable == true)
    case "generateObject": generate(args, result: result)
    case "listen": listen(locale, result: result)
    case "stopListening":
      audioEngine.stop()
      speechRequest?.endAudio()
      speechTimer?.invalidate()
      speechTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: false) { [weak self] _ in
        Task { @MainActor in self?.finishSpeech() }
      }
      result(nil)
    case "cancel":
      generation?.cancel()
      finishSpeech(text: "")
      result(nil)
    default: result(FlutterMethodNotImplemented)
    }
  }

  /// Creates app-private directories that iCloud never backs up.
  private func environment(_ names: [String], result: FlutterResult) {
    do {
      let base = try FileManager.default.url(for: .applicationSupportDirectory,
        in: .userDomainMask, appropriateFor: nil, create: true)
      var paths: [String: String] = [:]
      for name in names {
        guard !name.isEmpty, !name.contains("/"), !name.contains("..") else { throw SchemaError.invalid }
        var directory = base.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try directory.setResourceValues(values)
        paths[name] = directory.path
      }
      let attributes = try FileManager.default.attributesOfFileSystem(forPath: base.path)
      result(["supported": true, "directories": paths,
        "freeBytes": (attributes[.systemFreeSize] as? NSNumber)?.int64Value ?? 0,
        "memoryBytes": ProcessInfo.processInfo.physicalMemory])
    } catch { result(FlutterError(code: "storage_error", message: nil, details: nil)) }
  }

  private func availability(_ locale: String) -> String {
    #if canImport(FoundationModels)
    if #available(iOS 26.0, *) {
      let model = SystemLanguageModel.default
      switch model.availability {
      case .available:
        return model.supportsLocale(Locale(identifier: locale)) ? "available" : "unsupported_language"
      case .unavailable(.appleIntelligenceNotEnabled): return "disabled"
      case .unavailable(.modelNotReady): return "model_not_ready"
      default: return "unsupported"
      }
    }
    #endif
    return "unsupported"
  }

  private func generate(_ args: [String: Any], result: @escaping FlutterResult) {
    guard generation == nil else { result(FlutterError(code: "busy", message: nil, details: nil)); return }
    let locale = args["locale"] as? String ?? "en"
    let status = availability(locale)
    guard status == "available" else { result(FlutterError(code: status, message: nil, details: nil)); return }
    #if canImport(FoundationModels)
    if #available(iOS 26.0, *) {
      guard let schemaJSON = args["schema"] as? [String: Any],
            let root = try? dynamicSchema(schemaJSON, name: "Response"),
            let schema = try? GenerationSchema(root: root, dependencies: []) else {
        result(FlutterError(code: "invalid_request", message: nil, details: nil)); return
      }
      let maxTokens = (args["maxTokens"] as? NSNumber)?.intValue ?? 512
      generation = Task { @MainActor [weak self] in
        defer { self?.generation = nil }
        do {
          // A fresh session per call: nothing is remembered between requests.
          let session = LanguageModelSession(
            model: SystemLanguageModel.default,
            tools: [],
            instructions: args["instructions"] as? String ?? ""
          )
          let options = GenerationOptions(sampling: .greedy, maximumResponseTokens: maxTokens)
          let reply = try await session.respond(
            to: args["input"] as? String ?? "", schema: schema, options: options)
          try Task.checkCancellation()
          result(reply.content.jsonString)
        } catch is CancellationError {
          result(FlutterError(code: "cancelled", message: nil, details: nil))
        } catch let error as LanguageModelSession.GenerationError {
          result(FlutterError(code: errorCode(for: error), message: nil, details: nil))
        } catch {
          // Do not forward provider error text: it may include private input.
          result(FlutterError(code: "generation_failed", message: nil, details: nil))
        }
      }
      return
    }
    #endif
    result(FlutterError(code: "unsupported", message: nil, details: nil))
  }

  /// Streams a free-text answer. Each event is new text to append.
  func startStream(_ args: [String: Any], sink: @escaping FlutterEventSink) {
    func fail(_ code: String) {
      sink(FlutterError(code: code, message: nil, details: nil))
      sink(FlutterEndOfEventStream)
    }
    guard generation == nil else { fail("busy"); return }
    let status = availability(args["locale"] as? String ?? "en")
    guard status == "available" else { fail(status); return }
    #if canImport(FoundationModels)
    if #available(iOS 26.0, *) {
      let maxTokens = (args["maxTokens"] as? NSNumber)?.intValue ?? 512
      generationIsStream = true
      generation = Task { @MainActor [weak self] in
        defer { self?.generation = nil; self?.generationIsStream = false }
        do {
          let session = LanguageModelSession(
            model: SystemLanguageModel.default,
            tools: [],
            instructions: args["instructions"] as? String ?? ""
          )
          let options = GenerationOptions(sampling: .greedy, maximumResponseTokens: maxTokens)
          var sent = ""
          for try await snapshot in session.streamResponse(to: args["input"] as? String ?? "", options: options) {
            try Task.checkCancellation()
            // Snapshots hold the text so far; send only what is new.
            let text = snapshot.content
            if text.count > sent.count, text.hasPrefix(sent) {
              sink(String(text.dropFirst(sent.count)))
              sent = text
            }
          }
          sink(FlutterEndOfEventStream)
        } catch is CancellationError {
          sink(FlutterEndOfEventStream)
        } catch let error as LanguageModelSession.GenerationError {
          fail(errorCode(for: error))
        } catch {
          // Do not forward provider error text: it may include private input.
          fail("generation_failed")
        }
      }
      return
    }
    #endif
    fail("unsupported")
  }

  /// Stops a running stream. Ignores a late cancel that arrives after the
  /// stream finished and another kind of request started.
  func cancelStream() {
    if generationIsStream { generation?.cancel() }
  }

  private func listen(_ locale: String, result: @escaping FlutterResult) {
    guard speechResult == nil else { result(FlutterError(code: "busy", message: nil, details: nil)); return }
    guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: locale)),
          recognizer.supportsOnDeviceRecognition, recognizer.isAvailable else {
      result(FlutterError(code: "speech_unavailable", message: nil, details: nil)); return
    }
    speechResult = result
    transcript = ""
    let id = UUID()
    speechID = id
    SFSpeechRecognizer.requestAuthorization { [weak self] status in
      Task { @MainActor in
        guard let self = self, self.speechID == id, self.speechResult != nil else { return }
        guard status == .authorized else { self.finishSpeech(error: "permission_denied"); return }
        AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
          Task { @MainActor in
            guard let self = self, self.speechID == id, self.speechResult != nil else { return }
            if granted { self.startSpeech(recognizer, id: id) }
            else { self.finishSpeech(error: "permission_denied") }
          }
        }
      }
    }
  }

  private func startSpeech(_ recognizer: SFSpeechRecognizer, id: UUID) {
    do {
      let audio = AVAudioSession.sharedInstance()
      try audio.setCategory(.record, mode: .measurement)
      try audio.setActive(true)
      let request = SFSpeechAudioBufferRecognitionRequest()
      request.requiresOnDeviceRecognition = true
      request.shouldReportPartialResults = true
      speechRequest = request
      let node = audioEngine.inputNode
      let format = node.outputFormat(forBus: 0)
      guard format.channelCount > 0, format.sampleRate > 0 else {
        finishSpeech(error: "speech_unavailable"); return
      }
      node.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in request.append(buffer) }
      hasAudioTap = true
      speechTask = recognizer.recognitionTask(with: request) { [weak self] response, error in
        Task { @MainActor in
          guard let self = self, self.speechID == id, self.speechResult != nil else { return }
          if let response = response {
            self.transcript = response.bestTranscription.formattedString
            if response.isFinal { self.finishSpeech(); return }
          }
          if error != nil { self.finishSpeech(error: self.transcript.isEmpty ? "no_speech" : nil) }
        }
      }
      audioEngine.prepare()
      try audioEngine.start()
      speechTimer = Timer.scheduledTimer(withTimeInterval: 45, repeats: false) { [weak self] _ in
        Task { @MainActor in self?.finishSpeech() }
      }
    } catch { finishSpeech(error: "speech_unavailable") }
  }

  private func finishSpeech(text: String? = nil, error: String? = nil) {
    let pending = speechResult
    speechResult = nil
    speechID = UUID()
    speechTimer?.invalidate()
    speechTimer = nil
    audioEngine.stop()
    if hasAudioTap { audioEngine.inputNode.removeTap(onBus: 0); hasAudioTap = false }
    speechRequest?.endAudio()
    speechTask?.cancel()
    speechTask = nil
    speechRequest = nil
    if pending != nil { try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
    if let error = error { pending?(FlutterError(code: error, message: nil, details: nil)) }
    else { pending?(String((text ?? transcript).prefix(1000))) }
  }

  public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
    generation?.cancel()
    finishSpeech(text: "")
  }
}
