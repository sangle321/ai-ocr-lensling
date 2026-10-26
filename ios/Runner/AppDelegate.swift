import Flutter
import UIKit
import NaturalLanguage
import SwiftUI
import Translation

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var translationBridge: AppleTranslationBridge?
  private var importBridge: ImageImportBridge?
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // History is local-only, including exclusion from iCloud device backups.
    if let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
      var root = support.appendingPathComponent("lensling", isDirectory: true)
      do {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try root.setResourceValues(values)
      } catch { NSLog("Lensling could not prepare local storage") }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "LenslingNative") else { return }
    translationBridge = AppleTranslationBridge(registrar: registrar)
    importBridge = ImageImportBridge(messenger: registrar.messenger())
  }
}

// A view-backed session works on iOS 18, including the system download prompt.
// Keep it attached to the Flutter view hierarchy for the session's lifetime.
@MainActor
final class TranslationJob: ObservableObject {
  @Published var configuration: TranslationSession.Configuration?
  var texts: [String] = []
  var downloadOnly = false
  var completion: FlutterResult?

  func perform(using session: TranslationSession) async {
    guard let complete = completion else { return }
    do {
      if downloadOnly {
        try await session.prepareTranslation()
        completion = nil
        complete(nil)
      } else {
        let requests = texts.enumerated().map {
          TranslationSession.Request(sourceText: $0.element, clientIdentifier: String($0.offset))
        }
        let responses = try await session.translations(from: requests)
        completion = nil
        complete(responses.map(\.targetText))
      }
    } catch {
      completion = nil
      complete(FlutterError(code: "TRANSLATION_FAILED",
        message: "Apple translation could not finish. Check the downloaded languages and retry. Your recognized text is saved.",
        details: nil))
    }
  }
}

struct TranslationHost: View {
  @ObservedObject var job: TranslationJob
  var body: some View {
    Color.clear
      .translationTask(job.configuration) { session in
        await job.perform(using: session)
      }
  }
}

@MainActor
final class AppleTranslationBridge {
  private let channel: FlutterMethodChannel
  private let registrar: FlutterPluginRegistrar
  private let job = TranslationJob()
  private var host: UIHostingController<TranslationHost>?

  init(registrar: FlutterPluginRegistrar) {
    self.registrar = registrar
    channel = FlutterMethodChannel(name: "app.lensling/translation", binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { return }
      Task { @MainActor in await self.handle(call, result: result) }
    }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) async {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "supportedLanguages":
      let available = await LanguageAvailability().supportedLanguages
      result(Array(Set(available.compactMap { $0.languageCode?.identifier })).sorted())
    case "identify":
      let recognizer = NLLanguageRecognizer()
      recognizer.processString(String((args["text"] as? String ?? "").prefix(10000)))
      let hypotheses = recognizer.languageHypotheses(withMaximum: 1)
      if let language = recognizer.dominantLanguage, (hypotheses[language] ?? 0) >= 0.5 {
        result(language.rawValue.components(separatedBy: "-").first)
      } else { result(nil) }
    case "pairStatus":
      guard let source = args["source"] as? String, let target = args["target"] as? String else {
        result("unsupported"); return
      }
      if source == target { result("installed"); return }
      let status = await LanguageAvailability().status(from: Locale.Language(identifier: source),
        to: Locale.Language(identifier: target))
      switch status {
      case .installed: result("installed")
      case .supported: result("downloadable")
      default: result("unsupported")
      }
    case "downloadPair", "translate":
      guard job.completion == nil else {
        result(FlutterError(code: "BUSY", message: "Wait for the current translation to finish.", details: nil)); return
      }
      guard let source = args["source"] as? String, let target = args["target"] as? String else {
        result(FlutterError(code: "INVALID_PAIR", message: "Choose both languages.", details: nil)); return
      }
      let texts = args["texts"] as? [String] ?? []
      if source == target { result(call.method == "translate" ? texts : nil); return }
      // Translation must not implicitly download models. Downloads have their own
      // explicit button and system permission sheet.
      let status = await LanguageAvailability().status(from: Locale.Language(identifier: source),
        to: Locale.Language(identifier: target))
      if call.method == "translate" && status != .installed {
        result(FlutterError(code: "PACK_REQUIRED", message: "Open Language packs and download this pair first.", details: nil)); return
      }
      if status == .unsupported {
        result(FlutterError(code: "UNSUPPORTED_PAIR", message: "This language pair is unavailable on this device.", details: nil)); return
      }
      guard attachHost() else {
        result(FlutterError(code: "NO_VIEW", message: "Open the app and retry translation.", details: nil)); return
      }
      job.texts = texts
      job.downloadOnly = call.method == "downloadPair"
      job.completion = result
      var configuration = TranslationSession.Configuration(
        source: Locale.Language(identifier: source), target: Locale.Language(identifier: target))
      if job.configuration?.source == configuration.source && job.configuration?.target == configuration.target {
        configuration = job.configuration!
        configuration.invalidate()
      }
      job.configuration = configuration
    case "deleteLanguage":
      result(FlutterError(code: "SYSTEM_MANAGED", message: "Manage Apple translation languages in system settings.", details: nil))
    case "dispose":
      job.completion?(FlutterError(code: "CANCELLED", message: "Translation cancelled.", details: nil))
      job.completion = nil
      job.configuration = nil
      host?.willMove(toParent: nil); host?.view.removeFromSuperview(); host?.removeFromParent(); host = nil
      result(nil)
    default: result(FlutterMethodNotImplemented)
    }
  }

  private func attachHost() -> Bool {
    if host != nil { return true }
    guard let parent = registrar.viewController, parent.view.window != nil else { return false }
    let controller = UIHostingController(rootView: TranslationHost(job: job))
    controller.view.backgroundColor = .clear
    controller.view.isUserInteractionEnabled = false
    parent.addChild(controller)
    parent.view.addSubview(controller.view)
    controller.view.frame = CGRect(x: 0, y: 0, width: 1, height: 1)
    controller.didMove(toParent: parent)
    host = controller
    return true
  }
}

final class ImageImportBridge {
  private let channel: FlutterMethodChannel
  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "app.lensling/import", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      let group = Bundle.main.object(forInfoDictionaryKey: "LenslingAppGroup") as? String ?? ""
      guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else {
        // An unsigned development build may not have App Groups enabled yet.
        result(nil); return
      }
      let shared = container.appendingPathComponent("pending.jpg")
      switch call.method {
      case "takeImage":
        guard FileManager.default.fileExists(atPath: shared.path) else { result(nil); return }
        do {
          let local = FileManager.default.temporaryDirectory.appendingPathComponent("shared-\(UUID().uuidString).jpg")
          try FileManager.default.moveItem(at: shared, to: local)
          result(local.path)
        } catch {
          result(FlutterError(code: "IMPORT_FAILED", message: "Could not open the shared photo.", details: nil))
        }
      case "releaseImage":
        if let args = call.arguments as? [String: Any], let path = args["path"] as? String {
          let file = URL(fileURLWithPath: path).standardizedFileURL
          if file.deletingLastPathComponent() == FileManager.default.temporaryDirectory.standardizedFileURL &&
              file.lastPathComponent.hasPrefix("shared-") { try? FileManager.default.removeItem(at: file) }
        }
        result(nil)
      default: result(FlutterMethodNotImplemented)
      }
    }
  }
}
