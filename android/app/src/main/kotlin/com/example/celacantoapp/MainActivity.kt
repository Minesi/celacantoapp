package com.example.celacantoapp

import android.content.Intent
import android.content.ContentValues
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
	private val channelName = "celacantoapp/relatorios"

	override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
		super.configureFlutterEngine(flutterEngine)
		MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
			when (call.method) {
				"salvarNoDownloads" -> salvarNoDownloads(call.argument<String>("nomeArquivo"), call.argument<ByteArray>("bytes"), result)
				"abrirRelatorio" -> abrirRelatorio(call.argument<String>("uri"), result)
				else -> result.notImplemented()
			}
		}
	}

	private fun salvarNoDownloads(nomeArquivo: String?, bytes: ByteArray?, result: MethodChannel.Result) {
		if (nomeArquivo == null || bytes == null) {
			result.error("ARGUMENTOS_INVALIDOS", "Nome ou conteúdo do relatório ausente.", null)
			return
		}
		try {
			val values = ContentValues().apply {
				put(MediaStore.Downloads.DISPLAY_NAME, nomeArquivo)
				put(MediaStore.Downloads.MIME_TYPE, "application/vnd.openxmlformats-officedocument.wordprocessingml.document")
				if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
					put(MediaStore.Downloads.RELATIVE_PATH, "Download/Celacanto")
					put(MediaStore.Downloads.IS_PENDING, 1)
				}
			}
			val uri = contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
				?: throw IllegalStateException("Não foi possível criar o arquivo em Downloads.")
			contentResolver.openOutputStream(uri)?.use { it.write(bytes) }
				?: throw IllegalStateException("Não foi possível gravar o relatório.")
			if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
				values.clear()
				values.put(MediaStore.Downloads.IS_PENDING, 0)
				contentResolver.update(uri, values, null, null)
			}
			result.success(uri.toString())
		} catch (e: Exception) {
			result.error("FALHA_AO_SALVAR", e.message, null)
		}
	}

	private fun abrirRelatorio(uriTexto: String?, result: MethodChannel.Result) {
		if (uriTexto == null) {
			result.error("URI_INVALIDA", "Localização do relatório ausente.", null)
			return
		}
		try {
			val intent = Intent(Intent.ACTION_VIEW).apply {
				setDataAndType(Uri.parse(uriTexto), "application/vnd.openxmlformats-officedocument.wordprocessingml.document")
				addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
			}
			startActivity(Intent.createChooser(intent, "Abrir relatório"))
			result.success(true)
		} catch (e: Exception) {
			result.success(false)
		}
	}
}
