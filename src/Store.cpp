#include "Store.h"
#include <QSqlQuery>
#include <QSqlError>
#include <QSqlRecord>
#include <QUuid>
#include <QDir>
#include <QFileInfo>
#include <stdexcept>

static void fail(const QString &s) { throw std::runtime_error(s.toUtf8().constData()); }
Store::Store(const QString &path) {
    QDir().mkpath(QFileInfo(path).absolutePath());
    connection = QUuid::createUuid().toString(QUuid::WithoutBraces);
    db = QSqlDatabase::addDatabase("QSQLITE", connection);
    db.setDatabaseName(path);
    db.setConnectOptions("QSQLITE_BUSY_TIMEOUT=10000");
    if (!db.open()) fail(db.lastError().text());
    exec("PRAGMA journal_mode=WAL");
    exec("PRAGMA synchronous=FULL");
    exec("CREATE TABLE IF NOT EXISTS settings(key TEXT PRIMARY KEY,value TEXT NOT NULL)");
    exec("CREATE TABLE IF NOT EXISTS assets(id TEXT PRIMARY KEY,path TEXT NOT NULL UNIQUE,root TEXT NOT NULL,size INTEGER,mtime INTEGER,type TEXT,blocked TEXT DEFAULT '')");
    exec("CREATE TABLE IF NOT EXISTS operations(id TEXT PRIMARY KEY,kind TEXT NOT NULL,source TEXT,target TEXT,temp TEXT,sha TEXT,size INTEGER,mtime INTEGER,identity TEXT,state TEXT NOT NULL,error TEXT DEFAULT '',parent TEXT DEFAULT '',created TEXT DEFAULT CURRENT_TIMESTAMP)");
    exec("CREATE INDEX IF NOT EXISTS operations_state ON operations(state)");
    exec("CREATE TABLE IF NOT EXISTS cleared_history(operation TEXT PRIMARY KEY)");
    exec("CREATE TABLE IF NOT EXISTS drafts(asset TEXT PRIMARY KEY,stamp TEXT NOT NULL,json TEXT NOT NULL)");
    exec("CREATE TABLE IF NOT EXISTS live_metadata(path TEXT PRIMARY KEY,size INTEGER,mtime INTEGER,identifier TEXT NOT NULL)");
    exec("CREATE TABLE IF NOT EXISTS live_members(group_id TEXT,position INTEGER,source TEXT,target TEXT,sha TEXT,size INTEGER,mtime INTEGER,identity TEXT,PRIMARY KEY(group_id,position))");
    exec("PRAGMA user_version=1");
}
Store::~Store() { db.close(); db = QSqlDatabase(); QSqlDatabase::removeDatabase(connection); }
void Store::exec(const QString &sql, const QVariantList &args) {
    QSqlQuery q(db);
    if (!q.prepare(sql)) fail(q.lastError().text());
    for (const auto &arg : args) q.addBindValue(arg.isNull() || (arg.metaType().id()==QMetaType::QString && arg.toString().isNull()) ? QVariant(QStringLiteral("")) : arg);
    if (!q.exec()) fail(q.lastError().text());
}
QVariantList Store::rows(const QString &sql, const QVariantList &args) {
    QSqlQuery q(db);
    if (!q.prepare(sql)) fail(q.lastError().text());
    for (const auto &arg : args) q.addBindValue(arg);
    if (!q.exec()) fail(q.lastError().text());
    QVariantList out;
    while (q.next()) {
        QVariantMap row;
        for (int i=0; i<q.record().count(); ++i) row[q.record().fieldName(i)] = q.value(i);
        out.append(row);
    }
    return out;
}
QString Store::value(const QString &key, const QString &fallback) {
    const auto r = rows("SELECT value FROM settings WHERE key=?", {key});
    return r.isEmpty() ? fallback : r[0].toMap()["value"].toString();
}
void Store::setValue(const QString &key, const QString &value) {
    exec("INSERT INTO settings(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value", {key,value});
}
