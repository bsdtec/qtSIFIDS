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
    Q_PROPERTY(QVariantList mapPins READ mapPins NOTIFY dataChanged)
    Q_PROPERTY(QVariantList places READ places NOTIFY placesChanged)
    Q_PROPERTY(QVariantList ports READ ports CONSTANT)
    Q_PROPERTY(QVariantList gears READ gears CONSTANT)
    Q_PROPERTY(QVariantList species READ species CONSTANT)
    Q_PROPERTY(QVariantList states READ states CONSTANT)
    Q_PROPERTY(QVariantList presentations READ presentations CONSTANT)
    Q_PROPERTY(QString status READ status NOTIFY statusChanged)
    Q_PROPERTY(bool statusNeedsAttention READ statusNeedsAttention NOTIFY statusChanged)
    Q_PROPERTY(bool uploading READ uploading NOTIFY uploadingChanged)
    Q_PROPERTY(bool consented READ consented NOTIFY dataChanged)
    Q_PROPERTY(bool uploadEnabled READ uploadEnabled NOTIFY dataChanged)
    Q_PROPERTY(QString uploadUrl READ uploadUrl NOTIFY dataChanged)

public:
    explicit AppStore(QObject *parent = nullptr);
    ~AppStore() override;

    QVariantList forms() const;
    QVariantList observations() const;
    QVariantList locations() const;
    QVariantList mapPins() const;
    QVariantList places() const;
    QVariantList ports() const;
    QVariantList gears() const;
    QVariantList species() const;
    QVariantList states() const;
    QVariantList presentations() const;
    QString status() const;
    bool statusNeedsAttention() const;
    bool uploading() const;
    bool consented() const;
    bool uploadEnabled() const;
    QString uploadUrl() const;
    static QString defaultUploadUrl();

    Q_INVOKABLE QVariantList rowsForForm(int formId) const;
    Q_INVOKABLE QVariantMap settings() const;
    Q_INVOKABLE QVariantMap pinRecord(const QString &kind, int id) const;
    Q_INVOKABLE int dropPot(double latitude, double longitude, qint64 timestamp = 0);
    Q_INVOKABLE bool deletePot(int potId);
    Q_INVOKABLE int savePlace(const QString &name, double latitude, double longitude);
    Q_INVOKABLE bool deletePlace(int placeId);
    Q_INVOKABLE bool saveSettings(const QVariantMap &values);
    Q_INVOKABLE int saveForm(const QVariantMap &form);
    Q_INVOKABLE bool deleteForm(int formId);
    Q_INVOKABLE int saveFormRow(const QVariantMap &row);
    Q_INVOKABLE bool deleteFormRow(int rowId);
    Q_INVOKABLE int saveObservation(const QVariantMap &observation);
    Q_INVOKABLE bool deleteObservation(int observationId);
    Q_INVOKABLE void recordLocation(double latitude, double longitude,
                                    double accuracy, qint64 timestamp, bool fishing);
    Q_INVOKABLE QString exportFormCsv(int formId, const QString &destination = QString());
    Q_INVOKABLE QString exportTrackCsv(bool lastDayOnly, const QString &destination = QString());
    Q_INVOKABLE void uploadPending(const QString &vesselPln);
    Q_INVOKABLE void uploadFormCsv(int formId, const QString &vesselPln);
    Q_INVOKABLE bool importAndroidDatabase(const QString &filePath);
    Q_INVOKABLE QString exportDatabase(const QString &destination);
    Q_INVOKABLE bool importDatabase(const QString &source);

signals:
    void dataChanged();
    void placesChanged();
    void statusChanged();
    void uploadingChanged();

private:
    bool initialize();
    bool execute(const QString &sql) const;
    void finishUploads();
    bool uploadAllowed();
    void setStatus(const QString &status, bool needsAttention = true);
    QString writeExportFile(const QString &destination, const QString &defaultName,
                            const QString &contents);
    QVariantList queryRows(const QString &sql) const;
    QVariantList lookupValues(const QString &table, const QString &nameColumn) const;

    QSqlDatabase *m_database = nullptr;
    QNetworkAccessManager *m_network = nullptr;
    QString m_databasePath;
    QString m_status;
    bool m_statusNeedsAttention = false;
    bool m_uploading = false;
    int m_pendingUploads = 0;
};
