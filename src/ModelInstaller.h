#pragma once
#include <QObject>
#include <QTimer>
#include <QElapsedTimer>

class ModelInstaller : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString state READ state NOTIFY changed)
    Q_PROPERTY(QString detail READ detail NOTIFY changed)
    Q_PROPERTY(bool installing READ installing NOTIFY changed)
    Q_PROPERTY(bool installed READ installed NOTIFY changed)
    Q_PROPERTY(QString logPath READ logPath CONSTANT)
public:
    ModelInstaller(QString projectRoot,QString installRoot,QObject *parent=nullptr);
    QString state() const {return m_state;}
    QString detail() const {return m_detail;}
    bool installing() const {return m_state=="installing";}
    bool installed() const {return m_state=="installed";}
    QString logPath() const {return installRoot+"/install.log";}
    Q_INVOKABLE void install();
    Q_INVOKABLE void refresh();
signals:
    void changed();
private:
    QString projectRoot,installRoot,m_state,m_detail,attempt,localFailure;
    qint64 launchPid=0;
    QTimer poll;
    QElapsedTimer launchTime;
    bool verifiedFilesPresent() const;
    void update(const QString &state,const QString &detail);
};
