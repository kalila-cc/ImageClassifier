#include "SmartCrop.h"
#include "Store.h"
#include "Media.h"
#include "CropGeometry.h"
#include <QtConcurrent>
#include <QDir>
#include <QFileInfo>
#include <QSaveFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <QDateTime>
#include <QUuid>
#include <QRegularExpression>
#include <QProcessEnvironment>
#include <stdexcept>

namespace {
void fail(const QString &message){throw std::runtime_error(message.toUtf8().constData());}
QStringList recordNames(const QString &root) {
    QStringList result;
    const QRegularExpression name("^r-[0-9]{17}-[0-9a-f-]{36}$");
    for(const auto &entry:QDir(root+"/recent").entryInfoList(QDir::Dirs|QDir::NoDotAndDotDot|QDir::NoSymLinks,QDir::Name))
        if(!entry.isJunction()&&name.match(entry.fileName()).hasMatch()&&QFileInfo::exists(entry.filePath()+"/record.json"))result.append(entry.fileName());
    return result;
}
void prune(const QString &root) {
    auto names=recordNames(root);
    while(names.size()>100) {
        const auto directory=QDir(root+"/recent").absoluteFilePath(names.takeFirst());
        // Only application-created, direct-child records; never follow a junction.
        const QFileInfo info(directory);
        if(info.isSymLink()||info.isJunction()||info.absolutePath()!=QDir(root+"/recent").absolutePath())continue;
        if(!QDir(directory).removeRecursively())fail("无法清理过期学习记录，请检查学习目录权限或占用");
    }
}
void cleanTemporaryRecords(const QString &root) {
    const QRegularExpression record("^r-[0-9]{17}-[0-9a-f-]{36}$"),request("^[0-9a-f-]{36}\\.jpg$");
    for(const auto &entry:QDir(root+"/staging").entryInfoList(QDir::Dirs|QDir::NoDotAndDotDot|QDir::NoSymLinks)) {
        if(!entry.isJunction()&&record.match(entry.fileName()).hasMatch()&&entry.absolutePath()==QDir(root+"/staging").absolutePath())
            QDir(entry.absoluteFilePath()).removeRecursively();
    }
    for(const auto &entry:QDir(root+"/requests").entryInfoList(QDir::Files|QDir::NoSymLinks))
        if(!entry.isJunction()&&request.match(entry.fileName()).hasMatch())QFile::remove(entry.absoluteFilePath());
}
}
QString SmartCropRecords::rootFor(const QString &database){return QFileInfo(database).absolutePath()+"/smart-crop";}
QVariantMap SmartCropRecords::frame(QSize size,double angle) {
    CropGeometry geometry(size,angle);
    const auto t=QImage::trueMatrix(QTransform().rotate(angle),size.width(),size.height());
    return {{"width",size.width()},{"height",size.height()},{"canvasWidth",geometry.canvasSize().width()},{"canvasHeight",geometry.canvasSize().height()},
            {"transform",QVariantList{t.m11(),t.m12(),t.m21(),t.m22(),t.dx(),t.dy()}}};
}
int SmartCropRecords::count(const QString &root){return recordNames(root).size();}
void SmartCropRecords::save(const QString &root,const QImage &image,const QString &hash,const QVariantList &crops,const QString &operationId) {
    if(!operationId.isEmpty())for(const auto &entry:recordNames(root)) {
        QFile existing(root+"/recent/"+entry+"/record.json");
        if(!existing.open(QIODevice::ReadOnly))fail("无法核对已有学习记录");
        if(QJsonDocument::fromJson(existing.readAll()).object().value("operationId").toString()==operationId)return;
    }
    const auto name="r-"+QDateTime::currentDateTimeUtc().toString("yyyyMMddHHmmsszzz")+"-"+QUuid::createUuid().toString(QUuid::WithoutBraces);
    const auto recent=root+"/recent",staging=root+"/staging/"+name;
    if(!QDir().mkpath(staging)||!QDir().mkpath(recent))fail("无法建立智能裁剪学习目录");
    try {
        auto sample=(image.width()>1280||image.height()>1280?image.scaled(1280,1280,Qt::KeepAspectRatio,Qt::SmoothTransformation):image).convertToFormat(QImage::Format_RGB32);
        if(!sample.save(staging+"/source.jpg","JPG",92))fail("无法保存学习用缩略原图");
        QVariantList labels;
        for(const auto &v:crops) {
            auto c=v.toMap();c.remove("target");c["frame"]=frame(image.size(),c.value("angle").toDouble());labels.append(c);
        }
        QVariantMap record{{"schema",1},{"id",name},{"created",QDateTime::currentDateTimeUtc().toString(Qt::ISODateWithMs)},
                           {"sourceHash",hash},{"operationId",operationId},{"width",image.width()},{"height",image.height()},{"crops",labels}};
        QSaveFile file(staging+"/record.json");
        const auto bytes=QJsonDocument::fromVariant(record).toJson();
        if(!file.open(QIODevice::WriteOnly)||file.write(bytes)!=bytes.size()||!file.commit())fail("无法保存学习记录");
        if(!QDir().rename(staging,recent+"/"+name))fail("无法提交学习记录");
        try {prune(root);}
        catch(...) {QDir(recent+"/"+name).removeRecursively();throw;}
    } catch(...) {QDir(staging).removeRecursively();throw;}
}

SmartCrop::SmartCrop(const QString &db,QObject *parent):QObject(parent),database(db),root(SmartCropRecords::rootFor(db)) {
    const auto install=qEnvironmentVariable("IMAGECLASSIFIER_AI_HOME",QString(APP_PROJECT_DIR)+"/.tools/smart-crop");
    python=install+"/runtime/Scripts/python.exe";models=install+"/models";worker=QString(APP_PROJECT_DIR)+"/tools/ai/worker.py";
    m_installer=new ModelInstaller(QString(APP_PROJECT_DIR),install,this);
    connect(m_installer,&ModelInstaller::changed,this,[this]{
        if(!available()){pendingPrediction.clear();latestToken.clear();}
        if(!busy())m_status=available()?"本地模型已就绪":(m_installer->installing()?"模型安装中，可继续手动裁剪":"智能模型未安装，可前往设置安装");
        emit changed();
    });
    Store store(db);m_enabled=store.value("smartCropEnabled","0")=="1";
    cleanTemporaryRecords(root);
    QString cleanupWarning;
    try {prune(root);}catch(const std::exception &e){cleanupWarning=QString::fromUtf8(e.what());}
    m_count=SmartCropRecords::count(root);
    deadline.setSingleShot(true);deadline.setInterval(120000);
    connect(&deadline,&QTimer::timeout,this,[this]{processError("智能裁剪计算超时，可点击重新建议重试");});
    connect(&process,&QProcess::started,this,&SmartCrop::sendActive);
    connect(&process,&QProcess::readyReadStandardError,this,[this]{stderrBuffer+=process.readAllStandardError();stderrBuffer=stderrBuffer.right(8192);});
    connect(&process,&QProcess::readyReadStandardOutput,this,[this]{
        stdoutBuffer+=process.readAllStandardOutput();
        while(stdoutBuffer.contains('\n')) {
            const auto end=stdoutBuffer.indexOf('\n');const auto line=stdoutBuffer.left(end);stdoutBuffer.remove(0,end+1);
            const auto response=QJsonDocument::fromJson(line).toVariant().toMap();
            if(!response.isEmpty()&&response.value("token")==active.value("token"))finish(response);
        }
    });
    connect(&process,&QProcess::errorOccurred,this,[this](QProcess::ProcessError){if(!closing)processError("本地智能裁剪服务无法启动，请前往设置检查模型状态");});
    connect(&process,qOverload<int,QProcess::ExitStatus>(&QProcess::finished),this,[this](int code,QProcess::ExitStatus){
        if(!closing&&!active.isEmpty())processError(QString("智能裁剪服务已退出（%1），可重试").arg(code));
    });
    connect(&preparation,&QFutureWatcher<QVariantMap>::finished,this,[this]{
        const auto result=preparation.result();
        if(closing)return;
        if(result.contains("error")){finish({{"error",result["error"]}});return;}
        active["image"]=result["image"];
        if(!m_enabled||active.value("token").toString()!=latestToken){finish({{"error","已取消过期建议"}});return;}
        if(process.state()==QProcess::NotRunning){deadline.start();process.start(python,{"-u",worker,"--models",models,"--data",root});}
        else sendActive();
    });
    auto env=QProcessEnvironment::systemEnvironment();env.insert("PYTHONUTF8","1");env.insert("OMP_NUM_THREADS","4");
    process.setProcessEnvironment(env);process.setWorkingDirectory(QString(APP_PROJECT_DIR));
    m_status=available()?"本地模型已就绪":"智能模型未安装，可前往设置安装";
    if(!cleanupWarning.isEmpty())m_status=cleanupWarning;
    if(m_count&&available())QTimer::singleShot(1000,this,&SmartCrop::train);
}
SmartCrop::~SmartCrop() {
    closing=true;deadline.stop();preparation.waitForFinished();process.closeWriteChannel();
    if(preparation.future().isValid()&&preparation.future().resultCount()) {
        const auto prepared=preparation.result().value("image").toString();if(!prepared.isEmpty())QFile::remove(prepared);
    }
    if(!process.waitForFinished(1500)){process.kill();process.waitForFinished(1000);}
    const auto path=active.value("image").toString();if(!path.isEmpty())QFile::remove(path);
}
bool SmartCrop::available() const {
    if(!m_installer||!m_installer->installed())return false;
    for(const auto &path:{python,worker,models+"/person.onnx",models+"/pose.onnx",models+"/features.onnx"})if(!QFileInfo::exists(path))return false;
    return true;
}
void SmartCrop::refreshAvailability(){m_installer->refresh();m_status=available()?"本地模型已就绪":"智能模型未安装，可前往设置安装";emit changed();}
void SmartCrop::setEnabled(bool value) {
    if(value&&!available()){m_status="智能模型尚不可用，请前往设置安装";emit changed();return;}
    if(m_enabled==value)return;
    try {Store store(database);store.setValue("smartCropEnabled",value?"1":"0");}
    catch(const std::exception &e){m_status="智能模式设置保存失败："+QString::fromUtf8(e.what());emit changed();return;}
    m_enabled=value;if(!value){pendingPrediction.clear();latestToken.clear();}emit changed();
}
void SmartCrop::request(const QVariantMap &asset,const QVariantMap &dimensions,const QVariantMap &spec,const QString &token) {
    if(!m_enabled||asset.isEmpty()||asset.value("type")=="视频")return;
    latestToken=token;
    if(!available()){m_status="智能模型未安装，可前往设置安装";emit changed();emit suggestionFailed(token,m_status);return;}
    try {
        pendingPrediction={{"action","predict"},{"token",token},{"asset",asset},{"spec",spec},
            {"frame",SmartCropRecords::frame(QSize(dimensions["width"].toInt(),dimensions["height"].toInt()),spec.value("angle").toDouble())}};
        dispatch();
    }catch(const std::exception &e){emit suggestionFailed(token,QString::fromUtf8(e.what()));}
}
void SmartCrop::recordsChanged(){m_count=SmartCropRecords::count(root);emit changed();train();}
void SmartCrop::train(){if(!available())return;trainPending=true;dispatch();}
void SmartCrop::dispatch() {
    if(closing||!active.isEmpty()||!available())return;
    if(!pendingPrediction.isEmpty()) {
        active=pendingPrediction;pendingPrediction.clear();m_status="正在分析人物与裁剪偏好…";emit changed();
        const auto a=active.value("asset").toMap();const auto output=root+"/requests/"+QUuid::createUuid().toString(QUuid::WithoutBraces)+".jpg";
        preparation.setFuture(QtConcurrent::run([a,output]()->QVariantMap{
            try {
                QFileInfo source(a["path"].toString());
                auto unchanged=[&]{source.refresh();return source.exists()&&source.size()==a["size"].toLongLong()&&source.lastModified().toMSecsSinceEpoch()==a["mtime"].toLongLong();};
                if(!unchanged())fail("原图已变化，请刷新后重试");
                const auto image=Media::read(source.filePath(),1280);
                if(!unchanged())fail("原图在分析期间发生变化");
                if(!QDir().mkpath(QFileInfo(output).absolutePath())||!image.save(output,"JPG",92))fail("无法准备智能裁剪预览");
                return {{"image",output}};
            }catch(const std::exception &e){return {{"error",QString::fromUtf8(e.what())}};}
        }));
    } else if(trainPending) {
        trainPending=false;active={{"action","train"},{"token",QUuid::createUuid().toString()}};
        m_status="正在更新最近记录的裁剪偏好…";emit changed();
        if(process.state()==QProcess::NotRunning){deadline.start();process.start(python,{"-u",worker,"--models",models,"--data",root});}else sendActive();
    }
}
void SmartCrop::sendActive(){if(active.isEmpty())return;deadline.start();process.write(QJsonDocument::fromVariant(active).toJson(QJsonDocument::Compact)+'\n');}
void SmartCrop::finish(const QVariantMap &response) {
    if(active.isEmpty())return;
    deadline.stop();const auto completed=active;active.clear();
    const auto image=completed.value("image").toString();if(!image.isEmpty())QFile::remove(image);
    const bool predict=completed.value("action")=="predict";
    m_status=response.value("message","本地模型已就绪").toString();
    if(response.contains("error")) {
        m_status=response["error"].toString();
        if(predict&&m_enabled&&completed["token"].toString()==latestToken)emit suggestionFailed(completed["token"].toString(),m_status);
    } else if(predict&&m_enabled&&completed["token"].toString()==latestToken) {
        const auto a=completed["asset"].toMap();const QFileInfo file(a["path"].toString());
        if(file.exists()&&file.size()==a["size"].toLongLong()&&file.lastModified().toMSecsSinceEpoch()==a["mtime"].toLongLong()) {
            auto spec=completed["spec"].toMap();const auto crop=response["crop"].toMap();
            for(const auto &key:{"x","y","w","h"})spec[key]=crop.value(key);
            try {
                const auto f=completed["frame"].toMap();CropGeometry g(QSize(f["width"].toInt(),f["height"].toInt()),spec["angle"].toDouble());
                spec=g.constrain(spec);g.checkedPixelRect(spec);
                const QRectF region(spec["x"].toDouble(),spec["y"].toDouble(),spec["w"].toDouble(),spec["h"].toDouble());
                for(const auto &point:response.value("protectedFace").toList()) {
                    const auto p=point.toList();
                    if(p.size()!=2||!region.contains(QPointF(p[0].toDouble(),p[1].toDouble())))
                        fail("当前旋转角度或比例无法安全保留面部，请手动调整");
                }
                emit suggested(completed["token"].toString(),spec,m_status);
            }catch(const std::exception &e){emit suggestionFailed(completed["token"].toString(),QString::fromUtf8(e.what()));}
        } else emit suggestionFailed(completed["token"].toString(),"原图已变化，已忽略智能建议");
    }
    m_count=SmartCropRecords::count(root);emit changed();QTimer::singleShot(0,this,&SmartCrop::dispatch);
}
void SmartCrop::processError(const QString &error) {
    // Disconnect restart signals while terminating a failed worker.
    process.blockSignals(true);process.kill();process.waitForFinished(1000);process.blockSignals(false);
    stdoutBuffer.clear();stderrBuffer.clear();finish({{"error",error}});
}
