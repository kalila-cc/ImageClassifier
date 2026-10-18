#pragma once
#include <QSize>
#include <QRectF>
#include <QTransform>
#include <QVariantMap>

// All coordinates refer to the EXIF-oriented source and Qt's rotated canvas.
class CropGeometry {
public:
    CropGeometry(QSize source, double angle);
    QSize canvasSize() const { return canvas; }
    QPointF sourceCenter() const { return forward.map(QPointF(source.width()/2.0,source.height()/2.0)); }
    bool contains(const QRectF &pixelRect, double margin = 0) const;
    QVariantMap constrain(const QVariantMap &requested, const QVariantMap &previous = {}) const;
    QRect checkedPixelRect(const QVariantMap &spec) const;
private:
    QSize source, canvas;
    QTransform forward, inverse;
    double angle, inset;
    QRectF pixels(const QVariantMap &spec) const;
};
