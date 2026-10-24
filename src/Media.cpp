#include "Media.h"
#include "LivePhoto.h"
#include "HeifImage.h"
#include "FileOps.h"
#include "CropGeometry.h"
#include <QDirIterator>
#include <QImageReader>
#include <QUrl>
#include <QUuid>
#include <QDateTime>
#include <QCollator>
#include <QPainter>
#include <QRegularExpression>
#include <windows.h>
#include <algorithm>
#include <cmath>
#include <stdexcept>

QString Media::path(const QString &s) { return QDir::cleanPath(QUrl(s).isLocalFile()?QUrl(s).toLocalFile():s); }
bool Media::isSupportedFile(const QFileInfo &file) {
    static const QSet<QString> extensions={"jpg","jpeg","png","heic","heif","mp4","mov","webp","bmp"};
    return file.isFile()&&!file.isSymLink()&&!file.isJunction()&&extensions.contains(file.suffix().toLower())
           &&!file.fileName().startsWith(".imageclassifier-");
}
bool Media::validDirectoryName(const QString &s) {
    if(s.isEmpty() || s=="." || s==".." || s.endsWith('.') || s.endsWith(' ') || s.contains(QRegularExpression("[<>:\"/\\\\|?*\\x00-\\x1f]"))) return false;
    return !QRegularExpression("^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\\..*)?$",QRegularExpression::CaseInsensitiveOption).match(s).hasMatch();
}
QVariantList Media::scan(Store &store,const QStringList &roots,bool recursive,const std::shared_ptr<std::atomic_bool> &cancel) {
    QVariantList result; QSet<QString> seen;
    QCollator collator; collator.setNumericMode(true); collator.setCaseSensitivity(Qt::CaseInsensitive);
    store.exec("BEGIN IMMEDIATE");
    try {
    for(const auto &root:roots) {
        if(!QFileInfo(root).isDir()) throw std::runtime_error(("来源目录不存在："+root).toUtf8().constData());
        QStringList paths;
        std::function<void(const QString &)> visit=[&](const QString &directory) {
            if(cancel->load()) return;
            const auto entries=QDir(directory).entryInfoList(QDir::Files|QDir::Dirs|QDir::NoDotAndDotDot|QDir::NoSymLinks,QDir::Name);
            for(const auto &f:entries) {
                if(cancel->load()) return;
                const auto native=QDir::toNativeSeparators(f.absoluteFilePath());
                const auto attr=GetFileAttributesW(reinterpret_cast<LPCWSTR>(native.utf16()));
                if(attr==INVALID_FILE_ATTRIBUTES || attr&FILE_ATTRIBUTE_REPARSE_POINT) continue;
                if(f.isDir()) { if(recursive && !f.fileName().startsWith('.')) visit(f.absoluteFilePath()); }
                else if(isSupportedFile(f)) paths.append(f.absoluteFilePath());
            }
        };
        visit(root);
        std::sort(paths.begin(),paths.end(),[&](const QString &a,const QString &b){return collator.compare(a,b)<0;});
        QHash<QString,QStringList> groups;
        for(const auto &p:paths) { QFileInfo f(p); groups[(f.absolutePath()+"/"+f.completeBaseName()).toLower()].append(p); }
        for(const auto &p:paths) {
            if(cancel->load()) break;
            const QFileInfo f(p); const auto key=f.canonicalFilePath().toLower();
            if(seen.contains(key)) continue; seen.insert(key);
            const bool video=QStringList{"mov","mp4"}.contains(f.suffix().toLower());
            bool hasImage=false,hasMov=false;
            for(const auto &g:groups[(f.absolutePath()+"/"+f.completeBaseName()).toLower()]) {
                const auto ext=QFileInfo(g).suffix().toLower();
                if(ext=="mov") hasMov=true;
                if(QStringList{"jpg","jpeg","heic","heif"}.contains(ext)) hasImage=true;
            }
            const QString blocked=hasImage&&hasMov?"同名照片与 MOV 可能属于 Live Photos；配对尚未确认，暂不允许单独移动、复制或裁剪":"";
            auto old=store.rows("SELECT id FROM assets WHERE path=?",{p});
            const auto id=old.isEmpty()?QUuid::createUuid().toString(QUuid::WithoutBraces):old[0].toMap()["id"].toString();
            store.exec("INSERT INTO assets(id,path,root,size,mtime,type,blocked) VALUES(?,?,?,?,?,?,?) ON CONFLICT(path) DO UPDATE SET size=excluded.size,mtime=excluded.mtime,type=excluded.type,blocked=excluded.blocked",{id,p,root,f.size(),f.lastModified().toMSecsSinceEpoch(),video?"视频":"图片",blocked});
            result.append(QVariantMap{{"id",id},{"path",p},{"root",root},{"name",f.fileName()},{"size",f.size()},{"mtime",f.lastModified().toMSecsSinceEpoch()},{"type",video?"视频":"图片"},{"blocked",blocked},{"kind",blocked.isEmpty()?(video?"视频":""):"待配对"},{"url",QUrl::fromLocalFile(p).toString()},{"thumb","image://media/"+id+"/0/"+QString::number(f.lastModified().toMSecsSinceEpoch())}});
            auto item=result.last().toMap();const auto time=captureTime(p);
            for(auto it=time.begin();it!=time.end();++it)item.insert(it.key(),it.value());
            LivePhoto::annotate(item);
            result.last()=item;
        }
    }
    if(!cancel->load())result=LivePhoto::pairAssets(store,result,cancel);
    sortByCaptureTime(result);
    if(cancel->load())store.exec("ROLLBACK");else store.exec("COMMIT");
    } catch(...) {store.exec("ROLLBACK");throw;}
    return result;
}
QSize Media::orientedSize(const QString &path) {
    if(HeifImage::supportedPath(path))return HeifImage::size(path);
    QImageReader reader(path);auto size=reader.size();
    if(reader.transformation() & QImageIOHandler::TransformationRotate90)size.transpose();
    if(!size.isValid())throw std::runtime_error(("无法读取图片尺寸："+reader.errorString()).toUtf8().constData());
    return size;
}
QImage Media::rotateAndCrop(const QImage &source,const QVariantMap &spec) {
    const auto angle=spec.value("angle").toDouble();const CropGeometry geometry(source.size(),angle);
    const auto rect=geometry.checkedPixelRect(spec);
    const auto rotated=angle==0?source:source.transformed(QTransform().rotate(angle),Qt::SmoothTransformation);
    if(rotated.size()!=geometry.canvasSize())throw std::runtime_error("旋转坐标校验失败，未输出图片");
    return rotated.copy(rect);
}
QImage Media::read(const QString &path,int maxEdge,double angle) {
    if(HeifImage::supportedPath(path)){
        const auto image=HeifImage::read(path,maxEdge);
        return angle==0?image:image.transformed(QTransform().rotate(angle),Qt::SmoothTransformation);
    }
    QImageReader reader(path); reader.setAutoTransform(true);
    const QSize raw=reader.size();
    if(!raw.isValid()) throw std::runtime_error(("无法解码："+reader.errorString()).toUtf8().constData());
    if(qint64(raw.width())*raw.height()>160000000) throw std::runtime_error("图片过大，超过单图 1.6 亿像素资源上限");
    if(maxEdge>0 && std::max(raw.width(),raw.height())>maxEdge) reader.setScaledSize(raw.scaled(maxEdge,maxEdge,Qt::KeepAspectRatio));
    auto image=reader.read();
    if(image.isNull()) throw std::runtime_error(("无法解码："+reader.errorString()).toUtf8().constData());
    if(angle!=0) image=image.transformed(QTransform().rotate(angle),Qt::SmoothTransformation);
    return image;
}
QImage Media::thumbnail(const QString &path,QSize target) {
    target=QSize(std::max(1,target.width()),std::max(1,target.height()));
    if(target.width()>1024||target.height()>1024)target=target.scaled(1024,1024,Qt::KeepAspectRatio).expandedTo(QSize(1,1));
    const auto centerRect=[](QSize image,QSize aspect){
        QSize crop=image;
        if(qint64(image.width())*aspect.height()>qint64(image.height())*aspect.width())
            crop.setWidth(qBound(1,qRound(double(image.height())*aspect.width()/aspect.height()),image.width()));
        else crop.setHeight(qBound(1,qRound(double(image.width())*aspect.height()/aspect.width()),image.height()));
        return QRect(QPoint((image.width()-crop.width())/2,(image.height()-crop.height())/2),crop);
    };
    QImage image;
    if(!HeifImage::supportedPath(path)) {
        QImageReader reader(path);reader.setAutoTransform(true);
        const auto raw=reader.size();
        if(!raw.isValid()||qint64(raw.width())*raw.height()>160000000)
            throw std::runtime_error("图片尺寸无效或超过资源上限");
        if(reader.supportsOption(QImageIOHandler::ClipRect)) {
            // Clip in raw pixel coordinates, then scale and apply EXIF orientation.
            // A long JPEG no longer loses its short-axis detail before being cropped.
            auto rawTarget=target;
            if(reader.transformation()&QImageIOHandler::TransformationRotate90)rawTarget.transpose();
            const auto clip=centerRect(raw,rawTarget);
            reader.setClipRect(clip);
            if(clip.width()>rawTarget.width()||clip.height()>rawTarget.height())
                reader.setScaledSize(rawTarget);
            image=reader.read();
            if(image.isNull())throw std::runtime_error(("无法生成缩略图："+reader.errorString()).toUtf8().constData());
        }
    }
    if(image.isNull()) {
        // Formats without native region decoding need a sufficiently detailed
        // whole-image intermediate. Bound the result before retaining only its center.
        const auto oriented=orientedSize(path);
        const double coverScale=std::max(double(target.width())/oriented.width(),double(target.height())/oriented.height());
        const double budgetScale=std::sqrt(16000000.0/(double(oriented.width())*oriented.height()));
        const double scale=std::min({1.0,coverScale,budgetScale});
        const int edge=qBound(1,int(std::floor(std::max(oriented.width(),oriented.height())*scale)),32768);
        image=read(path,edge);
    }
    image=image.copy(centerRect(image.size(),target));
    return image.scaled(target,Qt::IgnoreAspectRatio,Qt::SmoothTransformation);
}
QImage Media::crop(const QImage &image,const QVariantMap &s) {
    const double x=s["x"].toDouble(),y=s["y"].toDouble(),w=s["w"].toDouble(),h=s["h"].toDouble();
    if(!std::isfinite(x+y+w+h) || x<0 || y<0 || w<=0 || h<=0 || x+w>1.000001 || y+h>1.000001) throw std::runtime_error("裁剪区域超出图片");
    QRect r(qRound(x*image.width()),qRound(y*image.height()),qRound(w*image.width()),qRound(h*image.height()));
    r=r.intersected(image.rect());
    if(r.width()<2 || r.height()<2) throw std::runtime_error("裁剪区域过小");
    return image.copy(r);
}
int Media::boundary(const QString &a,const QString &b) {
    try {
        const auto x=read(a,64).scaled(9,8).convertToFormat(QImage::Format_RGB32),y=read(b,64).scaled(9,8).convertToFormat(QImage::Format_RGB32);
        int hashDistance=0; double colorDistance=0;
        for(int row=0;row<8;++row) for(int col=0;col<8;++col) {
            if((qGray(x.pixel(col,row))>qGray(x.pixel(col+1,row)))!=(qGray(y.pixel(col,row))>qGray(y.pixel(col+1,row)))) ++hashDistance;
            const QColor p=x.pixelColor(col,row),q=y.pixelColor(col,row);
            colorDistance+=(abs(p.red()-q.red())+abs(p.green()-q.green())+abs(p.blue()-q.blue()))/3.0;
        }
        colorDistance/=64;
        if(hashDistance<=7 && colorDistance<32) return 1;
        if(hashDistance>=20 && colorDistance>50) return 0;
    } catch(...) {}
    return -1;
}
