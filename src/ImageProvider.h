#pragma once
#include <QQuickImageProvider>
class ImageProvider : public QQuickImageProvider {
public:
    explicit ImageProvider(QString database);
    QImage requestImage(const QString &id,QSize *size,const QSize &requestedSize) override;
private:
    QString database;
};
