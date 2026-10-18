#pragma once
#include <QObject>
#include <QVariantList>
#include <QFutureWatcher>
#include <QUrl>
#include <functional>
#include <atomic>

class Backend : public QObject {
    Q_OBJECT
    Q_PROPERTY(QVariantList items READ items NOTIFY changed)
    Q_PROPERTY(QVariantList directories READ directories NOTIFY changed)
    Q_PROPERTY(QStringList sources READ sources NOTIFY changed)
    Q_PROPERTY(bool recursive READ recursive NOTIFY changed)
    Q_PROPERTY(QString targetRoot READ targetRoot NOTIFY changed)
    Q_PROPERTY(bool busy READ busy NOTIFY changed)
    Q_PROPERTY(QString status READ status NOTIFY changed)
    Q_PROPERTY(int remaining READ remaining NOTIFY changed)
    Q_PROPERTY(int batchNumber READ batchNumber NOTIFY changed)
    Q_PROPERTY(int batchSize READ batchSize NOTIFY changed)
    Q_PROPERTY(QVariantList history READ history NOTIFY changed)
    Q_PROPERTY(int pending READ pending NOTIFY changed)
public:
    explicit Backend(const QString &database,QObject *parent=nullptr);
    ~Backend();
    QVariantList items() const {return m_items;}
    QVariantList directories() const {return m_directories;}
    QStringList sources() const {return m_sources;}
    bool recursive() const {return m_recursive;}
    QString targetRoot() const {return m_targetRoot;}
    bool busy() const {return m_busy;}
    QString status() const {return m_status;}
    int remaining() const {return m_queue.size();}
    int batchNumber() const {return m_batch;}
    int batchSize() const {return m_batchSize;}
    QVariantList history() const {return m_history;}
    int pending() const {return m_pending;}
    Q_INVOKABLE void addSources(const QVariantList &paths,bool recursive=true);
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
    Q_INVOKABLE void cancel();
    Q_INVOKABLE void loadHistory();
    Q_INVOKABLE void undo(const QString &id);
    Q_INVOKABLE void recover(const QString &id);
    Q_INVOKABLE QString localPath(const QString &path) {return QUrl(path).isLocalFile()?QUrl(path).toLocalFile():path;}
    Q_INVOKABLE QVariantList loadDraft(const QString &id);
    Q_INVOKABLE QVariantMap imageDimensions(const QString &id);
    Q_INVOKABLE QVariantMap constrainCrop(const QVariantMap &dimensions,const QVariantMap &spec,const QVariantMap &previous);
    Q_INVOKABLE void saveDraft(const QString &id,const QVariantList &draft);
    Q_INVOKABLE void exportCrops(const QString &id,const QVariantList &draft);
    Q_INVOKABLE void reveal(const QString &path);
signals:
    void changed();
    void message(const QString &text);
    void directoryRenamed(const QString &from,const QString &to);
    void directoryCreated(const QString &parent,const QString &path);
private:
    QString database,m_targetRoot,m_status="添加来源目录开始整理";
    QStringList m_sources;
    QVariantList m_items,m_queue,m_directories,m_history;
    QSet<QString> consumed;
    int m_batch=0,m_pending=0,m_batchSize=100;
    bool m_busy=false,m_recursive=true;
    std::shared_ptr<std::atomic_bool> stop;
    QFutureWatcher<QVariantMap> watcher;
    void run(const QString &title,std::function<QVariantMap()> job,std::function<void(const QVariantMap &)> done,bool refreshTree=false);
    void scan(bool reset,const QStringList &requestedRoots={},bool requestedRecursive=true);
    void persist();
    void removeItems(const QStringList &ids);
    void applyDirectoryRename(const QString &from,const QString &to);
    QVariantMap asset(const QString &id) const;
};
