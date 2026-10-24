#pragma once
#include <QObject>
#include <QVariantList>
#include <QFutureWatcher>
#include <QUrl>
#include <functional>
#include <atomic>
class SmartCrop;
class LivePhotoService;

class Backend : public QObject {
    Q_OBJECT
    Q_PROPERTY(QVariantList items READ items NOTIFY changed)
    Q_PROPERTY(QVariantList directories READ directories NOTIFY changed)
    Q_PROPERTY(QStringList sources READ sources NOTIFY changed)
    Q_PROPERTY(bool recursive READ recursive NOTIFY changed)
    Q_PROPERTY(QString targetRoot READ targetRoot NOTIFY changed)
    Q_PROPERTY(bool busy READ busy NOTIFY changed)
    Q_PROPERTY(bool restarting READ restarting NOTIFY restartStateChanged)
    Q_PROPERTY(QString cancelAction READ cancelAction NOTIFY changed)
    Q_PROPERTY(bool cancelRequested READ cancelRequested NOTIFY changed)
    Q_PROPERTY(QString status READ status NOTIFY changed)
    Q_PROPERTY(int remaining READ remaining NOTIFY changed)
    Q_PROPERTY(int batchNumber READ batchNumber NOTIFY changed)
    Q_PROPERTY(int batchSize READ batchSize NOTIFY changed)
    Q_PROPERTY(QVariantList history READ history NOTIFY changed)
    Q_PROPERTY(bool canClearHistory READ canClearHistory NOTIFY changed)
    Q_PROPERTY(int pending READ pending NOTIFY changed)
    Q_PROPERTY(bool largeMode READ largeMode WRITE setLargeMode NOTIFY largeModeChanged)
    Q_PROPERTY(bool cropMode READ cropMode WRITE setCropMode NOTIFY preferencesChanged)
    Q_PROPERTY(int thumbnailSize READ thumbnailSize WRITE setThumbnailSize NOTIFY preferencesChanged)
    Q_PROPERTY(bool showFilmstrip READ showFilmstrip WRITE setShowFilmstrip NOTIFY preferencesChanged)
    Q_PROPERTY(bool defaultRecursive READ defaultRecursive WRITE setDefaultRecursive NOTIFY preferencesChanged)
    Q_PROPERTY(QString dataDirectory READ dataDirectory CONSTANT)
    Q_PROPERTY(QObject* smartCrop READ smartCrop CONSTANT)
    Q_PROPERTY(QObject* livePhoto READ livePhoto CONSTANT)
public:
    QObject *livePhoto() const;
    Q_INVOKABLE void playLive(const QString &id,const QString &owner);
    explicit Backend(const QString &database,QObject *parent=nullptr);
    ~Backend();
    QVariantList items() const {return m_sourceRequest.active?m_sourceRequest.items:m_items;}
    QVariantList directories() const {return m_directories;}
    QStringList sources() const {return m_sourceRequest.active?m_sourceRequest.sources:m_sources;}
    bool recursive() const {return m_sourceRequest.active?m_sourceRequest.recursive:m_recursive;}
    QString targetRoot() const {return m_targetRoot;}
    bool busy() const {return m_busy;}
    bool restarting() const {return m_restarting;}
    Q_INVOKABLE bool restartApplication();
    void restartFailed(const QString &error);
    QString cancelAction() const {return m_cancelAction;}
    bool cancelRequested() const {return m_cancelRequested;}
    QString status() const {return m_status;}
    int remaining() const {return m_sourceRequest.active?m_sourceRequest.queue.size():m_queue.size();}
    int batchNumber() const {return m_sourceRequest.active?m_sourceRequest.batch:m_batch;}
    int batchSize() const {return m_batchSize;}
    QVariantList history() const {return m_history;}
    bool canClearHistory() const {return m_canClearHistory;}
    int pending() const {return m_pending;}
    bool largeMode() const {return m_largeMode;}
    void setLargeMode(bool enabled);
    bool cropMode() const {return m_cropMode;}
    void setCropMode(bool enabled);
    int thumbnailSize() const {return m_thumbnailSize;}
    bool showFilmstrip() const {return m_showFilmstrip;}
    bool defaultRecursive() const {return m_defaultRecursive;}
    QString dataDirectory() const;
    void setThumbnailSize(int size);
    void setShowFilmstrip(bool enabled);
    void setDefaultRecursive(bool enabled);
    QObject *smartCrop() const;
    Q_INVOKABLE void suggestCrop(const QString &id,const QVariantMap &dimensions,const QVariantMap &spec,const QString &token);
    Q_INVOKABLE void addSources(const QVariantList &paths,bool recursive=true);
    Q_INVOKABLE QVariantMap validateSources(const QVariantList &paths) const;
    Q_INVOKABLE void applySources(const QVariantList &paths,bool recursive);
    Q_INVOKABLE void openSource(const QString &path,bool recursive=false);
    Q_INVOKABLE void refresh();
    Q_INVOKABLE void setTargetRoot(const QString &path);
    Q_INVOKABLE void refreshDirectories();
    Q_INVOKABLE void createDirectory(const QString &parent,const QString &name);
    Q_INVOKABLE void renameDirectory(const QString &path,const QString &name);
    Q_INVOKABLE QString relocatedPath(const QString &path,const QString &from,const QString &to);
    Q_INVOKABLE void nextBatch(int count=0);
    Q_INVOKABLE void setBatchSize(int count);
    Q_INVOKABLE void extendBatch(int count=10);
    Q_INVOKABLE void moveAssets(const QStringList &ids,const QString &target);
    Q_INVOKABLE void copyAssets(const QStringList &ids,const QString &target);
    Q_INVOKABLE void cancel();
    Q_INVOKABLE void loadHistory();
    Q_INVOKABLE void clearHistory();
    Q_INVOKABLE void undo(const QString &id);
    Q_INVOKABLE void recover(const QString &id);
    Q_INVOKABLE QString localPath(const QString &path) {return QUrl(path).isLocalFile()?QUrl(path).toLocalFile():path;}
    Q_INVOKABLE QVariantList loadDraft(const QString &id);
    Q_INVOKABLE QVariantMap imageDimensions(const QString &id);
    Q_INVOKABLE QVariantMap constrainCrop(const QVariantMap &dimensions,const QVariantMap &spec,const QVariantMap &previous);
    Q_INVOKABLE bool saveDraft(const QString &id,const QVariantList &draft);
    Q_INVOKABLE void exportCrops(const QString &id,const QVariantList &draft,bool onlyCrop=false);
    Q_INVOKABLE void reveal(const QString &path);
signals:
    void restartRequested();
    void restartStateChanged();
    void largeModeChanged();
    void preferencesChanged();
    void changed();
    void message(const QString &text);
    void directoryRenamed(const QString &from,const QString &to);
    void directoryCreated(const QString &parent,const QString &path);
    void sourcesApplied(bool success,const QString &error);
private:
    QString database,m_targetRoot,m_status="添加来源目录开始整理";
    QStringList m_sources;
    QVariantList m_items,m_queue,m_directories,m_history;
    QSet<QString> consumed;
    int m_batch=0,m_pending=0,m_batchSize=100;
    bool m_busy=false,m_recursive=true,m_largeMode=false;
    bool m_restarting=false;
    bool m_canClearHistory=false;
    QString m_cancelAction;
    bool m_cancelRequested=false;
    int m_thumbnailSize=240;
    bool m_showFilmstrip=true,m_defaultRecursive=true,m_cropMode=true;
    bool savePreference(const QString &key,const QString &value);
    std::shared_ptr<std::atomic_bool> stop;
    QFutureWatcher<QVariantMap> watcher;
    SmartCrop *m_smartCrop=nullptr;
    LivePhotoService *m_livePhoto=nullptr;
    struct SourceRequest {
        bool active=false,recursive=true;
        QStringList sources;
        QVariantList items,queue;
        QSet<QString> consumed;
        int batch=0;
        QString error;
    } m_sourceRequest;
    void finishSourceRequest(const QString &error={});
    void run(const QString &title,std::function<QVariantMap()> job,std::function<void(const QVariantMap &)> done,bool refreshTree=false,const QString &cancellationLabel={});
    void scan(bool reset,const QStringList &requestedRoots={},bool requestedRecursive=true);
    bool persist(bool commitSourceRequest=false);
    void removeItems(const QStringList &ids);
    void transferAssets(const QStringList &ids,const QString &target,bool copyOnly);
    void applyDirectoryRename(const QString &from,const QString &to);
    QVariantMap asset(const QString &id) const;
};
