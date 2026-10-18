#include "FileOps.h"
#include "Media.h"
#include <QJsonDocument>
#include <QUrl>
#include <QFile>
#include <QFileInfo>
#include <QDir>
#include <QCryptographicHash>
#include <QUuid>
#include <QImageWriter>
#include <QDateTime>
#include <windows.h>
#include <stdexcept>

static void fail(const QString &message) { throw std::runtime_error(message.toUtf8().constData()); }
static QString native(const QString &path) {
    QString p=QDir::toNativeSeparators(QFileInfo(path).absoluteFilePath());
    if(p.startsWith("\\\\?\\")) return p;
    return p.startsWith("\\\\") ? "\\\\?\\UNC\\"+p.mid(2) : "\\\\?\\"+p;
}
class ReadGuard {
public:
    HANDLE h=INVALID_HANDLE_VALUE;
    explicit ReadGuard(const QString &path) {
        const auto p=native(path);
        h=CreateFileW(reinterpret_cast<LPCWSTR>(p.utf16()), GENERIC_READ, FILE_SHARE_READ|FILE_SHARE_DELETE, nullptr, OPEN_EXISTING, FILE_FLAG_SEQUENTIAL_SCAN, nullptr);
        if(h==INVALID_HANDLE_VALUE) fail("无法锁定文件读取，文件可能被占用："+path);
    }
    ~ReadGuard() { if(h!=INVALID_HANDLE_VALUE) CloseHandle(h); }
    QString identity() const {
        BY_HANDLE_FILE_INFORMATION info{};
        if(!GetFileInformationByHandle(h,&info)) fail("无法读取文件身份");
        return QString("%1:%2:%3").arg(info.dwVolumeSerialNumber).arg(info.nFileIndexHigh).arg(info.nFileIndexLow);
    }
};
static bool renameExclusive(const QString &from, const QString &to) {
    const auto a=native(from), b=native(to);
    return MoveFileExW(reinterpret_cast<LPCWSTR>(a.utf16()),reinterpret_cast<LPCWSTR>(b.utf16()),MOVEFILE_WRITE_THROUGH);
}
static QString directoryIdentity(const QString &path) {
    const auto p=native(path);
    HANDLE h=CreateFileW(reinterpret_cast<LPCWSTR>(p.utf16()),FILE_READ_ATTRIBUTES,
                        FILE_SHARE_READ|FILE_SHARE_WRITE|FILE_SHARE_DELETE,nullptr,OPEN_EXISTING,
                        FILE_FLAG_BACKUP_SEMANTICS|FILE_FLAG_OPEN_REPARSE_POINT,nullptr);
    if(h==INVALID_HANDLE_VALUE)fail("无法读取目录身份："+path);
    BY_HANDLE_FILE_INFORMATION info{};
    const bool ok=GetFileInformationByHandle(h,&info);CloseHandle(h);
    if(!ok||!(info.dwFileAttributes&FILE_ATTRIBUTE_DIRECTORY)||(info.dwFileAttributes&FILE_ATTRIBUTE_REPARSE_POINT))
        fail("目录不可用，或为链接目录："+path);
    return QString("%1:%2:%3").arg(info.dwVolumeSerialNumber).arg(info.nFileIndexHigh).arg(info.nFileIndexLow);
}
QString FileOps::relocatedPath(const QString &path,const QString &from,const QString &to) {
    if(path.isEmpty())return path;
    const auto p=QDir::fromNativeSeparators(path),a=QDir::cleanPath(from),b=QDir::cleanPath(to);
    if(p.compare(a,Qt::CaseInsensitive)==0)return b;
    if(p.startsWith(a+"/",Qt::CaseInsensitive))return b+p.mid(a.size());
    return path;
}
QVariant FileOps::relocatedValue(const QVariant &value,const QString &from,const QString &to) {
    if(value.metaType().id()==QMetaType::QVariantMap) {
        auto map=value.toMap();for(auto it=map.begin();it!=map.end();++it)it.value()=relocatedValue(it.value(),from,to);return map;
    }
    if(value.metaType().id()==QMetaType::QVariantList||value.metaType().id()==QMetaType::QStringList) {
        QVariantList list;for(const auto &v:value.toList())list.append(relocatedValue(v,from,to));return list;
    }
    if(value.metaType().id()==QMetaType::QString) {
        const QUrl url(value.toString());
        if(url.isLocalFile())return QUrl::fromLocalFile(relocatedPath(url.toLocalFile(),from,to)).toString();
        return relocatedPath(value.toString(),from,to);
    }
    return value;
}
QString FileOps::finishDirectoryRename(const QVariantMap &record) {
    const auto id=record["id"].toString(),from=record["source"].toString(),to=record["target"].toString();
    const bool samePath=from.compare(to,Qt::CaseInsensitive)==0;
    const bool targetHasName=QDir(QFileInfo(to).absolutePath()).entryList(QDir::Dirs|QDir::Hidden|QDir::NoDotAndDotDot).contains(QFileInfo(to).fileName());
    if(!targetHasName||(!samePath&&QFileInfo::exists(from))) {
        if(directoryIdentity(from)==record["identity"].toString()) {phase(id,"abandoned");return from;}
        fail("重命名目录状态不符，请核对来源与目标");
    }
    if(directoryIdentity(to)!=record["identity"].toString())fail("目标目录身份已变化，拒绝更新路径");
    store.exec("BEGIN IMMEDIATE");
    try {
        for(const auto &v:store.rows("SELECT id,path,root FROM assets")) {
            const auto r=v.toMap();const auto p=relocatedPath(r["path"].toString(),from,to),root=relocatedPath(r["root"].toString(),from,to);
            if(p!=r["path"]||root!=r["root"])store.exec("UPDATE assets SET path=?,root=? WHERE id=?",{p,root,r["id"]});
        }
        for(const auto &v:store.rows("SELECT id,source,target,temp FROM operations WHERE kind!='rename_directory'")) {
            const auto r=v.toMap();const auto updated=relocatedValue(r,from,to).toMap();
            if(updated!=r)store.exec("UPDATE operations SET source=?,target=?,temp=? WHERE id=?",{updated["source"],updated["target"],updated["temp"],r["id"]});
        }
        for(const auto &v:store.rows("SELECT asset,json FROM drafts")) {
            const auto r=v.toMap();const auto old=QJsonDocument::fromJson(r["json"].toString().toUtf8()).toVariant();
            const auto updated=relocatedValue(old,from,to);
            if(updated!=old)store.exec("UPDATE drafts SET json=? WHERE asset=?",{QString::fromUtf8(QJsonDocument::fromVariant(updated).toJson(QJsonDocument::Compact)),r["asset"]});
        }
        for(const auto &key:{"sources","session"}) {
            const auto value=store.value(key);if(value.isEmpty())continue;
            const auto updated=relocatedValue(QJsonDocument::fromJson(value.toUtf8()).toVariant(),from,to);
            store.setValue(key,QString::fromUtf8(QJsonDocument::fromVariant(updated).toJson(QJsonDocument::Compact)));
        }
        store.setValue("target",relocatedPath(store.value("target"),from,to));
        store.exec("UPDATE operations SET state='committed',error='' WHERE id=?",{id});
        store.exec("COMMIT");
    } catch(...) {store.exec("ROLLBACK");throw;}
    return to;
}
QString FileOps::renameDirectory(const QString &source,const QString &name) {
    if(!Media::validDirectoryName(name))fail("目录名称无效");
    const auto from=QFileInfo(source).absoluteFilePath(),to=QDir(QFileInfo(from).absolutePath()).filePath(name);
    if(from==to)return to;
    if(from.compare(to,Qt::CaseInsensitive)!=0&&QFileInfo::exists(to))fail("同名文件或目录已存在，未覆盖目标");
    const auto identity=directoryIdentity(from),id=QUuid::createUuid().toString(QUuid::WithoutBraces);
    store.exec("INSERT INTO operations(id,kind,source,target,identity,state) VALUES(?,'rename_directory',?,?,?,'planned')",{id,from,to,identity});
    try {
        if(directoryIdentity(from)!=identity)fail("来源目录已变化");
        if(!renameExclusive(from,to)) {phase(id,"abandoned");fail("重命名失败：目录被占用、无权限或名称冲突");}
        phase(id,"target_ready");
        return finishDirectoryRename(store.rows("SELECT * FROM operations WHERE id=?",{id})[0].toMap());
    } catch(const std::exception &e) {store.exec("UPDATE operations SET error=? WHERE id=?",{QString::fromUtf8(e.what()),id});throw;}
}
QString FileOps::hash(const QString &path) {
    QFile f(path); if(!f.open(QIODevice::ReadOnly)) fail("读取失败："+path);
    QCryptographicHash h(QCryptographicHash::Sha256);
    if(!h.addData(&f)) fail("校验失败："+path);
    return QString::fromLatin1(h.result().toHex());
}
FileStamp FileOps::stamp(const QString &path, bool withHash) {
    ReadGuard guard(path); QFileInfo info(path);
    if(!info.isFile() || info.isSymLink()) fail("不是普通文件："+path);
    return {info.size(),info.lastModified().toMSecsSinceEpoch(),guard.identity(),withHash ? hash(path) : QString()};
}
QString FileOps::uniquePath(const QString &directory,const QString &name) {
    QFileInfo f(name); const auto base=f.completeBaseName(), ext=f.suffix();
    QString path=QDir(directory).filePath(name);
    for(int n=2; QFileInfo::exists(path); ++n) path=QDir(directory).filePath(base+QString(" (%1)").arg(n)+(ext.isEmpty()?"":"."+ext));
    return path;
}
void FileOps::phase(const QString &id,const QString &state) {
    store.exec("UPDATE operations SET state=?,error='' WHERE id=?",{state,id});
    if(checkpoint) checkpoint(state);
}
QString FileOps::move(const QString &source,const QString &directory,qint64 expectedSize,qint64 expectedMtime,const QString &parent,const QString &exactName,const QString &expectedSha) {
    if(!QFileInfo(directory).isDir()) fail("目标目录不存在");
    ReadGuard guard(source); const auto before=stamp(source,true);
    if(!expectedSha.isEmpty() && before.sha!=expectedSha) fail("文件内容已变化，拒绝操作");
    if(expectedSize>=0 && (before.size!=expectedSize || before.mtime!=expectedMtime)) fail("原文件已变化，请重新扫描："+source);
    if(QFileInfo(source).absolutePath().compare(QFileInfo(directory).absoluteFilePath(),Qt::CaseInsensitive)==0 && exactName.isEmpty()) fail("已在此目录");
    const QString id=QUuid::createUuid().toString(QUuid::WithoutBraces);
    QString target=exactName.isEmpty()?uniquePath(directory,QFileInfo(source).fileName()):QDir(directory).filePath(exactName);
    const QString temp=QDir(directory).filePath(".imageclassifier-"+id+".part");
    store.exec("INSERT INTO operations(id,kind,source,target,temp,sha,size,mtime,identity,state,parent) VALUES(?,?,?,?,?,?,?,?,?,'planned',?)",{id,"move",source,target,temp,before.sha,before.size,before.mtime,before.identity,parent});
    try {
        phase(id,"running");
        if(stamp(source).identity!=guard.identity()) fail("来源已被替换");
        if(!forceCopy && renameExclusive(source,target)) {
            phase(id,"target_ready");
        } else {
            const auto error=GetLastError();
            if(!forceCopy && error!=ERROR_NOT_SAME_DEVICE) fail("移动失败（目标重名、文件占用或权限不足），未覆盖目标");
            QFile in(source), out(temp);
            if(!in.open(QIODevice::ReadOnly) || !out.open(QIODevice::WriteOnly|QIODevice::NewOnly)) fail("无法建立复制临时文件");
            while(!in.atEnd()) {
                auto bytes=in.read(1024*1024);
                if(bytes.isEmpty() && in.error()!=QFileDevice::NoError) fail("来源读取失败");
                if(out.write(bytes)!=bytes.size()) fail("目标写入失败或磁盘已满");
            }
            if(!out.flush()) fail("目标刷新失败");
            out.close(); in.close();
            phase(id,"copied");
            if(hash(temp)!=before.sha || stamp(source).identity!=before.identity || hash(source)!=before.sha) fail("复制校验失败或来源变化");
            if(!renameExclusive(temp,target)) fail("提交目标失败，来源已保留");
            phase(id,"target_ready");
            if(stamp(source).identity!=before.identity || hash(source)!=before.sha) fail("来源已变化，保留两端等待核对");
            if(!QFile::remove(source)) fail("来源清理失败，保留两端等待核对");
        }
        phase(id,"source_removed");
        if(hash(target)!=before.sha) fail("目标校验失败，需要人工核对");
        phase(id,"committed");
        return target;
    } catch(const std::exception &e) { store.exec("UPDATE operations SET error=? WHERE id=?",{QString::fromUtf8(e.what()),id}); throw; }
}
QString FileOps::writeImage(const QImage &image,const QString &directory,const QString &name,const QString &id,const QString &parent) {
    if(image.isNull() || !QFileInfo(directory).isDir()) fail("图片为空或输出目录不存在");
    const auto old=store.rows("SELECT * FROM operations WHERE id=?",{id});
    if(!old.isEmpty()) {
        const auto r=old[0].toMap();
        if(r["state"]=="committed" && QFileInfo::exists(r["target"].toString()) && hash(r["target"].toString())==r["sha"].toString()) return r["target"].toString();
        fail("此输出存在未完成记录，请先核对操作日志");
    }
    const auto target=uniquePath(directory,name), temp=QDir(directory).filePath(".imageclassifier-"+id+".part");
    store.exec("INSERT INTO operations(id,kind,source,target,temp,state,parent) VALUES(?,'export','',?,?,'planned',?)",{id,target,temp,parent});
    try {
        phase(id,"running");
        QFile f(temp); if(!f.open(QIODevice::WriteOnly|QIODevice::NewOnly)) fail("无法创建临时输出");
        QImageWriter w(&f,QFileInfo(name).suffix().toLower().toLatin1()); w.setQuality(95);
        if(!w.write(image) || !f.flush()) fail("输出失败："+w.errorString());
        f.close();
        store.exec("UPDATE operations SET sha=? WHERE id=?",{hash(temp),id});
        phase(id,"copied");
        if(!renameExclusive(temp,target)) fail("目标重名或提交失败，未覆盖文件");
        phase(id,"target_ready"); phase(id,"committed"); return target;
    } catch(const std::exception &e) { store.exec("UPDATE operations SET error=? WHERE id=?",{QString::fromUtf8(e.what()),id}); throw; }
}
QVariantList FileOps::reconcile() {
    for(const auto &v:store.rows("SELECT * FROM operations WHERE kind='rename_directory' AND state NOT IN ('committed','undone','abandoned') ORDER BY created")) {
        const auto r=v.toMap();try {finishDirectoryRename(r);}catch(const std::exception &e) {
            store.exec("UPDATE operations SET error=? WHERE id=?",{QString::fromUtf8(e.what()),r["id"]});
        }
    }
    auto pending=store.rows("SELECT * FROM operations WHERE state NOT IN ('committed','undone','abandoned') ORDER BY created");
    for(const auto &v:pending) {
        auto r=v.toMap(); const auto src=r["source"].toString(), dst=r["target"].toString();
        if(r["kind"]=="rename_directory")continue;
        bool targetOk=false;
        try { targetOk=QFileInfo::exists(dst) && !r["sha"].toString().isEmpty() && hash(dst)==r["sha"].toString(); } catch(...) {}
        // Recovery never deletes a remaining source automatically.
        if(targetOk && (r["kind"]=="export" || !QFileInfo::exists(src))) phase(r["id"].toString(),"committed");
        else store.exec("UPDATE operations SET error=? WHERE id=?",{targetOk?"目标完整，来源仍存在；请人工核对后处理":"操作未完成；原文件及临时文件已保留，请核对",r["id"]});
    }
    return store.rows("SELECT * FROM operations WHERE state NOT IN ('committed','undone','abandoned') ORDER BY created");
}
QString FileOps::undo(const QString &id) {
    const auto rows=store.rows("SELECT * FROM operations WHERE id=? AND state='committed' AND kind='move'",{id});
    if(rows.isEmpty()) fail("该操作不能撤销");
    const auto r=rows[0].toMap(); const auto source=r["source"].toString(),target=r["target"].toString();
    if(QFileInfo::exists(source)) fail("原位置已有文件，拒绝覆盖");
    if(hash(target)!=r["sha"].toString()) fail("目标已被外部修改，拒绝撤销");
    const auto result=move(target,QFileInfo(source).absolutePath(),-1,-1,id,QFileInfo(source).fileName(),r["sha"].toString());
    store.exec("UPDATE operations SET state='undone' WHERE id=?",{id});
    return result;
}
QString FileOps::recover(const QString &id) {
    const auto rows=store.rows("SELECT * FROM operations WHERE id=?",{id});
    if(rows.isEmpty())fail("记录不存在");
    auto r=rows[0].toMap();const auto source=r["source"].toString(),target=r["target"].toString(),temp=r["temp"].toString(),sha=r["sha"].toString();
    if(r["state"]=="committed")return target;
    if(r["state"]=="undone"||r["state"]=="abandoned")fail("此记录已结束");
    if(r["kind"]=="rename_directory")return finishDirectoryRename(r);
    if(r["kind"]=="mkdir") {
        if(!QFileInfo(target).isDir()&&!QDir().mkdir(target))fail("目录恢复失败");
        phase(id,"committed");return target;
    }
    if(QFileInfo::exists(target)) {
        ReadGuard targetGuard(target);
        if(sha.isEmpty()||hash(target)!=sha)fail("目标与记录不符，禁止自动恢复");
        if(r["kind"]=="move"&&QFileInfo::exists(source)) {
            ReadGuard sourceGuard(source);auto st=stamp(source,true);
            if(st.identity!=r["identity"].toString()||st.sha!=sha)fail("来源已变化，禁止清理");
            if(!QFile::remove(source))fail("来源仍被占用，未清理");
        }
        phase(id,"committed");return target;
    }
    if(r["kind"]=="export") {
        if(!sha.isEmpty()&&QFileInfo::exists(temp)&&hash(temp)==sha&&renameExclusive(temp,target)){phase(id,"committed");return target;}
        fail("输出未完整落盘；原图仍保留。请保留记录并重新建立该子图输出");
    }
    if(r["kind"]=="move"&&QFileInfo::exists(source)) {
        ReadGuard sourceGuard(source);const auto st=stamp(source,true);
        if(st.identity!=r["identity"].toString()||st.sha!=sha)fail("来源已变化，拒绝恢复");
        const auto result=move(source,QFileInfo(target).absolutePath(),st.size,st.mtime,id,QFileInfo(target).fileName(),sha);
        phase(id,"abandoned");return result;
    }
    fail("缺少可核对文件，请人工检查来源和目标位置");return {};
}
