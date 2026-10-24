#pragma once
#include "Store.h"
#include <QImage>
#include <functional>

struct FileStamp { qint64 size=0, mtime=0; QString identity, sha; };
struct ImageExportResult { QString path, operationId; bool created=false; QString warning; };
class FileOps {
public:
    explicit FileOps(Store &store) : store(store) {}
    // Test-only fault injection. The application never sets this hook.
    std::function<void(const QString &)> checkpoint;
    std::function<bool(const QString &,QString *)> trashFile; // Test-only replacement for the OS recycle call.
    bool forceCopy = false;
    static QString hash(const QString &path);
    static FileStamp stamp(const QString &path, bool withHash = false);
    static QString uniquePath(const QString &directory, const QString &name);
    static QString relocatedPath(const QString &path,const QString &from,const QString &to);
    static QVariant relocatedValue(const QVariant &value,const QString &from,const QString &to);
    QString renameDirectory(const QString &source,const QString &name);
    QString move(const QString &source, const QString &directory, qint64 expectedSize=-1, qint64 expectedMtime=-1, const QString &parent={}, const QString &exactName={}, const QString &expectedSha={});
    QString copy(const QString &source, const QString &directory, qint64 expectedSize=-1, qint64 expectedMtime=-1, const QString &parent={}, const QString &exactName={}, const QString &expectedSha={});
    QString transferLive(const QVariantList &members,const QString &directory,bool copyOnly);
    ImageExportResult writeImage(const QImage &image, const QString &directory, const QString &name, const QString &operationId, const QString &parent);
    ImageExportResult replaceImage(const QImage &image,const QString &path,const FileStamp &expected,const QString &parent);
    QString recycleAfterExport(const QVariantList &members,const QStringList &outputs,const QString &parent);
    QString recycle(const QVariantList &members,const QString &parent);
    QVariantList reconcile();
    QString undo(const QString &id);
    QString recover(const QString &id);
private:
    Store &store;
    QString transfer(const QString &source,const QString &directory,qint64 expectedSize,qint64 expectedMtime,const QString &parent,const QString &exactName,const QString &expectedSha,bool copyOnly);
    void phase(const QString &id, const QString &state);
    QString finishDirectoryRename(const QVariantMap &record);
    QString planLive(const QVariantList &members,const QStringList &targets,bool copyOnly,const QString &parent={});
    QString finishLive(const QString &id);
    QString planRecycle(const QVariantList &members,const QStringList &outputs,const QString &parent,bool afterExport);
    QString finishRecycle(const QString &id,bool recovering=false);
    ImageExportResult finishImageReplacement(const QString &id);
};
