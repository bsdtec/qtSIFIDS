#include "LocationTracker.h"

#include <QGeoPositionInfo>
#include <QCoreApplication>
#include <QGeoPositionInfoSource>
#include <QLocationPermission>
#include <QVariant>
#include <QDateTime>
#include <QtMath>
#include <algorithm>
#include <cmath>

LocationTracker::LocationTracker(QObject *parent)
    : QObject(parent),
      m_source(QGeoPositionInfoSource::createDefaultSource(this))
{
    m_simTimer.setInterval(1000);
    connect(&m_simTimer, &QTimer::timeout, this, &LocationTracker::advanceSimulation);
    if (!m_source) {
        setStatus(tr("No location provider is available on this device."));
        return;
    }

    m_source->setUpdateInterval(30000);
    connect(m_source, &QGeoPositionInfoSource::positionUpdated,
            this, &LocationTracker::handlePositionUpdate);
    connect(m_source, &QGeoPositionInfoSource::errorOccurred, this, [this] {
        setStatus(tr("The location provider reported an error."));
    });
    setStatus(tr("Location is off."));
}

LocationTracker::~LocationTracker()
{
    if (m_source)
        m_source->stopUpdates();
}

bool LocationTracker::tracking() const
{
    return m_tracking;
}

void LocationTracker::setTracking(bool tracking)
{
    if (m_simulating && !tracking)
        stopSimulation();
    if (m_tracking == tracking)
        return;

    if (!m_source && tracking) {
        setStatus(tr("No location provider is available on this device."));
        return;
    }

    if (tracking) {
        QLocationPermission permission;
        permission.setAccuracy(QLocationPermission::Precise);
        switch (qApp->checkPermission(permission)) {
        case Qt::PermissionStatus::Undetermined:
            qApp->requestPermission(permission, this, [this](const QPermission &result) {
                if (result.status() == Qt::PermissionStatus::Granted)
                    setTracking(true);
                else
                    setStatus(tr("Location permission was denied."));
            });
            setStatus(tr("Waiting for location permission…"));
            return;
        case Qt::PermissionStatus::Denied:
            setStatus(tr("Location permission was denied."));
            return;
        case Qt::PermissionStatus::Granted:
            break;
        }
    }

    m_tracking = tracking;
    if (m_tracking) {
        m_source->startUpdates();
        setStatus(tr("Waiting for a location fix…"));
    } else {
        m_source->stopUpdates();
        resetMotion();
        setStatus(tr("Location is off."));
    }
    emit trackingChanged();
}

bool LocationTracker::hasPosition() const
{
    return m_hasPosition;
}

double LocationTracker::latitude() const
{
    return m_latitude;
}

double LocationTracker::longitude() const
{
    return m_longitude;
}

double LocationTracker::accuracy() const
{
    return m_accuracy;
}

bool LocationTracker::hasDirection() const
{
    return m_hasDirection;
}

double LocationTracker::direction() const
{
    return m_direction;
}

QString LocationTracker::status() const
{
    return m_status;
}

void LocationTracker::setStatus(const QString &status)
{
    if (m_status == status)
        return;

    m_status = status;
    emit statusChanged();
}

bool LocationTracker::hasMotion() const { return m_hasMotion; }
double LocationTracker::speedKnots() const { return m_speedKnots; }
bool LocationTracker::hasCourse() const { return m_hasCourse; }
double LocationTracker::courseDegrees() const { return m_courseDegrees; }

void LocationTracker::resetMotion()
{
    m_samples.clear();
    m_hasMotion = false;
    m_hasCourse = false;
    m_speedKnots = 0.0;
    m_courseDegrees = 0.0;
}

// Speed and course come from the displacement between the newest fix and the oldest one
// within a ~20 s window (always at least the previous fix, since real GPS fixes are 30 s apart).
void LocationTracker::recordSample(double latitude, double longitude, qint64 timestamp)
{
    m_samples.append({timestamp, latitude, longitude});
    while (m_samples.size() > 2 && timestamp - m_samples.at(1).timestamp >= 20000)
        m_samples.removeFirst();

    m_hasMotion = false;
    m_hasCourse = false;
    const Sample &from = m_samples.first();
    const double seconds = (timestamp - from.timestamp) / 1000.0;
    if (m_samples.size() < 2 || seconds <= 0.0)
        return;

    const double phi1 = qDegreesToRadians(from.latitude);
    const double phi2 = qDegreesToRadians(latitude);
    const double dPhi = phi2 - phi1;
    const double dLambda = qDegreesToRadians(longitude - from.longitude);
    const double a = std::sin(dPhi / 2) * std::sin(dPhi / 2)
        + std::cos(phi1) * std::cos(phi2) * std::sin(dLambda / 2) * std::sin(dLambda / 2);
    const double metres = 2.0 * 6371000.0 * std::asin(std::min(1.0, std::sqrt(a)));

    m_speedKnots = metres / seconds / 0.514444;
    m_hasMotion = true;
    // Course is meaningless when effectively stationary (GPS jitter).
    if (m_speedKnots >= 0.5) {
        const double y = std::sin(dLambda) * std::cos(phi2);
        const double x = std::cos(phi1) * std::sin(phi2) - std::sin(phi1) * std::cos(phi2) * std::cos(dLambda);
        m_courseDegrees = std::fmod(qRadiansToDegrees(std::atan2(y, x)) + 360.0, 360.0);
        m_hasCourse = true;
    }
}

bool LocationTracker::simulatorAvailable() const
{
#ifdef SIFIDS_VESSEL_SIMULATOR
    return true;
#else
    return false;
#endif
}

bool LocationTracker::simulating() const { return m_simulating; }
double LocationTracker::simHeading() const { return m_simHeading; }
double LocationTracker::simSpeed() const { return m_simSpeed; }

void LocationTracker::startSimulation(double latitude, double longitude)
{
    if (!simulatorAvailable())
        return;
    if (!m_simulating && m_tracking && m_source)
        m_source->stopUpdates();

    m_simulating = true;
    const bool wasTracking = m_tracking;
    m_tracking = true;
    m_latitude = qBound(-85.0, latitude, 85.0);
    m_longitude = longitude;
    m_accuracy = 5.0;
    m_hasPosition = true;
    m_hasDirection = true;
    m_direction = m_simHeading;
    m_simTicks = 0;
    resetMotion();
    recordSample(m_latitude, m_longitude, QDateTime::currentMSecsSinceEpoch());
    m_simTimer.start();
    setStatus(tr("Simulated vessel active."));
    if (!wasTracking)
        emit trackingChanged();
    emit simulationChanged();
    emit positionChanged();
    emit locationReceived(m_latitude, m_longitude, m_accuracy,
                          QDateTime::currentMSecsSinceEpoch());
}

void LocationTracker::setSimulation(double headingDegrees, double speedKnots)
{
    m_simHeading = std::fmod(std::fmod(headingDegrees, 360.0) + 360.0, 360.0);
    m_simSpeed = qMax(0.0, speedKnots);
    if (m_simulating) {
        m_direction = m_simHeading;
        emit positionChanged();
    }
    emit simulationChanged();
}

void LocationTracker::stopSimulation()
{
    if (!m_simulating)
        return;
    m_simTimer.stop();
    m_simulating = false;
    m_tracking = false;
    m_hasPosition = false;
    m_hasDirection = false;
    resetMotion();
    setStatus(tr("Location is off."));
    emit simulationChanged();
    emit trackingChanged();
    emit positionChanged();
}

void LocationTracker::advanceSimulation()
{
    const double metres = m_simSpeed * 0.514444;
    const double heading = qDegreesToRadians(m_simHeading);
    m_latitude = qBound(-85.0, m_latitude + metres * std::cos(heading) / 111320.0, 85.0);
    m_longitude += metres * std::sin(heading) / (111320.0 * std::cos(qDegreesToRadians(m_latitude)));
    if (m_longitude > 180.0)
        m_longitude -= 360.0;
    else if (m_longitude < -180.0)
        m_longitude += 360.0;
    m_direction = m_simHeading;
    recordSample(m_latitude, m_longitude, QDateTime::currentMSecsSinceEpoch());
    emit positionChanged();
    // Record a track point every 5 s, like a denser GPS feed.
    if (++m_simTicks % 5 == 0)
        emit locationReceived(m_latitude, m_longitude, m_accuracy,
                              QDateTime::currentMSecsSinceEpoch());
}

void LocationTracker::handlePositionUpdate(const QGeoPositionInfo &info)
{
    if (m_simulating)
        return;
    const QGeoCoordinate coordinate = info.coordinate();
    if (!coordinate.isValid())
        return;

    m_latitude = coordinate.latitude();
    m_longitude = coordinate.longitude();
    m_hasPosition = true;
    m_accuracy = info.hasAttribute(QGeoPositionInfo::HorizontalAccuracy)
        ? info.attribute(QGeoPositionInfo::HorizontalAccuracy)
        : 0.0;
    m_hasDirection = info.hasAttribute(QGeoPositionInfo::Direction);
    m_direction = m_hasDirection ? info.attribute(QGeoPositionInfo::Direction) : 0.0;

    recordSample(m_latitude, m_longitude, info.timestamp().toMSecsSinceEpoch());
    setStatus(m_accuracy > 0.0
                  ? tr("Position updated (±%1 m).").arg(m_accuracy, 0, 'f', 0)
                  : tr("Position updated."));
    emit positionChanged();
    emit locationReceived(m_latitude, m_longitude, m_accuracy,
                          info.timestamp().toMSecsSinceEpoch());
}
