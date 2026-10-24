#pragma once

#include <QObject>
#include <QString>
#include <QVariantList>
#include <QVariantMap>
#include <QtQml/qqmlregistration.h>

class QSqlDatabase;
class QNetworkAccessManager;

class AppStore : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(QVariantList forms READ forms NOTIFY dataChanged)
    Q_PROPERTY(QVariantList observations READ observations NOTIFY dataChanged)
    Q_PROPERTY(QVariantList locations READ locations NOTIFY dataChanged)
    Q_PROPERTY(QVariantList ports READ ports CONSTANT)
    Q_PROPERTY(QVariantList gears READ gears CONSTANT)
    Q_PROPERTY(QVariantList species READ species CONSTANT)
    Q_PROPERTY(QVariantList states READ states CONSTANT)
    Q_PROPERTY(QVariantList presentations READ presentations CONSTANT)
    Q_PROPERTY(QString status READ status NOTIFY statusChanged)
    Q_PROPERTY(bool uploading READ uploading NOTIFY uploadingChanged)
    Q_PROPERTY(bool consented READ consented NOTIFY dataChanged)

public:
    explicit AppStore(QObject *parent = nullptr);
    ~AppStore() override;

    QVariantList forms() const;
    QVariantList observations() const;
    QVariantList locations() const;
    QVariantList ports() const;
    QVariantList gears() const;
    QVariantList species() const;
    QVariantList states() const;
    QVariantList presentations() const;
    QString status() const;
    bool uploading() const;
    bool consented() const;

    Q_INVOKABLE QVariantList rowsForForm(int formId) const;
    Q_INVOKABLE QVariantMap settings() const;
    Q_INVOKABLE bool saveSettings(const QVariantMap &values);
    Q_INVOKABLE int saveForm(const QVariantMap &form);
    Q_INVOKABLE bool deleteForm(int formId);
    Q_INVOKABLE int saveFormRow(const QVariantMap &row);
    Q_INVOKABLE bool deleteFormRow(int rowId);
    Q_INVOKABLE int saveObservation(const QVariantMap &observation);
    Q_INVOKABLE bool deleteObservation(int observationId);
    Q_INVOKABLE void recordLocation(double latitude, double longitude,
                                    double accuracy, qint64 timestamp, bool fishing);
    Q_INVOKABLE QString exportFormCsv(int formId);
    Q_INVOKABLE void uploadPending(const QString &vesselPln);
    Q_INVOKABLE void uploadFormCsv(int formId, const QString &vesselPln);
    Q_INVOKABLE bool importAndroidDatabase(const QString &filePath);

signals:
    void dataChanged();
    void statusChanged();
    void uploadingChanged();

private:
    bool initialize();
    bool execute(const QString &sql) const;
    void finishUploads();
    void setStatus(const QString &status);
    QVariantList queryRows(const QString &sql) const;
    QVariantList lookupValues(const QString &table, const QString &nameColumn) const;

    QSqlDatabase *m_database = nullptr;
    QNetworkAccessManager *m_network = nullptr;
    QString m_status;
    bool m_uploading = false;
    int m_pendingUploads = 0;
};
