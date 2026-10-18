#include <QtTest>
#include <QTemporaryDir>
#include <QFile>
#include <QDir>
#include <QJsonDocument>
#include "FileOps.h"
#include "Media.h"
#include "Backend.h"
#include "CropGeometry.h"

static void write(const QString &p,const QByteArray &b){QFile f(p);if(!f.open(QIODevice::WriteOnly))qFatal("fixture failed");f.write(b);}
static int directoryCount(const Backend &backend,const QString &path) {
    for(const auto &v:backend.directories())if(v.toMap()["path"].toString()==QDir::cleanPath(path))return v.toMap()["mediaCount"].toInt();
    return -999;
}
class CoreTests:public QObject {
    Q_OBJECT
private slots:
    void reopenClassifiedDirectory(){
        QTemporaryDir t;const auto source=t.filePath("source"),root=t.filePath("target"),first=root+"/01",second=root+"/02",db=t.filePath("state/db.sqlite");
        QVERIFY(QDir().mkpath(source));QVERIFY(QDir().mkpath(first+"/01-01"));QVERIFY(QDir().mkpath(second));
        QImage image(32,32,QImage::Format_RGB32);image.fill(Qt::green);
        QVERIFY(image.save(source+"/moved.png"));
        for(int i=0;i<2;++i)QVERIFY(image.save(first+QString("/direct%1.png").arg(i)));
        for(int i=0;i<9;++i)QVERIFY(image.save(first+QString("/01-01/nested%1.png").arg(i)));
        QString id;
        {
            Backend b(db);b.setTargetRoot(root);QTRY_VERIFY_WITH_TIMEOUT(!b.busy(),5000);
            b.addSources({source},true);QTRY_VERIFY_WITH_TIMEOUT(!b.busy(),5000);
            id=b.items()[0].toMap()["id"].toString();
            b.saveDraft(id,{QVariantMap{{"id","crop"},{"target",second},{"angle",13.7}}});
            b.moveAssets({id},first);QTRY_VERIFY_WITH_TIMEOUT(!b.busy(),5000);QCOMPARE(b.items().size(),0);
            b.openSource(first,false);QTRY_VERIFY_WITH_TIMEOUT(!b.busy(),5000);
            QCOMPARE(b.items().size(),3);QVERIFY(!b.recursive());QCOMPARE(directoryCount(b,first),12);
            for(const auto &v:b.items())QCOMPARE(QFileInfo(v.toMap()["path"].toString()).absolutePath(),first);
            QCOMPARE(b.loadDraft(id)[0].toMap()["angle"].toDouble(),13.7);
            b.moveAssets({id},second);QTRY_VERIFY_WITH_TIMEOUT(!b.busy(),5000);QCOMPARE(b.items().size(),2);
            b.openSource(second,false);QTRY_VERIFY_WITH_TIMEOUT(!b.busy(),5000);
            QCOMPARE(b.items().size(),1);QCOMPARE(b.items()[0].toMap()["id"].toString(),id);
            b.openSource(root,false);QTRY_VERIFY_WITH_TIMEOUT(!b.busy(),5000);QCOMPARE(b.items().size(),0);
            b.openSource(first,false);QTRY_VERIFY_WITH_TIMEOUT(!b.busy(),5000);QCOMPARE(b.items().size(),2);
            b.openSource(t.filePath("missing"),false);QCOMPARE(b.sources(),QStringList{first});QCOMPARE(b.items().size(),2);
        }
        Backend restored(db);QCOMPARE(restored.sources(),QStringList{first});QVERIFY(!restored.recursive());QCOMPARE(restored.items().size(),2);
    }
    void directoryRenameWorkflow(){
        QTemporaryDir t;const auto root=t.filePath("target"),old=root+"/old",next=root+"/新名称",db=t.filePath("state/db.sqlite");
        QVERIFY(QDir().mkpath(old+"/nested"));QVERIFY(QDir().mkpath(root+"/older"));
        QImage image(32,32,QImage::Format_RGB32);image.fill(Qt::blue);
        QVERIFY(image.save(old+"/nested/photo.png"));QVERIFY(image.save(root+"/older/untouched.png"));
        const auto external=t.filePath("external.png"),renamedRoot=t.filePath("root-renamed"),renamedChild=renamedRoot+"/新名称";QVERIFY(image.save(external));QString id;
        {
            Backend b(db);b.setTargetRoot(root);QTRY_VERIFY_WITH_TIMEOUT(!b.busy(),5000);
            b.addSources({old},true);QTRY_VERIFY_WITH_TIMEOUT(!b.busy(),5000);QCOMPARE(b.items().size(),1);
            id=b.items()[0].toMap()["id"].toString();
            b.saveDraft(id,{QVariantMap{{"id","draft"},{"target",old+"/nested"},{"angle",13.7}}});
            QString moveId;
            {Store s(db);FileOps f(s);f.move(external,old+"/nested");moveId=s.rows("SELECT id FROM operations WHERE kind='move'")[0].toMap()["id"].toString();}
            QSignalSpy renamed(&b,&Backend::directoryRenamed),messages(&b,&Backend::message);
            b.renameDirectory(old,"新名称");QTRY_VERIFY_WITH_TIMEOUT(!b.busy(),5000);
            QCOMPARE(messages.size(),0);QCOMPARE(renamed.size(),1);
            QVERIFY(!QFileInfo::exists(old));QVERIFY(QFileInfo::exists(next+"/nested/photo.png"));
            QVERIFY(QFileInfo::exists(root+"/older/untouched.png"));
            QCOMPARE(b.sources(),QStringList{next});QCOMPARE(b.items()[0].toMap()["id"].toString(),id);
            QCOMPARE(b.items()[0].toMap()["path"].toString(),next+"/nested/photo.png");
            QCOMPARE(QUrl(b.items()[0].toMap()["url"].toString()).toLocalFile(),next+"/nested/photo.png");
            QCOMPARE(b.loadDraft(id)[0].toMap()["target"].toString(),next+"/nested");
            QCOMPARE(directoryCount(b,next),2);QCOMPARE(directoryCount(b,root),3);
            b.undo(moveId);QTRY_VERIFY_WITH_TIMEOUT(!b.busy(),5000);QVERIFY(QFileInfo::exists(external));
            QCOMPARE(directoryCount(b,next),1);
            b.createDirectory(next,"child");QTRY_VERIFY_WITH_TIMEOUT(!b.busy(),5000);QCOMPARE(directoryCount(b,next+"/child"),0);
            b.renameDirectory(next,"older");QTRY_VERIFY_WITH_TIMEOUT(!b.busy(),5000);QVERIFY(QFileInfo::exists(next));QCOMPARE(messages.size(),1);
            b.renameDirectory(next,"../bad");QCOMPARE(messages.size(),2);
            b.renameDirectory(root,"root-renamed");QTRY_VERIFY_WITH_TIMEOUT(!b.busy(),5000);
            QCOMPARE(messages.size(),2);QCOMPARE(renamed.size(),2);
            QCOMPARE(b.targetRoot(),renamedRoot);QVERIFY(!QFileInfo::exists(root));
            QCOMPARE(directoryCount(b,renamedRoot),2);QCOMPARE(directoryCount(b,renamedChild),1);
            QCOMPARE(b.sources(),QStringList{renamedChild});
            QCOMPARE(b.items()[0].toMap()["path"].toString(),renamedChild+"/nested/photo.png");
            QCOMPARE(b.loadDraft(id)[0].toMap()["target"].toString(),renamedChild+"/nested");
            b.createDirectory(renamedRoot,"root-child");QTRY_VERIFY_WITH_TIMEOUT(!b.busy(),5000);
            QCOMPARE(directoryCount(b,renamedRoot+"/root-child"),0);
            b.refreshDirectories();QTRY_VERIFY_WITH_TIMEOUT(!b.busy(),5000);QCOMPARE(directoryCount(b,renamedRoot),2);
            b.renameDirectory(t.path(),"outside");QCOMPARE(messages.size(),3);QVERIFY(QFileInfo::exists(t.path()));
        }
        Backend restored(db);QTRY_VERIFY_WITH_TIMEOUT(!restored.busy(),5000);
        QCOMPARE(restored.targetRoot(),renamedRoot);
        QCOMPARE(restored.sources(),QStringList{renamedChild});QCOMPARE(restored.items()[0].toMap()["path"].toString(),renamedChild+"/nested/photo.png");
        QCOMPARE(restored.loadDraft(id)[0].toMap()["target"].toString(),renamedChild+"/nested");
        QTRY_COMPARE_WITH_TIMEOUT(directoryCount(restored,renamedRoot),2,5000);
    }
    void directoryRenameRecovery(){
        QTemporaryDir t;const auto old=t.filePath("before"),next=t.filePath("after");QVERIFY(QDir().mkpath(old+"/nested"));
        write(old+"/nested/photo.png","preserve these bytes");
        Store s(t.filePath("state/db.sqlite"));FileOps f(s);
        s.exec("INSERT INTO assets(id,path,root,size,mtime,type) VALUES('asset',?,?,20,0,'图片')",{old+"/nested/photo.png",old});
        f.checkpoint=[](const QString &phase){if(phase=="target_ready")throw std::runtime_error("simulated interruption");};
        QVERIFY_EXCEPTION_THROWN(f.renameDirectory(old,"after"),std::runtime_error);
        QVERIFY(QFileInfo::exists(next+"/nested/photo.png"));
        QCOMPARE(s.rows("SELECT path FROM assets")[0].toMap()["path"].toString(),old+"/nested/photo.png");
        f.checkpoint={};QCOMPARE(f.reconcile().size(),0);
        QCOMPARE(s.rows("SELECT path FROM assets")[0].toMap()["path"].toString(),next+"/nested/photo.png");
        const auto hash=FileOps::hash(next+"/nested/photo.png");
        // Windows case-only renames must update references as well.
        QCOMPARE(f.renameDirectory(next,"AFTER"),t.filePath("AFTER"));
        QCOMPARE(s.rows("SELECT path FROM assets")[0].toMap()["path"].toString(),t.filePath("AFTER/nested/photo.png"));
        QCOMPARE(FileOps::hash(t.filePath("AFTER/nested/photo.png")),hash);
        QCOMPARE(f.reconcile().size(),0);
    }
    void directoryMediaCounts(){
        QTemporaryDir t;const auto root=t.filePath("target"),db=t.filePath("state/db.sqlite");
        QVERIFY(QDir().mkpath(root+"/child/nested"));QVERIFY(QDir().mkpath(root+"/empty"));
        write(root+"/photo.JPG","count without decoding");write(root+"/notes.txt","excluded");
        write(root+"/child/photo.png","image");write(root+"/child/clip.MOV","video");
        write(root+"/child/.imageclassifier-pending.png","excluded temporary output");
        write(root+"/child/nested/live.HEIC","image");
        {
            Backend b(db);b.setTargetRoot(root);QTRY_VERIFY_WITH_TIMEOUT(!b.busy(),5000);
            QCOMPARE(directoryCount(b,root),4);QCOMPARE(directoryCount(b,root+"/child"),3);
            QCOMPARE(directoryCount(b,root+"/child/nested"),1);QCOMPARE(directoryCount(b,root+"/empty"),0);
            for(const auto &v:b.directories())if(v.toMap()["path"].toString()==root+"/child") {
                QCOMPARE(v.toMap()["imageCount"].toInt(),2);QCOMPARE(v.toMap()["videoCount"].toInt(),1);
                QCOMPARE(v.toMap()["directCount"].toInt(),2);
                QCOMPARE(v.toMap()["directImageCount"].toInt(),1);QCOMPARE(v.toMap()["directVideoCount"].toInt(),1);
            }
            write(root+"/external.PNG","added externally");b.refreshDirectories();QTRY_VERIFY_WITH_TIMEOUT(!b.busy(),5000);
            QCOMPARE(directoryCount(b,root),5);
            b.createDirectory(root,"new");QTRY_VERIFY_WITH_TIMEOUT(!b.busy(),5000);QCOMPARE(directoryCount(b,root+"/new"),0);
        }
        Backend restored(db);QTRY_COMPARE_WITH_TIMEOUT(directoryCount(restored,root),5,5000);
    }
    void rotatedCropStaysInside(){
        for(const QSize size:{QSize(320,180),QSize(181,321),QSize(256,256),QSize(900,80),QSize(81,900)}) {
            QImage source(size,QImage::Format_ARGB32);source.fill(Qt::red);
            for(double angle:{-179.9,-135.0,-90.0,-45.0,-13.7,0.0,.1,13.7,45.0,89.9,90.0,135.0,180.0,270.0,359.9}) {
                const CropGeometry g(size,angle);
                QCOMPARE(g.canvasSize(),source.transformed(QTransform().rotate(angle),Qt::SmoothTransformation).size());
                for(double ratio:{0.0,1.0,4.0/3,3.0/4,16.0/9}) {
                    QVariantMap requested{{"x",.05},{"y",.05},{"w",.9},{"h",.9},{"angle",angle},{"ratio",ratio}};
                    auto fitted=g.constrain(requested);
                    const auto output=Media::rotateAndCrop(source,fitted);
                    QVERIFY(!output.isNull());
                    // Check actual rendered pixels, not just the constraint calculation.
                    for(int y=0;y<output.height();++y)for(int x=0;x<output.width();++x)QCOMPARE(qAlpha(output.pixel(x,y)),255);
                    if(ratio>0)QVERIFY(std::abs(fitted["w"].toDouble()*g.canvasSize().width()/(fitted["h"].toDouble()*g.canvasSize().height())-ratio)<1e-7);
                    auto dragged=fitted;dragged["x"]=-1.0;dragged["y"]=-1.0;
                    dragged=g.constrain(dragged,fitted);
                    QVERIFY(std::abs(dragged["w"].toDouble()-fitted["w"].toDouble())<1e-9);
                    QVERIFY(std::abs(dragged["h"].toDouble()-fitted["h"].toDouble())<1e-9);
                    QVERIFY(!Media::rotateAndCrop(source,dragged).isNull());
                }
            }
        }
    }
    void cornerResizeAndInvalidExport(){
        const QSize size(1000,600);const CropGeometry g(size,33.3);
        const auto fitted=g.constrain({{"x",.4},{"y",.4},{"w",.2},{"h",.2},{"angle",33.3},{"ratio",0}});
        for(int corner=0;corner<4;++corner) {
            auto request=fitted;const double x=fitted["x"].toDouble(),y=fitted["y"].toDouble(),w=fitted["w"].toDouble(),h=fitted["h"].toDouble();
            request["x"]=corner%2?x:x-.8;request["y"]=corner>1?y:y-.8;request["w"]=w+.8;request["h"]=h+.8;
            auto out=g.constrain(request,fitted);
            QVERIFY(out["w"].toDouble()>w);QVERIFY(out["h"].toDouble()>h);
            QVERIFY(std::abs((out["x"].toDouble()+(corner%2?0:out["w"].toDouble()))-(x+(corner%2?0:w)))<1e-8);
            QVERIFY(std::abs((out["y"].toDouble()+(corner>1?0:out["h"].toDouble()))-(y+(corner>1?0:h)))<1e-8);
            g.checkedPixelRect(out);
        }
        QImage source(size,QImage::Format_RGB32);source.fill(Qt::red);
        QVERIFY_EXCEPTION_THROWN(Media::rotateAndCrop(source,{{"x",0},{"y",0},{"w",1},{"h",1},{"angle",45}}),std::runtime_error);
        QTemporaryDir t;QDir(t.path()).mkdir("target");QVERIFY(source.save(t.filePath("input.png")));
        Backend b(t.filePath("state/db.sqlite"));b.addSources({t.path()},false);QTRY_VERIFY_WITH_TIMEOUT(!b.busy(),10000);
        auto valid=fitted;valid["target"]=t.filePath("target");valid["id"]="valid";
        auto invalid=valid;invalid["x"]=0;invalid["y"]=0;invalid["w"]=1;invalid["h"]=1;invalid["id"]="invalid";
        b.exportCrops(b.items()[0].toMap()["id"].toString(),{valid,invalid});QTRY_VERIFY_WITH_TIMEOUT(!b.busy(),10000);
        QVERIFY(QDir(t.filePath("target")).entryList(QDir::Files).isEmpty());QVERIFY(QFile::exists(t.filePath("input.png")));QCOMPARE(b.pending(),0);
    }
    void moveCollisionUndo(){
        QTemporaryDir t;QDir(t.path()).mkdir("dst");Store s(t.filePath("db.sqlite"));FileOps f(s);
        write(t.filePath("a.jpg"),"original");write(t.filePath("dst/a.jpg"),"existing");
        const auto dest=f.move(t.filePath("a.jpg"),t.filePath("dst"));
        QVERIFY(dest.endsWith("a (2).jpg"));QVERIFY(!QFile::exists(t.filePath("a.jpg")));QCOMPARE(FileOps::hash(dest),QString::fromLatin1(QCryptographicHash::hash("original",QCryptographicHash::Sha256).toHex()));
        const auto id=s.rows("SELECT id FROM operations WHERE kind='move'")[0].toMap()["id"].toString();
        f.undo(id);QVERIFY(QFile::exists(t.filePath("a.jpg")));QVERIFY(QFile::exists(t.filePath("dst/a.jpg")));
    }
    void interruptedCopyKeepsSource(){
        QTemporaryDir t;QDir(t.path()).mkdir("dst");Store s(t.filePath("db.sqlite"));FileOps f(s);f.forceCopy=true;
        write(t.filePath("a.png"),QByteArray(200000,'X'));
        f.checkpoint=[](const QString &phase){if(phase=="target_ready")throw std::runtime_error("simulated crash");};
        QVERIFY_EXCEPTION_THROWN(f.move(t.filePath("a.png"),t.filePath("dst")),std::runtime_error);
        QVERIFY(QFile::exists(t.filePath("a.png")));QVERIFY(QFile::exists(t.filePath("dst/a.png")));
        FileOps recovery(s);auto pending=recovery.reconcile();QCOMPARE(pending.size(),1);QVERIFY(QFile::exists(t.filePath("a.png")));
        recovery.recover(pending[0].toMap()["id"].toString());QVERIFY(!QFile::exists(t.filePath("a.png")));QVERIFY(recovery.reconcile().isEmpty());
    }
    void renameCrashRecovered(){
        QTemporaryDir t;QDir(t.path()).mkdir("dst");Store s(t.filePath("db.sqlite"));FileOps f(s);
        write(t.filePath("a.jpg"),"data");f.checkpoint=[](const QString &phase){if(phase=="target_ready")throw std::runtime_error("crash");};
        QVERIFY_EXCEPTION_THROWN(f.move(t.filePath("a.jpg"),t.filePath("dst")),std::runtime_error);
        FileOps recovery(s);QVERIFY(recovery.reconcile().isEmpty());QCOMPARE(s.rows("SELECT state FROM operations")[0].toMap()["state"].toString(),QString("committed"));
    }
    void changedFileAndUndoRefused(){
        QTemporaryDir t;QDir(t.path()).mkdir("dst");Store s(t.filePath("db.sqlite"));FileOps f(s);write(t.filePath("a.jpg"),"before");
        QVERIFY_EXCEPTION_THROWN(f.move(t.filePath("a.jpg"),t.filePath("dst"),999,0),std::runtime_error);
        auto target=f.move(t.filePath("a.jpg"),t.filePath("dst"));write(target,"changed");
        const auto id=s.rows("SELECT id FROM operations")[0].toMap()["id"].toString();QVERIFY_EXCEPTION_THROWN(f.undo(id),std::runtime_error);QVERIFY(QFile::exists(target));
    }
    void exportIdempotencyAndCrop(){
        QTemporaryDir t;Store s(t.filePath("db.sqlite"));FileOps f(s);QImage im(200,100,QImage::Format_ARGB32);im.fill(Qt::red);
        auto cropped=Media::crop(im,{{"x",.25},{"y",.2},{"w",.5},{"h",.6}});QCOMPARE(cropped.size(),QSize(100,60));
        auto first=f.writeImage(cropped,t.path(),"crop.png","output1","asset");QCOMPARE(f.writeImage(cropped,t.path(),"crop.png","output1","asset"),first);
        QCOMPARE(QDir(t.path()).entryList({"*.png"},QDir::Files).size(),1);
        QVERIFY_EXCEPTION_THROWN(Media::crop(im,{{"x",.9},{"y",0},{"w",.5},{"h",1}}),std::runtime_error);
    }
    void overlapAndLiveCandidate(){
        QTemporaryDir t;QDir(t.path()).mkdir("sub");QImage im(40,40,QImage::Format_RGB32);im.fill(Qt::green);im.save(t.filePath("sub/IMG_1.jpg"));write(t.filePath("sub/IMG_1.MOV"),"fakevideo");
        Store s(t.filePath("db.sqlite"));auto rows=Media::scan(s,{t.path(),t.filePath("sub")},true,std::make_shared<std::atomic_bool>(false));QCOMPARE(rows.size(),2);
        for(const auto &r:rows)QVERIFY(!r.toMap()["blocked"].toString().isEmpty());
        QVERIFY(!Media::validDirectoryName(".."));QVERIFY(!Media::validDirectoryName("CON"));QVERIFY(!Media::validDirectoryName("a/b"));QVERIFY(Media::validDirectoryName("初二"));
    }
    void backendWorkflow(){
        QTemporaryDir t;QDir(t.path()).mkdir("source");QDir(t.path()).mkdir("target");
        for(int i=0;i<3;++i){QImage im(512,256,QImage::Format_RGB32);im.fill(QColor(30+i*60,80,130));QVERIFY(im.save(t.filePath(QString("source/photo%1.png").arg(i))));}
        QString assetId;
        {
            Backend b(t.filePath("state/db.sqlite"));b.addSources({t.filePath("source")});QTRY_VERIFY_WITH_TIMEOUT(!b.busy(),10000);QVERIFY2(b.items().size()==3,qPrintable(b.status()));
            b.setTargetRoot(t.filePath("target"));QTRY_VERIFY_WITH_TIMEOUT(!b.busy(),5000);b.createDirectory(t.filePath("target"),"初二");QTRY_VERIFY_WITH_TIMEOUT(!b.busy(),5000);
            auto a=b.items()[0].toMap();assetId=a["id"].toString();
            b.moveAssets({assetId},t.filePath("target/初二"));QTRY_VERIFY_WITH_TIMEOUT(!b.busy(),10000);QCOMPARE(b.items().size(),2);QVERIFY(QFile::exists(t.filePath("target/初二/photo0.png")));
            QCOMPARE(directoryCount(b,t.filePath("target")),1);QCOMPARE(directoryCount(b,t.filePath("target/初二")),1);
            b.loadHistory();QString moveId;for(const auto &v:b.history())if(v.toMap()["kind"]=="move")moveId=v.toMap()["id"].toString();
            QVERIFY(!moveId.isEmpty());b.undo(moveId);QTRY_VERIFY_WITH_TIMEOUT(!b.busy(),10000);QVERIFY(QFile::exists(t.filePath("source/photo0.png")));
            QCOMPARE(directoryCount(b,t.filePath("target/初二")),0);QCOMPARE(directoryCount(b,t.filePath("target")),0);
            a=b.items()[0].toMap();const auto id=a["id"].toString();QVariantList drafts;
            for(int i=0;i<3;++i){const auto dir=t.filePath(QString("target/out%1").arg(i));QDir().mkdir(dir);drafts.append(QVariantMap{{"id",QString::number(i)},{"x",.25},{"y",.25},{"w",.5},{"h",.5},{"angle",0},{"target",dir}});}
            b.saveDraft(id,drafts);QCOMPARE(b.loadDraft(id).size(),3);
            b.exportCrops(id,drafts);QTRY_VERIFY_WITH_TIMEOUT(!b.busy(),15000);QVERIFY2(b.items().size()==1,qPrintable(b.status()));
            QVERIFY(QFile::exists(t.filePath("source/已处理/photo1.png")));QVERIFY(!QFile::exists(t.filePath("source/photo1.png")));
            for(int i=0;i<3;++i)QCOMPARE(directoryCount(b,t.filePath(QString("target/out%1").arg(i))),1);
            QCOMPARE(directoryCount(b,t.filePath("target")),3);
            for(int i=0;i<3;++i){auto out=t.filePath(QString("target/out%1/photo1_crop_%2.png").arg(i).arg(i+1,3,10,QChar('0')));QImage image(out);QCOMPARE(image.size(),QSize(256,128));}
        }
        Backend restored(t.filePath("state/db.sqlite"));QCOMPARE(restored.items().size(),1);QCOMPARE(restored.pending(),0);
    }
    void boundaryAndRotation(){
        QTemporaryDir t;QImage im(100,60,QImage::Format_RGB32);im.fill(Qt::red);im.save(t.filePath("a.png"));im.save(t.filePath("b.png"));
        QCOMPARE(Media::boundary(t.filePath("a.png"),t.filePath("b.png")),1);
        auto rotated=Media::read(t.filePath("a.png"),0,90);QCOMPARE(rotated.size(),QSize(60,100));
        QCOMPARE(Media::boundary(t.filePath("a.png"),t.filePath("missing.png")),-1);
    }
    void batchSizePersistenceAndCap(){
        QTemporaryDir t;QDir(t.path()).mkdir("source");QImage im(20,20,QImage::Format_RGB32);im.fill(Qt::red);
        for(int i=0;i<35;++i)QVERIFY(im.save(t.filePath(QString("source/%1.png").arg(i))));
        {
            Backend b(t.filePath("state/db.sqlite"));b.setBatchSize(10);b.addSources({t.filePath("source")});
            QTRY_VERIFY_WITH_TIMEOUT(!b.busy(),10000);QCOMPARE(b.items().size(),20);QCOMPARE(b.remaining(),15);
        }
        Backend restored(t.filePath("state/db.sqlite"));QCOMPARE(restored.batchSize(),10);QCOMPARE(restored.items().size(),20);
        QStringList ids;for(const auto &v:restored.items())ids.append(v.toMap()["id"].toString());
        QDir(t.path()).mkdir("target");restored.moveAssets(ids,t.filePath("target"));QTRY_VERIFY_WITH_TIMEOUT(!restored.busy(),10000);QCOMPARE(restored.items().size(),15);QCOMPARE(restored.remaining(),0);
    }
    void restoreHiddenSourceItems(){
        QTemporaryDir t;QDir(t.path()).mkdir("source");QDir(t.filePath("source")).mkdir("sorted");
        QImage image(32,32,QImage::Format_RGB32);image.fill(Qt::blue);
        for(int i=0;i<4;++i)QVERIFY(image.save(t.filePath(QString("source/%1.png").arg(i))));
        const auto db=t.filePath("state/db.sqlite");QString draftId;
        {
            Store s(db);auto assets=Media::scan(s,{t.filePath("source")},true,std::make_shared<std::atomic_bool>(false));
            QStringList consumed;for(int i=0;i<3;++i)consumed.append(assets[i].toMap()["id"].toString());
            draftId=consumed[0];s.exec("INSERT INTO drafts(asset,stamp,json) VALUES(?,'version','[]')",{draftId});
            FileOps files(s);const auto moved=files.move(t.filePath("source/2.png"),t.filePath("source/sorted"));
            s.exec("UPDATE assets SET path=? WHERE id=?",{moved,consumed[2]});
            s.setValue("sources",QString::fromUtf8(QJsonDocument::fromVariant(QStringList{t.filePath("source")}).toJson()));
            s.setValue("session",QString::fromUtf8(QJsonDocument::fromVariant(QVariantMap{{"items",QVariantList{assets[3]}},{"queue",QVariantList{}},{"batch",1},{"consumed",consumed}}).toJson()));
        }
        const auto originalHash=FileOps::hash(t.filePath("source/0.png"));
        {
            Backend restored(db);QCOMPARE(restored.items().size(),3);QCOMPARE(restored.remaining(),0);
            QCOMPARE(restored.items()[0].toMap()["name"].toString(),QString("0.png"));
            QVERIFY(restored.status().contains("2"));
        }
        Backend reopened(db);QCOMPARE(reopened.items().size(),3);
        QCOMPARE(FileOps::hash(t.filePath("source/0.png")),originalHash);QVERIFY(QFile::exists(t.filePath("source/sorted/2.png")));
        Store s(db);QCOMPARE(s.rows("SELECT * FROM drafts WHERE asset=?",{draftId}).size(),1);
        QVERIFY(!s.value("sessionBeforeHiddenItemsRestore").isEmpty());
    }
};
QTEST_GUILESS_MAIN(CoreTests)
#include "core_tests.moc"
