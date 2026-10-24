#include "ImageProvider.h"
#include "Store.h"
#include "Media.h"
#include <QDateTime>
#include <QFileInfo>
#include <QDir>
#include <QEventLoop>
#include <QMediaPlayer>
#include <QVideoSink>
#include <QVideoFrame>
#include <QTimer>
#include <QUrl>
#include <QMutexLocker>
#include <QThread>
#include <QFile>
#include <QBuffer>
#include <QImageReader>
#include <QRegularExpression>
#include <cmath>
ImageProvider::ImageProvider(QString db):QQuickImageProvider(QQuickImageProvider::Image,QQmlImageProviderBase::ForceAsynchronousImageLoading),database(std::move(db)),
    thumbnails(QFileInfo(database).absoluteDir().filePath("cache/thumbnails-v1")){}
QImage ImageProvider::videoThumbnail(const QString &path,int edge) {
    const QFileInfo file(path);
    if(!file.isFile())return {};
    edge=qBound(192,edge,960);
    const auto key=file.absoluteFilePath()+"|"+QString::number(file.size())+"|"+QString::number(file.lastModified().toMSecsSinceEpoch());
    {QMutexLocker lock(&videoFramesMutex);if(const auto cached=videoFrames.object(key))return cached->scaled(edge,edge,Qt::KeepAspectRatio,Qt::SmoothTransformation);}
    // Keep the decoder's event loop off Qt Quick's image-loading thread: pumping
    // that thread's events inside requestImage can reenter/cancel its active job.
    // Only one frame is decoded, without an audio output or a player per tile.
    QImage image;
    auto *decoder=QThread::create([&]{
    QEventLoop loop;
    QTimer timeout;timeout.setSingleShot(true);
    QMediaPlayer player;QVideoSink sink;player.setVideoSink(&sink);
    bool positioned=false;
    QObject::connect(&player,&QMediaPlayer::durationChanged,&loop,[&](qint64 duration){
        if(!positioned&&duration>0){positioned=true;player.setPosition(qMin<qint64>(1000,duration/10));}
    });
    QObject::connect(&sink,&QVideoSink::videoFrameChanged,&loop,[&](const QVideoFrame &frame){
        if(!frame.isValid())return;
        const auto decoded=frame.toImage();if(decoded.isNull())return;
        image=decoded.scaled(960,960,Qt::KeepAspectRatio,Qt::SmoothTransformation);loop.quit();
    });
    QObject::connect(&player,&QMediaPlayer::errorOccurred,&loop,&QEventLoop::quit);
    QObject::connect(&player,&QMediaPlayer::mediaStatusChanged,&loop,[&](QMediaPlayer::MediaStatus status){
        if(status==QMediaPlayer::InvalidMedia||status==QMediaPlayer::EndOfMedia)loop.quit();
    });
    QObject::connect(&timeout,&QTimer::timeout,&loop,&QEventLoop::quit);
    timeout.start(4000);player.setSource(QUrl::fromLocalFile(path));player.play();
    if(image.isNull()&&player.error()==QMediaPlayer::NoError)loop.exec();
    timeout.stop();player.stop();player.setSource({});
    });
    decoder->start();decoder->wait();delete decoder;
    // Cache successful frames only: a transient failure remains retryable.
    if(!image.isNull()) {QMutexLocker lock(&videoFramesMutex);videoFrames.insert(key,new QImage(image),int((image.sizeInBytes()+1023)/1024));}
    return image.isNull()?image:image.scaled(edge,edge,Qt::KeepAspectRatio,Qt::SmoothTransformation);
}
QImage ImageProvider::requestImage(const QString &id,QSize *size,const QSize &requested) {
    const auto parts=id.split('/');
    try {
        // Recolor the existing SVG assets without GPU effects. This also works
        // with software rendering and keeps a single source for each icon.
        if(parts.value(0)=="icon") {
            static const QStringList icons={"crop-free","crop-1-1","crop-4-3","crop-3-4","crop-16-9","rotate-left","rotate-right"};
            if(!icons.contains(parts.value(1))||!QRegularExpression("^[0-9a-fA-F]{6}$").match(parts.value(2)).hasMatch())throw std::runtime_error("Invalid icon");
#ifdef APP_UI_DIR
            const QString root=QString(APP_UI_DIR);
#else
            const QString root=QString(TEST_UI_DIR)+"/../ui";
#endif
            QFile file(root+"/icons/"+parts[1]+".svg");if(!file.open(QIODevice::ReadOnly))throw std::runtime_error("Icon missing");
            auto svg=file.readAll().replace("#16756a",("#"+parts[2]).toUtf8());
            QBuffer buffer(&svg);buffer.open(QIODevice::ReadOnly);QImageReader reader(&buffer,"svg");
            const int edge=qBound(16,qMax(requested.width(),requested.height()),128);reader.setScaledSize(QSize(edge,edge));
            auto image=reader.read();if(size)*size=image.size();return image;
        }
        Store s(database);const auto rows=s.rows("SELECT path,type FROM assets WHERE id=?",{parts.value(0)});
        if(rows.isEmpty())throw std::runtime_error("文件未找到");
        const auto a=rows[0].toMap();
        if(a["type"]=="视频") {
            auto image=videoThumbnail(a["path"].toString(),std::max(requested.width(),requested.height()));
            if(size)*size=image.size();return image;
        }
        if(parts.last()=="cover") {
            auto target=requested.isValid()?requested:QSize(600,420);
            if(target.width()>1024||target.height()>1024)target=target.scaled(1024,1024,Qt::KeepAspectRatio).expandedTo(QSize(1,1));
            const auto path=a["path"].toString();
            auto image=thumbnails.get(path,target,[&]{return Media::thumbnail(path,target);});
            if(size)*size=image.size();return image;
        }
        int edge=qBound(64,std::max(requested.width(),requested.height()),2560);
        if(parts.value(2)=="detail") {
            const auto dimensions=Media::orientedSize(a["path"].toString());
            const double pixels=double(dimensions.width())*dimensions.height();
            const double budgetScale=std::min(1.0,std::sqrt(16000000.0/std::max(1.0,pixels)));
            const int budgetEdge=std::max(1,int(std::max(dimensions.width(),dimensions.height())*budgetScale));
            edge=std::min(qBound(64,std::max(requested.width(),requested.height()),8192),budgetEdge);
        }
        auto image=Media::read(a["path"].toString(),edge,parts.value(1).toDouble());
        if(size)*size=image.size();return image;
    }catch(const std::exception &){
        // A rendered error message is still Image.Ready to QML. Return failure so
        // the UI can offer retry and prevent cropping an unavailable preview.
        if(size)*size=QSize();return {};
    }
}
