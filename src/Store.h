#pragma once
#include <QSqlDatabase>
#include <QVariant>
#include <QString>

class Store {
public:
    explicit Store(const QString &path);
    ~Store();
    Store(const Store &) = delete;
    Store &operator=(const Store &) = delete;
    void exec(const QString &sql, const QVariantList &args = {});
    QVariantList rows(const QString &sql, const QVariantList &args = {});
    QString value(const QString &key, const QString &fallback = {});
    void setValue(const QString &key, const QString &value);
private:
    QSqlDatabase db;
    QString connection;
};
