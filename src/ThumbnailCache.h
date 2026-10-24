#pragma once
#include <QCache>
#include <QImage>
#include <QMutex>
#include <QString>
#include <functional>

// Only small, cropped thumbnails belong here; full-size previews stay uncached.
class ThumbnailCache {
public:
    explicit ThumbnailCache(QString directory,int memoryKiB=128*1024,qint64 diskBytes=512LL*1024*1024);
    QImage get(const QString &source,QSize size,const std::function<QImage()> &decode);
private:
    QString directory;
    QCache<QString,QImage> memory;
    QMutex mutex;
    qint64 diskLimit,diskUsage=-1;
    void pruneDisk();
};
