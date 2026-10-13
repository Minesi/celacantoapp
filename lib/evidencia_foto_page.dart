// lib/evidencia_foto_page.dart
// Captura da foto de evidência (ex.: fita do contador de partículas) exigida antes de
// finalizar determinados ensaios em campo.
import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

Future<String?> abrirCapturaFotoEvidencia(BuildContext context) =>
  Navigator.push<String>(context, MaterialPageRoute(builder: (_) => const EvidenciaFotoPage()));

class EvidenciaFotoPage extends StatefulWidget {
  const EvidenciaFotoPage({super.key});

  @override
  State<EvidenciaFotoPage> createState() => _EvidenciaFotoPageState();
}

class _EvidenciaFotoPageState extends State<EvidenciaFotoPage> with WidgetsBindingObserver {
  CameraController? _cameraController;
  bool _erroNaCamera = false;
  bool _capturando = false;
  bool _cameraSuspensa = false;
  bool _inicializandoCamera = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _inicializarCamera();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      _cameraSuspensa = true;
      final controller = _cameraController;
      _cameraController = null;
      unawaited(controller?.dispose() ?? Future<void>.value());
    } else if (state == AppLifecycleState.resumed && mounted) {
      _cameraSuspensa = false;
      unawaited(_inicializarCamera());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_cameraController?.dispose() ?? Future<void>.value());
    super.dispose();
  }

  Future<void> _inicializarCamera() async {
    if (_inicializandoCamera) return;
    _inicializandoCamera = true;
    try {
      final cameras = await availableCameras();
      if (!mounted || _cameraSuspensa) return;
      if (cameras.isEmpty) {
        setState(() => _erroNaCamera = true);
        return;
      }
      final controller = CameraController(cameras.first, ResolutionPreset.high, enableAudio: false);
      await controller.initialize();
      if (!mounted || _cameraSuspensa) {
        await controller.dispose();
        return;
      }
      _cameraController = controller;
      setState(() => _erroNaCamera = false);
    } catch (e) {
      debugPrint('Erro ao abrir a câmera para evidência: $e');
      if (mounted && !_cameraSuspensa) setState(() => _erroNaCamera = true);
    } finally {
      _inicializandoCamera = false;
    }
  }

  Future<void> _capturarFoto() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized || _capturando) return;
    setState(() => _capturando = true);
    try {
      final arquivo = await _cameraController!.takePicture();
      if (!mounted) return;
      Navigator.of(context).pop(arquivo.path);
    } catch (e) {
      debugPrint('Falha ao capturar foto de evidência: $e');
      setState(() => _capturando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: const Text('Foto da Evidência'), backgroundColor: Colors.black),
      body: _erroNaCamera
          ? const Center(
              child: Text('Câmera indisponível neste dispositivo.', style: TextStyle(color: Colors.white)),
            )
          : (_cameraController == null || !_cameraController!.value.isInitialized)
              ? const Center(child: CircularProgressIndicator())
              : Stack(
                  alignment: Alignment.bottomCenter,
                  children: [
                    CameraPreview(_cameraController!),
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: FloatingActionButton(
                        onPressed: _capturarFoto,
                        backgroundColor: Colors.white,
                        child: _capturando
                            ? const CircularProgressIndicator()
                            : const Icon(Icons.camera_alt, color: Colors.black),
                      ),
                    ),
                  ],
                ),
    );
  }
}
