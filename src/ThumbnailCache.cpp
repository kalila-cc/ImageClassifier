#include "ThumbnailCache.h"
#include <QCryptographicHash>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QImageReader>
#include <QImageWriter>
#include <QMutexLocker>
#include <QSaveFile>
#include <algorithm>

namespace {
QString version(const QFileInfo &file) {
    return file.absoluteFilePath()+"|"+QString::number(file.size())+"|"+QString::number(file.lastModified().toMSecsSinceEpoch());
}
}

ThumbnailCache::ThumbnailCache(QString path,int memoryKiB,qint64 diskBytes)
    :directory(std::move(path)),memory(std::max(0,memoryKiB)),diskLimit(std::max<qint64>(0,diskBytes)) {}

void ThumbnailCache::pruneDisk() {
    const auto files=QDir(directory).entryInfoList({"*.png"},QDir::Files|QDir::NoSymLinks,QDir::Time|QDir::Reversed);
    diskUsage=0;
    for(const auto &file:files)diskUsage+=file.size();
    for(const auto &file:files) {
        if(diskUsage<=diskLimit)break;
        if(QFile::remove(file.absoluteFilePath()))diskUsage-=file.size();
    }
}

QImage ThumbnailCache::get(const QString &source,QSize size,const std::function<QImage()> &decode) {
    const QFileInfo file(source);
    if(!file.isFile())return {};
    const auto sourceVersion=version(file);
    const auto key=QString::fromLatin1(QCryptographicHash::hash(
        ("cover-v1|"+sourceVersion+"|"+QString::number(size.width())+"x"+QString::number(size.height())).toUtf8(),QCryptographicHash::Sha256).toHex());
    const auto cachedPath=QDir(directory).filePath(key+".png");
    {
        QMutexLocker lock(&mutex);
        if(const auto *cached=memory.object(key))return *cached;
        if(diskLimit>0) {
            if(diskUsage<0)pruneDisk();
            QImageReader reader(cachedPath);
            // Reject corrupt/mismatched cache entries before allocating their pixels.
            if(reader.size()==size) {
                auto image=reader.read();
                if(!image.isNull()) {
                    memory.insert(key,new QImage(image),int((image.sizeInBytes()+1023)/1024));
                    return image;
                }
            }
        }
    }
    auto image=decode();
    if(image.isNull()||image.size()!=size)return image;
    // An external edit during decoding must not poison a versioned cache entry.
    const QFileInfo after(source);
    if(!after.isFile()||version(after)!=sourceVersion)return image;
    {
        QMutexLocker lock(&mutex);
        memory.insert(key,new QImage(image),int((image.sizeInBytes()+1023)/1024));
        if(diskLimit>0&&QDir().mkpath(directory)) {
            const auto oldSize=QFileInfo(cachedPath).size();
            QSaveFile output(cachedPath);
            if(output.open(QIODevice::WriteOnly)) {
                QImageWriter writer(&output,"png");writer.setCompression(1);
                if(writer.write(image)&&output.commit()) {
                    diskUsage+=QFileInfo(cachedPath).size()-oldSize;
                    if(diskUsage>diskLimit)pruneDisk();
                }
            }
        }
    }
    return image;
}
