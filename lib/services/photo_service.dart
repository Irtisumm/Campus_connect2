import 'package:flutter/material.dart';

class PhotoUploadService extends ChangeNotifier {
  final List<PhotoFile> _uploadedPhotos = [];

  List<PhotoFile> get uploadedPhotos => _uploadedPhotos;

  Future<bool> uploadPhoto(String fileName, {String? base64Data}) async {
    // Simulate network upload
    await Future.delayed(const Duration(seconds: 1));

    final photo = PhotoFile(
      id: 'PHOTO_${DateTime.now().millisecondsSinceEpoch}',
      fileName: fileName,
      uploadedAt: DateTime.now(),
      size: '2.5 MB',
      status: 'success',
    );

    _uploadedPhotos.add(photo);
    notifyListeners();
    return true;
  }

  void removePhoto(String id) {
    _uploadedPhotos.removeWhere((p) => p.id == id);
    notifyListeners();
  }

  void clearPhotos() {
    _uploadedPhotos.clear();
    notifyListeners();
  }

  List<String> getPhotoIds() {
    return _uploadedPhotos.map((p) => p.id).toList();
  }
}

class PhotoFile {
  final String id;
  final String fileName;
  final DateTime uploadedAt;
  final String size;
  final String status; // success, uploading, failed

  PhotoFile({
    required this.id,
    required this.fileName,
    required this.uploadedAt,
    required this.size,
    this.status = 'success',
  });
}
