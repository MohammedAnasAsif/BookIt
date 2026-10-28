import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../models/book_content.dart';
import '../translation/translation_data.dart';

/// A BookIt edition: a book plus one translation in a single gzip'd JSON file
/// (`.bookit`). Used for sharing translations and for the community library.
class Edition {
  final BookContent content;
  final TranslationData translation;
  final int? gutenbergId;
  final String sourceLang;
  final Uint8List? cover;
  final String? coverExtension;
  final String? translatorNote;

  Edition({
    required this.content,
    required this.translation,
    required this.sourceLang,
    this.gutenbergId,
    this.cover,
    this.coverExtension,
    this.translatorNote,
  });

  Uint8List encode() {
    final json = {
      'format': 'bookit-edition',
      'version': 1,
      'sourceLang': sourceLang,
      if (gutenbergId != null) 'gutenbergId': gutenbergId,
      if (translatorNote != null) 'note': translatorNote,
      if (cover != null) 'cover': base64.encode(cover!),
      if (coverExtension != null) 'coverExt': coverExtension,
      'content': content.toJson(),
      'translation': translation.toJson(),
    };
    final raw = utf8.encode(jsonEncode(json));
    return Uint8List.fromList(GZipEncoder().encode(raw)!);
  }

  static Edition decode(Uint8List bytes) {
    List<int> raw = bytes;
    if (bytes.length > 2 && bytes[0] == 0x1f && bytes[1] == 0x8b) {
      raw = GZipDecoder().decodeBytes(bytes);
    }
    final j = jsonDecode(utf8.decode(raw)) as Map<String, dynamic>;
    if (j['format'] != 'bookit-edition') throw const FormatException('Not a BookIt edition file');
    final content = BookContent.fromJson(j['content'] as Map<String, dynamic>);
    final translation = TranslationData.fromJson(j['translation'] as Map<String, dynamic>);
    translation.conformTo(content);
    return Edition(
      content: content,
      translation: translation,
      sourceLang: (j['sourceLang'] as String?) ?? translation.sourceLang,
      gutenbergId: (j['gutenbergId'] as num?)?.toInt(),
      cover: j['cover'] is String ? base64.decode(j['cover'] as String) : null,
      coverExtension: j['coverExt'] as String?,
      translatorNote: j['note'] as String?,
    );
  }
}
