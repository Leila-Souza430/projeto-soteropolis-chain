import 'dart:io';

import 'package:camera/camera.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

const String _fotosBucket = 'descarte-fotos';

/// No usable camera hardware was found, or the OS denied camera access.
class CameraUnavailableException implements Exception {
  final String message;
  const CameraUnavailableException(this.message);
}

/// Camera mechanics (open/close/capture) and the resulting photo's upload to
/// Supabase Storage.
///
/// Deliberately has no gallery-picker equivalent anywhere in this class or
/// its call sites: allowing an already-existing image from the gallery
/// would defeat the antifraude purpose of this screen entirely (SPEC
/// decision #2) - the photo must be captured live, at the moment the
/// citizen is actually standing at the ecoponto.
class CameraService {
  CameraController? _controller;
  static const _uuid = Uuid();

  CameraController? get controller => _controller;

  /// Opens the device's back camera. Throws [CameraUnavailableException] on
  /// no hardware or a denied permission (the `camera` plugin surfaces a
  /// denied OS permission as a [CameraException] from `initialize()`, which
  /// this wraps into the app's own exception type).
  Future<CameraController> initialize() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) {
      throw const CameraUnavailableException(
        'Nenhuma câmera disponível neste aparelho.',
      );
    }

    final back = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );

    final controller = CameraController(
      back,
      ResolutionPreset.high,
      enableAudio: false, // photo-only capture, no video/audio needed
    );

    try {
      await controller.initialize();
    } on CameraException catch (e) {
      await controller.dispose();
      throw CameraUnavailableException(
        e.code == 'CameraAccessDenied'
            ? 'Permissão de câmera negada.'
            : 'Não foi possível abrir a câmera.',
      );
    }

    _controller = controller;
    return controller;
  }

  /// Captures a single still photo. GPS/timestamp are read by the caller
  /// (camera_descarte_screen.dart) at this same instant via
  /// LocationService - kept as two separate calls made back-to-back rather
  /// than bundled into this method, so the screen can show location-fix
  /// progress independently of shutter feedback.
  Future<XFile> capturePhoto() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      throw const CameraUnavailableException('Câmera não inicializada.');
    }
    return controller.takePicture();
  }

  /// Uploads [photo] to the `descarte-fotos` bucket under the citizen's own
  /// path prefix and returns its public URL, ready for `foto_url` in
  /// POST /descartes.
  ///
  /// Path convention `{userId}/{uuid}.jpg` is fixed by the pending storage
  /// RLS policy (migrations/fase4_descarte_fotos_storage_policy.sql), which
  /// checks the path's first segment against auth.uid() - it must be
  /// followed exactly or the upload is rejected once that policy is applied.
  Future<String> uploadPhoto(XFile photo, String userId) async {
    final path = '$userId/${_uuid.v4()}.jpg';
    final storage = Supabase.instance.client.storage.from(_fotosBucket);
    await storage.upload(
      path,
      File(photo.path),
      fileOptions: const FileOptions(contentType: 'image/jpeg'),
    );
    return storage.getPublicUrl(path);
  }

  Future<void> dispose() async {
    await _controller?.dispose();
    _controller = null;
  }
}
