import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

/// Outcome of a Cloudinary upload operation.
///
/// [url] is the secure HTTPS URL of the uploaded image.
/// [publicId] is the Cloudinary public ID for later deletion.
class CloudinaryUploadResult {
  final String url;
  final String publicId;

  const CloudinaryUploadResult({
    required this.url,
    required this.publicId,
  });
}

/// Exception thrown when a Cloudinary operation fails.
///
/// Carries a [message] safe to display to the user and an optional
/// machine-readable [code] for programmatic handling.
class CloudinaryException implements Exception {
  final String message;
  final String? code;

  const CloudinaryException(this.message, {this.code});

  @override
  String toString() => 'CloudinaryException: $message${code != null ? ' ($code)' : ''}';
}

/// Reusable Cloudinary image upload service.
///
/// This service is **module-agnostic** — it knows nothing about Events,
/// Firestore, AppState, or any other domain concept. Every module in the
/// app (Events, Lost & Found, Issues, Profiles, Clubs, Gallery) can reuse
/// the same instance.
///
/// ## Architecture
///
/// ```
/// UI → AppState → DomainService → CloudinaryService → Cloudinary API
/// ```
///
/// [CloudinaryService] sits at the infrastructure layer, below all domain
/// services. It is not a [ChangeNotifier] — it returns results directly
/// and lets callers decide how to propagate state.
///
/// ## Usage
///
/// ```dart
/// final cloudinary = CloudinaryService(
///   cloudName: 'xijxwdly',
///   uploadPreset: 'campus_connect_events',
/// );
///
/// // Pick from gallery
/// final file = await cloudinary.pickImageFromGallery();
///
/// // Upload
/// final result = await cloudinary.uploadImage(file);
/// print(result.url); // https://res.cloudinary.com/...
/// ```
class CloudinaryService {
  /// Cloudinary cloud name used to construct API URLs.
  final String cloudName;

  /// Unsigned upload preset configured in the Cloudinary dashboard.
  final String uploadPreset;

  /// Optional folder path within Cloudinary (e.g. 'events').
  final String? folder;

  /// Timeout for HTTP requests in seconds.
  final int timeoutSeconds;

  final ImagePicker _picker;

  CloudinaryService({
    required this.cloudName,
    required this.uploadPreset,
    this.folder,
    this.timeoutSeconds = 30,
    ImagePicker? imagePicker,
  }) : _picker = imagePicker ?? ImagePicker();

  /// The Cloudinary upload endpoint for this instance.
  String get _uploadEndpoint =>
      'https://api.cloudinary.com/v1_1/$cloudName/image/upload';

  // ── Image Picking ───────────────────────────────────────────────

  /// Opens the device gallery and returns the selected image file.
  ///
  /// Returns `null` if the user cancels the picker.
  ///
  /// Throws [CloudinaryException] if the image source is not available
  /// or the selected file cannot be read.
  Future<File?> pickImageFromGallery({
    int maxWidth = 1920,
    int maxHeight = 1080,
    int imageQuality = 85,
  }) async {
    try {
      final xFile = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: maxWidth.toDouble(),
        maxHeight: maxHeight.toDouble(),
        imageQuality: imageQuality,
      );
      if (xFile == null) return null;
      return File(xFile.path);
    } on Exception catch (e) {
      throw CloudinaryException(
        'Could not open gallery: ${_friendlyMessage(e)}',
        code: 'gallery-error',
      );
    }
  }

  /// Opens the device camera and returns the captured image file.
  ///
  /// Returns `null` if the user cancels the capture.
  ///
  /// Throws [CloudinaryException] if the camera is not available
  /// or the captured file cannot be read.
  Future<File?> pickImageFromCamera({
    int maxWidth = 1920,
    int maxHeight = 1080,
    int imageQuality = 85,
  }) async {
    try {
      final xFile = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: maxWidth.toDouble(),
        maxHeight: maxHeight.toDouble(),
        imageQuality: imageQuality,
      );
      if (xFile == null) return null;
      return File(xFile.path);
    } on Exception catch (e) {
      throw CloudinaryException(
        'Could not open camera: ${_friendlyMessage(e)}',
        code: 'camera-error',
      );
    }
  }

  // ── Upload ──────────────────────────────────────────────────────

  /// Uploads [imageFile] to Cloudinary using the unsigned upload preset.
  ///
  /// Returns a [CloudinaryUploadResult] with the secure URL and public ID.
  ///
  /// Throws [CloudinaryException] for:
  /// - No internet connection
  /// - Invalid or unreadable image file
  /// - Cloudinary API errors (auth, quota, etc.)
  /// - HTTP timeout
  Future<CloudinaryUploadResult> uploadImage(
    File imageFile, {
    void Function(int sent, int total)? onProgress,
  }) async {
    // Validate the file exists and is readable.
    if (!await imageFile.exists()) {
      throw const CloudinaryException(
        'Image file not found.',
        code: 'file-not-found',
      );
    }

    final length = await imageFile.length();
    if (length == 0) {
      throw const CloudinaryException(
        'Image file is empty.',
        code: 'empty-file',
      );
    }

    // Build the multipart request.
    final uri = Uri.parse(_uploadEndpoint);
    final request = http.MultipartRequest('POST', uri)
      ..fields['upload_preset'] = uploadPreset
      ..files.add(await http.MultipartFile.fromPath('file', imageFile.path));

    if (folder != null && folder!.isNotEmpty) {
      request.fields['folder'] = folder!;
    }

    // Send with timeout.
    try {
      final streamed = await request.send().timeout(
        Duration(seconds: timeoutSeconds),
        onTimeout: () => throw CloudinaryException(
          'Upload timed out after $timeoutSeconds seconds.',
          code: 'timeout',
        ),
      );

      final response = await http.Response.fromStream(streamed);

      if (response.statusCode == 200) {
        final body = _parseJson(response.body);
        final url = body['secure_url'] as String?;
        final publicId = body['public_id'] as String?;

        if (url == null || url.isEmpty) {
          throw const CloudinaryException(
            'Cloudinary returned success but no URL.',
            code: 'missing-url',
          );
        }

        return CloudinaryUploadResult(
          url: url,
          publicId: publicId ?? '',
        );
      } else {
        final body = _tryParseJson(response.body);
        final errorMsg = body?['error']?['message'] as String? ??
            'HTTP ${response.statusCode}';
        throw CloudinaryException(
          'Upload failed: $errorMsg',
          code: 'upload-${response.statusCode}',
        );
      }
    } on CloudinaryException {
      rethrow;
    } on http.ClientException {
      throw const CloudinaryException(
        'No internet connection.',
        code: 'no-internet',
      );
    } on SocketException {
      throw const CloudinaryException(
        'No internet connection.',
        code: 'no-internet',
      );
    } on Exception catch (e) {
      throw CloudinaryException(
        'Upload failed: ${_friendlyMessage(e)}',
        code: 'upload-error',
      );
    }
  }

  // ── Deletion (stub) ─────────────────────────────────────────────

  /// Deletes an image from Cloudinary by its [publicId].
  ///
  /// **Stub**: Cloudinary deletion requires a signed request with the
  /// API secret, which must be handled by a backend service. This method
  /// is provided as a placeholder for future backend integration.
  ///
  /// Throws [UnimplementedError] — do not call in production until a
  /// backend deletion endpoint is available.
  Future<void> deleteImage(String publicId) async {
    throw UnimplementedError(
      'Cloudinary deletion requires a signed request. '
      'Implement a backend endpoint that signs the deletion API call '
      'using the Cloudinary API secret, then call that endpoint here.',
    );
  }

  // ── Helpers ─────────────────────────────────────────────────────

  /// Parses a JSON string into a [Map]. Throws [CloudinaryException] on
  /// malformed input.
  Map<String, dynamic> _parseJson(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      throw const CloudinaryException(
        'Unexpected response format from Cloudinary.',
        code: 'bad-response',
      );
    } on CloudinaryException {
      rethrow;
    } on Exception {
      throw const CloudinaryException(
        'Could not parse Cloudinary response.',
        code: 'parse-error',
      );
    }
  }

  /// Tries to parse JSON; returns `null` on failure.
  Map<String, dynamic>? _tryParseJson(String raw) {
    try {
      return _parseJson(raw);
    } on CloudinaryException {
      return null;
    }
  }

  /// Converts an exception into a user-friendly message.
  String _friendlyMessage(Object e) {
    final s = e.toString();
    // Strip the exception class name prefix if present.
    if (s.contains(': ')) {
      return s.substring(s.indexOf(': ') + 2);
    }
    return s;
  }
}
