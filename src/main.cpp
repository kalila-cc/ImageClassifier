#include "Backend.h"
#include "AppRestart.h"
#include "ImageProvider.h"
#include <QApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QStandardPaths>
#include <QImageReader>
#include <QIcon>
#include <QLockFile>
#include <QDir>
#include <QTimer>
#include <QMessageBox>
#include <QDebug>

int main(int argc,char **argv) {
    qputenv("QT_QUICK_CONTROLS_STYLE","Basic");
    qputenv("QT_FORCE_STDERR_LOGGING","1");
    QApplication app(argc,argv);app.setOrganizationName("ImageClassifier");app.setApplicationName("ImageClassifier");
    app.setWindowIcon(QIcon(":/brand/guitu.ico"));
    app.setFont(QFont("Microsoft YaHei UI",10));QImageReader::setAllocationLimit(512);
    QString restartError;
    if(!AppRestart::waitForParent(app.arguments().mid(1),&restartError)){
        qCritical().noquote()<<restartError;return 4;
    }
    QString data=qEnvironmentVariable("IMAGECLASSIFIER_DATA_DIR");
    if(data.isEmpty())data=QStandardPaths::writableLocation(QStandardPaths::AppLocalDataLocation);
    QDir().mkpath(data);QLockFile lock(data+"/app.lock");
    if(!lock.tryLock(0)){QMessageBox::information(nullptr,"归图","应用已打开，请使用现有窗口。");return 1;}
    try {
        Backend backend(data+"/library.sqlite");
        AppRestart restart;
        QObject::connect(&backend,&Backend::restartRequested,&restart,[&]{
            QString error;
            if(!restart.start(AppRestart::currentContext(data),&error))backend.restartFailed(error);
        });
        QObject::connect(&restart,&AppRestart::failed,&backend,&Backend::restartFailed);
        QObject::connect(&restart,&AppRestart::ready,&app,&QCoreApplication::quit);
        QQmlApplicationEngine engine;engine.rootContext()->setContextProperty("backend",&backend);
        engine.addImageProvider("media",new ImageProvider(data+"/library.sqlite"));
        engine.load(QUrl::fromLocalFile(QString(APP_UI_DIR)+"/Application.qml"));
        if(engine.rootObjects().isEmpty())return 2;
        if(app.arguments().contains("--smoke"))QTimer::singleShot(1200,&app,&QCoreApplication::quit);
        return app.exec();
    }catch(const std::exception &e){QMessageBox::critical(nullptr,"启动失败",QString::fromUtf8(e.what()));return 3;}
}
