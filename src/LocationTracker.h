#pragma once

#include <QObject>
#include <QString>
#include <QtQml/qqmlregistration.h>

class QGeoPositionInfo;
class QGeoPositionInfoSource;

class LocationTracker : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(bool tracking READ tracking WRITE setTracking NOTIFY trackingChanged)
    Q_PROPERTY(bool hasPosition READ hasPosition NOTIFY positionChanged)
    Q_PROPERTY(double latitude READ latitude NOTIFY positionChanged)
    Q_PROPERTY(double longitude READ longitude NOTIFY positionChanged)
    Q_PROPERTY(double accuracy READ accuracy NOTIFY positionChanged)
    Q_PROPERTY(QString status READ status NOTIFY statusChanged)

public:
    explicit LocationTracker(QObject *parent = nullptr);
    ~LocationTracker() override;

    bool tracking() const;
    void setTracking(bool tracking);

    bool hasPosition() const;
    double latitude() const;
    double longitude() const;
    double accuracy() const;
    QString status() const;

signals:
    void trackingChanged();
    void positionChanged();
    void statusChanged();
    void locationReceived(double latitude, double longitude, double accuracy,
                          qint64 timestamp);

private:
    void setStatus(const QString &status);
    void handlePositionUpdate(const QGeoPositionInfo &info);

    QGeoPositionInfoSource *m_source = nullptr;
    bool m_tracking = false;
    bool m_hasPosition = false;
    double m_latitude = 0.0;
    double m_longitude = 0.0;
    double m_accuracy = 0.0;
    QString m_status;
};
