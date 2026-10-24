#pragma once
#include <QObject>
#include <QVariantMap>
#include <QFutureWatcher>
#include <QTemporaryDir>
#include <atomic>
class Store;

// Single-file JPEG Motion Photos. No filename-based pairing or source rewriting.
namespace LivePhoto {
QVariantMap inspect(const QString &path);
void annotate(QVariantMap &asset);
QVariantList pairAssets(Store &store,QVariantList items,const std::shared_ptr<std::atomic_bool> &cancel);
}

class LivePhotoService : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString assetId READ assetId NOTIFY changed)
    Q_PROPERTY(QString owner READ owner NOTIFY changed)
    Q_PROPERTY(QString source READ source NOTIFY changed)
    Q_PROPERTY(bool loading READ loading NOTIFY changed)
public:
    explicit LivePhotoService(QObject *parent=nullptr);
    ~LivePhotoService() override;
    QString assetId() const { return m_id; }
    QString owner() const { return m_owner; }
    QString source() const { return m_source; }
    bool loading() const { return m_loading; }
    void start(const QVariantMap &asset,const QString &owner);
    Q_INVOKABLE void stop();
signals:
    void changed();
    void failed(const QString &message);
private:
    void launch();
    QString m_id,m_owner,m_source;
    bool m_loading=false;
    bool m_working=false;
    QVariantMap m_pending;
    QTemporaryDir m_cache;
    QFutureWatcher<QVariantMap> m_watcher;
    std::shared_ptr<std::atomic_uint64_t> m_generation;
};
