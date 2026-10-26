package app.lensling.lensling

import com.google.android.gms.tasks.Tasks
import com.google.mlkit.common.model.DownloadConditions
import com.google.mlkit.common.model.RemoteModelManager
import com.google.mlkit.nl.languageid.LanguageIdentification
import com.google.mlkit.nl.translate.TranslateLanguage
import com.google.mlkit.nl.translate.Translation
import com.google.mlkit.nl.translate.TranslateRemoteModel
import com.google.mlkit.nl.translate.Translator
import com.google.mlkit.nl.translate.TranslatorOptions
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** Native clients live only as long as their asynchronous operation. No cloud API. */
class TranslationBridge(messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "app.lensling/translation")
    private val identifier = LanguageIdentification.getClient()
    private val models = RemoteModelManager.getInstance()
    private val clients = mutableSetOf<Translator>()

    init { channel.setMethodCallHandler(::handle) }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        if (call.method == "supportedLanguages") { result.success(TranslateLanguage.getAllLanguages()); return }
        if (call.method == "identify") {
            val text = call.argument<String>("text").orEmpty().take(10000)
            identifier.identifyLanguage(text)
                .addOnSuccessListener { result.success(if (it == "und") null else it) }
                .addOnFailureListener { result.error("IDENTIFY_FAILED", "Choose the source language manually.", null) }
            return
        }
        if (call.method == "dispose") { dispose(); result.success(null); return }
        if (call.method == "deleteLanguage") {
            val code = validLanguage(call.argument("language"))
            if (code == null) { result.error("INVALID_LANGUAGE", "Choose a supported language.", null); return }
            if (code == "en") { result.success(null); return }
            models.deleteDownloadedModel(TranslateRemoteModel.Builder(code).build())
                .addOnSuccessListener { result.success(null) }
                .addOnFailureListener { result.error("DELETE_FAILED", "Could not remove this language pack. Try again.", null) }
            return
        }
        if (call.method !in setOf("pairStatus", "downloadPair", "translate")) { result.notImplemented(); return }
        val source = validLanguage(call.argument("source"))
        val target = validLanguage(call.argument("target"))
        if (source == null || target == null) {
            if (call.method == "pairStatus") { result.success("unsupported") }
            else { result.error("UNSUPPORTED_PAIR", "This language pair is unavailable on this device.", null) }
            return
        }
        when (call.method) {
            "pairStatus" -> {
                // English is built into the translation infrastructure, not a downloadable model.
                val checks = if (source == target) emptyList() else
                    setOf(source, target).filter { it != "en" }.map {
                        models.isModelDownloaded(TranslateRemoteModel.Builder(it).build())
                    }
                Tasks.whenAllSuccess<Boolean>(checks)
                    .addOnSuccessListener { states -> result.success(if (states.all { it }) "installed" else "downloadable") }
                    .addOnFailureListener { result.error("STATUS_FAILED", "Could not check downloaded language packs.", null) }
            }
            "downloadPair" -> {
                if (source == target) { result.success(null); return }
                val client = newClient(source, target)
                val conditions = DownloadConditions.Builder().apply {
                    if (call.argument<Boolean>("wifiOnly") != false) { requireWifi() }
                }.build()
                client.downloadModelIfNeeded(conditions)
                    .addOnSuccessListener { close(client); result.success(null) }
                    .addOnFailureListener {
                        close(client)
                        result.error("DOWNLOAD_FAILED", "Download could not finish. Connect to Wi-Fi, check free storage and retry.", null)
                    }
            }
            "translate" -> {
                val texts = call.argument<List<String>>("texts")
                if (texts == null || texts.isEmpty()) { result.success(emptyList<String>()); return }
                if (source == target) { result.success(texts); return }
                val client = newClient(source, target)
                // ML Kit has a single-string native API. Flutter sends one batch;
                // native tasks preserve response order and share one client.
                Tasks.whenAllSuccess<String>(texts.map { client.translate(it) })
                    .addOnSuccessListener { translated -> close(client); result.success(translated) }
                    .addOnFailureListener {
                        close(client)
                        result.error("TRANSLATION_FAILED", "On-device translation failed. Check Language packs and try again. Your text is saved.", null)
                    }
            }
        }
    }

    private fun validLanguage(value: String?): String? =
        value?.let { TranslateLanguage.fromLanguageTag(it) }

    private fun newClient(source: String, target: String): Translator =
        Translation.getClient(TranslatorOptions.Builder()
            .setSourceLanguage(source).setTargetLanguage(target).build()).also { clients.add(it) }

    private fun close(client: Translator) { clients.remove(client); client.close() }

    fun dispose() {
        clients.toList().forEach { it.close() }
        clients.clear()
        identifier.close()
        channel.setMethodCallHandler(null)
    }
}
