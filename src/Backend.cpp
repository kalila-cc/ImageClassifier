#include "Backend.h"
#include "Store.h"
#include "FileOps.h"
#include "Media.h"
#include "CropGeometry.h"
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
#include <stdexcept>

namespace {
QString json(const QVariant &v) {return QString::fromUtf8(QJsonDocument::fromVariant(v).toJson(QJsonDocument::Compact));}
QVariant parse(const QString &s) {return QJsonDocument::fromJson(s.toUtf8()).toVariant();}
QString version(const QVariantMap &a) {return a["size"].toString()+":"+a["mtime"].toString();}
void fail(const QString &s) {throw std::runtime_error(s.toUtf8().constData());}
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
    Store s(database); FileOps files(s);
    m_pending=files.reconcile().size();
    m_sources=parse(s.value("sources","[]")).toStringList();
    m_targetRoot=s.value("target");
    m_directories=directoryTree(m_targetRoot,false);
    QTimer::singleShot(0,this,[this]{if(!m_busy&&!m_targetRoot.isEmpty())refreshDirectories();});
    m_recursive=s.value("recursive","1")=="1";
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
    // Stored snapshots are revalidated on every modifying command, never replayed.
    if(!m_items.isEmpty() || !m_queue.isEmpty()) m_status="已恢复浏览；执行操作前会重新核对文件";
    if(restoredCount)m_status=QString("已恢复 %1 张被隐藏的图片，原文件与编辑草稿均保留").arg(restoredCount);
    if(m_pending) m_status=QString("有 %1 项未完成文件操作，请先在记录中核对").arg(m_pending);
}
Backend::~Backend() {stop->store(true); watcher.waitForFinished();}
void Backend::run(const QString &title,std::function<QVariantMap()> job,std::function<void(const QVariantMap &)> done,bool refreshTree) {
    if(m_busy) {emit message("请等待当前任务完成");return;}
    m_busy=true; stop->store(false); m_status=title; emit changed();
    disconnect(&watcher,nullptr,this,nullptr);
    connect(&watcher,&QFutureWatcher<QVariantMap>::finished,this,[this,done] {
        const auto result=watcher.result(); m_busy=false;
        if(result.contains("tree"))m_directories=result["tree"].toList();
        if(result.contains("error")) {
            m_status=result["error"].toString();
            try {Store s(database);m_pending=s.rows("SELECT id FROM operations WHERE state NOT IN ('committed','undone','abandoned')").size();}catch(...){}
            emit message(m_status);
        }
        else {try {done(result);} catch(const std::exception &e) {m_status=QString::fromUtf8(e.what());emit message(m_status);}}
        emit changed();
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
void Backend::persist() try {
    Store s(database); s.setValue("sources",json(m_sources)); s.setValue("target",m_targetRoot);s.setValue("recursive",m_recursive?"1":"0");
    s.setValue("batchSize",QString::number(m_batchSize));
    s.setValue("session",json(QVariantMap{{"items",m_items},{"queue",m_queue},{"batch",m_batch},{"consumed",QStringList(consumed.begin(),consumed.end())}}));
} catch(const std::exception &e) {emit message("浏览记录保存失败："+QString::fromUtf8(e.what()));}
void Backend::addSources(const QVariantList &values,bool recursive) {
    if(m_busy) return;
    for(const auto &v:values) {const auto p=QFileInfo(Media::path(v.toString())).canonicalFilePath(); if(QFileInfo(p).isDir() && !m_sources.contains(p,Qt::CaseInsensitive)) m_sources.append(p);}
    m_recursive=recursive;scan(false);
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
    run("扫描目录并建立轻量索引…",[=] {Store s(db);auto all=Media::scan(s,roots,recursive,cancellation);return QVariantMap{{"all",all},{"cancelled",cancellation->load()}};},[this,reset,roots,recursive](const auto &r) {
        if(r["cancelled"].toBool()) {m_status="扫描已取消，当前批次保持原状";return;}
        m_sources=roots;m_recursive=recursive;
        if(reset) {m_items.clear();m_queue.clear();consumed.clear();m_batch=0;}
        QSet<QString> active; for(const auto &a:m_items) active.insert(a.toMap()["id"].toString());
        m_queue.clear();for(const auto &v:r["all"].toList()) {auto id=v.toMap()["id"].toString();if(!consumed.contains(id)&&!active.contains(id)) m_queue.append(v);}
        m_status=QString("扫描完成，共 %1 项；未解码内容在浏览时按需加载").arg(r["all"].toList().size());persist();
        if(m_items.isEmpty()) nextBatch();
    },true);
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
    if(!m_items.isEmpty()) {emit message("请先完成当前批图片的归类或编辑归档");return;}
    count=count>0?qBound(10,count,500):m_batchSize;const auto queue=m_queue;const auto cancellation=stop;
    run("准备当前批与边界检查…",[=]{
        int n=std::min(count,int(queue.size()));QString note;
        while(n>0 && n<queue.size()) {
            if(cancellation->load()) return QVariantMap{{"cancelled",true}};
            int relation=Media::boundary(queue[n-1].toMap()["path"].toString(),queue[n].toMap()["path"].toString());
            if(relation==0) break;
            if(relation<0) {note="批次边界无法确定，可查看相邻图片并手动纳入";break;}
            if(n>=count*2) {note="相似图片达到自动延伸上限，可继续纳入";break;}
            ++n;
        }
        return QVariantMap{{"count",n},{"note",note}};
    },[this](const auto &r){
        if(r["cancelled"].toBool()){m_status="批次准备已取消";return;}
        int n=r["count"].toInt();m_items=m_queue.mid(0,n);m_queue=m_queue.mid(n);if(n)++m_batch;
        m_status=r["note"].toString();if(m_status.isEmpty())m_status=n?QString("第 %1 批，%2 项").arg(m_batch).arg(n):"当前范围已整理完，可重新打开目录继续分类";
        persist();
    });
}
void Backend::extendBatch(int count) {
    if(m_busy)return;count=qBound(1,count,100);
    m_items.append(m_queue.mid(0,count));m_queue=m_queue.mid(count);m_status="已手动扩展当前批次";persist();emit changed();
}
void Backend::removeItems(const QStringList &ids) {
    for(const auto &id:ids)consumed.insert(id);
    for(qsizetype i=m_items.size();i-->0;) if(ids.contains(m_items[i].toMap()["id"].toString()))m_items.removeAt(i);
    persist();
}
QVariantMap Backend::asset(const QString &id) const {for(const auto &v:m_items) if(v.toMap()["id"]==id)return v.toMap();return {};}
void Backend::moveAssets(const QStringList &ids,const QString &target) {
    if(m_busy)return;if(m_pending){emit message("存在未完成操作，请先核对记录");return;}
    if(!QFileInfo(target).isDir()){emit message("请先选择有效目标目录");return;}
    QVariantList selected;for(const auto &id:ids){auto a=asset(id);if(!a.isEmpty())selected.append(a);}
    if(selected.isEmpty())return;
    const auto db=database;const auto cancellation=stop;
    run("安全移动文件…",[=]{
        Store s(db);FileOps f(s);QStringList done,errors;
        for(const auto &v:selected) {
            if(cancellation->load())break;auto a=v.toMap();
            try {
                if(!a["blocked"].toString().isEmpty())fail(a["blocked"].toString());
                const auto dest=f.move(a["path"].toString(),target,a["size"].toLongLong(),a["mtime"].toLongLong());
                s.exec("UPDATE assets SET path=? WHERE id=?",{dest,a["id"]});done.append(a["id"].toString());
            }catch(const std::exception &e){errors.append(a["name"].toString()+"："+QString::fromUtf8(e.what()));}
        }
        return QVariantMap{{"done",done},{"errors",errors},{"pending",f.reconcile().size()}};
    },[this](const auto &r){removeItems(r["done"].toStringList());m_pending=r["pending"].toInt();m_status=QString("已移动 %1 项").arg(r["done"].toStringList().size());auto e=r["errors"].toStringList();if(!e.isEmpty()){m_status+="；"+e.join("\n");emit message(m_status);}if(m_items.isEmpty())nextBatch();},true);
}
void Backend::cancel(){stop->store(true);}
void Backend::loadHistory() try {
    if(m_busy)return;Store s(database);FileOps f(s);
    const auto renames=s.rows("SELECT * FROM operations WHERE kind='rename_directory' AND state NOT IN ('committed','undone','abandoned')");
    m_pending=f.reconcile().size();
    for(const auto &v:renames) {const auto r=v.toMap();if(s.rows("SELECT state FROM operations WHERE id=?",{r["id"]})[0].toMap()["state"]=="committed") {
        applyDirectoryRename(r["source"].toString(),r["target"].toString());m_directories=directoryTree(m_targetRoot);
    }}
    m_history=s.rows("SELECT * FROM operations ORDER BY created DESC,rowid DESC LIMIT 100");emit changed();
} catch(const std::exception &e) {emit message("操作记录读取失败："+QString::fromUtf8(e.what()));}
void Backend::undo(const QString &id) {
    if(m_busy)return;const auto db=database;
    run("核对并撤销移动…",[=]{Store s(db);FileOps f(s);auto old=s.rows("SELECT * FROM operations WHERE id=?",{id});QString p=f.undo(id);s.exec("UPDATE assets SET path=? WHERE path=?",{p,old[0].toMap()["target"]});return QVariantMap{{"path",p}};},[this](const auto &){m_status="已撤销，重新打开原目录可继续整理";loadHistory();},true);
}
void Backend::recover(const QString &id) {
    if(m_busy)return;const auto db=database,root=m_targetRoot;
    run("核对并恢复文件操作…",[=]{
        Store s(db);FileOps f(s);auto r=s.rows("SELECT * FROM operations WHERE id=?",{id});
        if(r.isEmpty())fail("记录不存在");auto old=r[0].toMap();QString p=f.recover(id);QStringList done;
        if(old["kind"]=="move") {
            for(const auto &a:s.rows("SELECT id FROM assets WHERE path=?",{old["source"]}))done.append(a.toMap()["id"].toString());
            s.exec("UPDATE assets SET path=? WHERE path=?",{p,old["source"]});
        }
        return QVariantMap{{"done",done},{"pending",f.reconcile().size()},{"renameFrom",old["kind"]=="rename_directory"?old["source"]:QVariant()},{"renameTo",p},
                           {"treeRoot",old["kind"]=="rename_directory"?FileOps::relocatedPath(root,old["source"].toString(),p):root}};
    },[this](const auto &r){if(!r["renameFrom"].toString().isEmpty())applyDirectoryRename(r["renameFrom"].toString(),r["renameTo"].toString());removeItems(r["done"].toStringList());m_pending=r["pending"].toInt();m_status="操作已核对恢复";loadHistory();},true);
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
void Backend::saveDraft(const QString &id,const QVariantList &draft) try {
    auto a=asset(id);if(a.isEmpty() || m_busy)return;Store s(database);s.exec("INSERT INTO drafts(asset,stamp,json) VALUES(?,?,?) ON CONFLICT(asset) DO UPDATE SET stamp=excluded.stamp,json=excluded.json",{id,version(a),json(draft)});
} catch(const std::exception &e) {emit message("草稿保存失败："+QString::fromUtf8(e.what()));}
void Backend::exportCrops(const QString &id,const QVariantList &draft) {
    if(m_busy)return;auto a=asset(id);if(a.isEmpty()||draft.isEmpty())return;
    if(m_pending){emit message("存在未完成操作，请先核对记录");return;}
    if(!a["blocked"].toString().isEmpty()){emit message(a["blocked"].toString());return;}
    if(a["type"]=="视频"){emit message("视频不支持裁剪");return;}
    saveDraft(id,draft);const auto db=database;
    run("导出子图并归档原图…",[=]{
        Store s(db);FileOps f(s);const auto path=a["path"].toString(),root=a["root"].toString();
        auto before=FileOps::stamp(path,true);
        if(before.size!=a["size"].toLongLong() || before.mtime!=a["mtime"].toLongLong())fail("原图已变化，请重新扫描");
        if(QFileInfo(root).fileName()=="已处理")fail("来源已是归档目录，请先从其他工作目录整理，避免嵌套归档");
        for(const auto &v:draft)if(!QFileInfo(v.toMap()["target"].toString()).isDir())fail("每个子图都需要有效目标目录");
        const auto oriented=Media::read(path);
        // Validate every child before writing any output, including unvisited saved drafts.
        for(const auto &v:draft) {const auto spec=v.toMap();CropGeometry(oriented.size(),spec.value("angle").toDouble()).checkedPixelRect(spec);}
        int n=0;
        for(const auto &v:draft) {
            const auto spec=v.toMap();const double angle=spec["angle"].toDouble();if(!std::isfinite(angle)||abs(angle)>360)fail("旋转角度无效");
            const auto output=Media::rotateAndCrop(oriented,spec);
            const auto key=QString::fromLatin1(QCryptographicHash::hash((id+before.sha+json(spec)).toUtf8(),QCryptographicHash::Sha256).toHex());
            const auto name=QFileInfo(path).completeBaseName()+QString("_crop_%1.png").arg(++n,3,10,QChar('0'));
            f.writeImage(output,spec["target"].toString(),name,key,id);
        }
        if(FileOps::hash(path)!=before.sha)fail("导出期间原图已变化，保留输出和原图，不执行归档");
        auto relative=QDir(root).relativeFilePath(QFileInfo(path).absolutePath());if(relative.startsWith(".."))fail("原图不在来源范围内");
        const auto archive=QDir(root).filePath("已处理/"+(relative=="."?QString():relative));ensureDir(s,archive);
        auto dest=f.move(path,archive,before.size,before.mtime,id,{},before.sha);s.exec("UPDATE assets SET path=? WHERE id=?",{dest,id});s.exec("DELETE FROM drafts WHERE asset=?",{id});
        return QVariantMap{{"count",n}};
    },[this,id](const auto &r){removeItems({id});m_status=QString("已输出 %1 个 PNG 子图，原图已移入“已处理”").arg(r["count"].toInt());if(m_items.isEmpty())nextBatch();},true);
}
void Backend::reveal(const QString &input){const auto p=Media::path(input);QDesktopServices::openUrl(QUrl::fromLocalFile(QFileInfo(p).isDir()?p:QFileInfo(p).absolutePath()));}
