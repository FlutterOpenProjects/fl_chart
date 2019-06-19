import 'dart:ui' as ui;

import 'package:fl_chart/fl_chart.dart';
import 'package:fl_chart/src/chart/base/axis_chart/axis_chart_data.dart';
import 'package:fl_chart/src/chart/base/axis_chart/axis_chart_painter.dart';
import 'package:fl_chart/src/chart/base/base_chart/base_chart_painter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';

import 'line_chart_data.dart';

class LineChartPainter extends AxisChartPainter {
  final LineChartData data;

  /// [barPaint] is responsible to painting the bar line
  /// [belowBarPaint] is responsible to fill the below space of our bar line
  /// [dotPaint] is responsible to draw dots on spot points
  /// [clearAroundBorderPaint] is responsible to clip the border
  /// [extraLinesPaint] is responsible to draw extr lines
  /// [touchLinePaint] is responsible to draw touch indicators(below line and spot)
  /// [bgTouchTooltipPaint] is responsible to draw box backgroundTooltip of touched point;
  Paint barPaint, belowBarPaint, belowBarLinePaint,
    dotPaint, clearAroundBorderPaint, extraLinesPaint,
    touchLinePaint, bgTouchTooltipPaint;

  LineChartPainter(
    this.data,
    FlTouchController touchController,
  ) : super(data, touchController: touchController) {

    barPaint = Paint()
      ..style = PaintingStyle.stroke;

    belowBarPaint = Paint()..style = PaintingStyle.fill;

    belowBarLinePaint = Paint()
      ..style = PaintingStyle.stroke;

    dotPaint = Paint()
      ..style = PaintingStyle.fill;

    clearAroundBorderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..color = const Color(0x000000000)
      ..blendMode = BlendMode.dstIn;

    extraLinesPaint = Paint()
      ..style = PaintingStyle.stroke;

    touchLinePaint = Paint()
      ..style = PaintingStyle.fill
      ..color = Colors.black;

    bgTouchTooltipPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = Colors.white;
  }

  @override
  void paint(Canvas canvas, Size viewSize) {
    super.paint(canvas, viewSize);
    if (data.lineBarsData.isEmpty) {
      return;
    }

    if (data.clipToBorder) {
      /// save layer to clip it to border after lines drew
      canvas.saveLayer(Rect.fromLTWH(0, -40, viewSize.width + 40, viewSize.height + 40), Paint());
    }

    /// it holds list of nearest touched spots of each line
    /// and we use it to draw touch stuff on them
    final List<TouchedSpot> touchedSpots = [];
    /// draw each line independently on the chart
    for (LineChartBarData barData in data.lineBarsData) {
      drawBarLine(canvas, viewSize, barData);
      drawDots(canvas, viewSize, barData);

      // find the nearest spot on touch area in this bar line
      final TouchedSpot foundTouchedSpot = _getNearestTouchedSpot(canvas, viewSize, barData);
      if (foundTouchedSpot != null) {
        touchedSpots.add(foundTouchedSpot);
      }
    }

    if (data.clipToBorder) {
      removeOutsideBorder(canvas, viewSize);
      /// restore layer to previous state (after clipping the chart)
      canvas.restore();
    }

    // Draw touch indicators (below spot line and spot dot)
    drawTouchedSpotsIndicator(canvas, viewSize, touchedSpots);

    drawTitles(canvas, viewSize);

    drawExtraLines(canvas, viewSize);

    // Draw touch tooltip on most top spot
    drawTouchTooltip(canvas, viewSize, touchedSpots);
  }

  void drawBarLine(Canvas canvas, Size viewSize, LineChartBarData barData) {
    Path barPath = _generateBarPath(viewSize, barData);
    drawBelowBar(canvas, viewSize, barPath, barData);
    drawBar(canvas, viewSize, barPath, barData);
  }

  /// find the nearest spot base on the touched offset
  TouchedSpot _getNearestTouchedSpot(Canvas canvas, Size viewSize, LineChartBarData barData) {
    final Size chartViewSize = getChartUsableDrawSize(viewSize);

    final Offset touchedPoint = touchController != null ? touchController.value : null;

    if (touchedPoint == null) {
      return null;
    }

    FlSpot nearestSpot;

    /// Find the nearest spot (on X axis)
    for (FlSpot spot in barData.spots) {
      if ((touchedPoint.dx - getPixelX(spot.x, chartViewSize)).abs() <= 10) {
        nearestSpot = spot;
      }
    }

    if (nearestSpot == null) {
      return null;
    }

    final double x = getPixelX(nearestSpot.x, chartViewSize);
    final Offset nearestSpotPos = Offset(x, getPixelY(nearestSpot.y, chartViewSize));

    return TouchedSpot(nearestSpot, nearestSpotPos, barData);
  }

  void drawDots(Canvas canvas, Size viewSize, LineChartBarData barData) {
    if (!barData.dotData.show) {
      return;
    }
    viewSize = getChartUsableDrawSize(viewSize);
    barData.spots.forEach((spot) {
      if (barData.dotData.checkToShowDot(spot)) {
        double x = getPixelX(spot.x, viewSize);
        double y = getPixelY(spot.y, viewSize);
        dotPaint.color = barData.dotData.dotColor;
        canvas.drawCircle(Offset(x, y), barData.dotData.dotSize, dotPaint);
      }
    });
  }

  /// firstly we generate the bar line that we should draw,
  /// then we reuse it to fill below bar space.
  /// there is two type of barPath that generate here,
  /// first one is the sharp corners line on spot connections
  /// second one is curved corners line on spot connections,
  /// and we use isCurved to find out how we should generate it,
  Path _generateBarPath(Size viewSize, LineChartBarData barData) {
    viewSize = getChartUsableDrawSize(viewSize);
    Path path = Path();
    int size = barData.spots.length;
    path.reset();

    double lX = 0.0, lY = 0.0;

    double x = getPixelX(barData.spots[0].x, viewSize);
    double y = getPixelY(barData.spots[0].y, viewSize);
    path.moveTo(x, y);
    for (int i = 1; i < size; i++) {
      /// CurrentSpot
      FlSpot p = barData.spots[i];
      double px = getPixelX(p.x, viewSize);
      double py = getPixelY(p.y, viewSize);

      /// previous spot
      FlSpot p0 = barData.spots[i - 1];
      double p0x = getPixelX(p0.x, viewSize);
      double p0y = getPixelY(p0.y, viewSize);

      double x1 = p0x + lX;
      double y1 = p0y + lY;

      /// next point
      FlSpot p1 = barData.spots[i + 1 < size ? i + 1 : i];
      double p1x = getPixelX(p1.x, viewSize);
      double p1y = getPixelY(p1.y, viewSize);

      /// if the isCurved is false, we set 0 for smoothness,
      /// it means we should not have any smoothness then we face with
      /// the sharped corners line
      double smoothness = barData.isCurved ? barData.curveSmoothness : 0.0;
      lX = ((p1x - p0x) / 2) * smoothness;
      lY = ((p1y - p0y) / 2) * smoothness;
      double x2 = px - lX;
      double y2 = py - lY;

      path.cubicTo(x1, y1, x2, y2, px, py);
    }

    return path;
  }

  /// in this phase we get the generated [barPath] as input
  /// that is the raw line bar.
  /// then we make a copy from it and call it [belowBarPath],
  /// we continue to complete the path to cover the below section.
  /// then we close the path to fill the below space with a color or gradient.
  void drawBelowBar(Canvas canvas, Size viewSize, Path barPath, LineChartBarData barData) {
    if (!barData.belowBarData.show) {
      return;
    }

    var belowBarPath = Path.from(barPath);

    Size chartViewSize = getChartUsableDrawSize(viewSize);

    /// Line To Bottom Right
    double x = getPixelX(barData.spots[barData.spots.length - 1].x, chartViewSize);
    double y = chartViewSize.height - getTopOffsetDrawSize();
    belowBarPath.lineTo(x, y);

    /// Line To Bottom Left
    x = getPixelX(barData.spots[0].x, chartViewSize);
    y = chartViewSize.height - getTopOffsetDrawSize();
    belowBarPath.lineTo(x, y);

    /// Line To Top Left
    x = getPixelX(barData.spots[0].x, chartViewSize);
    y = getPixelY(barData.spots[0].y, chartViewSize);
    belowBarPath.lineTo(x, y);
    belowBarPath.close();

    /// here we update the [belowBarPaint] to draw the solid color
    /// or the gradient based on the [BelowBarData] class.
    if (barData.belowBarData.colors.length == 1) {
      belowBarPaint.color = barData.belowBarData.colors[0];
      belowBarPaint.shader = null;
    } else {

      List<double> stops = [];
      if (barData.belowBarData.gradientColorStops == null
        || barData.belowBarData.gradientColorStops.length != barData.belowBarData.colors.length) {
        /// provided gradientColorStops is invalid and we calculate it here
        barData.colors.asMap().forEach((index, color) {
          double ss = 1.0 / barData.colors.length;
          stops.add(ss * (index + 1));
        });
      } else {
        stops = barData.colorStops;
      }

      var from = barData.belowBarData.gradientFrom;
      var to = barData.belowBarData.gradientTo;
      belowBarPaint.shader = ui.Gradient.linear(
        Offset(
          getLeftOffsetDrawSize() + (chartViewSize.width * from.dx),
          getTopOffsetDrawSize() + (chartViewSize.height * from.dy),
        ),
        Offset(
          getLeftOffsetDrawSize() + (chartViewSize.width * to.dx),
          getTopOffsetDrawSize() + (chartViewSize.height * to.dy),
        ),
        barData.belowBarData.colors,
        stops,
      );
    }

    canvas.drawPath(belowBarPath, belowBarPaint);


    /// draw below spots line
    if (barData.belowBarData.belowSpotsLine != null) {
      for (FlSpot spot in barData.spots) {
        if (barData.belowBarData.belowSpotsLine.show &&
          barData.belowBarData.belowSpotsLine.checkToShowSpotBelowLine(spot)) {
          final Offset from = Offset(
            getPixelX(spot.x, chartViewSize),
            getPixelY(spot.y, chartViewSize),
          );

          final double bottomPadding = getExtraNeededVerticalSpace() - getTopOffsetDrawSize();
          final Offset to = Offset(
            getPixelX(spot.x, chartViewSize),
            viewSize.height - bottomPadding,
          );

          belowBarLinePaint.color = barData.belowBarData.belowSpotsLine.flLineStyle.color;
          belowBarLinePaint.strokeWidth =
            barData.belowBarData.belowSpotsLine.flLineStyle.strokeWidth;

          canvas.drawLine(from, to, belowBarLinePaint);
        }
      }
    }
  }

  void drawBar(Canvas canvas, Size viewSize, Path barPath, LineChartBarData barData) {
    if (!barData.show) {
      return;
    }

    barPaint.strokeCap = barData.isStrokeCapRound ? StrokeCap.round : StrokeCap.butt;

    /// here we update the [barPaint] to draw the solid color or
    /// the gradient color,
    /// if we have one color, solid color will apply,
    /// but if we have more than one color, gradient will apply.
    if (barData.colors.length == 1) {
      barPaint.color = barData.colors[0];
      barPaint.shader = null;
    } else {

      List<double> stops = [];
      if (barData.colorStops == null || barData.colorStops.length != barData.colors.length) {
        /// provided colorStops is invalid and we calculate it here
        barData.colors.asMap().forEach((index, color) {
          double ss = 1.0 / barData.colors.length;
          stops.add(ss * (index + 1));
        });
      } else {
        stops = barData.colorStops;
      }

      barPaint.shader = ui.Gradient.linear(
        Offset(
          getLeftOffsetDrawSize(),
          getTopOffsetDrawSize() + (viewSize.height / 2),
        ),
        Offset(
          getLeftOffsetDrawSize() + viewSize.width,
          getTopOffsetDrawSize() + (viewSize.height / 2),
        ),
        barData.colors,
        stops,
      );
    }

    barPaint.strokeWidth = barData.barWidth;
    canvas.drawPath(barPath, barPaint);
  }

  /// clip the border (remove outside the border)
  void removeOutsideBorder(Canvas canvas, Size viewSize) {
    if (!data.clipToBorder) {
      return;
    }

    clearAroundBorderPaint.strokeWidth = barPaint.strokeWidth / 2;
    double halfStrokeWidth = clearAroundBorderPaint.strokeWidth / 2;
    Rect rect = Rect.fromLTRB(
      getLeftOffsetDrawSize() - halfStrokeWidth,
      getTopOffsetDrawSize() - halfStrokeWidth,
      viewSize.width - (getExtraNeededHorizontalSpace() - getLeftOffsetDrawSize()) + halfStrokeWidth,
      viewSize.height - (getExtraNeededVerticalSpace() - getTopOffsetDrawSize()) + halfStrokeWidth,
    );
    canvas.drawRect(rect, clearAroundBorderPaint);
  }

  void drawTouchedSpotsIndicator(Canvas canvas, Size viewSize, List<TouchedSpot> touchedSpotOffsets) {
    if (touchedSpotOffsets == null || touchedSpotOffsets.isEmpty) {
      return;
    }

    final Size chartViewSize = getChartUsableDrawSize(viewSize);

    /// sort the touched spots top to down, base on their y value
    touchedSpotOffsets.sort((a, b) => a.offset.dy.compareTo(b.offset.dy));

    final List<TouchedSpotIndicatorData> indicatorsData =
      data.touchData.getTouchedSpotIndicator(touchedSpotOffsets);

    if (indicatorsData.length != touchedSpotOffsets.length) {
      throw Exception('indicatorsData and touchedSpotOffsets size should be same');
    }

    for (int i = 0; i < touchedSpotOffsets.length; i++) {
      final TouchedSpotIndicatorData indicatorData = indicatorsData[i];
      final TouchedSpot touchedSpot = touchedSpotOffsets[i];

      if (indicatorData == null) {
        continue;
      }

      /// Draw the indicator line
      final from = Offset(touchedSpot.offset.dx, getTopOffsetDrawSize() + chartViewSize.height);
      final to = touchedSpot.offset;

      touchLinePaint.color = indicatorData.indicatorBelowLine.color;
      touchLinePaint.strokeWidth = indicatorData.indicatorBelowLine.strokeWidth;
      canvas.drawLine(from, to, touchLinePaint);

      /// Draw the indicator dot
      final double selectedSpotDotSize =
        indicatorData.touchedSpotDotData.dotSize;
      dotPaint.color = indicatorData.touchedSpotDotData.dotColor;
      canvas.drawCircle(to, selectedSpotDotSize, dotPaint);
    }
  }

  void drawTitles(Canvas canvas, Size viewSize) {
    if (!data.titlesData.show) {
      return;
    }
    viewSize = getChartUsableDrawSize(viewSize);

    // Vertical Titles
    if (data.titlesData.showVerticalTitles) {
      double verticalSeek = data.minY;
      while (verticalSeek <= data.maxY) {
        double x = 0 + getLeftOffsetDrawSize();
        double y = getPixelY(verticalSeek, viewSize) +
            getTopOffsetDrawSize();

        final String text =
            data.titlesData.getVerticalTitles(verticalSeek);

        final TextSpan span = TextSpan(style: data.titlesData.verticalTitlesTextStyle, text: text);
        final TextPainter tp = TextPainter(
            text: span, textAlign: TextAlign.center, textDirection: TextDirection.ltr);
        tp.layout(maxWidth: getExtraNeededHorizontalSpace());
        x -= tp.width + data.titlesData.verticalTitleMargin;
        y -= tp.height / 2;
        tp.paint(canvas, Offset(x, y));

        verticalSeek += data.gridData.verticalInterval;
      }
    }

    // Horizontal titles
    if (data.titlesData.showHorizontalTitles) {
      double horizontalSeek = data.minX;
      while (horizontalSeek <= data.maxX) {
        double x = getPixelX(horizontalSeek, viewSize);
        double y = viewSize.height + getTopOffsetDrawSize();

        String text = data.titlesData
            .getHorizontalTitles(horizontalSeek);

        TextSpan span = TextSpan(style: data.titlesData.horizontalTitlesTextStyle, text: text);
        TextPainter tp = TextPainter(
            text: span, textAlign: TextAlign.center, textDirection: TextDirection.ltr);
        tp.layout();

        x -= tp.width / 2;
        y += data.titlesData.horizontalTitleMargin;

        tp.paint(canvas, Offset(x, y));

        horizontalSeek += data.gridData.horizontalInterval;
      }
    }
  }

  void drawExtraLines(Canvas canvas, Size viewSize) {
    if (data.extraLinesData == null) {
      return;
    }

    final Size chartUsableSize = getChartUsableDrawSize(viewSize);

    if (data.extraLinesData.showHorizontalLines) {
      for (HorizontalLine line in data.extraLinesData.horizontalLines) {

        final double topChartPadding = getTopOffsetDrawSize();
        final Offset from = Offset(getPixelX(line.x, chartUsableSize), topChartPadding);

        final double bottomChartPadding = getExtraNeededVerticalSpace() - getTopOffsetDrawSize();
        final Offset to = Offset(getPixelX(line.x, chartUsableSize), viewSize.height - bottomChartPadding);

        extraLinesPaint.color = line.color;
        extraLinesPaint.strokeWidth = line.strokeWidth;

        canvas.drawLine(from, to, extraLinesPaint);
      }
    }

    if (data.extraLinesData.showVerticalLines) {
      for (VerticalLine line in data.extraLinesData.verticalLines) {

        final double leftChartPadding = getLeftOffsetDrawSize();
        final Offset from = Offset(leftChartPadding, getPixelY(line.y, chartUsableSize));

        final double rightChartPadding = getExtraNeededHorizontalSpace() - getLeftOffsetDrawSize();
        final Offset to = Offset(viewSize.width - rightChartPadding, getPixelY(line.y, chartUsableSize));

        extraLinesPaint.color = line.color;
        extraLinesPaint.strokeWidth = line.strokeWidth;

        canvas.drawLine(from, to, extraLinesPaint);
      }
    }
  }

  void drawTouchTooltip(Canvas canvas, Size viewSize, List<TouchedSpot> sortedTouchedSpotOffsets) {
    const double textsBelowMargin = 4;

    final TouchTooltipData tooltipData = data.touchData.touchTooltipData;

    /// creating TextPainters to calculate the width and height of the tooltip
    final List<TextPainter> drawingTextPainters = [];

    final List<TooltipItem> tooltipItems = data.touchData.getTooltipItems(sortedTouchedSpotOffsets);
    if (tooltipItems.length != sortedTouchedSpotOffsets.length) {
      throw Exception('tooltipItems and touchedSpots size should be same');
    }

    for (int i = 0; i < sortedTouchedSpotOffsets.length; i++) {
      final TooltipItem tooltipItem = tooltipItems[i];
      if (tooltipItem == null) {
        continue;
      }

      final TextSpan span = TextSpan(style: tooltipItem.textStyle, text: tooltipItem.text);
      final TextPainter tp = TextPainter(
        text: span, textAlign: TextAlign.center, textDirection: TextDirection.ltr);
      tp.layout(maxWidth: tooltipData.maxContentWidth);
      drawingTextPainters.add(tp);
    }
    if (drawingTextPainters.isEmpty) {
      return;
    }

    /// biggerWidth
    /// some texts maybe larger, then we should
    /// draw the tooltip' width as wide as biggerWidth
    ///
    /// sumTextsHeight
    /// sum up all Texts height, then we should
    /// draw the tooltip's height as tall as sumTextsHeight
    double biggerWidth = 0;
    double sumTextsHeight = 0;
    for (TextPainter tp in drawingTextPainters) {
      if (tp.width > biggerWidth) {
        biggerWidth = tp.width;
      }
      sumTextsHeight += tp.height;
    }
    sumTextsHeight += (drawingTextPainters.length - 1) * textsBelowMargin;


    /// if we have multiple bar lines,
    /// there are more than one FlCandidate on touch area,
    /// we should get the most top FlSpot Offset to draw the tooltip on top of it
    final Offset mostTopOffset = sortedTouchedSpotOffsets.first.offset;

    final double tooltipWidth = biggerWidth + tooltipData.tooltipPadding.horizontal;
    final double tooltipHeight = sumTextsHeight + tooltipData.tooltipPadding.vertical;

    /// draw the background rect with rounded radius
    final Rect rect = Rect.fromLTWH(mostTopOffset.dx - (tooltipWidth / 2), mostTopOffset.dy - tooltipHeight - tooltipData.tooltipBottomMargin, tooltipWidth, tooltipHeight);
    final Radius radius = Radius.circular(tooltipData.tooltipRoundedRadius);
    final RRect roundedRect = RRect.fromRectAndCorners(rect, topLeft: radius, topRight: radius, bottomLeft: radius, bottomRight: radius);
    bgTouchTooltipPaint.color = tooltipData.tooltipBgColor;
    canvas.drawRRect(roundedRect, bgTouchTooltipPaint);

    /// draw the texts one by one in below of each other
    double topPosSeek = tooltipData.tooltipPadding.top;
    for (TextPainter tp in drawingTextPainters) {
      final drawOffset = Offset(
        rect.center.dx - (tp.width / 2),
        rect.topCenter.dy + topPosSeek,
      );
      tp.paint(canvas, drawOffset);
      topPosSeek += tp.height;
      topPosSeek += textsBelowMargin;
    }
  }

  /// We add our needed horizontal space to parent needed.
  /// we have some titles that maybe draw in the left side of our chart,
  /// then we should draw the chart a with some left space,
  /// the left space is [getLeftOffsetDrawSize], and the whole
  @override
  double getExtraNeededHorizontalSpace() {
    double parentNeeded = super.getExtraNeededHorizontalSpace();
    if (data.titlesData.show && data.titlesData.showVerticalTitles) {
      return parentNeeded +
        data.titlesData.verticalTitlesReservedWidth +
        data.titlesData.verticalTitleMargin;
    }
    return parentNeeded;
  }

  /// We add our needed vertical space to parent needed.
  /// we have some titles that maybe draw in the bottom side of our chart.
  @override
  double getExtraNeededVerticalSpace() {
    double parentNeeded = super.getExtraNeededVerticalSpace();
    if (data.titlesData.show && data.titlesData.showHorizontalTitles) {
      return parentNeeded +
        data.titlesData.horizontalTitlesReservedHeight +
        data.titlesData.horizontalTitleMargin;
    }
    return parentNeeded;
  }

  /// calculate left offset for draw the chart,
  /// maybe we want to show both left and right titles,
  /// then just the left titles will effect on this function.
  @override
  double getLeftOffsetDrawSize() {
    double parentNeeded = super.getLeftOffsetDrawSize();
    if (data.titlesData.show && data.titlesData.showVerticalTitles) {
      return parentNeeded +
        data.titlesData.verticalTitlesReservedWidth +
        data.titlesData.verticalTitleMargin;
    }
    return parentNeeded;
  }

  @override
  bool shouldRepaint(LineChartPainter oldDelegate) =>
      oldDelegate.data != data ||
        oldDelegate.touchController != touchController;

}

class TouchedSpot {
  final FlSpot spot;
  final Offset offset;
  final LineChartBarData barData;

  TouchedSpot(
    this.spot,
    this.offset,
    this.barData,
  );
}