#pragma once
#include <QImage>
namespace HeifImage {
bool supportedPath(const QString &path);
QSize size(const QString &path);
QImage read(const QString &path,int maxEdge);
}
