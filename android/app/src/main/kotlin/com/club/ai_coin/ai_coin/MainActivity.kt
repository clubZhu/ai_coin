package com.club.ai_coin.ai_coin

import android.content.ClipData
import android.content.Intent
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val recordExportChannel = "crypto_pilot/record_export"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            recordExportChannel,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "shareCsv" -> shareCsv(call.argument("title"), call.argument("fileName"), call.argument("content"), result)
                else -> result.notImplemented()
            }
        }
    }

    private fun shareCsv(
        title: String?,
        fileName: String?,
        content: String?,
        result: MethodChannel.Result,
    ) {
        try {
            val exportDir = File(cacheDir, "exports")
            if (!exportDir.exists()) exportDir.mkdirs()

            val exportFile = File(exportDir, safeFileName(fileName ?: "cryptopilot_records.csv"))
            exportFile.writeText(content.orEmpty(), Charsets.UTF_8)

            val uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", exportFile)
            val shareTitle = title ?: "分享交易记录"
            val shareIntent = Intent(Intent.ACTION_SEND).apply {
                type = "text/csv"
                putExtra(Intent.EXTRA_STREAM, uri)
                putExtra(Intent.EXTRA_SUBJECT, shareTitle)
                putExtra(Intent.EXTRA_TEXT, "CryptoPilot 交易记录导出")
                clipData = ClipData.newUri(contentResolver, shareTitle, uri)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }

            startActivity(Intent.createChooser(shareIntent, shareTitle))
            result.success(null)
        } catch (error: Exception) {
            result.error("SHARE_FAILED", error.localizedMessage, null)
        }
    }

    private fun safeFileName(fileName: String): String {
        val cleaned = fileName.replace(Regex("[^A-Za-z0-9._-]"), "_")
        return cleaned.ifBlank { "cryptopilot_records.csv" }
    }
}
