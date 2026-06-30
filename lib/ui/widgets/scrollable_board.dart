import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// A vertical board layout that fills the viewport when there is room, but
/// becomes **scrollable** when the content is taller than the available height
/// (e.g. a phone in landscape, where the board is short and wide).
///
/// The board is composed of three regions:
///  * [header] — fixed-height widgets at the top (turn bar, helper line,
///    center row). Rendered at their natural height.
///  * [field]  — the flexible middle play field. When there is spare vertical
///    space it expands to fill it (matching the old `Expanded` behaviour); when
///    space is tight it shrinks to [minFieldHeight] and the whole board scrolls
///    so the [footer] stays reachable.
///  * [footer] — fixed-height widgets at the bottom (hand, action buttons).
///
/// ### Why a custom layout?
/// The textbook "scroll only when content overflows" idiom is a
/// `SingleChildScrollView` + `ConstrainedBox(minHeight: viewport)` +
/// `IntrinsicHeight` + `Expanded`. That throws here because the board contains
/// `LayoutBuilder`-based descendants (e.g. the card fan, center row), and
/// `IntrinsicHeight` cannot compute intrinsics through a `LayoutBuilder`.
///
/// Instead we measure the header and footer at layout time with a small
/// [_BoardLayout] render object (no intrinsics needed), compute the field
/// height as `max(minFieldHeight, viewport - header - footer)`, and lay all
/// three out in a single pass. The result is placed inside a
/// [SingleChildScrollView] so that when `header + field + footer` exceeds the
/// viewport, the board scrolls. When everything fits, the field expands to fill
/// the slack and there is nothing to scroll — pixel-identical to the old
/// `Column` + `Expanded` layout.
class ScrollableBoard extends StatelessWidget {
  const ScrollableBoard({
    super.key,
    required this.header,
    required this.field,
    required this.footer,
    this.minFieldHeight = 120,
  });

  /// Fixed-height widgets rendered above the flexible [field].
  final List<Widget> header;

  /// The flexible middle region (the play field).
  final Widget field;

  /// Fixed-height widgets rendered below the flexible [field].
  final List<Widget> footer;

  /// The smallest height the [field] is allowed to occupy before the board
  /// starts scrolling instead of squeezing it further. Keeps the play area
  /// usable (and its children laid out) on very short viewports.
  final double minFieldHeight;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportHeight = constraints.maxHeight;
        final headerWidget = Column(
          mainAxisSize: MainAxisSize.min,
          children: header,
        );
        final footerWidget = Column(
          mainAxisSize: MainAxisSize.min,
          children: footer,
        );

        if (!viewportHeight.isFinite) {
          // Defensive: no bounded height to fill — lay out naturally.
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              headerWidget,
              SizedBox(height: minFieldHeight, child: field),
              footerWidget,
            ],
          );
        }

        return SingleChildScrollView(
          child: _BoardLayout(
            viewportHeight: viewportHeight,
            minFieldHeight: minFieldHeight,
            header: headerWidget,
            field: field,
            footer: footerWidget,
          ),
        );
      },
    );
  }
}

/// Lays out header / field / footer vertically. The field is sized to
/// `max(minFieldHeight, viewportHeight - headerHeight - footerHeight)` so it
/// fills spare space on tall viewports and clamps to its minimum on short ones,
/// at which point the parent [SingleChildScrollView] provides scrolling.
///
/// Children are passed in fixed order: header, field, footer.
class _BoardLayout extends MultiChildRenderObjectWidget {
  _BoardLayout({
    required this.viewportHeight,
    required this.minFieldHeight,
    required Widget header,
    required Widget field,
    required Widget footer,
  }) : super(children: [header, field, footer]);

  final double viewportHeight;
  final double minFieldHeight;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _BoardRenderLayout(
      viewportHeight: viewportHeight,
      minFieldHeight: minFieldHeight,
    );
  }

  @override
  void updateRenderObject(
      BuildContext context, _BoardRenderLayout renderObject) {
    renderObject
      ..viewportHeight = viewportHeight
      ..minFieldHeight = minFieldHeight;
  }
}

class _BoardChildData extends ContainerBoxParentData<RenderBox> {}

class _BoardRenderLayout extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _BoardChildData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _BoardChildData> {
  _BoardRenderLayout({
    required double viewportHeight,
    required double minFieldHeight,
  })  : _viewportHeight = viewportHeight,
        _minFieldHeight = minFieldHeight;

  double _viewportHeight;
  double get viewportHeight => _viewportHeight;
  set viewportHeight(double value) {
    if (_viewportHeight == value) return;
    _viewportHeight = value;
    markNeedsLayout();
  }

  double _minFieldHeight;
  double get minFieldHeight => _minFieldHeight;
  set minFieldHeight(double value) {
    if (_minFieldHeight == value) return;
    _minFieldHeight = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _BoardChildData) {
      child.parentData = _BoardChildData();
    }
  }

  @override
  void performLayout() {
    // Children are in declared order: header, field, footer.
    final header = firstChild!;
    final field = (header.parentData as _BoardChildData).nextSibling!;
    final footer = (field.parentData as _BoardChildData).nextSibling!;

    final width = constraints.maxWidth.isFinite
        ? constraints.maxWidth
        : constraints.minWidth;
    final tight = BoxConstraints.tightFor(width: width);

    header.layout(tight.copyWith(minHeight: 0, maxHeight: double.infinity),
        parentUsesSize: true);
    footer.layout(tight.copyWith(minHeight: 0, maxHeight: double.infinity),
        parentUsesSize: true);

    final headerHeight = header.size.height;
    final footerHeight = footer.size.height;

    // Field fills the leftover viewport space, but never below its minimum.
    final slack = _viewportHeight - headerHeight - footerHeight;
    final fieldHeight =
        slack > _minFieldHeight ? slack : _minFieldHeight;

    field.layout(
      BoxConstraints.tightFor(width: width, height: fieldHeight),
      parentUsesSize: true,
    );

    // Position children stacked vertically.
    (header.parentData as _BoardChildData).offset = Offset.zero;
    (field.parentData as _BoardChildData).offset = Offset(0, headerHeight);
    (footer.parentData as _BoardChildData).offset =
        Offset(0, headerHeight + fieldHeight);

    final totalHeight = headerHeight + fieldHeight + footerHeight;
    size = Size(width, totalHeight);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    defaultPaint(context, offset);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    return defaultHitTestChildren(result, position: position);
  }
}
