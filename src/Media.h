#pragma once
#include "Store.h"
#include <QImage>
#include <QFileInfo>
#include <atomic>

namespace Media {
bool isSupportedFile(const QFileInfo &file);
QVariantMap captureTime(const QString &path);
void inheritCaptureTime(QImage &image,const QVariantMap &time);
void sortByCaptureTime(QVariantList &items);
QVariantList scan(Store &store,const QStringList &roots,bool recursive,const std::shared_ptr<std::atomic_bool> &cancel);
QImage read(const QString &path,int maxEdge=0,double angle=0);
QImage thumbnail(const QString &path,QSize target);
QImage crop(const QImage &image,const QVariantMap &spec);
QSize orientedSize(const QString &path);
QImage rotateAndCrop(const QImage &orientedSource,const QVariantMap &spec);
int boundary(const QString &left,const QString &right); // 1 similar, 0 different, -1 uncertain
QString path(const QString &input);
bool validDirectoryName(const QString &name);
}
