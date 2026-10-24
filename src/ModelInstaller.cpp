#include "ModelInstaller.h"
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QVariantMap>
#include <QProcess>
#include <QProcessEnvironment>
#include <QUuid>
#include <windows.h>

namespace {
bool running(qint64 pid,const QString &creation={}) {
    if(pid<=0||pid>MAXDWORD)return false;
    const auto process=OpenProcess(SYNCHRONIZE|PROCESS_QUERY_LIMITED_INFORMATION,FALSE,DWORD(pid));
    if(!process)return false;
    bool alive=WaitForSingleObject(process,0)==WAIT_TIMEOUT;
    if(alive&&!creation.isEmpty()) {
        FILETIME created,exited,kernel,user;
        alive=GetProcessTimes(process,&created,&exited,&kernel,&user)
            &&((quint64(created.dwHighDateTime)<<32)|created.dwLowDateTime)==creation.toULongLong();
    }
    CloseHandle(process);return alive;
}
QVariantMap readState(const QString &path) {
    QFile file(path);if(!file.open(QIODevice::ReadOnly)||file.size()>1024*1024)return {};
    return QJsonDocument::fromJson(file.readAll()).toVariant().toMap();
}
}

ModelInstaller::ModelInstaller(QString project,QString root,QObject *parent)
    :QObject(parent),projectRoot(std::move(project)),installRoot(std::move(root)) {
    refresh();poll.setInterval(1000);connect(&poll,&QTimer::timeout,this,&ModelInstaller::refresh);poll.start();
}
void ModelInstaller::update(const QString &state,const QString &detail) {
    if(state==m_state&&detail==m_detail)return;
    m_state=state;m_detail=detail;emit changed();
}
bool ModelInstaller::verifiedFilesPresent() const {
    if(!QFileInfo::exists(installRoot+"/runtime/Scripts/python.exe"))return false;
    const auto manifest=readState(installRoot+"/models/manifest.json").value("models").toMap();
    for(const auto &name:{QString("person"),QString("pose"),QString("features")}) {
        const auto entry=manifest.value(name).toMap();const QFileInfo file(installRoot+"/models/"+name+".onnx");
        if(!file.isFile()||file.size()<=0||entry.value("bytes").toLongLong()!=file.size()||entry.value("sha256").toString().size()!=64)return false;
    }
    return true;
}
void ModelInstaller::refresh() {
    if(!localFailure.isEmpty()&&verifiedFilesPresent())localFailure.clear();
    if(!localFailure.isEmpty()){update("failed",localFailure);return;}
    const auto state=readState(installRoot+"/install-state.json");
    if(state.value("state")=="installing"&&running(state.value("pid").toLongLong(),state.value("processCreated").toString())) {
        const QMap<QString,QString> stages{{"preparing","正在准备安装"},{"runtime","正在安装本地推理环境"},
            {"person-pose","正在下载并校验人物与关键点模型"},{"features","正在准备画面特征模型"},
            {"verifying","正在校验全部模型"},{"cleanup","正在清理临时安装文件"}};
        attempt.clear();update("installing",stages.value(state.value("stage").toString(),"正在安装模型"));return;
    }
    if(!attempt.isEmpty()&&state.value("attempt").toString()!=attempt) {
        if(launchTime.elapsed()<30000&&running(launchPid)){update("installing","正在启动安装任务");return;}
        attempt.clear();localFailure="安装任务未能启动，请重试或查看安装日志";update("failed",localFailure);return;
    }
    attempt.clear();
    if(state.value("state")=="installing") {update("failed","上次安装意外中断，可以重新安装");return;}
    if(state.value("state")=="failed") {update("failed","安装失败，可重试或查看安装日志。\n"+state.value("detail").toString());return;}
    if(verifiedFilesPresent())update("installed","本地模型已安装，可以开启智能裁剪");
    else update("notInstalled","可选功能，点击安装后才会下载模型；手动裁剪无需安装");
}
void ModelInstaller::install() {
    localFailure.clear();
    refresh();if(installing()||installed())return;
    const auto script=projectRoot+"/Setup-AI.ps1";
    if(!QFileInfo::exists(script)||!QFileInfo::exists(projectRoot+"/.venv/Scripts/python.exe")) {
        localFailure="缺少安装脚本或项目 Python 环境，请先按 README 完成构建环境配置";update("failed",localFailure);return;
    }
    if(!QDir().mkpath(installRoot)){localFailure="无法创建模型目录，请检查项目目录的写入权限";update("failed",localFailure);return;}
    const auto id=QUuid::createUuid().toString(QUuid::WithoutBraces);
    QProcess installer;
    installer.setProgram(qEnvironmentVariable("SystemRoot","C:/Windows")+"/System32/WindowsPowerShell/v1.0/powershell.exe");
    installer.setArguments({"-NoProfile","-NonInteractive","-ExecutionPolicy","Bypass","-File",script,"-Root",installRoot,"-AttemptId",id});
    installer.setWorkingDirectory(projectRoot);
    auto environment=QProcessEnvironment::systemEnvironment();environment.insert("PYTHONUTF8","1");environment.insert("PIP_DISABLE_PIP_VERSION_CHECK","1");
    installer.setProcessEnvironment(environment);
    installer.setCreateProcessArgumentsModifier([](QProcess::CreateProcessArguments *args){
        args->flags|=CREATE_NO_WINDOW;args->startupInfo->dwFlags|=STARTF_USESHOWWINDOW;args->startupInfo->wShowWindow=SW_HIDE;
    });
    if(!installer.startDetached(&launchPid)){localFailure="无法启动模型安装任务："+installer.errorString();update("failed",localFailure);return;}
    attempt=id;launchTime.start();update("installing","正在启动安装任务");
}
