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
#include <memory>
#include <vector>
#include <algorithm>

static void fail(const QString &message) { throw std::runtime_error(message.toUtf8().constData()); }
static QString native(const QString &path) {
    QString p=QDir::toNativeSeparators(QFileInfo(path).absoluteFilePath());
    if(p.startsWith("\\\\?\\")) return p;
    return p.startsWith("\\\\") ? "\\\\?\\UNC\\"+p.mid(2) : "\\\\?\\"+p;
}
static bool confirmedMissing(const QString &path) {
    if(path.isEmpty())return false;
    // A missing/disconnected parent cannot prove that its files are absent.
    const auto parent=native(QFileInfo(path).absolutePath());
    const auto parentAttributes=GetFileAttributesW(reinterpret_cast<LPCWSTR>(parent.utf16()));
    if(parentAttributes==INVALID_FILE_ATTRIBUTES||!(parentAttributes&FILE_ATTRIBUTE_DIRECTORY))return false;
    const auto p=native(path);
    if(GetFileAttributesW(reinterpret_cast<LPCWSTR>(p.utf16()))!=INVALID_FILE_ATTRIBUTES)return false;
    const auto error=GetLastError();return error==ERROR_FILE_NOT_FOUND||error==ERROR_PATH_NOT_FOUND;
}
class ReadGuard {
public:
    HANDLE h=INVALID_HANDLE_VALUE;
    explicit ReadGuard(const QString &path,bool allowDelete=true) {
        const auto p=native(path);
        h=CreateFileW(reinterpret_cast<LPCWSTR>(p.utf16()), GENERIC_READ, FILE_SHARE_READ|(allowDelete?FILE_SHARE_DELETE:0), nullptr, OPEN_EXISTING, FILE_FLAG_SEQUENTIAL_SCAN, nullptr);
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
        for(const auto &v:store.rows("SELECT group_id,position,source,target FROM live_members")){
            const auto r=v.toMap();store.exec("UPDATE live_members SET source=?,target=? WHERE group_id=? AND position=?",{relocatedPath(r["source"].toString(),from,to),relocatedPath(r["target"].toString(),from,to),r["group_id"],r["position"]});
        }
        for(const auto &v:store.rows("SELECT operation,backup FROM image_replacements")){
            const auto r=v.toMap();store.exec("UPDATE image_replacements SET backup=? WHERE operation=?",{relocatedPath(r["backup"].toString(),from,to),r["operation"]});
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
QString FileOps::directoryToken(const QString &path) {return directoryIdentity(path);}
QString FileOps::recycleDirectory(const QString &source,const QString &expectedIdentity,bool includeContents) {
    const auto path=QFileInfo(source).absoluteFilePath();
    if(QDir(path).isRoot())fail("不能删除磁盘或共享根目录");
    if(expectedIdentity.isEmpty()||directoryIdentity(path)!=expectedIdentity)fail("目录已变化，请重新确认删除");
    const auto entries=QDir::AllEntries|QDir::Hidden|QDir::System|QDir::NoDotAndDotDot;
    if(!includeContents&&!QDir(path).isEmpty(entries))fail("目录已不为空，请重新打开删除确认框");
    const auto id=QUuid::createUuid().toString(QUuid::WithoutBraces);
    store.exec("INSERT INTO operations(id,kind,source,target,identity,state) VALUES(?,'trash_directory',?,'回收站',?,'planned')",{id,path,expectedIdentity});
    try {
        if(checkpoint)checkpoint("directory_recycle_planned");
        if(directoryIdentity(path)!=expectedIdentity)fail("目录已变化，请重新确认删除");
        if(!includeContents&&!QDir(path).isEmpty(entries))fail("目录已不为空，请重新打开删除确认框");
        phase(id,"running");QString trash;
        const bool ok=trashFile?trashFile(path,&trash):QFile::moveToTrash(path,&trash);
        if(!ok)fail("无法将目录移入回收站：目录可能被占用、无权限或所在磁盘不支持回收站");
        if(!confirmedMissing(path))fail("目录仍在原位置，未确认删除完成，请核对回收站");
        if(checkpoint)checkpoint("directory_recycled");
        store.exec("UPDATE operations SET state='committed',temp=?,error='' WHERE id=?",{trash,id});
    } catch(const std::exception &e) {
        // A failed attempt must not automatically resume deletion on startup.
        // If the source still exists, close the attempt so the user can confirm anew.
        store.exec("UPDATE operations SET state=?,error=? WHERE id=?",{QFileInfo(path).isDir()?"abandoned":"running",QString::fromUtf8(e.what()),id});throw;
    }
    return id;
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
    return transfer(source,directory,expectedSize,expectedMtime,parent,exactName,expectedSha,false);
}
QString FileOps::copy(const QString &source,const QString &directory,qint64 expectedSize,qint64 expectedMtime,const QString &parent,const QString &exactName,const QString &expectedSha) {
    return transfer(source,directory,expectedSize,expectedMtime,parent,exactName,expectedSha,true);
}
QString FileOps::transferLive(const QVariantList &members,const QString &directory,bool copyOnly){
    if(members.size()!=2||!QFileInfo(directory).isDir())fail("Live Photo 成员或目标目录无效");
    const QFileInfo primary(members[0].toMap()["path"].toString());
    if(primary.absolutePath().compare(QFileInfo(directory).absoluteFilePath(),Qt::CaseInsensitive)==0)fail("已在此目录");
    QStringList targets;
    for(int n=1;n<100000;++n){
        targets.clear();bool available=true;const auto base=primary.completeBaseName()+(n==1?QString():QString(" (%1)").arg(n));
        for(const auto &v:members){const auto path=QDir(directory).filePath(base+"."+QFileInfo(v.toMap()["path"].toString()).suffix());targets.append(path);if(QFileInfo::exists(path))available=false;}
        if(available)break;
    }
    return planLive(members,targets,copyOnly);
}
QString FileOps::planLive(const QVariantList &members,const QStringList &targets,bool copyOnly,const QString &parent){
    QVariantList plan;
    for(int i=0;i<members.size();++i){
        const auto a=members[i].toMap();const auto source=a["path"].toString();const auto st=stamp(source,true);
        if(st.size!=a["size"].toLongLong()||st.mtime!=a["mtime"].toLongLong()||(!a["sha"].toString().isEmpty()&&st.sha!=a["sha"]))fail("Live Photo 成员已变化，请刷新后重试");
        if(QFileInfo::exists(targets[i]))fail("Live Photo 目标重名，未覆盖文件");
        plan.append(QVariantMap{{"source",source},{"target",targets[i]},{"sha",st.sha},{"size",st.size},{"mtime",st.mtime},{"identity",st.identity}});
    }
    const auto id=QUuid::createUuid().toString(QUuid::WithoutBraces);store.exec("BEGIN IMMEDIATE");
    try{
        store.exec("INSERT INTO operations(id,kind,source,target,state,parent) VALUES(?,?,?,?,'planned',?)",{id,copyOnly?"live_copy":"live_move",plan[0].toMap()["source"],targets[0],parent});
        for(int i=0;i<plan.size();++i){const auto r=plan[i].toMap();store.exec("INSERT INTO live_members(group_id,position,source,target,sha,size,mtime,identity) VALUES(?,?,?,?,?,?,?,?)",{id,i,r["source"],r["target"],r["sha"],r["size"],r["mtime"],r["identity"]});}
        store.exec("COMMIT");
    }catch(...){store.exec("ROLLBACK");throw;}
    return finishLive(id);
}
QString FileOps::finishLive(const QString &id){
    const auto row=store.rows("SELECT * FROM operations WHERE id=?",{id});if(row.isEmpty())fail("Live Photo 操作记录不存在");
    const auto group=row[0].toMap();const bool copyOnly=group["kind"]=="live_copy";
    const auto members=store.rows("SELECT * FROM live_members WHERE group_id=? ORDER BY position",{id});if(members.size()!=2)fail("Live Photo 操作计划不完整");
    try{
        bool stageAll=!copyOnly&&(forceCopy||!store.rows("SELECT id FROM operations WHERE parent=? AND kind='copy'",{id}).isEmpty());
        if(!copyOnly)for(const auto &v:members){const auto r=v.toMap();if(r["identity"].toString().section(':',0,0)!=directoryIdentity(QFileInfo(r["target"].toString()).absolutePath()).section(':',0,0))stageAll=true;}
        // Validate both members before continuing any partial operation.
        for(const auto &v:members){const auto r=v.toMap();const auto source=r["source"].toString(),target=r["target"].toString();
            const bool src=QFileInfo::exists(source),dst=QFileInfo::exists(target);
            if(!src&&!dst)fail("Live Photo 成员缺失，已保留其他文件等待核对");
            if(src){const auto st=stamp(source,true);if(st.sha!=r["sha"]||st.identity!=r["identity"])fail("Live Photo 来源已变化，拒绝继续");}
            if(dst){if(hash(target)!=r["sha"])fail("Live Photo 目标已变化，拒绝继续");
                if(store.rows("SELECT id FROM operations WHERE parent=? AND source=? AND target=?",{id,source,target}).isEmpty())fail("Live Photo 目标被其他文件占用，拒绝接管");}
        }
        phase(id,"running");int index=0;
        for(const auto &v:members){const auto r=v.toMap();const auto source=r["source"].toString(),target=r["target"].toString();
            if(QFileInfo::exists(target)){
                ReadGuard targetGuard(target,false);if(hash(target)!=r["sha"])fail("Live Photo 目标校验失败");
                if(!copyOnly&&!stageAll&&QFileInfo::exists(source)){
                    ReadGuard sourceGuard(source);const auto st=stamp(source,true);if(st.sha!=r["sha"]||st.identity!=r["identity"])fail("Live Photo 来源变化，保留两端");
                    if(!QFile::remove(source))fail("Live Photo 来源清理失败，保留两端等待核对");
                }
                store.exec("UPDATE operations SET state='committed',error='' WHERE parent=? AND source=? AND target=? AND state NOT IN ('undone','abandoned')",{id,source,target});
            }else{
                const auto st=stamp(source,true);if(st.identity!=r["identity"])fail("Live Photo 来源身份变化");
                if(copyOnly||stageAll)copy(source,QFileInfo(target).absolutePath(),st.size,st.mtime,id,QFileInfo(target).fileName(),r["sha"].toString());
                else move(source,QFileInfo(target).absolutePath(),st.size,st.mtime,id,QFileInfo(target).fileName(),r["sha"].toString());
            }
            if(checkpoint)checkpoint(QString("live_member_%1").arg(++index));
        }
        for(const auto &v:members){const auto r=v.toMap();if(hash(r["target"].toString())!=r["sha"])fail("Live Photo 成组校验失败，请核对操作记录");}
        if(stageAll){
            // Across volumes, both verified targets must exist before either source is removed.
            std::vector<std::unique_ptr<ReadGuard>> guards;
            for(const auto &v:members){const auto r=v.toMap();guards.push_back(std::make_unique<ReadGuard>(r["target"].toString(),false));if(hash(r["target"].toString())!=r["sha"])fail("Live Photo 目标变化，保留来源");}
            for(const auto &v:members){const auto r=v.toMap();const auto source=r["source"].toString();if(QFileInfo::exists(source)){
                ReadGuard sourceGuard(source);const auto st=stamp(source,true);if(st.sha!=r["sha"]||st.identity!=r["identity"])fail("Live Photo 来源变化，保留两端等待核对");
                if(!QFile::remove(source))fail("Live Photo 来源清理失败，目标已完整保存");
            }}
        }
        phase(id,"committed");
        if(!group["parent"].toString().isEmpty())store.exec("UPDATE operations SET state='undone' WHERE id=? AND kind='live_move'",{group["parent"]});
        return group["target"].toString();
    }catch(const std::exception &e){store.exec("UPDATE operations SET error=? WHERE id=?",{QString::fromUtf8(e.what()),id});throw;}
}
QString FileOps::transfer(const QString &source,const QString &directory,qint64 expectedSize,qint64 expectedMtime,const QString &parent,const QString &exactName,const QString &expectedSha,bool copyOnly) {
    if(!QFileInfo(directory).isDir()) fail("目标目录不存在");
    ReadGuard guard(source,!copyOnly); const auto before=stamp(source,true);
    if(!expectedSha.isEmpty() && before.sha!=expectedSha) fail("文件内容已变化，拒绝操作");
    if(expectedSize>=0 && (before.size!=expectedSize || before.mtime!=expectedMtime)) fail("原文件已变化，请重新扫描："+source);
    if(QFileInfo(source).absolutePath().compare(QFileInfo(directory).absoluteFilePath(),Qt::CaseInsensitive)==0 && exactName.isEmpty()) fail("已在此目录");
    const QString id=QUuid::createUuid().toString(QUuid::WithoutBraces);
    QString target=exactName.isEmpty()?uniquePath(directory,QFileInfo(source).fileName()):QDir(directory).filePath(exactName);
    const QString temp=QDir(directory).filePath(".imageclassifier-"+id+".part");
    store.exec("INSERT INTO operations(id,kind,source,target,temp,sha,size,mtime,identity,state,parent) VALUES(?,?,?,?,?,?,?,?,?,'planned',?)",{id,copyOnly?"copy":"move",source,target,temp,before.sha,before.size,before.mtime,before.identity,parent});
    try {
        std::unique_ptr<ReadGuard> targetGuard;
        phase(id,"running");
        if(stamp(source).identity!=guard.identity()) fail("来源已被替换");
        if(!copyOnly && !forceCopy && renameExclusive(source,target)) {
            phase(id,"target_ready");
            targetGuard=std::make_unique<ReadGuard>(target,false);
        } else {
            const auto error=GetLastError();
            if(!copyOnly && !forceCopy && error!=ERROR_NOT_SAME_DEVICE) {
                if(error==ERROR_SHARING_VIOLATION||error==ERROR_LOCK_VIOLATION)fail("文件正被占用，未移动；请关闭播放或其他程序的文件预览后重试");
                if(error==ERROR_ACCESS_DENIED)fail("没有移动权限或文件被保护，原文件保留；请检查来源和目标目录权限");
                if(error==ERROR_FILE_EXISTS||error==ERROR_ALREADY_EXISTS)fail("目标已出现同名文件，未覆盖；请重试以分配新名称");
                fail(QString("移动失败（系统错误 %1），原文件保留，未覆盖目标").arg(error));
            }
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
            targetGuard=std::make_unique<ReadGuard>(target,false);
            if(stamp(target).size!=before.size || hash(target)!=before.sha) fail("正式目标校验失败，来源已保留");
            if(stamp(source).identity!=before.identity || hash(source)!=before.sha) fail("来源已变化，保留两端等待核对");
            if(!copyOnly && !QFile::remove(source)) fail("来源清理失败，保留两端等待核对");
        }
        if(!copyOnly)phase(id,"source_removed");
        if(hash(target)!=before.sha) fail("目标校验失败，需要人工核对");
        phase(id,"committed");
        return target;
    } catch(const std::exception &e) { store.exec("UPDATE operations SET error=? WHERE id=?",{QString::fromUtf8(e.what()),id}); throw; }
}
ImageExportResult FileOps::writeImage(const QImage &image,const QString &directory,const QString &name,const QString &requestId,const QString &parent) {
    if(image.isNull() || !QFileInfo(directory).isDir()) fail("图片为空或输出目录不存在");
    // Keep completed history immutable. Repeating an export whose output was
    // removed creates a new operation, and later retries reuse that latest one.
    const auto prefix=requestId+"-repeat-";
    const auto old=store.rows("SELECT * FROM operations WHERE kind='export' AND (id=? OR substr(id,1,?)=?) ORDER BY rowid DESC LIMIT 1",{requestId,prefix.size(),prefix});
    QString id=requestId;
    if(!old.isEmpty()) {
        const auto r=old[0].toMap();
        if(r["state"]!="committed")fail("此裁剪输出尚未完成，请在操作记录中核对后继续");
        const auto path=r["target"].toString(),p=native(path);
        const auto attributes=GetFileAttributesW(reinterpret_cast<LPCWSTR>(p.utf16()));
        const auto error=attributes==INVALID_FILE_ATTRIBUTES?GetLastError():ERROR_SUCCESS;
        if(attributes!=INVALID_FILE_ATTRIBUTES) {
            if(hash(path)==r["sha"].toString())return {path,r["id"].toString(),false};
            fail("先前导出的子图已被修改，未覆盖该文件；请调整裁剪区域或目标目录后重新导出");
        }
        if(error!=ERROR_FILE_NOT_FOUND&&error!=ERROR_PATH_NOT_FOUND)
            fail("暂时无法读取先前导出的子图，请检查目录权限或磁盘连接后重试");
        id=prefix+QUuid::createUuid().toString(QUuid::WithoutBraces);
    }
    const auto target=uniquePath(directory,name), temp=QDir(directory).filePath(".imageclassifier-"+id+".part");
    store.exec("INSERT INTO operations(id,kind,source,target,temp,state,parent) VALUES(?,'export','',?,?,'planned',?)",{id,target,temp,parent});
    try {
        phase(id,"running");
        QFile f(temp); if(!f.open(QIODevice::WriteOnly|QIODevice::NewOnly)) fail("无法创建临时输出");
        QImageWriter w(&f,QFileInfo(name).suffix().toLower().toLatin1()); w.setQuality(95);
        if(!w.write(image) || !f.flush()) fail("输出失败："+w.errorString());
        f.close();
        const auto outputSha=hash(temp);
        store.exec("UPDATE operations SET sha=? WHERE id=?",{outputSha,id});
        phase(id,"copied");
        if(!renameExclusive(temp,target)) fail("目标重名或提交失败，未覆盖文件");
        phase(id,"target_ready");
        ReadGuard targetGuard(target,false);
        if(hash(target)!=outputSha)fail("正式输出校验失败，原图应保留，请核对操作记录");
        phase(id,"committed"); return {target,id,true};
    } catch(const std::exception &e) { store.exec("UPDATE operations SET error=? WHERE id=?",{QString::fromUtf8(e.what()),id}); throw; }
}
ImageExportResult FileOps::replaceImage(const QImage &image,const QString &path,const FileStamp &expected,const QString &parent) {
    if(image.isNull()||expected.sha.isEmpty())fail("缺少可校验的裁剪图片或原图信息");
    const auto before=stamp(path,true);
    if(before.sha!=expected.sha||before.identity!=expected.identity||before.size!=expected.size||before.mtime!=expected.mtime)fail("原图已变化，未覆盖");
    const auto id=QUuid::createUuid().toString(QUuid::WithoutBraces),directory=QFileInfo(path).absolutePath();
    const auto temp=directory+"/.imageclassifier-"+id+".part";
    const auto backup=directory+"/.imageclassifier-"+id+"-original."+QFileInfo(path).suffix();
    store.exec("BEGIN IMMEDIATE");
    try {
        store.exec("INSERT INTO operations(id,kind,source,target,temp,size,mtime,identity,state,parent) VALUES(?,'replace_image',?,?,?,?,?,?,'planned',?)",{id,path,path,temp,before.size,before.mtime,before.identity,parent});
        store.exec("INSERT INTO image_replacements(operation,source_sha,backup) VALUES(?,?,?)",{id,before.sha,backup});
        store.exec("COMMIT");
    }catch(...){store.exec("ROLLBACK");throw;}
    try {
        phase(id,"running");
        QFile file(temp);if(!file.open(QIODevice::WriteOnly|QIODevice::NewOnly))fail("无法创建裁剪临时文件，原图保留");
        QImageWriter writer(&file,QFileInfo(path).suffix().toLower().toLatin1());writer.setQuality(95);
        if(!writer.write(image)||!file.flush())fail("裁剪保存失败，原图保留："+writer.errorString());
        file.close();
        if(Media::read(temp).size()!=image.size())fail("裁剪文件解码校验失败，原图保留");
        store.exec("UPDATE operations SET sha=? WHERE id=?",{hash(temp),id});phase(id,"copied");
        return finishImageReplacement(id);
    }catch(const std::exception &e){store.exec("UPDATE operations SET error=? WHERE id=?",{QString::fromUtf8(e.what()),id});throw;}
}
ImageExportResult FileOps::finishImageReplacement(const QString &id) {
    const auto rows=store.rows("SELECT o.*,r.source_sha,r.backup FROM operations o JOIN image_replacements r ON r.operation=o.id WHERE o.id=?",{id});
    if(rows.isEmpty())fail("缺少覆盖记录");const auto r=rows[0].toMap();
    const auto path=r["source"].toString(),temp=r["temp"].toString(),backup=r["backup"].toString(),sha=r["sha"].toString();
    if(r["state"]=="committed")return {path,id,false,{}};
    try {
        if(sha.isEmpty()||!QFileInfo::exists(path)||hash(path)!=sha){
            ReadGuard original(path);const auto current=stamp(path,true);
            if(current.sha!=r["source_sha"]||current.identity!=r["identity"]||current.size!=r["size"].toLongLong()||current.mtime!=r["mtime"].toLongLong())fail("原图已变化，拒绝覆盖；请核对操作记录");
            if(sha.isEmpty()){phase(id,"abandoned");return {path,id,false,"临时输出未完成，原图保留，请重新裁剪"};}
            if(!confirmedMissing(backup)||!QFileInfo::exists(temp)||hash(temp)!=sha)fail("临时输出或备份状态不符，原图保留");
            const auto a=native(path),b=native(temp),c=native(backup);
            if(!ReplaceFileW(reinterpret_cast<LPCWSTR>(a.utf16()),reinterpret_cast<LPCWSTR>(b.utf16()),reinterpret_cast<LPCWSTR>(c.utf16()),0,nullptr,nullptr))
                fail(QString("覆盖未完成（系统错误 %1），请关闭其他程序的文件预览后在操作记录中核对").arg(GetLastError()));
            phase(id,"target_ready");
        }
        ReadGuard output(path,false);
        if(hash(path)!=sha)fail("覆盖结果校验失败，请保留文件并核对记录");
        if(!QFileInfo::exists(backup)||hash(backup)!=r["source_sha"])fail("旧图备份校验失败，未清理任何文件");
        // Persist cleanup together with completion: a crash must never leave
        // an untracked backup after replacing the user's original.
        const auto cleanup=QUuid::createUuid().toString(QUuid::WithoutBraces);
        const auto old=stamp(backup,true);
        store.exec("BEGIN IMMEDIATE");
        try {
            store.exec("INSERT INTO operations(id,kind,source,target,state,parent) VALUES(?,'recycle',?,'回收站','planned',?)",{cleanup,backup,id});
            store.exec("INSERT INTO recycle_members(group_id,position,source,sha,size,mtime,identity) VALUES(?,0,?,?,?,?,?)",{cleanup,backup,old.sha,old.size,old.mtime,old.identity});
            store.exec("INSERT INTO recycle_outputs(group_id,operation) VALUES(?,?)",{cleanup,id});
            store.exec("UPDATE operations SET state='committed',error='' WHERE id=?",{id});
            store.exec("COMMIT");
        }catch(...){store.exec("ROLLBACK");throw;}
        if(checkpoint)checkpoint("committed");
        QString warning;
        try {
            finishRecycle(cleanup);
        }catch(const std::exception &e){warning="图片已覆盖，旧图备份回收未完成："+QString::fromUtf8(e.what());}
        return {path,id,true,warning};
    }catch(const std::exception &e){store.exec("UPDATE operations SET error=? WHERE id=?",{QString::fromUtf8(e.what()),id});throw;}
}
QString FileOps::recycleAfterExport(const QVariantList &members,const QStringList &outputs,const QString &parent) {
    if(outputs.isEmpty())fail("没有可核对的裁剪输出");
    return planRecycle(members,outputs,parent,true);
}
QString FileOps::recycle(const QVariantList &members,const QString &parent) {
    return planRecycle(members,{},parent,false);
}
QString FileOps::planRecycle(const QVariantList &members,const QStringList &outputs,const QString &parent,bool afterExport) {
    if(members.isEmpty())fail("没有可核对的原文件");
    const auto id=QUuid::createUuid().toString(QUuid::WithoutBraces);
    store.exec("BEGIN IMMEDIATE");
    try {
        store.exec("INSERT INTO operations(id,kind,source,target,state,parent) VALUES(?,?,?,'回收站','planned',?)",{id,afterExport?"recycle":"trash",members[0].toMap()["path"],parent});
        int position=0;
        for(const auto &v:members){const auto m=v.toMap();
            if(m["sha"].toString().isEmpty()||m["identity"].toString().isEmpty())fail("原文件校验信息不完整");
            store.exec("INSERT INTO recycle_members(group_id,position,source,sha,size,mtime,identity) VALUES(?,?,?,?,?,?,?)",{id,position++,m["path"],m["sha"],m["size"],m["mtime"],m["identity"]});
        }
        for(const auto &output:outputs)store.exec("INSERT INTO recycle_outputs(group_id,operation) VALUES(?,?)",{id,output});
        store.exec("COMMIT");
    }catch(...){store.exec("ROLLBACK");throw;}
    return finishRecycle(id);
}
QString FileOps::finishRecycle(const QString &id,bool recovering) {
    const auto group=store.rows("SELECT * FROM operations WHERE id=? AND kind IN ('recycle','trash')",{id});
    if(group.isEmpty())fail("回收记录不存在");
    const auto source=group[0].toMap()["source"].toString();
    if(group[0].toMap()["state"]=="committed")return source;
    try {
        const auto members=store.rows("SELECT * FROM recycle_members WHERE group_id=? ORDER BY position",{id});
        if(members.isEmpty())fail("回收计划为空");
        // A crash between the OS operation and its journal write is ambiguous.
        // Explicit recovery closes that plan without deleting any remaining files.
        if(recovering)for(const auto &v:members){const auto m=v.toMap();
            if(m["state"]!="recycled"&&!QFileInfo::exists(m["source"].toString())) {
                store.exec("UPDATE operations SET state='abandoned',error=? WHERE id=?",{"原文件缺失，无法确认回收结果；已停止剩余回收，请手动核对回收站和原目录",id});
                return source;
            }
        }
        std::vector<std::unique_ptr<ReadGuard>> guards;
        const auto outputs=store.rows("SELECT o.* FROM operations o JOIN recycle_outputs r ON r.operation=o.id WHERE r.group_id=?",{id});
        if((group[0].toMap()["kind"]=="recycle"&&outputs.isEmpty())||outputs.size()!=store.rows("SELECT operation FROM recycle_outputs WHERE group_id=?",{id}).size())fail("缺少裁剪输出记录，原文件保留");
        for(const auto &v:outputs){const auto out=v.toMap();const auto path=out["target"].toString();
            guards.push_back(std::make_unique<ReadGuard>(path,false));
            if((out["kind"]!="export"&&out["kind"]!="replace_image")||out["state"]!="committed"||hash(path)!=out["sha"].toString())fail("子图缺失或已变化，停止回收原文件");
        }
        // Preflight ALL Live members before recycling either one, and keep the
        // originals protected against writes throughout the operation.
        for(const auto &v:members){const auto m=v.toMap();if(m["state"]=="recycled")continue;
            const auto path=m["source"].toString();guards.push_back(std::make_unique<ReadGuard>(path));
            const auto st=stamp(path,true);
            if(st.sha!=m["sha"]||st.identity!=m["identity"]||st.size!=m["size"].toLongLong()||st.mtime!=m["mtime"].toLongLong())fail("原文件已变化，停止回收，请刷新后核对");
        }
        phase(id,"running");
        for(const auto &v:members){const auto m=v.toMap();if(m["state"]=="recycled")continue;
            const auto path=m["source"].toString();QString trash;
            store.exec("UPDATE recycle_members SET state='recycling' WHERE group_id=? AND position=?",{id,m["position"]});
            // QFile uses Windows' recycle-only operation. Never fall back to remove().
            const bool ok=trashFile?trashFile(path,&trash):QFile::moveToTrash(path,&trash);
            if(!ok||QFileInfo::exists(path))fail("无法将文件移入回收站；请在操作记录中核对后重试");
            store.exec("UPDATE recycle_members SET state='recycled',trash=? WHERE group_id=? AND position=?",{trash,id,m["position"]});
            if(checkpoint)checkpoint("recycled_member");
        }
        phase(id,"committed");return source;
    }catch(const std::exception &e){store.exec("UPDATE operations SET error=? WHERE id=?",{QString::fromUtf8(e.what()),id});throw;}
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
        if(r["kind"]=="recycle"||r["kind"]=="trash") {
            const auto members=store.rows("SELECT state FROM recycle_members WHERE group_id=?",{r["id"]});
            if(!members.isEmpty()&&std::all_of(members.begin(),members.end(),[](const QVariant &m){return m.toMap()["state"]=="recycled";}))phase(r["id"].toString(),"committed");
            continue; // Startup never resumes deletion automatically.
        }
        if(r["kind"]=="trash_directory"||r["kind"]=="replace_image"||r["kind"]=="rename_directory"||r["kind"]=="live_move"||r["kind"]=="live_copy")continue;
        // An untouched top-level transfer need not block every later action.
        // Require positive evidence: no destination or temp, original identity,
        // version and bytes intact. Partial transfers and Live groups stay pending.
        if((r["kind"]=="move"||r["kind"]=="copy")&&r["parent"].toString().isEmpty()&&
           (r["state"]=="planned"||r["state"]=="running")&&confirmedMissing(dst)&&confirmedMissing(r["temp"].toString())) {
            try {
                ReadGuard guard(src,false);const auto current=stamp(src,true);
                if(current.identity==r["identity"].toString()&&current.sha==r["sha"].toString()&&
                   current.size==r["size"].toLongLong()&&current.mtime==r["mtime"].toLongLong()) {
                    store.exec("UPDATE operations SET state='abandoned',error=? WHERE id=?",{r["error"].toString()+"；已核对文件未移动、未产生副本，可重新操作",r["id"]});
                    continue;
                }
            }catch(...){} // Unavailable or changed files are never assumed safe.
        }
        bool targetOk=false;
        try { targetOk=QFileInfo::exists(dst) && !r["sha"].toString().isEmpty() && hash(dst)==r["sha"].toString(); } catch(...) {}
        // Recovery never deletes a remaining source automatically.
        if(targetOk && (r["kind"]=="export" || r["kind"]=="copy" || !QFileInfo::exists(src))) phase(r["id"].toString(),"committed");
        else store.exec("UPDATE operations SET error=? WHERE id=?",{targetOk?"目标完整，来源仍存在；请人工核对后处理":"操作未完成；原文件及临时文件已保留，请核对",r["id"]});
    }
    return store.rows("SELECT * FROM operations WHERE state NOT IN ('committed','undone','abandoned') ORDER BY created");
}
QString FileOps::undo(const QString &id) {
    const auto live=store.rows("SELECT * FROM operations WHERE id=? AND state='committed' AND kind='live_move'",{id});
    if(!live.isEmpty()){
        QVariantList members;QStringList targets;
        for(const auto &v:store.rows("SELECT * FROM live_members WHERE group_id=? ORDER BY position",{id})){
            const auto r=v.toMap();const auto path=r["target"].toString();const auto st=stamp(path,true);
            if(st.sha!=r["sha"])fail("Live Photo 目标已修改，拒绝撤销");
            members.append(QVariantMap{{"path",path},{"size",st.size},{"mtime",st.mtime},{"sha",r["sha"]}});targets.append(r["source"].toString());
        }
        if(members.size()!=2)fail("Live Photo 撤销计划不完整");return planLive(members,targets,false,id);
    }
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
    const auto replacement=store.rows("SELECT id FROM operations WHERE id=? AND kind='replace_image'",{id});
    if(!replacement.isEmpty())return finishImageReplacement(id).path;
    const auto rows=store.rows("SELECT * FROM operations WHERE id=?",{id});
    if(rows.isEmpty())fail("记录不存在");
    auto r=rows[0].toMap();const auto source=r["source"].toString(),target=r["target"].toString(),temp=r["temp"].toString(),sha=r["sha"].toString();
    if(r["state"]=="committed")return target;
    if(r["state"]=="undone"||r["state"]=="abandoned")fail("此记录已结束");
    if(r["kind"]=="trash_directory") {
        store.exec("UPDATE operations SET state='abandoned',error=? WHERE id=?",{"已结束未确认的目录删除；请核对原目录和回收站，需要删除时重新确认",id});
        return source;
    }
    if(r["kind"]=="recycle"||r["kind"]=="trash")return finishRecycle(id,true);
    if(r["kind"]=="rename_directory")return finishDirectoryRename(r);
    if(r["kind"]=="live_move"||r["kind"]=="live_copy")return finishLive(id);
    if(r["kind"]=="mkdir") {
        if(!QFileInfo(target).isDir()&&!QDir().mkdir(target))fail("目录恢复失败");
        phase(id,"committed");return target;
    }
    if(QFileInfo::exists(target)) {
        ReadGuard targetGuard(target,false);
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
    if(r["kind"]=="copy") {
        if(!sha.isEmpty()&&QFileInfo::exists(temp)&&hash(temp)==sha&&renameExclusive(temp,target)) {
            ReadGuard targetGuard(target,false);
            if(hash(target)!=sha)fail("复制目标校验失败，来源已保留");
            phase(id,"committed");return target;
        }
        ReadGuard sourceGuard(source,false);const auto st=stamp(source,true);
        if(st.identity!=r["identity"].toString()||st.sha!=sha)fail("复制来源已变化，拒绝恢复");
        const auto result=copy(source,QFileInfo(target).absolutePath(),st.size,st.mtime,id,QFileInfo(target).fileName(),sha);
        phase(id,"abandoned");return result;
    }
    if(r["kind"]=="move"&&QFileInfo::exists(source)) {
        ReadGuard sourceGuard(source);const auto st=stamp(source,true);
        if(st.identity!=r["identity"].toString()||st.sha!=sha)fail("来源已变化，拒绝恢复");
        const auto result=move(source,QFileInfo(target).absolutePath(),st.size,st.mtime,id,QFileInfo(target).fileName(),sha);
        phase(id,"abandoned");return result;
    }
    fail("缺少可核对文件，请人工检查来源和目标位置");return {};
}
