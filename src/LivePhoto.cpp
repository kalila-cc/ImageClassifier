#include "LivePhoto.h"
#include <QFile>
#include <QFileInfo>
#include <QDir>
#include <QDateTime>
#include <QSaveFile>
#include <QXmlStreamReader>
#include <QUrl>
#include <QUuid>
#include <QtEndian>
#include <QtConcurrent>
#include <stdexcept>

namespace {
constexpr qint64 maxClip=256*1024*1024;
constexpr qint64 maxHeader=4*1024*1024;
const QString cameraNs="http://ns.google.com/photos/1.0/camera/";
const QString itemNs="http://ns.google.com/photos/1.0/container/item/";
struct Metadata {bool legacy=false,modern=false; qint64 offset=0,length=0;};
bool parseXmp(const QByteArray &packet,Metadata &metadata) {
    QXmlStreamReader xml(packet);
    while(!xml.atEnd()) {
        if(xml.readNext()!=QXmlStreamReader::StartElement)continue;
        auto camera=[&](QStringView name,QStringView value) {
            if(name==u"MicroVideo")metadata.legacy=value==u"1";
            else if(name==u"MotionPhoto")metadata.modern=value==u"1";
            else if(name==u"MicroVideoOffset")metadata.offset=value.toLongLong();
        };
        QString semantic,mime; qint64 length=0;
        for(const auto &attr:xml.attributes()) {
            if(attr.namespaceUri()==cameraNs)camera(attr.name(),attr.value());
            if(attr.namespaceUri()!=itemNs)continue;
            if(attr.name()==u"Semantic")semantic=attr.value().toString();
            if(attr.name()==u"Mime")mime=attr.value().toString();
            if(attr.name()==u"Length")length=attr.value().toLongLong();
        }
        if(semantic=="MotionPhoto"&&(mime=="video/mp4"||mime=="video/quicktime"))metadata.length=length;
        if(xml.namespaceUri()==cameraNs) {
            const auto name=xml.name().toString();
            const auto text=xml.readElementText(QXmlStreamReader::ErrorOnUnexpectedElement);
            camera(name,text);
        }
    }
    return !xml.hasError();
}
bool validVideo(QFile &file,qint64 offset,qint64 length) {
    if(length<32||length>maxClip||offset<2||offset>file.size()-length)return false;
    const auto end=offset+length;
    bool first=true,moov=false,mdat=false;int boxes=0;
    for(qint64 pos=offset;pos<end;) {
        if(++boxes>4096||end-pos<8||!file.seek(pos))return false;
        const auto header=file.read(16);if(header.size()<8)return false;
        quint64 size=qFromBigEndian<quint32>(header.constData());
        const auto type=header.mid(4,4);quint64 minSize=8;
        if(size==1){if(header.size()<16)return false;size=qFromBigEndian<quint64>(header.constData()+8);minSize=16;}
        else if(size==0)size=end-pos;
        if(size<minSize||size>quint64(end-pos))return false;
        if(first&&(type!="ftyp"||size<16||size>4096))return false;
        first=false;
        if(type=="moov"&&size>minSize)moov=true;
        if(type=="mdat"&&size>minSize)mdat=true;
        pos+=qint64(size);
    }
    return moov&&mdat;
}
void fail(const char *message){throw std::runtime_error(message);}
}

QVariantMap LivePhoto::inspect(const QString &path) {
    QFile file(path);if(!file.open(QIODevice::ReadOnly)||file.read(2)!=QByteArray::fromHex("ffd8"))return {};
    Metadata metadata;
    // Only JPEG header segments are read during scanning, never pixel/video payloads.
    while(file.pos()<maxHeader) {
        auto marker=file.read(2);if(marker.size()!=2||quint8(marker[0])!=0xff)return {};
        while(quint8(marker[1])==0xff){auto next=file.read(1);if(next.isEmpty())return {};marker[1]=next[0];}
        const auto code=quint8(marker[1]);
        if(code==0xda)break;
        if(code==0xd9||code==0x00||code==0xd8)return {};
        if(code==0x01||(code>=0xd0&&code<=0xd7))continue;
        const auto lengthBytes=file.read(2);if(lengthBytes.size()!=2)return {};
        const auto length=qFromBigEndian<quint16>(lengthBytes.constData());
        if(length<2||file.pos()+length-2>file.size()||file.pos()+length-2>maxHeader)return {};
        if(code==0xe1) {
            const auto segment=file.read(length-2);
            static const QByteArray prefix("http://ns.adobe.com/xap/1.0/\0",29);
            if(segment.startsWith(prefix)&&!parseXmp(segment.mid(prefix.size()),metadata))return {};
        } else if(!file.seek(file.pos()+length-2))return {};
    }
    const qint64 length=metadata.modern?metadata.length:(metadata.legacy?metadata.offset:0);
    const qint64 offset=file.size()-length;
    if(offset<=file.pos()||!validVideo(file,offset,length))return {};
    return {{"offset",offset},{"length",length}};
}
void LivePhoto::annotate(QVariantMap &asset) {
    const auto extension=QFileInfo(asset["path"].toString()).suffix().toLower();
    const bool live=(extension=="jpg"||extension=="jpeg")&&!inspect(asset["path"].toString()).isEmpty();
    asset["isLive"]=live;
    asset["liveType"]=live?"embedded":"";
    asset["liveSchema"]=2;
    if(asset["blocked"].toString().isEmpty())asset["kind"]=live?"LIVE":asset["type"]=="视频"?"视频":"";
}

LivePhotoService::LivePhotoService(QObject *parent):QObject(parent),m_cache(QDir::tempPath()+"/ImageClassifier-live-XXXXXX"),m_generation(std::make_shared<std::atomic_uint64_t>(0)) {
    connect(&m_watcher,&QFutureWatcher<QVariantMap>::finished,this,[this]{
        const auto result=m_watcher.result();
        m_working=false;
        const bool current=result["generation"].toULongLong()==m_generation->load();
        if(current) {
            m_loading=false;m_source=result["source"].toString();
            if(m_source.isEmpty()){m_id.clear();m_owner.clear();}
            emit changed();
            if(result.contains("error"))emit failed(result["error"].toString());
        } else if(!result["source"].toString().isEmpty())QFile::remove(QUrl(result["source"].toString()).toLocalFile());
        if(!m_pending.isEmpty())launch();
    });
}
LivePhotoService::~LivePhotoService(){++*m_generation;m_watcher.waitForFinished();}
void LivePhotoService::stop(){
    ++*m_generation;m_pending.clear();m_id.clear();m_owner.clear();m_source.clear();m_loading=false;emit changed();
}
void LivePhotoService::start(const QVariantMap &asset,const QString &owner) {
    stop();
    if(!asset["isLive"].toBool()||asset["id"].toString().isEmpty()||!m_cache.isValid())return;
    m_id=asset["id"].toString();m_owner=owner;m_loading=true;m_pending=asset;emit changed();
    // One bounded worker; rapid switching replaces the pending request.
    if(!m_working)launch();
}
void LivePhotoService::launch(){
    m_working=true;
    const auto asset=m_pending;m_pending.clear();
    const auto epoch=m_generation->load();const auto generation=m_generation;
    const auto directory=m_cache.path();
    m_watcher.setFuture(QtConcurrent::run([asset,epoch,generation,directory]{
        QVariantMap result{{"generation",QVariant::fromValue<qulonglong>(epoch)}};
        try {
            for(const auto &old:QDir(directory).entryList({"*.mp4"},QDir::Files))QFile::remove(directory+"/"+old);
            const bool paired=asset["liveType"]=="apple";const auto media=paired?asset["liveVideo"].toMap():asset;
            const QString source=media["path"].toString();
            auto matches=[&]{for(const auto &a:{asset,media}){const QFileInfo f(a["path"].toString());if(!f.isFile()||f.size()!=a["size"].toLongLong()||f.lastModified().toMSecsSinceEpoch()!=a["mtime"].toLongLong())return false;}return true;};
            if(!matches())fail("文件已变化，请刷新目录后播放");
            const auto info=paired?QVariantMap{{"offset",0},{"length",media["size"]}}:LivePhoto::inspect(source);if(info.isEmpty())fail("未找到完整的实况视频，请刷新目录");
            if(info["length"].toLongLong()>maxClip)fail("实况视频超过 256 MB 预览上限");
            QFile input(source);if(!input.open(QIODevice::ReadOnly)||!input.seek(info["offset"].toLongLong()))fail("无法读取实况视频");
            const auto output=directory+"/"+QUuid::createUuid().toString(QUuid::WithoutBraces)+".mp4";
            QSaveFile destination(output);if(!destination.open(QIODevice::WriteOnly))fail("无法创建实况预览临时文件");
            qint64 left=info["length"].toLongLong();
            while(left>0) {
                if(generation->load()!=epoch)return result;
                const auto part=input.read(qMin<qint64>(left,1024*1024));
                if(part.isEmpty()||destination.write(part)!=part.size())fail("实况视频提取失败");
                left-=part.size();
            }
            if(!matches())fail("播放准备期间文件已变化，请刷新目录");
            if(generation->load()!=epoch)return result;
            if(!destination.commit())fail("实况预览临时文件保存失败");
            result["source"]=QUrl::fromLocalFile(output).toString();
        }catch(const std::exception &error){result["error"]=QString::fromUtf8(error.what());}
        return result;
    }));
}
