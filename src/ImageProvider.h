#pragma once
#include <QQuickImageProvider>
#include <QCache>
#include <QMutex>
#include "ThumbnailCache.h"
class ImageProvider : public QQuickImageProvider {
public:
    explicit ImageProvider(QString database);
    QImage requestImage(const QString &id,QSize *size,const QSize &requestedSize) override;
private:
    QString database;
    ThumbnailCache thumbnails;
    QCache<QString,QImage> videoFrames{32768}; // KiB; bounded across thumbnail sizes.
    QMutex videoFramesMutex;
    QImage videoThumbnail(const QString &path,int edge);
};
