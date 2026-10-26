package app.lensling.lensling

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private var translation: TranslationBridge? = null
    private var imports: MethodChannel? = null
    private var pendingImage: String? = null
    private var importError: String? = null
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        translation = TranslationBridge(flutterEngine.dartExecutor.binaryMessenger)
        imports = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app.lensling/import")
        imports!!.setMethodCallHandler { call, result ->
            when (call.method) {
                "translationInfo" -> {
                    try {
                        startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("https://translate.google.com/about/")))
                        result.success(null)
                    } catch (error: Exception) {
                        result.error("NO_BROWSER", "No browser is available on this device.", null)
                    }
                }
                "takeImage" -> {
                    if (importError != null) {
                        result.error("IMPORT_FAILED", importError, null)
                        importError = null
                    } else {
                        val image = pendingImage
                        pendingImage = null
                        result.success(image)
                    }
                }
                "releaseImage" -> {
                    val path = call.argument<String>("path")
                    if (path != null) {
                        val file = File(path).canonicalFile
                        if (file.parentFile == File(cacheDir, "shared").canonicalFile) { file.delete() }
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        receiveImage(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        receiveImage(intent)
    }

    private fun receiveImage(incoming: Intent?) {
        if (incoming?.action != Intent.ACTION_SEND || incoming.type?.startsWith("image/") != true) { return }
        @Suppress("DEPRECATION")
        val uri = incoming.getParcelableExtra<Uri>(Intent.EXTRA_STREAM) ?: return
        // Never interpret external paths or fetch network URLs.
        if (uri.scheme != "content") { return }
        worker.execute {
            var output: File? = null
            try {
                val folder = File(cacheDir, "shared").apply { mkdirs() }
                output = File.createTempFile("import_", ".image", folder)
                contentResolver.openInputStream(uri).use { input ->
                    requireNotNull(input) { "This photo is no longer available." }
                    output.outputStream().use { target ->
                        val buffer = ByteArray(65536)
                        var total = 0L
                        while (true) {
                            val count = input.read(buffer)
                            if (count < 0) { break }
                            total += count
                            require(total <= 40L * 1024 * 1024) { "Choose a photo smaller than 40 MB." }
                            target.write(buffer, 0, count)
                        }
                    }
                }
                val path = output.absolutePath
                main.post {
                    pendingImage?.let { File(it).delete() }
                    pendingImage = path
                    imports?.invokeMethod("imageAvailable", null)
                }
            } catch (error: Exception) {
                output?.delete()
                main.post {
                    importError = "Could not import this shared image. Use a JPEG or PNG under 40 MB."
                    imports?.invokeMethod("imageAvailable", null)
                }
            }
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        translation?.dispose()
        imports?.setMethodCallHandler(null)
        imports = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onDestroy() {
        worker.shutdown()
        super.onDestroy()
    }
}
