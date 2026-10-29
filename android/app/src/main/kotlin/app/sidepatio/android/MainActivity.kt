package app.sidepatio.android

import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.OpenableColumns
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private var pendingPick: MethodChannel.Result? = null
    private val pickCopier = Executors.newSingleThreadExecutor()
    private val mainThread = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // App updates (lib/services/update/apk_installer.dart).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app.sidepatio.android/apk_installer")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "canInstall" -> result.success(packageManager.canRequestPackageInstalls())
                        "openInstallPermission" -> {
                            startActivity(
                                Intent(
                                    Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                    Uri.parse("package:$packageName"),
                                ),
                            )
                            result.success(null)
                        }
                        "install" -> {
                            val path = call.argument<String>("path")
                            if (path == null) {
                                result.error("no_path", "No APK path was given.", null)
                            } else {
                                install(File(path))
                                result.success(null)
                            }
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    result.error("install_failed", e.message ?: e.toString(), null)
                }
            }
        // Opening files (lib/utils/android_document_picker.dart).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app.sidepatio.android/file_picker")
            .setMethodCallHandler { call, result ->
                if (call.method == "pickFiles") pickFiles(call.arguments as? Map<*, *>, result)
                else result.notImplemented()
            }
    }

    /** Android's installer confirms, then closes and replaces this app. */
    private fun install(apk: File) {
        val uri = FileProvider.getUriForFile(this, "$packageName.updates", apk)
        startActivity(
            Intent(Intent.ACTION_VIEW)
                .setDataAndType(uri, "application/vnd.android.package-archive")
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK),
        )
    }

    /**
     * "Get content" in Android's app chooser, the sheet other apps show, so
     * file managers such as Cx File Explorer can hand over a file. The storage
     * picker the file_picker plugin opens lists storage providers only.
     */
    private fun pickFiles(args: Map<*, *>?, result: MethodChannel.Result) {
        if (pendingPick != null) {
            result.error("busy", "A file window is already open.", null)
            return
        }
        val mimeTypes = (args?.get("mimeTypes") as? List<*>)?.filterIsInstance<String>().orEmpty()
        val request = Intent(Intent.ACTION_GET_CONTENT)
            .addCategory(Intent.CATEGORY_OPENABLE)
            .putExtra(Intent.EXTRA_ALLOW_MULTIPLE, args?.get("multiple") == true)
        if (mimeTypes.size == 1) {
            request.type = mimeTypes[0]
        } else {
            request.type = "*/*"
            if (mimeTypes.isNotEmpty()) request.putExtra(Intent.EXTRA_MIME_TYPES, mimeTypes.toTypedArray())
        }
        val title = args?.get("title") as? String ?: "Choose a file"
        pendingPick = result
        try {
            startActivityForResult(Intent.createChooser(request, title), PICK_FILES)
        } catch (e: Exception) {
            pendingPick = null
            result.error("pick_failed", e.message ?: e.toString(), null)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != PICK_FILES) {
            super.onActivityResult(requestCode, resultCode, data)
            return
        }
        val result = pendingPick ?: return
        pendingPick = null
        val uris = mutableListOf<Uri>()
        data?.clipData?.let { clip -> for (i in 0 until clip.itemCount) uris.add(clip.getItemAt(i).uri) }
        if (uris.isEmpty()) data?.data?.let { uris.add(it) }
        if (resultCode != RESULT_OK || uris.isEmpty()) {
            result.success(emptyList<Map<String, Any>>())
            return
        }
        // Copied off the main thread: a pick from a network share can be large.
        pickCopier.execute {
            try {
                val root = File(cacheDir, "picked")
                root.deleteRecursively()
                val pick = File(root, System.currentTimeMillis().toString())
                val files = uris.mapIndexed { i, uri -> copyPicked(uri, File(pick, i.toString())) }
                mainThread.post { result.success(files) }
            } catch (e: Exception) {
                mainThread.post { result.error("pick_failed", e.message ?: e.toString(), null) }
            }
        }
    }

    private fun copyPicked(uri: Uri, dir: File): Map<String, Any> {
        var name: String? = null
        contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c ->
            if (c.moveToFirst()) name = c.getString(0)
        }
        // A display name is only a label: keep its last segment, never a path.
        val safe = File(name ?: uri.lastPathSegment ?: "file").name.ifBlank { "file" }
        dir.mkdirs()
        val out = File(dir, safe)
        val input = contentResolver.openInputStream(uri) ?: throw IOException("Couldn't read $safe")
        input.use { source -> out.outputStream().use { source.copyTo(it) } }
        return mapOf("path" to out.path, "name" to safe, "size" to out.length())
    }

    private companion object {
        const val PICK_FILES = 4127
    }
}
