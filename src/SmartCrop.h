#pragma once
#include <QObject>
#include <QProcess>
#include <QFutureWatcher>
#include <QTimer>
#include <QImage>
#include <QVariantMap>
#include "ModelInstaller.h"

namespace SmartCropRecords {
QString rootFor(const QString &database);
QVariantMap frame(QSize source,double angle);
int count(const QString &root);
// Called only after every output has been committed and verified; originals remain intact.
void save(const QString &root,const QImage &oriented,const QString &sourceHash,const QVariantList &crops,const QString &operationId={});
}

class SmartCrop : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool enabled READ enabled WRITE setEnabled NOTIFY changed)
    Q_PROPERTY(bool busy READ busy NOTIFY changed)
    Q_PROPERTY(bool available READ available NOTIFY changed)
    Q_PROPERTY(QString status READ status NOTIFY changed)
    Q_PROPERTY(int recordCount READ recordCount NOTIFY changed)
    Q_PROPERTY(QString recordsPath READ recordsPath CONSTANT)
    Q_PROPERTY(QObject* installer READ installer CONSTANT)
public:
    explicit SmartCrop(const QString &database,QObject *parent=nullptr);
    ~SmartCrop();
    bool enabled() const {return m_enabled&&available();}
    QObject *installer() const {return m_installer;}
    bool busy() const {return !active.isEmpty();}
    bool available() const;
    QString status() const {return m_status;}
    int recordCount() const {return m_count;}
    QString recordsPath() const {return root+"/recent";}
    void setEnabled(bool value);
    void request(const QVariantMap &asset,const QVariantMap &dimensions,const QVariantMap &spec,const QString &token);
    Q_INVOKABLE void train();
    Q_INVOKABLE void refreshAvailability();
    void recordsChanged();
signals:
    void changed();
    void suggested(const QString &token,const QVariantMap &crop,const QString &explanation);
    void suggestionFailed(const QString &token,const QString &reason);
private:
    QString database,root,python,worker,models,m_status,latestToken;
    bool m_enabled=false,trainPending=false,closing=false;
    int m_count=0;
    QProcess process;
    ModelInstaller *m_installer=nullptr;
    QFutureWatcher<QVariantMap> preparation;
    QTimer deadline;
    QByteArray stdoutBuffer,stderrBuffer;
    QVariantMap active,pendingPrediction;
    void dispatch();
    void sendActive();
    void finish(const QVariantMap &response);
    void processError(const QString &error);
};
