#include "Backend.h"
#include "LivePhoto.h"
#include "Store.h"
#include "FileOps.h"
#include "Media.h"
#include "CropGeometry.h"
#include "SmartCrop.h"
#include <QtConcurrent>
#include <QJsonDocument>
#include <QJsonArray>
#include <QFileInfo>
#include <QDir>
#include <QDirIterator>
#include <QDesktopServices>
#include <QUrl>
#include <QTimer>
#include <QUuid>
#include <QDateTime>
#include <QCryptographicHash>
#include <QCollator>
#include <windows.h>
#include <algorithm>
#include <stdexcept>

namespace {
QString json(const QVariant &v) {return QString::fromUtf8(QJsonDocument::fromVariant(v).toJson(QJsonDocument::Compact));}
QVariant parse(const QString &s) {return QJsonDocument::fromJson(s.toUtf8()).toVariant();}
QString version(const QVariantMap &a) {return a["size"].toString()+":"+a["mtime"].toString();}
void fail(const QString &s) {throw std::runtime_error(s.toUtf8().constData());}
// Keep recovery groups visible if any member is unfinished. Clearing the UI must
// retain operation IDs and file hashes used by recovery and idempotent exports.
const QString historyProtection=QStringLiteral(
    "WITH RECURSIVE protected(id) AS ("
    "SELECT id FROM operations WHERE state NOT IN ('committed','undone','abandoned') "
    "UNION SELECT o.parent FROM operations o JOIN protected p ON o.id=p.id WHERE o.parent!='') ");
const QString topLevelHistory=QStringLiteral(
    "NOT(o.kind IN ('move','copy') AND o.parent IN (SELECT id FROM operations WHERE kind IN ('live_move','live_copy')))");
QVariantMap historyView(Store &s) {
    const auto rows=s.rows(historyProtection+"SELECT o.* FROM operations o WHERE "+topLevelHistory+
        " AND (o.id NOT IN (SELECT operation FROM cleared_history) OR o.id IN (SELECT id FROM protected)) "
        "ORDER BY (o.id IN (SELECT id FROM protected)) DESC,o.created DESC,o.rowid DESC LIMIT 100");
    const bool clearable=!s.rows(historyProtection+"SELECT o.id FROM operations o WHERE "+topLevelHistory+
        " AND o.id NOT IN (SELECT id FROM protected) AND o.id NOT IN (SELECT operation FROM cleared_history) LIMIT 1").isEmpty();
    return {{"history",rows},{"clearable",clearable}};
}
void ensureDir(Store &store,const QString &input) {
    const QString path=QDir::cleanPath(input);
    if(QFileInfo(path).isDir()) return;
    const QFileInfo f(path);
    if(f.exists() || f.absolutePath()==path) fail("无法创建目录："+path);
    ensureDir(store,f.absolutePath());
    const auto id=QUuid::createUuid().toString(QUuid::WithoutBraces);
    store.exec("INSERT INTO operations(id,kind,target,state) VALUES(?,'mkdir',?,'planned')",{id,path});
    if(!QDir().mkdir(path)) fail("目录创建失败："+path);
    store.exec("UPDATE operations SET state='committed' WHERE id=?",{id});
}
QVariantList directoryTree(const QString &root,bool countFiles=true) {
    QVariantList tree;
    struct Counts {int images=0,videos=0;bool known=false;};
    std::function<Counts(QString,int)> visit=[&](const QString &p,int depth)->Counts {
        if(depth>12 || tree.size()>=2000) return {};
        const auto entries=QDir(p).entryInfoList((countFiles?QDir::Files|QDir::Dirs:QDir::Dirs)|QDir::NoDotAndDotDot|QDir::NoSymLinks,QDir::Name);
        int images=0,videos=0;
        if(countFiles)for(const auto &f:entries)if(Media::isSupportedFile(f)) {
            if(f.suffix().compare("mov",Qt::CaseInsensitive)==0||f.suffix().compare("mp4",Qt::CaseInsensitive)==0)++videos;else ++images;
        }
        const bool known=countFiles&&QFileInfo(p).isReadable();
        const auto index=tree.size();
        QVariantMap row{{"path",p},{"name",depth?QFileInfo(p).fileName():QDir::toNativeSeparators(p)},{"depth",depth},
                        {"directCount",known?images+videos:-1},{"directImageCount",images},{"directVideoCount",videos}};
        tree.append(row);
        Counts total{images,videos,known};
        for(const auto &f:entries) if(f.isDir()&&!f.isJunction()&&!f.fileName().startsWith('.')) {
            const auto child=visit(f.absoluteFilePath(),depth+1);
            total.images+=child.images;total.videos+=child.videos;total.known=total.known&&child.known;
        }
        // Keep preorder rows for the tree, but aggregate each child exactly once.
        // An unreadable or truncated subtree must not appear as a complete total.
        row["mediaCount"]=total.known?total.images+total.videos:-1;
        row["imageCount"]=total.images;row["videoCount"]=total.videos;
        tree[index]=row;
        return total;
    };
    if(QFileInfo(root).isDir()) visit(root,0);
    return tree;
}
}
Backend::Backend(const QString &db,QObject *parent):QObject(parent),database(db),stop(std::make_shared<std::atomic_bool>(false)) {
    m_livePhoto=new LivePhotoService(this);
    connect(m_livePhoto,&LivePhotoService::failed,this,&Backend::message);
    m_smartCrop=new SmartCrop(database,this);
    Store s(database); FileOps files(s);
    m_pending=files.reconcile().size();
    m_sources=parse(s.value("sources","[]")).toStringList();
    m_targetRoot=s.value("target");
    m_directories=directoryTree(m_targetRoot,false);
    QTimer::singleShot(0,this,[this]{
        if(m_busy)return;
        bool missingTime=false;
        for(const auto &item:m_items+m_queue)if(!item.toMap().contains("captureTime")||!item.toMap().contains("isLive")||item.toMap().value("liveSchema").toInt()!=2){missingTime=true;break;}
        if(missingTime){
            const auto items=m_items,queue=m_queue;const auto db=database;const auto cancellation=stop;
            run("正在读取媒体信息…",[items,queue,db,cancellation]{
                auto update=[](QVariantList list){
                    for(auto &value:list){auto item=value.toMap();
                        if(!item.contains("captureTime")){
                            const auto time=Media::captureTime(item["path"].toString());
                            for(auto it=time.begin();it!=time.end();++it)item.insert(it.key(),it.value());
                        }
                        if(!item.contains("isLive")||item.value("liveSchema").toInt()!=2)LivePhoto::annotate(item);
                        value=item;
                    }
                    Media::sortByCaptureTime(list);return list;
                };
                Store store(db);QSet<QString> active;for(const auto &v:items)active.insert(v.toMap()["id"].toString());
                auto combined=update(items+queue);
                for(const auto &v:items+queue){const auto a=v.toMap();if(a.contains("liveVideo")){auto video=a["liveVideo"].toMap();const QFileInfo f(video["path"].toString());if(!f.isFile())continue;video["type"]="视频";video["root"]=a["root"];video["name"]=f.fileName();combined.append(video);}}
                const auto all=LivePhoto::pairAssets(store,combined,cancellation);QVariantList current,pending;
                for(const auto &v:all){const auto a=v.toMap();if(active.contains(a["id"].toString())||active.contains(a["liveVideo"].toMap()["id"].toString()))current.append(a);else pending.append(a);}
                return QVariantMap{{"items",current},{"queue",pending}};
            },[this](const auto &result){m_items=result["items"].toList();m_queue=result["queue"].toList();persist();m_status="已按拍摄时间从新到旧排列";},true);
        }else if(!m_targetRoot.isEmpty())refreshDirectories();
    });
    m_recursive=s.value("recursive","1")=="1";
    m_largeMode=s.value("viewMode","batch")=="large";
    m_cropMode=s.value("cropMode","1")=="1";
    m_thumbnailSize=qBound(170,s.value("thumbnailSize","240").toInt(),310);
    m_showFilmstrip=s.value("showFilmstrip","1")=="1";
    m_defaultRecursive=s.value("defaultRecursive","1")=="1";
    m_batchSize=qBound(10,s.value("batchSize","100").toInt(),500);
    auto session=parse(s.value("session","{}")).toMap();
    m_items=session["items"].toList(); m_queue=session["queue"].toList(); m_batch=session["batch"].toInt();
    for(const auto &id:session["consumed"].toStringList()) consumed.insert(id);
    int restoredCount=0;
    if(s.value("hiddenItemsRestoredV1")!="1") {
        // The removed defer command shared the consumed list with completed moves.
        // Restore only existing source files with no matching file-operation record.
        QVariantList restored;QSet<QString> visible;
        for(const auto &v:m_items+m_queue)visible.insert(v.toMap()["id"].toString());
        const auto oldConsumed=consumed;
        for(const auto &id:oldConsumed) {
            if(visible.contains(id))continue;
            const auto rows=s.rows("SELECT * FROM assets WHERE id=?",{id});if(rows.isEmpty())continue;
            auto a=rows[0].toMap();const QFileInfo f(a["path"].toString());
            if(!f.isFile()||f.isSymLink())continue;
            bool inSource=false;
            for(const auto &root:m_sources) {
                const auto relative=QDir(root).relativeFilePath(f.absoluteFilePath());
                if(!relative.startsWith("../")&&!QDir::isAbsolutePath(relative)&&
                   (m_recursive||!relative.contains('/'))&&!relative.split('/').contains("已处理")){inSource=true;break;}
            }
            if(!inSource)continue;
            if(!s.rows("SELECT id FROM operations WHERE kind='move' AND (source=? OR target=?) AND state NOT IN ('undone','abandoned') LIMIT 1",{f.absoluteFilePath(),f.absoluteFilePath()}).isEmpty())continue;
            a["name"]=f.fileName();a["size"]=f.size();a["mtime"]=f.lastModified().toMSecsSinceEpoch();
            a["kind"]=a["blocked"].toString().isEmpty()?(a["type"]=="视频"?"视频":""):"待配对";
            a["url"]=QUrl::fromLocalFile(f.absoluteFilePath()).toString();
            a["thumb"]="image://media/"+id+"/0/"+QString::number(f.lastModified().toMSecsSinceEpoch());
            restored.append(a);consumed.remove(id);
        }
        QCollator order;order.setNumericMode(true);order.setCaseSensitivity(Qt::CaseInsensitive);
        std::sort(restored.begin(),restored.end(),[&](const auto &a,const auto &b){return order.compare(a.toMap()["path"].toString(),b.toMap()["path"].toString())<0;});
        restoredCount=restored.size();
        if(restoredCount) {
            restored.append(m_items);m_items=restored.mid(0,m_batchSize*2);
            auto overflow=restored.mid(m_batchSize*2);overflow.append(m_queue);m_queue=overflow;
            if(!m_batch)m_batch=1;
        }
        s.exec("BEGIN IMMEDIATE");
        try {
            if(restoredCount){
                s.setValue("sessionBeforeHiddenItemsRestore",s.value("session","{}"));
                s.setValue("session",json(QVariantMap{{"items",m_items},{"queue",m_queue},{"batch",m_batch},{"consumed",QStringList(consumed.begin(),consumed.end())}}));
            }
            s.setValue("hiddenItemsRestoredV1","1");s.exec("COMMIT");
        }catch(...){s.exec("ROLLBACK");throw;}
    }
    Media::sortByCaptureTime(m_items);Media::sortByCaptureTime(m_queue);
    // Stored snapshots are revalidated on every modifying command, never replayed.
    if(!m_items.isEmpty() || !m_queue.isEmpty()) m_status="已恢复浏览；执行操作前会重新核对文件";
    if(restoredCount)m_status=QString("已恢复 %1 张被隐藏的图片，原文件与编辑草稿均保留").arg(restoredCount);
    if(m_pending) m_status=QString("有 %1 项未完成文件操作，请先在记录中核对").arg(m_pending);
}
Backend::~Backend() {stop->store(true); watcher.waitForFinished();}
QObject *Backend::smartCrop() const {return m_smartCrop;}
QObject *Backend::livePhoto() const {return m_livePhoto;}
void Backend::playLive(const QString &id,const QString &owner) {
    if(!m_busy)m_livePhoto->start(asset(id),owner);
}
void Backend::suggestCrop(const QString &id,const QVariantMap &dimensions,const QVariantMap &spec,const QString &token) {
    if(!m_busy)m_smartCrop->request(asset(id),dimensions,spec,token);
}
void Backend::run(const QString &title,std::function<QVariantMap()> job,std::function<void(const QVariantMap &)> done,bool refreshTree,const QString &cancellationLabel) {
    if(m_busy||m_restarting) {emit message(m_restarting?"应用正在重启，请稍候。":"请等待当前任务完成");return;}
    m_livePhoto->stop();
    m_busy=true; stop->store(false); m_cancelAction=cancellationLabel;m_cancelRequested=false;m_status=title;emit changed();
    disconnect(&watcher,nullptr,this,nullptr);
    connect(&watcher,&QFutureWatcher<QVariantMap>::finished,this,[this,done] {
        const auto result=watcher.result();m_busy=false;
        QString taskError;
        // Clear the completed task before done(), which may start the next batch.
        m_cancelAction.clear();m_cancelRequested=false;
        if(result.contains("tree"))m_directories=result["tree"].toList();
        if(result.contains("error")) {
            m_status=result["error"].toString();
            try {Store s(database);m_pending=s.rows("SELECT id FROM operations WHERE state NOT IN ('committed','undone','abandoned')").size();}catch(...){}
            taskError=m_status;
            if(!m_sourceRequest.active)emit message(m_status);
        }
        else {try {done(result);} catch(const std::exception &e) {m_status=QString::fromUtf8(e.what());taskError=m_status;if(!m_sourceRequest.active)emit message(m_status);}}
        bool sourceFinished=false;
        if(m_sourceRequest.active) {
            if(taskError.isEmpty()&&result.value("cancelled").toBool())taskError="扫描已取消，来源目录和当前批次保持原状";
            if(!taskError.isEmpty())m_sourceRequest.error=taskError;
            // scan() can dispatch the first nextBatch(); finish only after that task ends.
            if(!m_busy){finishSourceRequest(m_sourceRequest.error);sourceFinished=true;}
        }
        if(!sourceFinished)emit changed();
    });
    const auto targetRoot=m_targetRoot;
    watcher.setFuture(QtConcurrent::run([job,refreshTree,targetRoot] {
        QVariantMap result;
        try {result=job();} catch(const std::exception &e) {result={{"error",QString::fromUtf8(e.what())}};}
        // Recount after partial failures too: some output files may already exist.
        if(refreshTree)result["tree"]=directoryTree(result.value("treeRoot",targetRoot).toString());
        return result;
    }));
}
QString Backend::dataDirectory() const {return QFileInfo(database).absolutePath();}
bool Backend::restartApplication() {
    if(m_restarting)return false;
    if(m_busy||m_sourceRequest.active){emit message("当前操作尚未结束，请完成后再重启。");return false;}
    if(!persist())return false;
    m_livePhoto->stop();
    m_restarting=true;emit restartStateChanged();
    emit restartRequested();
    return m_restarting;
}
void Backend::restartFailed(const QString &error) {
    m_restarting=false;emit restartStateChanged();
    emit message(error.isEmpty()?"重启失败，请重试。":error);
}
bool Backend::savePreference(const QString &key,const QString &value) {
    try {Store store(database);store.setValue(key,value);return true;}
    catch(const std::exception &e){emit message("设置保存失败："+QString::fromUtf8(e.what()));return false;}
}
void Backend::setThumbnailSize(int size) {
    size=qBound(170,size,310);
    if(size==m_thumbnailSize||!savePreference("thumbnailSize",QString::number(size)))return;
    m_thumbnailSize=size;emit preferencesChanged();
}
void Backend::setShowFilmstrip(bool enabled) {
    if(enabled==m_showFilmstrip||!savePreference("showFilmstrip",enabled?"1":"0"))return;
    m_showFilmstrip=enabled;emit preferencesChanged();
}
void Backend::setCropMode(bool enabled) {
    if(enabled==m_cropMode||!savePreference("cropMode",enabled?"1":"0"))return;
    m_cropMode=enabled;emit preferencesChanged();
}
void Backend::setDefaultRecursive(bool enabled) {
    if(enabled==m_defaultRecursive||!savePreference("defaultRecursive",enabled?"1":"0"))return;
    m_defaultRecursive=enabled;emit preferencesChanged();
}
void Backend::setLargeMode(bool enabled) {
    if(m_largeMode==enabled)return;
    try {
        Store store(database);
        store.setValue("viewMode",enabled?"large":"batch");
        m_largeMode=enabled;
        emit largeModeChanged();
    } catch(const std::exception &e) {
        emit message("无法保存界面模式："+QString::fromUtf8(e.what()));
    }
}
bool Backend::persist(bool commitSourceRequest) {
    if(m_sourceRequest.active&&!commitSourceRequest)return true;
    try {
        Store s(database);s.exec("BEGIN IMMEDIATE");
        try {
            s.setValue("sources",json(m_sources));s.setValue("target",m_targetRoot);s.setValue("recursive",m_recursive?"1":"0");
            s.setValue("batchSize",QString::number(m_batchSize));
            s.setValue("session",json(QVariantMap{{"items",m_items},{"queue",m_queue},{"batch",m_batch},{"consumed",QStringList(consumed.begin(),consumed.end())}}));
            s.exec("COMMIT");
        }catch(...){s.exec("ROLLBACK");throw;}
        return true;
    }catch(const std::exception &e){
        const auto error="浏览记录保存失败："+QString::fromUtf8(e.what());
        if(m_sourceRequest.active)m_sourceRequest.error=error;else emit message(error);
        return false;
    }
}
QVariantMap Backend::validateSources(const QVariantList &values) const {
    QStringList paths;
    for(const auto &value:values) {
        auto input=value.toString().trimmed();
        if(input.isEmpty())continue;
        if(input.size()>=2&&((input.startsWith('"')&&input.endsWith('"'))||(input.startsWith('\'')&&input.endsWith('\''))))input=input.mid(1,input.size()-2).trimmed();
        const QUrl url(input);
        const auto path=QDir::fromNativeSeparators(url.isLocalFile()?url.toLocalFile():input);
        const auto invalid=[&](const QString &reason){return QVariantMap{{"paths",QStringList{}},{"error",reason+"："+input}};};
        if(input.isEmpty()||path.contains(QChar('\0'))||path.contains('\n')||path.contains('\r')||!QDir::isAbsolutePath(path)
           ||(input.contains("://")&&!url.isLocalFile()))return invalid("请输入本机目录的完整路径");
        const QFileInfo info(path);
        if(!info.exists())return invalid("目录不存在");
        if(!info.isDir())return invalid("请选择目录，而不是文件");
        const auto canonical=info.canonicalFilePath();
        const auto native=QDir::toNativeSeparators(canonical);
        const auto handle=CreateFileW(reinterpret_cast<LPCWSTR>(native.utf16()),FILE_LIST_DIRECTORY,
                                      FILE_SHARE_READ|FILE_SHARE_WRITE|FILE_SHARE_DELETE,nullptr,OPEN_EXISTING,FILE_FLAG_BACKUP_SEMANTICS,nullptr);
        if(handle==INVALID_HANDLE_VALUE)return invalid("无法读取目录，请检查访问权限");
        CloseHandle(handle);
        if(canonical.isEmpty()||!info.isReadable())return invalid("无法读取目录，请检查访问权限");
        if(!paths.contains(canonical,Qt::CaseInsensitive))paths.append(canonical);
    }
    return {{"paths",paths},{"error",QString{}}};
}
void Backend::finishSourceRequest(const QString &requestedError) {
    if(!m_sourceRequest.active)return;
    QString error=requestedError;
    if(error.isEmpty()&&!persist(true))error=m_sourceRequest.error;
    if(!error.isEmpty()) {
        m_sources=m_sourceRequest.sources;m_recursive=m_sourceRequest.recursive;
        m_items=m_sourceRequest.items;m_queue=m_sourceRequest.queue;
        consumed=m_sourceRequest.consumed;m_batch=m_sourceRequest.batch;m_status=error;
    }
    m_sourceRequest=SourceRequest{};
    emit changed();
    emit sourcesApplied(error.isEmpty(),error);
}
void Backend::applySources(const QVariantList &values,bool recursive) {
    if(m_busy||m_sourceRequest.active){emit sourcesApplied(false,"请等待当前任务完成");return;}
    const auto validation=validateSources(values);
    const auto error=validation.value("error").toString();
    if(!error.isEmpty()){emit sourcesApplied(false,error);return;}
    const auto roots=validation.value("paths").toStringList();
    const bool reset=recursive!=m_recursive||std::any_of(m_sources.cbegin(),m_sources.cend(),[&roots](const auto &source){return !roots.contains(source,Qt::CaseInsensitive);});
    m_sourceRequest.active=true;m_sourceRequest.sources=m_sources;m_sourceRequest.recursive=m_recursive;
    m_sourceRequest.items=m_items;m_sourceRequest.queue=m_queue;m_sourceRequest.consumed=consumed;m_sourceRequest.batch=m_batch;
    if(roots.isEmpty()) {
        m_sources.clear();m_items.clear();m_queue.clear();consumed.clear();m_batch=0;m_recursive=recursive;
        m_status="已清空来源目录，文件和裁剪草稿均保留";
        finishSourceRequest();return;
    }
    scan(reset,roots,recursive);
}
void Backend::addSources(const QVariantList &values,bool recursive) {
    if(m_busy) return;
    QVariantList combined;for(const auto &source:m_sources)combined.append(source);combined.append(values);
    const auto validation=validateSources(combined);const auto error=validation.value("error").toString();
    if(!error.isEmpty()){emit message(error);return;}
    const auto roots=validation.value("paths").toStringList();
    if(!roots.isEmpty())scan(false,roots,recursive);
}
void Backend::openSource(const QString &path,bool recursive) {
    if(m_busy) return;
    const auto p=QFileInfo(Media::path(path)).canonicalFilePath();
    if(!QFileInfo(p).isDir()) {emit message("目录不存在");return;}
    scan(true,{p},recursive);
}
void Backend::refresh() {if(!m_busy) scan(false);}
void Backend::refreshDirectories() {
    if(m_busy||m_targetRoot.isEmpty())return;
    const auto root=m_targetRoot;
    run("更新目录数量…",[root]{return QVariantMap{{"tree",directoryTree(root)}};},[this](const auto &){m_status="目录数量已更新（含子目录的图片和视频文件）";});
}
void Backend::scan(bool reset,const QStringList &requestedRoots,bool requestedRecursive) {
    const auto roots=requestedRoots.isEmpty()?m_sources:requestedRoots;
    if(roots.isEmpty()) return;
    const auto recursive=requestedRoots.isEmpty()?m_recursive:requestedRecursive;const auto db=database;const auto cancellation=stop;
    run("正在查找图片和视频…",[=] {Store s(db);auto all=Media::scan(s,roots,recursive,cancellation);return QVariantMap{{"all",all},{"cancelled",cancellation->load()}};},[this,reset,roots,recursive](const auto &r) {
        if(r["cancelled"].toBool()) {m_status="扫描已取消，当前批次保持原状";return;}
        m_sources=roots;m_recursive=recursive;
        int missing=0;
        if(reset) {m_items.clear();m_queue.clear();consumed.clear();m_batch=0;}
        else {
            QHash<QString,QVariantMap> scanned;QSet<QString> pairedMembers;
            for(const auto &value:r["all"].toList()) {
                const auto item=value.toMap();scanned.insert(item["id"].toString(),item);
                if(item.contains("liveVideo"))pairedMembers.insert(item["liveVideo"].toMap()["id"].toString());
            }
            QVariantList refreshed;
            for(const auto &value:m_items) {
                const auto item=value.toMap();const auto id=item["id"].toString();
                if(pairedMembers.contains(id))continue;
                if(scanned.contains(id))refreshed.append(scanned.value(id));
                else {
                    // A scan omission can mean an unreadable directory or changed scan scope.
                    // Remove a current item only when Windows confirms the path is absent.
                    const auto native=QDir::toNativeSeparators(item["path"].toString());
                    const auto attributes=GetFileAttributesW(reinterpret_cast<LPCWSTR>(native.utf16()));
                    const auto error=attributes==INVALID_FILE_ATTRIBUTES?GetLastError():ERROR_SUCCESS;
                    if(error==ERROR_FILE_NOT_FOUND||error==ERROR_PATH_NOT_FOUND)++missing;
                    else refreshed.append(item);
                }
            }
            m_items=refreshed;Media::sortByCaptureTime(m_items);
        }
        QSet<QString> active; for(const auto &a:m_items) active.insert(a.toMap()["id"].toString());
        m_queue.clear();for(const auto &v:r["all"].toList()) {auto id=v.toMap()["id"].toString();if(!consumed.contains(id)&&!active.contains(id)) m_queue.append(v);}
        m_status=QString("扫描完成，共找到 %1 项图片和视频").arg(r["all"].toList().size());
        if(missing)m_status+=QString("；%1 项已不在原位置，已更新列表").arg(missing);
        if(!m_queue.isEmpty()&&m_batch>0)m_status+=QString("；后续还有 %1 项待加载").arg(m_queue.size());
        persist();
        // Refresh preserves the current batch even if all its files disappeared externally.
        // New files stay in the queue until the user continues; opening a scope starts its first batch.
        if(m_items.isEmpty()&&m_batch==0) nextBatch();
    },true,"取消扫描");
}
void Backend::setTargetRoot(const QString &input) {
    if(m_busy)return;const auto p=QFileInfo(Media::path(input)).canonicalFilePath();
    if(!QFileInfo(p).isDir()) {emit message("请选择存在的目标目录");return;}
    run("加载目标目录树…",[p]{return QVariantMap{{"tree",directoryTree(p)}};},[this,p](const auto &r){m_targetRoot=p;m_directories=r["tree"].toList();m_status="目标目录已加载";persist();});
}
void Backend::createDirectory(const QString &parent,const QString &name) {
    if(m_busy)return;
    if(!Media::validDirectoryName(name)||!QFileInfo(parent).isDir()) {emit message("目录名称无效，或父目录不存在");return;}
    const auto p=QDir(parent).filePath(name),db=database,root=m_targetRoot;
    if(QFileInfo::exists(p)) {emit message("同名文件或目录已存在");return;}
    run("创建目录…",[=]{Store s(db);ensureDir(s,p);return QVariantMap{{"tree",directoryTree(root)}};},[this,parent,p](const auto &r){m_directories=r["tree"].toList();m_status="目录已创建";emit directoryCreated(parent,p);});
}
QString Backend::relocatedPath(const QString &path,const QString &from,const QString &to) {return FileOps::relocatedPath(path,from,to);}
void Backend::applyDirectoryRename(const QString &from,const QString &to) {
    m_items=FileOps::relocatedValue(m_items,from,to).toList();
    m_queue=FileOps::relocatedValue(m_queue,from,to).toList();
    for(auto &source:m_sources)source=FileOps::relocatedPath(source,from,to);
    m_targetRoot=FileOps::relocatedPath(m_targetRoot,from,to);
    emit directoryRenamed(from,to);
}
void Backend::renameDirectory(const QString &input,const QString &name) {
    if(m_busy)return;
    if(m_pending) {emit message("存在未完成操作，请先核对记录");return;}
    const auto path=QFileInfo(Media::path(input)).absoluteFilePath();
    const auto relative=QDir(m_targetRoot).relativeFilePath(path);
    if(m_targetRoot.isEmpty()||relative==".."||relative.startsWith("../")||QDir::isAbsolutePath(relative)||
       !QFileInfo(path).isDir()||QFileInfo(path).isSymLink()||QFileInfo(path).isJunction()) {
        emit message("请选择目标根目录或其内部的普通目录进行重命名");return;
    }
    if(QDir(path).isRoot()) {emit message("磁盘或共享根路径不能重命名，请选择普通目录");return;}
    if(!Media::validDirectoryName(name)) {emit message("目录名称无效");return;}
    const auto db=database,root=m_targetRoot;
    run("重命名目录并更新路径…",[=]{Store s(db);FileOps f(s);const auto renamed=f.renameDirectory(path,name);return QVariantMap{{"path",renamed},{"treeRoot",FileOps::relocatedPath(root,path,renamed)}};},
        [this,path](const auto &r){applyDirectoryRename(path,r["path"].toString());m_status="目录已重命名";},true);
}
void Backend::setBatchSize(int count) {if(m_busy)return;m_batchSize=qBound(10,count,500);persist();emit changed();}
void Backend::nextBatch(int count) {
    if(m_busy)return;
    if(!m_items.isEmpty()) {emit message("请先完成当前批文件的移动归类；仅裁剪和复制会保留当前文件");return;}
    count=count>0?qBound(10,count,500):m_batchSize;const auto queue=m_queue;const auto cancellation=stop;
    run("正在加载下一批并检查相邻图片…",[=]{
        if(cancellation->load())return QVariantMap{{"cancelled",true}};
        int n=std::min(count,int(queue.size()));QString note;
        while(n>0 && n<queue.size()) {
            if(cancellation->load()) return QVariantMap{{"cancelled",true}};
            int relation=Media::boundary(queue[n-1].toMap()["path"].toString(),queue[n].toMap()["path"].toString());
            if(relation==0) break;
            if(relation<0) {note="无法判断相邻图片是否相似，可手动加入后续图片一起查看";break;}
            if(n>=count*2) {note="已自动加入相似图片；需要时可继续加入后续图片";break;}
            ++n;
        }
        if(cancellation->load())return QVariantMap{{"cancelled",true}};
        return QVariantMap{{"count",n},{"note",note}};
    },[this](const auto &r){
        if(r["cancelled"].toBool()){m_status="已取消加载下一批";return;}
        int n=r["count"].toInt();m_items=m_queue.mid(0,n);m_queue=m_queue.mid(n);if(n)++m_batch;
        m_status=r["note"].toString();if(m_status.isEmpty())m_status=n?QString("第 %1 批，%2 项").arg(m_batch).arg(n):"当前来源已无待加载文件，可浏览其他目录继续整理";
        persist();
    },false,"取消加载");
}
void Backend::extendBatch(int count) {
    if(m_busy)return;count=qBound(1,count,100);
    const auto added=std::min(count,int(m_queue.size()));
    m_items.append(m_queue.mid(0,count));Media::sortByCaptureTime(m_items);m_queue=m_queue.mid(count);m_status=QString("已将后续 %1 项加入当前批次").arg(added);persist();emit changed();
}
void Backend::removeItems(const QStringList &ids) {
    for(const auto &id:ids)consumed.insert(id);
    for(qsizetype i=m_items.size();i-->0;) if(ids.contains(m_items[i].toMap()["id"].toString()))m_items.removeAt(i);
    persist();
}
QVariantMap Backend::asset(const QString &id) const {for(const auto &v:items()) if(v.toMap()["id"]==id)return v.toMap();return {};}
void Backend::moveAssets(const QStringList &ids,const QString &target) {
    transferAssets(ids,target,false);
}
void Backend::copyAssets(const QStringList &ids,const QString &target) {
    transferAssets(ids,target,true);
}
void Backend::transferAssets(const QStringList &ids,const QString &target,bool copyOnly) {
    if(m_busy)return;if(m_pending){emit message("存在未完成操作，请先核对记录");return;}
    if(!QFileInfo(target).isDir()){emit message("请先选择有效目标目录");return;}
    QVariantList selected;for(const auto &id:ids){auto a=asset(id);if(!a.isEmpty())selected.append(a);}
    if(selected.isEmpty())return;
    const auto db=database;const auto cancellation=stop;
    run(copyOnly?"校验并复制原文件…":"校验并移动原文件…",[=]{
        Store s(db);FileOps f(s);QStringList done,errors;
        for(const auto &v:selected) {
            if(cancellation->load())break;auto a=v.toMap();
            try {
                if(!a["blocked"].toString().isEmpty())fail(a["blocked"].toString());
                const bool paired=a["liveType"]=="apple";
                const auto dest=paired?f.transferLive({a,a["liveVideo"]},target,copyOnly):copyOnly?f.copy(a["path"].toString(),target,a["size"].toLongLong(),a["mtime"].toLongLong()):f.move(a["path"].toString(),target,a["size"].toLongLong(),a["mtime"].toLongLong());
                if(!copyOnly)s.exec("UPDATE assets SET path=? WHERE id=?",{dest,a["id"]});
                if(paired&&!copyOnly){const auto video=a["liveVideo"].toMap();const auto moved=QFileInfo(dest).absolutePath()+"/"+QFileInfo(dest).completeBaseName()+"."+QFileInfo(video["path"].toString()).suffix();s.exec("UPDATE assets SET path=? WHERE id=?",{moved,video["id"]});}
                done.append(a["id"].toString());
            }catch(const std::exception &e){errors.append(a["name"].toString()+"："+QString::fromUtf8(e.what()));}
        }
        return QVariantMap{{"done",done},{"errors",errors},{"pending",f.reconcile().size()}};
    },[this,copyOnly](const auto &r){if(!copyOnly)removeItems(r["done"].toStringList());m_pending=r["pending"].toInt();m_status=QString(copyOnly?"已复制 %1 项，原文件保留，可继续选择其他目录":"已移动 %1 项").arg(r["done"].toStringList().size());auto e=r["errors"].toStringList();if(!e.isEmpty()){m_status+="；"+e.join("\n");emit message(m_status);}if(!copyOnly&&m_items.isEmpty())nextBatch();},true,copyOnly?"停止复制":"停止移动");
}
void Backend::cancel(){
    if(!m_busy||m_cancelAction.isEmpty()||m_cancelRequested)return;
    m_cancelRequested=true;stop->store(true);emit changed();
}
void Backend::loadHistory() try {
    if(m_busy)return;Store s(database);FileOps f(s);
    const auto renames=s.rows("SELECT * FROM operations WHERE kind='rename_directory' AND state NOT IN ('committed','undone','abandoned')");
    m_pending=f.reconcile().size();
    for(const auto &v:renames) {const auto r=v.toMap();if(s.rows("SELECT state FROM operations WHERE id=?",{r["id"]})[0].toMap()["state"]=="committed") {
        applyDirectoryRename(r["source"].toString(),r["target"].toString());m_directories=directoryTree(m_targetRoot);
    }}
    const auto view=historyView(s);m_history=view["history"].toList();m_canClearHistory=view["clearable"].toBool();emit changed();
} catch(const std::exception &e) {emit message("操作记录读取失败："+QString::fromUtf8(e.what()));}
void Backend::clearHistory() {
    const auto db=database;
    run("正在清空操作记录…",[db]{
        Store s(db);s.exec("BEGIN IMMEDIATE");
        try {
            s.exec(historyProtection+"INSERT OR IGNORE INTO cleared_history(operation) "
                "SELECT id FROM operations WHERE id NOT IN (SELECT id FROM protected)");
            const auto view=historyView(s);s.exec("COMMIT");return view;
        }catch(...){s.exec("ROLLBACK");throw;}
    },[this](const auto &r){
        m_history=r["history"].toList();m_canClearHistory=r["clearable"].toBool();
        m_status=m_history.isEmpty()?"操作记录已清空":"已清空已结束的操作记录，未完成操作已保留";
    });
}
void Backend::undo(const QString &id) {
    if(m_busy)return;const auto db=database;
    run("核对并撤销移动…",[=]{Store s(db);FileOps f(s);auto old=s.rows("SELECT * FROM operations WHERE id=?",{id});QString p=f.undo(id);
        if(old[0].toMap()["kind"]=="live_move")for(const auto &v:s.rows("SELECT source,target FROM live_members WHERE group_id=?",{id})){const auto r=v.toMap();s.exec("UPDATE assets SET path=? WHERE path=?",{r["source"],r["target"]});}
        else s.exec("UPDATE assets SET path=? WHERE path=?",{p,old[0].toMap()["target"]});return QVariantMap{{"path",p}};},[this](const auto &){m_status="已撤销，重新打开原目录可继续整理";loadHistory();},true);
}
void Backend::recover(const QString &id) {
    if(m_busy)return;const auto db=database,root=m_targetRoot;
    run("核对并继续未完成操作…",[=]{
        Store s(db);FileOps f(s);auto r=s.rows("SELECT * FROM operations WHERE id=?",{id});
        if(r.isEmpty())fail("记录不存在");auto old=r[0].toMap();QString p=f.recover(id);QStringList done;
        if(old["kind"]=="move") {
            for(const auto &a:s.rows("SELECT id FROM assets WHERE path=?",{old["source"]}))done.append(a.toMap()["id"].toString());
            s.exec("UPDATE assets SET path=? WHERE path=?",{p,old["source"]});
        }
        if(old["kind"]=="live_move")for(const auto &v:s.rows("SELECT source,target FROM live_members WHERE group_id=?",{id})){
            const auto member=v.toMap();for(const auto &a:s.rows("SELECT id FROM assets WHERE path=?",{member["source"]}))done.append(a.toMap()["id"].toString());
            s.exec("UPDATE assets SET path=? WHERE path=?",{member["target"],member["source"]});
        }
        return QVariantMap{{"done",done},{"pending",f.reconcile().size()},{"renameFrom",old["kind"]=="rename_directory"?old["source"]:QVariant()},{"renameTo",p},
                           {"treeRoot",old["kind"]=="rename_directory"?FileOps::relocatedPath(root,old["source"].toString(),p):root}};
    },[this](const auto &r){if(!r["renameFrom"].toString().isEmpty())applyDirectoryRename(r["renameFrom"].toString(),r["renameTo"].toString());removeItems(r["done"].toStringList());m_pending=r["pending"].toInt();m_status="已核对并完成操作";loadHistory();},true);
}
QVariantMap Backend::imageDimensions(const QString &id) try {
    const auto a=asset(id);if(a.isEmpty()||a["type"]=="视频")return {};
    const auto size=Media::orientedSize(a["path"].toString());return {{"width",size.width()},{"height",size.height()}};
} catch(const std::exception &e) {emit message(QString::fromUtf8(e.what()));return {};}
QVariantMap Backend::constrainCrop(const QVariantMap &dimensions,const QVariantMap &spec,const QVariantMap &previous) try {
    const CropGeometry geometry(QSize(dimensions.value("width").toInt(),dimensions.value("height").toInt()),spec.value("angle").toDouble());
    auto result=geometry.constrain(spec,previous);result["canvasWidth"]=geometry.canvasSize().width();result["canvasHeight"]=geometry.canvasSize().height();
    result["imageCenterX"]=geometry.sourceCenter().x();result["imageCenterY"]=geometry.sourceCenter().y();return result;
} catch(const std::exception &) {return {};}
QVariantList Backend::loadDraft(const QString &id) try {
    auto a=asset(id);if(a.isEmpty())return {};Store s(database);auto r=s.rows("SELECT * FROM drafts WHERE asset=?",{id});
    if(r.isEmpty())return {};if(r[0].toMap()["stamp"]!=version(a)){emit message("原图版本已变化，旧草稿未加载");return {};}
    return parse(r[0].toMap()["json"].toString()).toList();
} catch(const std::exception &e) {emit message("草稿读取失败："+QString::fromUtf8(e.what()));return {};}
bool Backend::saveDraft(const QString &id,const QVariantList &draft) try {
    auto a=asset(id);if(a.isEmpty() || m_busy)return false;Store s(database);s.exec("INSERT INTO drafts(asset,stamp,json) VALUES(?,?,?) ON CONFLICT(asset) DO UPDATE SET stamp=excluded.stamp,json=excluded.json",{id,version(a),json(draft)});return true;
} catch(const std::exception &e) {emit message("草稿保存失败："+QString::fromUtf8(e.what()));return false;}
void Backend::exportCrops(const QString &id,const QVariantList &draft,bool onlyCrop) {
    if(m_busy)return;auto a=asset(id);if(a.isEmpty()||draft.isEmpty())return;
    if(m_pending){emit message("存在未完成操作，请先核对记录");return;}
    if(!a["blocked"].toString().isEmpty()){emit message(a["blocked"].toString());return;}
    if(a["type"]=="视频"){emit message("视频不支持裁剪");return;}
    saveDraft(id,draft);const auto db=database;
    run(onlyCrop?"裁剪并保存到原图目录…":"保存裁剪子图…",[=]{
        Store s(db);FileOps f(s);const auto path=a["path"].toString(),root=a["root"].toString();
        auto before=FileOps::stamp(path,true);
        if(before.size!=a["size"].toLongLong() || before.mtime!=a["mtime"].toLongLong())fail("原图已变化，请重新扫描");
        const auto sourceDirectory=QFileInfo(path).absolutePath();
        if(!onlyCrop)for(const auto &v:draft)if(!QFileInfo(v.toMap()["target"].toString()).isDir())fail("每个子图都需要有效目标目录，或使用“仅裁剪”先保存在原图目录");
        const auto oriented=Media::read(path);const auto captureTime=Media::captureTime(path);
        // Validate every child before writing any output, including unvisited saved drafts.
        for(const auto &v:draft) {const auto spec=v.toMap();CropGeometry(oriented.size(),spec.value("angle").toDouble()).checkedPixelRect(spec);}
        int n=0;QStringList outputKeys,outputs;QVariantList localOutputs;
        for(const auto &v:draft) {
            auto spec=v.toMap();if(onlyCrop)spec["target"]=sourceDirectory;
            const double angle=spec["angle"].toDouble();if(!std::isfinite(angle)||abs(angle)>360)fail("旋转角度无效");
            auto output=Media::rotateAndCrop(oriented,spec);Media::inheritCaptureTime(output,captureTime);
            // Metadata changes are a new output format; do not reuse a legacy export without its time.
            const auto key=QString::fromLatin1(QCryptographicHash::hash(("capture-time-v1:"+id+before.sha+json(spec)+json(captureTime)).toUtf8(),QCryptographicHash::Sha256).toHex());
            const auto name=QFileInfo(path).completeBaseName()+QString("_crop_%1.png").arg(++n,3,10,QChar('0'));
            outputs.append(f.writeImage(output,spec["target"].toString(),name,key,id));outputKeys.append(key);
        }
        if(FileOps::hash(path)!=before.sha)fail("导出期间原图已变化，保留输出和原图，请重新扫描核对");
        // Check the complete group again: an earlier child may have changed while later children were written.
        for(int i=0;i<outputs.size();++i) {
            const auto record=s.rows("SELECT sha,state FROM operations WHERE id=?",{outputKeys[i]})[0].toMap();
            if(record["state"]!="committed"||FileOps::hash(outputs[i])!=record["sha"].toString())fail("子图校验失败，原图保留，未记录学习样本");
        }
        for(const auto &outputPath:outputs)if(QFileInfo(outputPath).absolutePath().compare(sourceDirectory,Qt::CaseInsensitive)==0) {
            const QFileInfo file(outputPath);const auto old=s.rows("SELECT id FROM assets WHERE path=?",{outputPath});
            const auto outputId=old.isEmpty()?QUuid::createUuid().toString(QUuid::WithoutBraces):old[0].toMap()["id"].toString();
            s.exec("INSERT INTO assets(id,path,root,size,mtime,type,blocked) VALUES(?,?,?,?,?,'图片','') ON CONFLICT(path) DO UPDATE SET size=excluded.size,mtime=excluded.mtime,type=excluded.type,blocked=''",{outputId,outputPath,root,file.size(),file.lastModified().toMSecsSinceEpoch()});
            localOutputs.append(QVariantMap{{"id",outputId},{"path",outputPath},{"root",root},{"name",file.fileName()},{"size",file.size()},{"mtime",file.lastModified().toMSecsSinceEpoch()},{"type","图片"},{"blocked",""},{"kind",""},{"url",QUrl::fromLocalFile(outputPath).toString()},{"thumb","image://media/"+outputId+"/0/"+QString::number(file.lastModified().toMSecsSinceEpoch())}});
        }
        for(auto &value:localOutputs){auto item=value.toMap();const auto time=Media::captureTime(item["path"].toString());
            item["isLive"]=false;
            item["liveSchema"]=2;
            for(auto it=time.begin();it!=time.end();++it)item.insert(it.key(),it.value());value=item;
        }
        QString learningWarning;
        const auto learningKey=QString::fromLatin1(QCryptographicHash::hash(outputKeys.join('|').toUtf8(),QCryptographicHash::Sha256).toHex());
        try {SmartCropRecords::save(SmartCropRecords::rootFor(db),oriented,before.sha,draft,learningKey);}
        catch(const std::exception &e){learningWarning="裁剪已成功，但学习记录保存失败："+QString::fromUtf8(e.what());}
        return QVariantMap{{"count",n},{"learningWarning",learningWarning},{"localOutputs",localOutputs}};
    },[this,id,onlyCrop](const auto &r){
        QSet<QString> added;int insertAt=m_items.size();
        for(int i=0;i<m_items.size();++i){added.insert(m_items[i].toMap()["id"].toString());if(m_items[i].toMap()["id"]==id)insertAt=i+1;}
        for(const auto &v:r["localOutputs"].toList()) {const auto outputId=v.toMap()["id"].toString();if(!added.contains(outputId)){m_items.insert(insertAt++,v);added.insert(outputId);consumed.remove(outputId);}}
        Media::sortByCaptureTime(m_items);
        for(qsizetype i=m_queue.size();i-->0;)if(added.contains(m_queue[i].toMap()["id"].toString()))m_queue.removeAt(i);
        persist();m_smartCrop->recordsChanged();m_status=QString(onlyCrop?"已生成 %1 个子图并加入当前列表，原图保留，可继续分别移动":"已保存 %1 个 PNG 子图，原图保留在原位置").arg(r["count"].toInt());if(!r["learningWarning"].toString().isEmpty())emit message(r["learningWarning"].toString());
    },true);
}
void Backend::reveal(const QString &input){const auto p=Media::path(input);QDesktopServices::openUrl(QUrl::fromLocalFile(QFileInfo(p).isDir()?p:QFileInfo(p).absolutePath()));}
