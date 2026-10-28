#pragma once

#include <QObject>
#include <QString>
#include <QList>
#include <QTimer>
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
    Q_PROPERTY(bool hasDirection READ hasDirection NOTIFY positionChanged)
    Q_PROPERTY(double direction READ direction NOTIFY positionChanged)
    Q_PROPERTY(QString status READ status NOTIFY statusChanged)
    Q_PROPERTY(bool hasMotion READ hasMotion NOTIFY positionChanged)
    Q_PROPERTY(double speedKnots READ speedKnots NOTIFY positionChanged)
    Q_PROPERTY(bool hasCourse READ hasCourse NOTIFY positionChanged)
    Q_PROPERTY(double courseDegrees READ courseDegrees NOTIFY positionChanged)
    Q_PROPERTY(bool simulatorAvailable READ simulatorAvailable CONSTANT)
    Q_PROPERTY(bool simulating READ simulating NOTIFY simulationChanged)
    Q_PROPERTY(double simHeading READ simHeading NOTIFY simulationChanged)
    Q_PROPERTY(double simSpeed READ simSpeed NOTIFY simulationChanged)

public:
    explicit LocationTracker(QObject *parent = nullptr);
    ~LocationTracker() override;

    bool tracking() const;
    void setTracking(bool tracking);

    bool hasPosition() const;
    double latitude() const;
    double longitude() const;
    double accuracy() const;
    bool hasDirection() const;
    double direction() const;
    QString status() const;

    bool hasMotion() const;
    double speedKnots() const;
    bool hasCourse() const;
    double courseDegrees() const;

    bool simulatorAvailable() const;
    bool simulating() const;
    double simHeading() const;
    double simSpeed() const;
    Q_INVOKABLE void startSimulation(double latitude, double longitude);
    Q_INVOKABLE void setSimulation(double headingDegrees, double speedKnots);
    Q_INVOKABLE void stopSimulation();

signals:
    void simulationChanged();
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
    bool m_hasDirection = false;
    double m_direction = 0.0;
    QString m_status;

    void advanceSimulation();
    void recordSample(double latitude, double longitude, qint64 timestamp);
    void resetMotion();

    struct Sample {
        qint64 timestamp;
        double latitude;
        double longitude;
    };
    QList<Sample> m_samples;
    bool m_hasMotion = false;
    double m_speedKnots = 0.0;
    bool m_hasCourse = false;
    double m_courseDegrees = 0.0;

    QTimer m_simTimer;
    bool m_simulating = false;
    double m_simHeading = 0.0;
    double m_simSpeed = 0.0;
    int m_simTicks = 0;
};
