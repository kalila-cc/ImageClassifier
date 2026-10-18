#include "CropGeometry.h"
#include <QImage>
#include <QtMath>
#include <stdexcept>
#include <algorithm>

CropGeometry::CropGeometry(QSize size, double degrees):source(size),angle(degrees) {
    if(source.width()<2 || source.height()<2 || !std::isfinite(angle) || std::abs(angle)>360)
        throw std::runtime_error("图片尺寸或旋转角度无效");
    forward=QImage::trueMatrix(QTransform().rotate(angle),source.width(),source.height());
    inverse=forward.inverted();
    const auto bounds=forward.mapRect(QRectF(QPointF(0,0),source));
    canvas=QSize(qCeil(bounds.right()-1e-7),qCeil(bounds.bottom()-1e-7));
    // Leave room for output pixel rounding and smooth interpolation at oblique edges.
    inset=std::abs(std::remainder(angle,90.0))<1e-8?0:std::min({3.0,source.width()/20.0,source.height()/20.0});
}
QRectF CropGeometry::pixels(const QVariantMap &s) const {
    return {s.value("x").toDouble()*canvas.width(),s.value("y").toDouble()*canvas.height(),
            s.value("w").toDouble()*canvas.width(),s.value("h").toDouble()*canvas.height()};
}
bool CropGeometry::contains(const QRectF &r,double margin) const {
    if(!std::isfinite(r.x()+r.y()+r.width()+r.height()) || r.width()<0 || r.height()<0)return false;
    for(const auto &p:{r.topLeft(),r.topRight(),r.bottomLeft(),r.bottomRight()}) {
        const auto q=inverse.map(p);
        if(q.x()<margin-1e-7 || q.y()<margin-1e-7 || q.x()>source.width()-margin+1e-7 || q.y()>source.height()-margin+1e-7)return false;
    }
    return true;
}
QVariantMap CropGeometry::constrain(const QVariantMap &requested,const QVariantMap &previous) const {
    auto desired=pixels(requested);
    if(!std::isfinite(desired.x()+desired.y()+desired.width()+desired.height()) || desired.width()<=0 || desired.height()<=0)
        throw std::runtime_error("裁剪区域无效");
    const double ratio=requested.value("ratio").toDouble();
    if(!std::isfinite(ratio) || ratio<0)throw std::runtime_error("裁剪比例无效");
    if(ratio>0) {
        const auto center=desired.center();
        desired.setHeight(desired.width()/ratio);desired.moveCenter(center);
    }
    if(!contains(desired,inset)) {
        // Dragging interpolates from the last valid rectangle: translation keeps
        // its size, resizing keeps the opposite corner. Rotation starts at center.
        QRectF start(forward.map(QPointF(source.width()/2.0,source.height()/2.0)),QSizeF(0,0));
        if(!previous.isEmpty() && previous.value("angle").toDouble()==angle &&
           previous.value("ratio").toDouble()==ratio && contains(pixels(previous),inset))start=pixels(previous);
        auto at=[&](double t){return QRectF(start.x()+(desired.x()-start.x())*t,start.y()+(desired.y()-start.y())*t,
                                           start.width()+(desired.width()-start.width())*t,start.height()+(desired.height()-start.height())*t);};
        double low=0,high=1;
        for(int i=0;i<40;++i){const double mid=(low+high)/2;if(contains(at(mid),inset))low=mid;else high=mid;}
        desired=at(low);
    }
    auto result=requested;
    result["x"]=desired.x()/canvas.width();result["y"]=desired.y()/canvas.height();
    result["w"]=desired.width()/canvas.width();result["h"]=desired.height()/canvas.height();
    return result;
}
QRect CropGeometry::checkedPixelRect(const QVariantMap &s) const {
    const auto r=pixels(s);
    if(!contains(r) || r.width()<2 || r.height()<2)throw std::runtime_error("裁剪区域超出旋转后的有效图像，请打开该子图重新调整");
    const QRect rounded(qRound(r.x()),qRound(r.y()),qRound(r.width()),qRound(r.height()));
    if(rounded.width()<2 || rounded.height()<2 || !contains(QRectF(rounded),inset>0?std::min(1.0,inset/3):0))
        throw std::runtime_error("裁剪边缘超出有效图像，请稍微缩小区域后重试");
    return rounded;
}
