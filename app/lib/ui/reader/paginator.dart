import 'package:flutter/material.dart';

import '../../models/book_content.dart';

/// Text of a block as shown in the reader (original or translated).
class DisplayBlock {
  final BlockKind kind;
  final String text;

  /// True when the reader asked for a translation that isn't ready yet, so the
  /// original text is shown in its place.
  final bool pending;
  const DisplayBlock(this.kind, this.text, {this.pending = false});
}

/// A run of characters of one block placed on a page.
class PageSlice {
  final int block;
  final int start;
  final int end;
  final double spaceBefore;
  const PageSlice(this.block, this.start, this.end, this.spaceBefore);
}

class PageLayout {
  final List<PageSlice> slices;
  const PageLayout(this.slices);
}

/// Visual settings that affect layout.
class ReaderStyle {
  final double fontSize;
  final double lineHeight;
  final String? fontFamily;
  final Color color;
  final Color mutedColor;
  final bool justify;
  final TextDirection direction;

  const ReaderStyle({
    required this.fontSize,
    required this.lineHeight,
    required this.fontFamily,
    required this.color,
    required this.mutedColor,
    required this.justify,
    required this.direction,
  });

  TextStyle textStyle(BlockKind kind, {bool pending = false}) {
    final base = TextStyle(
      fontSize: fontSize,
      height: lineHeight,
      fontFamily: fontFamily,
      color: pending ? mutedColor : color,
    );
    return switch (kind) {
      BlockKind.heading1 => base.copyWith(fontSize: fontSize * 1.45, fontWeight: FontWeight.w700, height: 1.3),
      BlockKind.heading2 => base.copyWith(fontSize: fontSize * 1.25, fontWeight: FontWeight.w700, height: 1.3),
      BlockKind.heading3 => base.copyWith(fontSize: fontSize * 1.1, fontWeight: FontWeight.w600, height: 1.3),
      BlockKind.quote => base.copyWith(fontStyle: FontStyle.italic),
      BlockKind.preformatted => base.copyWith(fontFamily: 'monospace', fontSize: fontSize * 0.82, height: 1.35),
      BlockKind.separator => base.copyWith(color: mutedColor),
      _ => base,
    };
  }

  TextAlign align(BlockKind kind) {
    if (kind == BlockKind.heading1 || kind == BlockKind.heading2 || kind == BlockKind.heading3) {
      return TextAlign.center;
    }
    if (kind == BlockKind.separator) return TextAlign.center;
    if (kind == BlockKind.preformatted) return TextAlign.start;
    return justify ? TextAlign.justify : TextAlign.start;
  }

  double indent(BlockKind kind) => switch (kind) {
        BlockKind.quote => fontSize * 1.5,
        BlockKind.listItem => fontSize * 0.8,
        _ => 0,
      };

  double spaceBefore(BlockKind kind, bool firstOnPage) {
    if (firstOnPage) return 0;
    return switch (kind) {
      BlockKind.heading1 => fontSize * 1.6,
      BlockKind.heading2 || BlockKind.heading3 => fontSize * 1.2,
      BlockKind.separator => fontSize * 0.8,
      _ => fontSize * 0.55,
    };
  }

  bool sameLayoutAs(ReaderStyle o) =>
      o.fontSize == fontSize &&
      o.lineHeight == lineHeight &&
      o.fontFamily == fontFamily &&
      o.justify == justify &&
      o.direction == direction;
}

String displayText(DisplayBlock b) => b.kind == BlockKind.separator ? '⁂' : b.text;

/// Splits a chapter into pages that exactly fit [size].
class Paginator {
  static List<PageLayout> paginate(List<DisplayBlock> blocks, Size size, ReaderStyle style) {
    final pages = <PageLayout>[];
    var current = <PageSlice>[];
    var used = 0.0;
    final height = size.height;

    void newPage() {
      if (current.isNotEmpty) pages.add(PageLayout(current));
      current = <PageSlice>[];
      used = 0;
    }

    for (var bi = 0; bi < blocks.length; bi++) {
      final block = blocks[bi];
      final text = displayText(block);
      if (text.isEmpty) continue;
      final ts = style.textStyle(block.kind, pending: block.pending);
      final width = (size.width - style.indent(block.kind)).clamp(40.0, double.infinity);
      final isHeading = block.kind == BlockKind.heading1 ||
          block.kind == BlockKind.heading2 ||
          block.kind == BlockKind.heading3;
      // A new chapter heading never shares the bottom of a page.
      if (block.kind == BlockKind.heading1 && current.isNotEmpty && used > height * 0.6) newPage();

      var start = 0;
      while (start < text.length) {
        final before = style.spaceBefore(block.kind, current.isEmpty);
        final remaining = height - used - before;
        final tp = TextPainter(
          text: TextSpan(text: text.substring(start), style: ts),
          textAlign: style.align(block.kind),
          textDirection: style.direction,
          textScaler: TextScaler.noScaling,
        )..layout(maxWidth: width);

        if (tp.height <= remaining) {
          current.add(PageSlice(bi, start, text.length, before));
          used += before + tp.height;
          tp.dispose();
          break;
        }

        final lines = tp.computeLineMetrics();
        var fit = 0;
        var fitHeight = 0.0;
        for (final l in lines) {
          if (fitHeight + l.height <= remaining + 0.5) {
            fitHeight += l.height;
            fit++;
          } else {
            break;
          }
        }
        // Keep headings whole; avoid a single orphan line at the bottom.
        if (isHeading && fit < lines.length) fit = 0;
        if (fit == 1 && lines.length > 2 && current.isNotEmpty) fit = 0;

        if (fit == 0) {
          if (current.isEmpty) {
            fit = 1; // a line taller than the page: place it anyway
            fitHeight = lines.isNotEmpty ? lines.first.height : remaining;
          } else {
            tp.dispose();
            newPage();
            continue;
          }
        }

        final y = fitHeight - (lines.isNotEmpty ? lines[fit - 1].height / 2 : 0);
        final pos = tp.getPositionForOffset(Offset(style.direction == TextDirection.rtl ? 0 : width - 1, y));
        var end = tp.getLineBoundary(pos).end;
        if (end <= 0) end = pos.offset;
        if (end <= 0) end = 1;
        tp.dispose();
        current.add(PageSlice(bi, start, start + end, before));
        newPage();
        start += end;
        while (start < text.length && (text.codeUnitAt(start) == 0x20 || text.codeUnitAt(start) == 0x0A)) {
          start++;
        }
      }
    }
    newPage();
    if (pages.isEmpty) pages.add(const PageLayout([]));
    return pages;
  }

  /// Index of the page containing [block] at [fraction] of its length.
  static int pageFor(List<PageLayout> pages, List<DisplayBlock> blocks, int block, double fraction) {
    if (block < 0 || block >= blocks.length) return 0;
    final len = displayText(blocks[block]).length;
    final at = (fraction * len).round();
    var last = 0;
    for (var p = 0; p < pages.length; p++) {
      for (final s in pages[p].slices) {
        if (s.block < block) {
          last = p;
        } else if (s.block == block) {
          if (at < s.end || s.end >= len) return p;
          last = p;
        } else {
          return last;
        }
      }
    }
    return last;
  }
}

/// Renders one page laid out by [Paginator].
class PageView2 extends StatelessWidget {
  final PageLayout page;
  final List<DisplayBlock> blocks;
  final ReaderStyle style;

  const PageView2({super.key, required this.page, required this.blocks, required this.style});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.max,
      children: [
        for (final s in page.slices)
          Padding(
            padding: EdgeInsetsDirectional.only(top: s.spaceBefore, start: style.indent(blocks[s.block].kind)),
            child: Text(
              displayText(blocks[s.block]).substring(s.start, s.end),
              style: style.textStyle(blocks[s.block].kind, pending: blocks[s.block].pending),
              textAlign: style.align(blocks[s.block].kind),
              textDirection: style.direction,
              textScaler: TextScaler.noScaling,
              softWrap: true,
            ),
          ),
      ],
    );
  }
}
