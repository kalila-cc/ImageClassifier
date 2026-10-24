#pragma once

#include <QObject>
#include <QProcessEnvironment>
#include <QStringList>
#include <QTimer>
#include <memory>

// The successor acknowledges startup before the current process exits, then
// waits for that process to release its database and single-instance lock.
class AppRestart : public QObject {
    Q_OBJECT
public:
    struct Context {
        QString executable;
        QStringList arguments; // Does not include argv[0].
        QString workingDirectory;
        QString dataDirectory;
        QProcessEnvironment environment;
    };

    explicit AppRestart(QObject *parent=nullptr);
    ~AppRestart() override;
    static Context currentContext(const QString &dataDirectory);
    static QString executableForRestart(const QString &currentExecutable);
    static QStringList argumentsForRestart(const QStringList &arguments,qint64 parentPid,const QString &token);
    // Call before acquiring app.lock or opening the library. Ordinary launches
    // return immediately. A restart launch waits without creating a window.
    static bool waitForParent(const QStringList &arguments,QString *error=nullptr,int timeoutMs=120000);
    bool start(const Context &context,QString *error=nullptr);
signals:
    void ready();
    void failed(const QString &error);
private:
    struct State;
    std::unique_ptr<State> m_state;
    QTimer m_poll;
    void poll();
    void fail(const QString &error);
};
