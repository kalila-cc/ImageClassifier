#include "AppRestart.h"
#include <QCoreApplication>
#include <QDir>
#include <QElapsedTimer>
#include <QFileInfo>
#include <QProcess>
#include <QUuid>
#include <windows.h>
#include <algorithm>
#include <limits>

namespace {
QString eventName(const QString &token,const QString &kind) {
    return QStringLiteral("Local\\ImageClassifier.Restart.%1.%2").arg(token,kind);
}

struct Handle {
    HANDLE value=nullptr;
    explicit Handle(HANDLE handle=nullptr):value(handle) {}
    ~Handle(){if(value)CloseHandle(value);}
    Handle(const Handle &)=delete;
    Handle &operator=(const Handle &)=delete;
};

struct LaunchErrorMode {
    DWORD previous=0;
    bool applied=false;
    LaunchErrorMode() {
        // A damaged executable must be reported in the current window instead
        // of opening a blocking Windows loader/error dialog on the user's desktop.
        const DWORD mode=GetThreadErrorMode()|SEM_FAILCRITICALERRORS|SEM_NOOPENFILEERRORBOX;
        applied=SetThreadErrorMode(mode,&previous);
    }
    ~LaunchErrorMode(){if(applied)SetThreadErrorMode(previous,nullptr);}
    LaunchErrorMode(const LaunchErrorMode &)=delete;
    LaunchErrorMode &operator=(const LaunchErrorMode &)=delete;
};

HANDLE createEvent(const QString &name) {
    return CreateEventW(nullptr,TRUE,FALSE,reinterpret_cast<LPCWSTR>(name.utf16()));
}

HANDLE openEvent(const QString &name,DWORD access) {
    return OpenEventW(access,FALSE,reinterpret_cast<LPCWSTR>(name.utf16()));
}

bool readOption(const QStringList &arguments,const QString &option,QString *value,QString *error) {
    bool found=false;
    for(int i=0;i<arguments.size();++i){
        const auto &arg=arguments[i];
        if(arg!=option&&!arg.startsWith(option+"="))continue;
        if(found){if(error)*error=QStringLiteral("重启参数重复。");return false;}
        found=true;
        if(arg==option){
            if(i+1>=arguments.size()||arguments[i+1].startsWith("--")){
                if(error)*error=QStringLiteral("重启参数不完整。");return false;
            }
            *value=arguments[++i];
        }else *value=arg.mid(option.size()+1);
    }
    return true;
}
}

struct AppRestart::State {
    Handle readyEvent;
    Handle cancelEvent;
    Handle childProcess;
    QElapsedTimer elapsed;
    bool handedOff=false;
    ~State(){if(!handedOff&&cancelEvent.value)SetEvent(cancelEvent.value);}
};

AppRestart::AppRestart(QObject *parent):QObject(parent) {
    m_poll.setInterval(40);
    connect(&m_poll,&QTimer::timeout,this,&AppRestart::poll);
}

AppRestart::~AppRestart()=default;

QString AppRestart::executableForRestart(const QString &currentExecutable) {
    const QFileInfo current(currentExecutable);
    const QString standard=current.dir().absoluteFilePath(QStringLiteral("ImageClassifier.exe"));
    // A running development executable may have been renamed for a new build.
    if(QFileInfo(standard).isFile())return standard;
    return current.absoluteFilePath();
}

AppRestart::Context AppRestart::currentContext(const QString &dataDirectory) {
    return {executableForRestart(QCoreApplication::applicationFilePath()),
            QCoreApplication::arguments().mid(1),QDir::currentPath(),
            QFileInfo(dataDirectory).absoluteFilePath(),QProcessEnvironment::systemEnvironment()};
}

QStringList AppRestart::argumentsForRestart(const QStringList &arguments,qint64 parentPid,const QString &token) {
    QStringList result;
    for(int i=0;i<arguments.size();++i){
        const auto &arg=arguments[i];
        if(arg=="--smoke"||arg.startsWith("--smoke="))continue;
        if(arg=="--restart-parent"||arg=="--restart-token"){
            if(i+1<arguments.size()&&!arguments[i+1].startsWith("--"))++i;
            continue;
        }
        if(arg.startsWith("--restart-parent=")||arg.startsWith("--restart-token="))continue;
        result.append(arg);
    }
    result<<QStringLiteral("--restart-parent")<<QString::number(parentPid)
          <<QStringLiteral("--restart-token")<<token;
    return result;
}

bool AppRestart::waitForParent(const QStringList &arguments,QString *error,int timeoutMs) {
    if(error)error->clear();
    QString pidText,token;
    if(!readOption(arguments,QStringLiteral("--restart-parent"),&pidText,error)
       ||!readOption(arguments,QStringLiteral("--restart-token"),&token,error))return false;
    const bool requested=arguments.contains("--restart-parent")||arguments.contains("--restart-token")
        ||std::any_of(arguments.cbegin(),arguments.cend(),[](const QString &arg){
            return arg.startsWith("--restart-parent=")||arg.startsWith("--restart-token=");
        });
    if(!requested)return true;
    bool validPid=false;
    const quint64 pid=pidText.toULongLong(&validPid);
    if(!validPid||!pid||pid>std::numeric_limits<DWORD>::max()
       ||pid==GetCurrentProcessId()||QUuid(token).isNull()){
        if(error)*error=QStringLiteral("重启参数无效。");return false;
    }
    Handle readyEvent(openEvent(eventName(token,"Ready"),EVENT_MODIFY_STATE));
    Handle cancelEvent(openEvent(eventName(token,"Cancel"),SYNCHRONIZE));
    Handle parent(OpenProcess(SYNCHRONIZE,FALSE,static_cast<DWORD>(pid)));
    if(!readyEvent.value||!cancelEvent.value||!parent.value){
        if(error)*error=QStringLiteral("无法与原应用完成重启交接。");return false;
    }
    if(WaitForSingleObject(cancelEvent.value,0)==WAIT_OBJECT_0){
        if(error)*error=QStringLiteral("本次重启已取消。");return false;
    }
    if(!SetEvent(readyEvent.value)){
        if(error)*error=QStringLiteral("无法通知原应用准备就绪。");return false;
    }
    const HANDLE waits[]={cancelEvent.value,parent.value};
    const DWORD result=WaitForMultipleObjects(2,waits,FALSE,static_cast<DWORD>(qMax(0,timeoutMs)));
    if(result==WAIT_OBJECT_0+1)return true;
    if(error)*error=result==WAIT_TIMEOUT?QStringLiteral("等待原应用退出超时，已取消本次重启。")
                                     :QStringLiteral("本次重启已取消。");
    return false;
}

bool AppRestart::start(const Context &context,QString *error) {
    if(error)error->clear();
    const auto reject=[error](const QString &message){if(error)*error=message;return false;};
    if(m_state)return reject(QStringLiteral("应用正在重启，请稍候。"));
    if(!QFileInfo(context.executable).isFile())
        return reject(QStringLiteral("找不到应用程序，未能重启。请检查安装位置。"));
    const QString token=QUuid::createUuid().toString(QUuid::WithoutBraces);
    auto state=std::make_unique<State>();
    state->readyEvent.value=createEvent(eventName(token,"Ready"));
    state->cancelEvent.value=createEvent(eventName(token,"Cancel"));
    if(!state->readyEvent.value||!state->cancelEvent.value)
        return reject(QStringLiteral("无法创建重启交接通道，请稍后重试。"));
    QProcess process;
    process.setCreateProcessArgumentsModifier([](QProcess::CreateProcessArguments *args){
        args->flags&=~(CREATE_NEW_CONSOLE|DETACHED_PROCESS);
        args->flags|=CREATE_NO_WINDOW;
    });
    process.setProgram(context.executable);
    process.setArguments(argumentsForRestart(context.arguments,QCoreApplication::applicationPid(),token));
    process.setWorkingDirectory(context.workingDirectory);
    auto environment=context.environment;
    environment.insert(QStringLiteral("IMAGECLASSIFIER_DATA_DIR"),QFileInfo(context.dataDirectory).absoluteFilePath());
    process.setProcessEnvironment(environment);
    qint64 childPid=0;
    bool started=false;
    {
        LaunchErrorMode launchErrorMode;
        if(!launchErrorMode.applied)
            return reject(QStringLiteral("无法配置应用启动检查，未能重启。当前窗口已保留。"));
        started=process.startDetached(&childPid);
    }
    if(!started)
        return reject(QStringLiteral("无法启动应用：%1。当前窗口已保留。").arg(process.errorString()));
    state->childProcess.value=OpenProcess(SYNCHRONIZE,FALSE,static_cast<DWORD>(childPid));
    state->elapsed.start();
    m_state=std::move(state);
    m_poll.start();
    return true;
}

void AppRestart::poll() {
    if(!m_state)return;
    if(m_state->childProcess.value&&WaitForSingleObject(m_state->childProcess.value,0)==WAIT_OBJECT_0){
        fail(QStringLiteral("新应用未能启动，当前窗口已保留。请稍后重试。"));return;
    }
    if(WaitForSingleObject(m_state->readyEvent.value,0)==WAIT_OBJECT_0){
        m_poll.stop();
        m_state->handedOff=true;
        emit ready();
        return;
    }
    if(m_state->elapsed.elapsed()>=15000)
        fail(QStringLiteral("新应用启动超时，当前窗口已保留。请稍后重试。"));
}

void AppRestart::fail(const QString &error) {
    m_poll.stop();
    m_state.reset();
    emit failed(error);
}
