#include "SailPlan.h"

#include <QtMath>

namespace {
constexpr int kCheckinTimerIntervalMs = 15000;
constexpr double kArrivalRadiusMeters = 100.0;

double distanceMeters(double lat1, double lon1, double lat2, double lon2)
{
    const double r = 6371000.0;
    const double dLat = qDegreesToRadians(lat2 - lat1);
    const double dLon = qDegreesToRadians(lon2 - lon1);
    const double a = qPow(qSin(dLat / 2), 2)
        + qCos(qDegreesToRadians(lat1)) * qCos(qDegreesToRadians(lat2)) * qPow(qSin(dLon / 2), 2);
    return 2 * r * qAsin(qSqrt(a));
}
}

const QVector<int> &SailPlan::checkinOffsetsMinutes()
{
    static const QVector<int> offsets{15, 10, 5, 0};
    return offsets;
}

QVector<QDateTime> SailPlan::checkpointsFor(const QDateTime &eta)
{
    QVector<QDateTime> checkpoints;
    checkpoints.reserve(checkinOffsetsMinutes().size());
    for (int minutes : checkinOffsetsMinutes())
        checkpoints.append(eta.addSecs(-60 * minutes));
    return checkpoints;
}

SailPlan::SailPlan(QObject *parent)
    : QObject(parent)
{
    m_timer.setInterval(kCheckinTimerIntervalMs);
    connect(&m_timer, &QTimer::timeout, this,
            [this] { evaluateCheckinsAt(QDateTime::currentDateTime()); });
}

bool SailPlan::enabled() const { return m_enabled; }

void SailPlan::setEnabled(bool enabled)
{
    if (m_enabled == enabled)
        return;
    m_enabled = enabled;
    emit enabledChanged();
}

bool SailPlan::active() const { return m_active; }
bool SailPlan::hasDeparturePoint() const { return m_hasDeparturePoint; }
double SailPlan::departureLatitude() const { return m_departureLatitude; }
double SailPlan::departureLongitude() const { return m_departureLongitude; }
QDateTime SailPlan::departureTime() const { return m_departureTime; }
bool SailPlan::hasDestinationPoint() const { return m_hasDestinationPoint; }
double SailPlan::destinationLatitude() const { return m_destinationLatitude; }
double SailPlan::destinationLongitude() const { return m_destinationLongitude; }
QDateTime SailPlan::destinationTime() const { return m_destinationTime; }

void SailPlan::setDeparturePoint(double latitude, double longitude, const QString &name)
{
    m_departureName = name;
    m_hasDeparturePoint = true;
    m_departureLatitude = latitude;
    m_departureLongitude = longitude;
    emit planChanged();
}

void SailPlan::setDepartureTime(const QDateTime &time)
{
    m_departureTime = time;
    emit planChanged();
}

void SailPlan::setDestinationPoint(double latitude, double longitude, const QString &name)
{
    m_destinationName = name;
    m_hasDestinationPoint = true;
    m_destinationLatitude = latitude;
    m_destinationLongitude = longitude;
    emit planChanged();
}

void SailPlan::setDestinationTime(const QDateTime &time)
{
    m_destinationTime = time;
    emit planChanged();
}

QString SailPlan::summary() const
{
    if (!m_active)
        return tr("No sail plan is active.");

    int nextOffset = -1;
    for (int i = 0; i < m_checkpoints.size(); ++i) {
        if (!m_sentCheckpoints.contains(i)) {
            nextOffset = checkinOffsetsMinutes().at(i);
            break;
        }
    }
    const QString eta = formatTime(m_destinationTime);
    if (nextOffset < 0)
        return tr("Under way. ETA %1. All check-ins sent.").arg(eta);
    if (nextOffset == 0)
        return tr("Under way. ETA %1. Next check-in: at ETA.").arg(eta);
    return tr("Under way. ETA %1. Next check-in: %2 minutes before ETA.")
        .arg(eta).arg(nextOffset);
}

bool SailPlan::start()
{
    if (!m_enabled) {
        emit errorOccurred(tr("Enable sail plan check-ins in Settings first."));
        return false;
    }
    if (!m_hasDeparturePoint || !m_hasDestinationPoint) {
        emit errorOccurred(tr("Drop a departure point and a destination point on the map."));
        return false;
    }
    if (!m_departureTime.isValid() || !m_destinationTime.isValid()) {
        emit errorOccurred(tr("Set a departure time and a destination time (ETA)."));
        return false;
    }
    if (m_destinationTime <= m_departureTime) {
        emit errorOccurred(tr("The destination ETA must be after the departure time."));
        return false;
    }

    m_checkpoints = checkpointsFor(m_destinationTime);
    m_sentCheckpoints.clear();
    m_leftDestinationArea = false;
    m_active = true;

    emit activeChanged();
    emit planChanged();
    emit shareRequested(tr("Sail plan"), composeSailPlanMessage());

    m_timer.start();
    return true;
}

void SailPlan::endPlan(const QString &subject, const QString &body)
{
    m_timer.stop();
    m_active = false;
    m_sentCheckpoints.clear();
    emit activeChanged();
    emit planChanged();
    emit shareRequested(subject, body);
}

void SailPlan::cancel()
{
    if (!m_active)
        return;
    endPlan(tr("Sail plan cancelled"), composeCancelMessage());
}

void SailPlan::arrive()
{
    if (!m_active)
        return;
    endPlan(tr("Sail plan arrival"), composeArrivalMessage());
}

void SailPlan::updatePosition(double latitude, double longitude, double direction,
                              bool hasDirection, bool hasPosition, double accuracy)
{
    m_lastLatitude = latitude;
    m_lastLongitude = longitude;
    m_lastDirection = direction;
    m_hasDirection = hasDirection;
    m_hasPosition = hasPosition;

    if (!m_active || !hasPosition || !m_hasDestinationPoint)
        return;
    if (accuracy > kArrivalRadiusMeters)
        return;
    const double distance = distanceMeters(latitude, longitude,
                                           m_destinationLatitude, m_destinationLongitude);
    if (distance > kArrivalRadiusMeters)
        m_leftDestinationArea = true;
    else if (m_leftDestinationArea)
        arrive();
}

void SailPlan::evaluateCheckinsAt(const QDateTime &now)
{
    if (!m_active || !m_enabled)
        return;

    // Find the latest due-but-unsent checkpoint; if the app was suspended through
    // several checkpoints, send only the most recent one rather than flooding shares.
    int dueIndex = -1;
    for (int i = 0; i < m_checkpoints.size(); ++i) {
        if (!m_sentCheckpoints.contains(i) && now >= m_checkpoints.at(i))
            dueIndex = i;
    }
    if (dueIndex < 0)
        return;

    for (int i = 0; i <= dueIndex; ++i)
        m_sentCheckpoints.insert(i);

    emit shareRequested(tr("Position update"), composeCheckinMessage(dueIndex));
    emit planChanged();

    if (m_sentCheckpoints.size() >= m_checkpoints.size())
        m_timer.stop();
}

QString SailPlan::formatTime(const QDateTime &time)
{
    return time.toString(QStringLiteral("yyyy-MM-dd HH:mm"));
}

QString SailPlan::formatPoint(double latitude, double longitude, const QString &name)
{
    const QString latitudeText = QString::number(latitude, 'f', 5);
    const QString longitudeText = QString::number(longitude, 'f', 5);
    const QString point = tr("%1, %2 (https://maps.google.com/?q=%1,%2)").arg(latitudeText, longitudeText);
    return name.isEmpty() ? point : QStringLiteral("%1 [%2]").arg(name, point);
}

void SailPlan::setVesselInfo(const QString &pln, const QString &name)
{
    m_vesselPln = pln.trimmed();
    m_vesselName = name.trimmed();
}

QString SailPlan::withVessel(const QString &body) const
{
    const QString name = m_vesselName.isEmpty() ? tr("not set") : m_vesselName;
    const QString pln = m_vesselPln.isEmpty() ? tr("not set") : m_vesselPln;
    return tr("Vessel: %1 (PLN %2)\n").arg(name, pln) + body;
}

QString SailPlan::composeSailPlanMessage() const
{
    return withVessel(tr("Sail plan: departing %1 at %2, bound for %3. ETA %4. "
              "I'll send position updates as we approach the ETA \u2014 if you don't "
              "hear from me by then, please treat us as overdue.")
        .arg(formatPoint(m_departureLatitude, m_departureLongitude, m_departureName), formatTime(m_departureTime),
             formatPoint(m_destinationLatitude, m_destinationLongitude, m_destinationName), formatTime(m_destinationTime)));
}

QString SailPlan::composeCancelMessage() const
{
    return withVessel(tr("Sail plan CANCELLED by the skipper \u2014 everything is fine, no action needed. "
              "(Was bound for %1, ETA %2.) Please disregard earlier sail plan messages and "
              "do not treat us as overdue.")
        .arg(formatPoint(m_destinationLatitude, m_destinationLongitude, m_destinationName),
             formatTime(m_destinationTime)));
}

QString SailPlan::composeArrivalMessage() const
{
    return withVessel(tr("Sail plan ARRIVED \u2014 safely at %1 at %2. Everything is fine, "
              "no further check-ins will be sent.")
        .arg(formatPoint(m_destinationLatitude, m_destinationLongitude, m_destinationName),
             formatTime(QDateTime::currentDateTime())));
}

QString SailPlan::composeCheckinMessage(int checkpointIndex) const
{
    const int minutesLeft = checkinOffsetsMinutes().at(checkpointIndex);
    const QString when = minutesLeft > 0
        ? tr("%1 minutes before ETA").arg(minutesLeft)
        : tr("at ETA");

    QString position = tr("Position: not available");
    QString heading = tr("Heading: not available");
    if (m_hasPosition) {
        position = tr("Position: %1").arg(formatPoint(m_lastLatitude, m_lastLongitude));
        if (m_hasDirection)
            heading = tr("Heading: %1\u00b0").arg(qRound(m_lastDirection));
    }

    return withVessel(tr("Sail plan check-in (%1) \u2014 bound for %2, ETA %3.\n%4\n%5")
        .arg(when, formatPoint(m_destinationLatitude, m_destinationLongitude, m_destinationName),
             formatTime(m_destinationTime), position, heading));
}
