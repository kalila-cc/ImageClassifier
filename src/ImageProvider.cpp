#include "ImageProvider.h"
#include "Store.h"
#include "Media.h"
#include <QPainter>
ImageProvider::ImageProvider(QString db):QQuickImageProvider(QQuickImageProvider::Image,QQmlImageProviderBase::ForceAsynchronousImageLoading),database(std::move(db)){}
QImage ImageProvider::requestImage(const QString &id,QSize *size,const QSize &requested) {
    const auto parts=id.split('/');
    try {
        Store s(database);const auto rows=s.rows("SELECT path,type FROM assets WHERE id=?",{parts.value(0)});
        if(rows.isEmpty())throw std::runtime_error("文件未找到");
        const auto a=rows[0].toMap();
        if(a["type"]=="视频")throw std::runtime_error("视频 · 点击播放");
        auto image=Media::read(a["path"].toString(),qBound(64,std::max(requested.width(),requested.height()),2560),parts.value(1).toDouble());
        if(size)*size=image.size();return image;
    }catch(const std::exception &e){
        QImage image(480,320,QImage::Format_RGB32);image.fill(QColor("#e5eadf"));QPainter p(&image);p.setPen(QColor("#6a7d5c"));QFont f;f.setPixelSize(15);p.setFont(f);p.drawText(image.rect().adjusted(20,20,-20,-20),Qt::AlignCenter|Qt::TextWordWrap,QString::fromUtf8(e.what()));if(size)*size=image.size();return image;
    }
}
