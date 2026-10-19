import 'package:dio/dio.dart';
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';

import 'api_client.dart';

/// Multipart part for a picked image. The backend checks each part's MIME
/// type (JPEG, PNG, WEBP or GIF) and the file's magic bytes.
Future<MultipartFile> imagePart(XFile file) async {
  final name = file.name.toLowerCase();
  final subtype = name.endsWith('.png')
      ? 'png'
      : name.endsWith('.webp')
          ? 'webp'
          : name.endsWith('.gif')
              ? 'gif'
              : 'jpeg';
  final bytes = await file.readAsBytes();
  if (bytes.length > 8 * 1024 * 1024) {
    throw ApiException('Each image must be 8 MB or smaller.');
  }
  return MultipartFile.fromBytes(
    bytes,
    filename: file.name,
    contentType: MediaType('image', subtype),
  );
}
