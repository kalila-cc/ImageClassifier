#include "LivePhoto.h"
#include "Store.h"
#include <QCoreApplication>
#include <QFileInfo>
#include <QDateTime>
#include <QDir>
#include <QProcess>
#include <QTemporaryFile>
#include <QJsonDocument>
#include <QElapsedTimer>
#include <QUuid>
#include <windows.h>
#include <stdexcept>

namespace {
QString toolPath(){
    for(const auto &path:{QCoreApplication::applicationDirPath()+"/media/exiftool/ExifTool.exe",QString(APP_PROJECT_DIR)+"/.tools/exiftool/ExifTool.exe"})if(QFileInfo::exists(path))return path;
    return {};
}
QHash<QString,QString> identifiers(Store &store,const QVariantList &items,const std::shared_ptr<std::atomic_bool> &cancel){
    QHash<QString,QString> result;QStringList pending;QHash<QString,QVariantMap> records;
    const auto tool=toolPath();if(tool.isEmpty())return result;
    for(const auto &v:items){
        const auto a=v.toMap();const auto path=a["path"].toString();const auto ext=QFileInfo(path).suffix().toLower();
        if(!QStringList{"jpg","jpeg","heic","heif","mov","mp4"}.contains(ext)||a["liveType"]=="embedded")continue;
        const auto old=store.rows("SELECT identifier FROM live_metadata WHERE path=? AND size=? AND mtime=?",{path,a["size"],a["mtime"]});
        if(!old.isEmpty())result[path]=old[0].toMap()["identifier"].toString();
        else {pending.append(path);records[path]=a;}
    }
    for(int start=0;start<pending.size()&&!cancel->load();start+=128){
        QTemporaryFile args;if(!args.open())throw std::runtime_error("无法创建媒体元数据请求");
        args.write("--\n");for(const auto &path:pending.mid(start,128))args.write(path.toUtf8()+"\n");args.flush();
        QProcess process;auto environment=QProcessEnvironment::systemEnvironment();environment.remove("LC_ALL");environment.remove("LC_CTYPE");environment.remove("LANG");process.setProcessEnvironment(environment);
        process.setCreateProcessArgumentsModifier([](QProcess::CreateProcessArguments *args){args->flags|=CREATE_NO_WINDOW;});
        process.start(tool,{"-config","","-charset","filename=UTF8","-j","-G1","-Apple:ContentIdentifier","-Keys:ContentIdentifier","-@",args.fileName()});
        QElapsedTimer timer;timer.start();
        while(!process.waitForFinished(100)){
            if(cancel->load()||timer.elapsed()>30000||process.state()==QProcess::NotRunning){process.kill();process.waitForFinished();break;}
        }
        if(cancel->load())break;
        QJsonParseError error;const auto document=QJsonDocument::fromJson(process.readAllStandardOutput(),&error);
        if(error.error!=QJsonParseError::NoError||!document.isArray())throw std::runtime_error("Live Photos 元数据读取失败，请检查媒体组件后刷新");
        for(const auto &value:document.toVariant().toList()){
            const auto row=value.toMap();const auto path=QDir::cleanPath(row["SourceFile"].toString());if(!records.contains(path))continue;
            const auto a=records[path];const auto key=a["type"]=="视频"?"Keys:ContentIdentifier":"Apple:ContentIdentifier";
            const QUuid uuid(row[key].toString());const auto identifier=uuid.isNull()?QStringLiteral(""):uuid.toString(QUuid::WithoutBraces).toLower();
            result[path]=identifier;
            if(!row.contains("Error"))store.exec("INSERT INTO live_metadata(path,size,mtime,identifier) VALUES(?,?,?,?) ON CONFLICT(path) DO UPDATE SET size=excluded.size,mtime=excluded.mtime,identifier=excluded.identifier",{path,a["size"],a["mtime"],identifier});
        }
    }
    return result;
}
}
QVariantList LivePhoto::pairAssets(Store &store,QVariantList items,const std::shared_ptr<std::atomic_bool> &cancel){
    const auto ids=identifiers(store,items,cancel);QHash<QString,QList<int>> groups;
    for(int i=0;i<items.size();++i){auto a=items[i].toMap();const auto path=a["path"].toString();const auto id=ids.value(path);
        a["liveSchema"]=2;items[i]=a;
        if(!id.isEmpty())groups[QFileInfo(path).absolutePath().toLower()+"/"+id].append(i);
    }
    QSet<int> hidden;
    for(auto it=groups.cbegin();it!=groups.cend();++it){
        QList<int> photos,videos;for(int index:it.value()){if(items[index].toMap()["type"]=="视频")videos.append(index);else photos.append(index);}
        if(photos.size()==1&&videos.size()==1){
            auto photo=items[photos[0]].toMap();const auto video=items[videos[0]].toMap();
            photo["liveVideo"]=QVariantMap{{"id",video["id"]},{"path",video["path"]},{"size",video["size"]},{"mtime",video["mtime"]}};
            photo["liveIdentifier"]=ids.value(photo["path"].toString());photo["isLive"]=true;photo["liveType"]="apple";photo["kind"]="LIVE";photo["blocked"]="";
            items[photos[0]]=photo;hidden.insert(videos[0]);
            store.exec("UPDATE assets SET blocked='' WHERE id IN (?,?)",{photo["id"],video["id"]});
        }else for(int index:it.value()){
            auto a=items[index].toMap();a["blocked"]=photos.isEmpty()||videos.isEmpty()?"Live Photo 缺少配套照片或视频，请将完整文件放在同一目录后刷新":"Live Photo 关联标识重复，无法确定唯一配对，请分开副本后刷新";a["kind"]="待配对";a["isLive"]=false;
            store.exec("UPDATE assets SET blocked=? WHERE id=?",{a["blocked"],a["id"]});items[index]=a;
        }
    }
    QVariantList result;for(int i=0;i<items.size();++i)if(!hidden.contains(i))result.append(items[i]);return result;
}
