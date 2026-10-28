#include "LocationTracker.h"

#include <QGeoPositionInfo>
#include <QCoreApplication>
#include <QGeoPositionInfoSource>
#include <QLocationPermission>
#include <QVariant>

LocationTracker::LocationTracker(QObject *parent)
    : QObject(parent),
      m_source(QGeoPositionInfoSource::createDefaultSource(this))
{
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

void LocationTracker::handlePositionUpdate(const QGeoPositionInfo &info)
{
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

    setStatus(m_accuracy > 0.0
                  ? tr("Position updated (±%1 m).").arg(m_accuracy, 0, 'f', 0)
                  : tr("Position updated."));
    emit positionChanged();
    emit locationReceived(m_latitude, m_longitude, m_accuracy,
                          info.timestamp().toMSecsSinceEpoch());
}
