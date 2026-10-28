import 'dart:io';

import 'package:flutter/material.dart';

/// A book cover: the real image when there is one, otherwise a generated
/// cover with the title, in a colour picked from the title.
class BookCover extends StatelessWidget {
  final String title;
  final String author;
  final File? file;
  final String? url;
  final double width;
  final double? height;
  final double radius;

  const BookCover({
    super.key,
    required this.title,
    this.author = '',
    this.file,
    this.url,
    this.width = 110,
    this.height,
    this.radius = 6,
  });

  static const _palette = [
    (Color(0xFF1F2A44), Color(0xFF3A4E7A)),
    (Color(0xFF6B2E2E), Color(0xFFA3503F)),
    (Color(0xFF2F4F3A), Color(0xFF4F7D5C)),
    (Color(0xFF4A3B6B), Color(0xFF7A62A8)),
    (Color(0xFF6B4E1F), Color(0xFFB0823A)),
    (Color(0xFF1F4D5C), Color(0xFF3A8296)),
    (Color(0xFF5C1F45), Color(0xFF94396F)),
  ];

  @override
  Widget build(BuildContext context) {
    final h = height ?? width * 1.5;
    Widget generated() {
      final c = _palette[title.hashCode.abs() % _palette.length];
      return Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [c.$1, c.$2], begin: Alignment.topLeft, end: Alignment.bottomRight),
        ),
        padding: EdgeInsets.all(width * 0.09),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(height: 2, width: width * 0.3, color: Colors.white54),
            SizedBox(height: width * 0.08),
            Expanded(
              child: Text(
                title,
                maxLines: 6,
                overflow: TextOverflow.fade,
                style: TextStyle(
                  color: Colors.white,
                  fontFamily: 'serif',
                  fontWeight: FontWeight.w600,
                  fontSize: (width * 0.12).clamp(9, 22).toDouble(),
                  height: 1.2,
                ),
              ),
            ),
            if (author.isNotEmpty)
              Text(
                author,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.white70, fontSize: (width * 0.08).clamp(7, 14).toDouble()),
              ),
          ],
        ),
      );
    }

    Widget image;
    if (file != null && file!.existsSync()) {
      image = Image.file(file!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => generated());
    } else if (url != null) {
      image = Image.network(url!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => generated());
    } else {
      image = generated();
    }
    return Container(
      width: width,
      height: h,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 6, offset: Offset(0, 3))],
      ),
      clipBehavior: Clip.antiAlias,
      child: image,
    );
  }
}
