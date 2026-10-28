#pragma once

#include <QDateTime>
#include <QObject>
#include <QSet>
#include <QString>
#include <QTimer>
#include <QVector>
#include <QtQml/qqmlregistration.h>

// Tracks a simple "sail plan" (float plan): a departure point/time and a
// destination point/time, each point dropped on the map rather than typed in.
// Starting a plan requests an immediate share of the plan text; as the ETA
// approaches it requests further shares with the vessel's current position so
// a shore contact can tell if the vessel is overdue. The actual sending is
// done elsewhere (see ShareService) via shareRequested().
class SailPlan : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(bool enabled READ enabled WRITE setEnabled NOTIFY enabledChanged)
    Q_PROPERTY(bool active READ active NOTIFY activeChanged)
    Q_PROPERTY(bool hasDeparturePoint READ hasDeparturePoint NOTIFY planChanged)
    Q_PROPERTY(double departureLatitude READ departureLatitude NOTIFY planChanged)
    Q_PROPERTY(double departureLongitude READ departureLongitude NOTIFY planChanged)
    Q_PROPERTY(QDateTime departureTime READ departureTime NOTIFY planChanged)
    Q_PROPERTY(bool hasDestinationPoint READ hasDestinationPoint NOTIFY planChanged)
    Q_PROPERTY(double destinationLatitude READ destinationLatitude NOTIFY planChanged)
    Q_PROPERTY(double destinationLongitude READ destinationLongitude NOTIFY planChanged)
    Q_PROPERTY(QDateTime destinationTime READ destinationTime NOTIFY planChanged)
    Q_PROPERTY(QString departureName READ departureName NOTIFY planChanged)
    Q_PROPERTY(QString destinationName READ destinationName NOTIFY planChanged)
    Q_PROPERTY(QString summary READ summary NOTIFY planChanged)

public:
    explicit SailPlan(QObject *parent = nullptr);

    bool enabled() const;
    void setEnabled(bool enabled);
    bool active() const;
    bool hasDeparturePoint() const;
    double departureLatitude() const;
    double departureLongitude() const;
    QDateTime departureTime() const;
    bool hasDestinationPoint() const;
    double destinationLatitude() const;
    double destinationLongitude() const;
    QDateTime destinationTime() const;
    QString summary() const;
    QString departureName() const { return m_departureName; }
    QString destinationName() const { return m_destinationName; }

    // Sets the point dropped on the map for departure/destination; can be called
    // repeatedly while the plan is being edited (i.e. before start()).
    // Vessel identity included at the top of every message that is shared.
    Q_INVOKABLE void setVesselInfo(const QString &pln, const QString &name);
    Q_INVOKABLE void setDeparturePoint(double latitude, double longitude, const QString &name = QString());
    Q_INVOKABLE void setDepartureTime(const QDateTime &time);
    Q_INVOKABLE void setDestinationPoint(double latitude, double longitude, const QString &name = QString());
    Q_INVOKABLE void setDestinationTime(const QDateTime &time);

    // Starts the plan using the points/times set above and immediately emits
    // shareRequested() with the plan text. Returns false (and emits
    // errorOccurred) if the plan data is incomplete, the ETA is not after the
    // departure time, or check-ins are not enabled.
    Q_INVOKABLE bool start();
    // Clears the active plan and shares a "cancelled, everything is fine" message.
    Q_INVOKABLE void cancel();
    // Called whenever a new GPS fix arrives so the next check-in can report it.
    // Also ends the plan with an arrival message once the vessel is within 100 m of the
    // destination (after having been outside that radius). accuracy < 0 means unknown.
    Q_INVOKABLE void updatePosition(double latitude, double longitude, double direction,
                                    bool hasDirection, bool hasPosition, double accuracy = -1.0);
    // Ends the plan and shares an arrival message (manual arrival, e.g. poor GPS).
    Q_INVOKABLE void arrive();

    // The fixed check-in offsets (minutes before ETA), descending; exposed for tests.
    static const QVector<int> &checkinOffsetsMinutes();
    // The check-in timestamps for a given ETA, in the same order as the offsets above.
    static QVector<QDateTime> checkpointsFor(const QDateTime &eta);
    // Evaluates which check-ins are due as of a given time; exposed for tests so the
    // 15-second polling timer does not need to be exercised to test the scheduling.
    void evaluateCheckinsAt(const QDateTime &now);

signals:
    void enabledChanged();
    void activeChanged();
    void planChanged();
    void shareRequested(const QString &subject, const QString &body);
    void errorOccurred(const QString &message);

private:
    QString composeSailPlanMessage() const;
    QString composeCheckinMessage(int checkpointIndex) const;
    QString composeCancelMessage() const;
    QString withVessel(const QString &body) const;
    QString composeArrivalMessage() const;
    void endPlan(const QString &subject, const QString &body);
    static QString formatTime(const QDateTime &time);
    static QString formatPoint(double latitude, double longitude, const QString &name = QString());

    QTimer m_timer;
    QString m_vesselPln;
    QString m_vesselName;
    bool m_enabled = false;
    bool m_active = false;

    QString m_departureName;
    QString m_destinationName;
    bool m_hasDeparturePoint = false;
    double m_departureLatitude = 0.0;
    double m_departureLongitude = 0.0;
    QDateTime m_departureTime;

    bool m_hasDestinationPoint = false;
    double m_destinationLatitude = 0.0;
    double m_destinationLongitude = 0.0;
    QDateTime m_destinationTime;

    bool m_leftDestinationArea = false;
    QVector<QDateTime> m_checkpoints;
    QSet<int> m_sentCheckpoints;

    double m_lastLatitude = 0.0;
    double m_lastLongitude = 0.0;
    double m_lastDirection = 0.0;
    bool m_hasDirection = false;
    bool m_hasPosition = false;
};
