import 'package:bookit/models/book_content.dart';
import 'package:bookit/ui/reader/paginator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const style = ReaderStyle(
    fontSize: 18,
    lineHeight: 1.5,
    fontFamily: null,
    color: Colors.black,
    mutedColor: Colors.grey,
    justify: true,
    direction: TextDirection.ltr,
  );

  List<DisplayBlock> blocks(int n) => [
        const DisplayBlock(BlockKind.heading1, 'Chapter One'),
        for (var i = 0; i < n; i++)
          DisplayBlock(BlockKind.paragraph,
              'Paragraph $i. ${List.filled(30 + (i % 7) * 10, 'lorem ipsum dolor').join(' ')} end of paragraph $i.'),
      ];

  testWidgets('every character appears exactly once across pages', (tester) async {
    final b = blocks(40);
    final pages = Paginator.paginate(b, const Size(360, 600), style);
    expect(pages.length, greaterThan(5));
    for (var i = 0; i < b.length; i++) {
      final slices = pages.expand((p) => p.slices).where((s) => s.block == i).toList();
      expect(slices, isNotEmpty);
      expect(slices.first.start, 0);
      expect(slices.last.end, b[i].text.length);
      for (var k = 1; k < slices.length; k++) {
        // consecutive, only whitespace may be skipped between slices
        final gap = b[i].text.substring(slices[k - 1].end, slices[k].start);
        expect(gap.trim(), isEmpty);
      }
    }
  });

  testWidgets('pages fit in the height', (tester) async {
    final b = blocks(25);
    const size = Size(320, 500);
    final pages = Paginator.paginate(b, size, style);
    for (final p in pages) {
      var h = 0.0;
      for (final s in p.slices) {
        final tp = TextPainter(
          text: TextSpan(text: b[s.block].text.substring(s.start, s.end), style: style.textStyle(b[s.block].kind)),
          textAlign: style.align(b[s.block].kind),
          textDirection: TextDirection.ltr,
          textScaler: TextScaler.noScaling,
        )..layout(maxWidth: size.width - style.indent(b[s.block].kind));
        h += s.spaceBefore + tp.height;
      }
      expect(h, lessThanOrEqualTo(size.height + 1));
    }
  });

  testWidgets('pageFor finds the page of a block', (tester) async {
    final b = blocks(30);
    final pages = Paginator.paginate(b, const Size(360, 600), style);
    for (var p = 0; p < pages.length; p++) {
      final first = pages[p].slices.first;
      final len = b[first.block].text.length;
      expect(Paginator.pageFor(pages, b, first.block, first.start / len), p);
    }
  });
}
