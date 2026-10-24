#include "Media.h"
#include <QDateTime>
#include <QCollator>
#include <QFile>
#include <QImageReader>
#include <QDir>
#include <QtEndian>
#include <windows.h>
#include <shobjidl.h>
#include <propsys.h>
#include <algorithm>

namespace {
// COM belongs to the calling worker thread, including when Qt reuses that thread.
struct ComScope {
    HRESULT result=CoInitializeEx(nullptr,COINIT_MULTITHREADED);
    ~ComScope(){if(SUCCEEDED(result))CoUninitialize();}
};
const PROPERTYKEY photoDate={{0x14b81da1,0x0135,0x4d31,{0x96,0xd9,0x6c,0xbf,0xc9,0x67,0x1a,0x99}},36867};
const PROPERTYKEY mediaDate={{0x2e4b640d,0x5019,0x46d8,{0x88,0x81,0x55,0x41,0x4c,0xc5,0xca,0xa0}},100};
constexpr auto timeKey="ImageClassifier.CaptureTime";
constexpr auto sourceKey="ImageClassifier.TimeSource";

QVariantMap inheritedTime(const QString &path) {
    QFile file(path);if(!file.open(QIODevice::ReadOnly)||file.read(8)!=QByteArray::fromHex("89504e470d0a1a0a"))return {};
    QMap<QByteArray,QByteArray> values;
    // Skip pixel data without decoding it. Bound work and allocations for malformed input.
    for(int i=0;i<4096&&!file.atEnd();++i){
        const auto header=file.read(8);if(header.size()!=8)break;
        const auto length=qFromBigEndian<quint32>(reinterpret_cast<const uchar *>(header.constData()));
        const auto type=header.mid(4);const auto end=file.pos()+qint64(length)+4;
        if(end>file.size())break;
        if(type=="tEXt"&&length<=4096){
            const auto data=file.read(length);const auto separator=data.indexOf('\0');
            if(separator>0)values.insert(data.left(separator),data.mid(separator+1));
        }
        if(!file.seek(end)||type=="IEND")break;
    }
    const auto date=QDateTime::fromString(QString::fromLatin1(values.value(timeKey)),Qt::ISODateWithMs);
    if(!date.isValid())return {};
    auto source=QString::fromLatin1(values.value(sourceKey));
    if(source!="photo"&&source!="media"&&source!="modified")source="photo";
    return {{"captureTime",date.toMSecsSinceEpoch()},{"timeSource",source}};
}
}

QVariantMap Media::captureTime(const QString &path) {
    const QFileInfo file(path);
    if(file.suffix().compare("png",Qt::CaseInsensitive)==0){
        const auto inherited=inheritedTime(path);if(!inherited.isEmpty())return inherited;
    }
    if(QStringList{"jpg","jpeg"}.contains(file.suffix().toLower())){
        QImageReader reader(path);
        const auto date=QDateTime::fromString(reader.text(timeKey),Qt::ISODateWithMs);
        if(date.isValid()){
            auto source=reader.text(sourceKey);
            if(source!="photo"&&source!="media"&&source!="modified")source="photo";
            return {{"captureTime",date.toMSecsSinceEpoch()},{"timeSource",source}};
        }
    }
    const bool video=QStringList{"mp4","mov"}.contains(file.suffix().toLower());
    ComScope com;IPropertyStore *properties=nullptr;
    const auto native=QDir::toNativeSeparators(file.absoluteFilePath());
    if((SUCCEEDED(com.result)||com.result==RPC_E_CHANGED_MODE)&&
       SUCCEEDED(SHGetPropertyStoreFromParsingName(reinterpret_cast<LPCWSTR>(native.utf16()),nullptr,GPS_DEFAULT,IID_PPV_ARGS(&properties)))){
        PROPVARIANT value{};const auto result=properties->GetValue(video?mediaDate:photoDate,&value);
        qint64 time=0;bool valid=false;
        if(SUCCEEDED(result)&&value.vt==VT_FILETIME){
            ULARGE_INTEGER ticks;ticks.LowPart=value.filetime.dwLowDateTime;ticks.HighPart=value.filetime.dwHighDateTime;
            if(ticks.QuadPart){time=qint64(ticks.QuadPart/10000)-11644473600000LL;valid=QDateTime::fromMSecsSinceEpoch(time).isValid();}
        }
        PropVariantClear(&value);properties->Release();
        if(valid)return {{"captureTime",time},{"timeSource",video?"media":"photo"}};
    }
    return {{"captureTime",file.lastModified().toMSecsSinceEpoch()},{"timeSource","modified"}};
}

void Media::inheritCaptureTime(QImage &image,const QVariantMap &time) {
    image.setText(timeKey,QDateTime::fromMSecsSinceEpoch(time.value("captureTime").toLongLong(),QTimeZone::UTC).toString(Qt::ISODateWithMs));
    image.setText(sourceKey,time.value("timeSource","modified").toString());
}

void Media::sortByCaptureTime(QVariantList &items) {
    QCollator names;names.setNumericMode(true);names.setCaseSensitivity(Qt::CaseInsensitive);
    std::sort(items.begin(),items.end(),[&](const QVariant &a,const QVariant &b){
        const auto left=a.toMap(),right=b.toMap();
        const auto lt=left.value("captureTime",left.value("mtime")).toLongLong();
        const auto rt=right.value("captureTime",right.value("mtime")).toLongLong();
        if(lt!=rt)return lt>rt;
        const auto lp=left.value("path").toString(),rp=right.value("path").toString();
        const auto order=names.compare(lp,rp);return order?order<0:lp<rp;
    });
}
