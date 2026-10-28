#include "SailPlan.h"

#include <QSignalSpy>
#include <QtTest>

class SailPlanTests final : public QObject
{
    Q_OBJECT

private slots:
    void checkpointsAreFifteenTenFiveAndZeroMinutesBeforeEta()
    {
        const QDateTime eta(QDate(2026, 6, 1), QTime(14, 0));
        const QVector<QDateTime> checkpoints = SailPlan::checkpointsFor(eta);
        QCOMPARE(checkpoints.size(), 4);
        QCOMPARE(checkpoints.at(0), eta.addSecs(-15 * 60));
        QCOMPARE(checkpoints.at(1), eta.addSecs(-10 * 60));
        QCOMPARE(checkpoints.at(2), eta.addSecs(-5 * 60));
        QCOMPARE(checkpoints.at(3), eta);
    }

    void startRejectsIncompletePlans()
    {
        SailPlan plan;
        plan.setEnabled(true);
        QSignalSpy errorSpy(&plan, &SailPlan::errorOccurred);

        // No points set at all.
        QVERIFY(!plan.start());
        QCOMPARE(errorSpy.count(), 1);
        QVERIFY(!plan.active());

        // A departure point but no destination point.
        plan.setDeparturePoint(56.4, -5.9);
        plan.setDepartureTime(QDateTime::currentDateTime());
        QVERIFY(!plan.start());
        QCOMPARE(errorSpy.count(), 2);

        // Both points but no times.
        plan.setDestinationPoint(57.0, -6.5);
        QVERIFY(!plan.start());
        QCOMPARE(errorSpy.count(), 3);
    }

    void startRejectsEtaNotAfterDeparture()
    {
        SailPlan plan;
        plan.setEnabled(true);
        plan.setDeparturePoint(56.4, -5.9);
        plan.setDestinationPoint(57.0, -6.5);
        const QDateTime now = QDateTime::currentDateTime();
        plan.setDepartureTime(now);
        plan.setDestinationTime(now.addSecs(-60));

        QSignalSpy errorSpy(&plan, &SailPlan::errorOccurred);
        QVERIFY(!plan.start());
        QCOMPARE(errorSpy.count(), 1);
        QVERIFY(!plan.active());
    }

    void startRefusedWhenDisabled()
    {
        SailPlan plan;
        plan.setDeparturePoint(56.4, -5.9);
        plan.setDestinationPoint(57.0, -6.5);
        const QDateTime now = QDateTime::currentDateTime();
        plan.setDepartureTime(now);
        plan.setDestinationTime(now.addSecs(3600));

        QSignalSpy errorSpy(&plan, &SailPlan::errorOccurred);
        QVERIFY(!plan.start());
        QCOMPARE(errorSpy.count(), 1);
        QVERIFY(!plan.active());
    }

    void startSharesTheSailPlanImmediately()
    {
        SailPlan plan;
        plan.setEnabled(true);
        QSignalSpy shareSpy(&plan, &SailPlan::shareRequested);

        plan.setDeparturePoint(56.4, -5.9);
        plan.setDepartureTime(QDateTime(QDate(2026, 6, 1), QTime(10, 0)));
        plan.setDestinationPoint(57.0, -6.5);
        const QDateTime eta(QDate(2026, 6, 1), QTime(14, 0));
        plan.setDestinationTime(eta);

        QVERIFY(plan.start());
        QVERIFY(plan.active());
        QCOMPARE(shareSpy.count(), 1);
        const QString body = shareSpy.at(0).at(1).toString();
        QVERIFY(body.contains("56.40000"));
        QVERIFY(body.contains("57.00000"));
        QVERIFY(body.contains("2026-06-01 14:00"));
    }

    void checkinsFireInOrderAndOnlyOncePerCheckpoint()
    {
        SailPlan plan;
        plan.setEnabled(true);
        plan.setDeparturePoint(56.4, -5.9);
        plan.setDepartureTime(QDateTime(QDate(2026, 6, 1), QTime(10, 0)));
        plan.setDestinationPoint(57.0, -6.5);
        const QDateTime eta(QDate(2026, 6, 1), QTime(14, 0));
        plan.setDestinationTime(eta);
        QVERIFY(plan.start());
        plan.updatePosition(56.7, -6.2, 270.0, true, true);

        QSignalSpy shareSpy(&plan, &SailPlan::shareRequested);

        // Before the first checkpoint: nothing due yet.
        plan.evaluateCheckinsAt(eta.addSecs(-16 * 60));
        QCOMPARE(shareSpy.count(), 0);

        // At T-15: the first check-in fires, mentions position and heading.
        plan.evaluateCheckinsAt(eta.addSecs(-15 * 60));
        QCOMPARE(shareSpy.count(), 1);
        QString body = shareSpy.at(0).at(1).toString();
        QVERIFY(body.contains("15 minutes before ETA"));
        QVERIFY(body.contains("56.70000"));
        QVERIFY(body.contains("Heading: 270"));

        // Re-evaluating the same time must not resend.
        plan.evaluateCheckinsAt(eta.addSecs(-15 * 60));
        QCOMPARE(shareSpy.count(), 1);

        // Skipping straight to T-2 (simulating a backgrounded app) sends only the
        // latest due checkpoint (T-5), not a flood of the missed ones.
        plan.evaluateCheckinsAt(eta.addSecs(-2 * 60));
        QCOMPARE(shareSpy.count(), 2);
        QVERIFY(shareSpy.at(1).at(1).toString().contains("5 minutes before ETA"));

        // At ETA: the final check-in fires and the plan stops scheduling further ones.
        plan.evaluateCheckinsAt(eta);
        QCOMPARE(shareSpy.count(), 3);
        QVERIFY(shareSpy.at(2).at(1).toString().contains("at ETA"));

        plan.evaluateCheckinsAt(eta.addSecs(60));
        QCOMPARE(shareSpy.count(), 3);
    }

    void checkinWithoutPositionSaysSo()
    {
        SailPlan plan;
        plan.setEnabled(true);
        plan.setDeparturePoint(56.4, -5.9);
        const QDateTime eta(QDate(2026, 6, 1), QTime(14, 0));
        plan.setDepartureTime(eta.addSecs(-4 * 3600));
        plan.setDestinationPoint(57.0, -6.5);
        plan.setDestinationTime(eta);
        QVERIFY(plan.start());

        QSignalSpy shareSpy(&plan, &SailPlan::shareRequested);
        plan.evaluateCheckinsAt(eta.addSecs(-15 * 60));
        QCOMPARE(shareSpy.count(), 1);
        QVERIFY(shareSpy.at(0).at(1).toString().contains("Position: not available"));
    }

    void cancelStopsFurtherCheckins()
    {
        SailPlan plan;
        plan.setEnabled(true);
        plan.setVesselInfo("LK123", "Sea Hawk");
        plan.setDeparturePoint(56.4, -5.9);
        const QDateTime eta(QDate(2026, 6, 1), QTime(14, 0));
        plan.setDepartureTime(eta.addSecs(-4 * 3600));
        plan.setDestinationPoint(57.0, -6.5);
        plan.setDestinationTime(eta);
        QVERIFY(plan.start());
        QSignalSpy cancelSpy(&plan, &SailPlan::shareRequested);
        plan.cancel();
        QVERIFY(!plan.active());
        QCOMPARE(cancelSpy.count(), 1);
        QVERIFY(cancelSpy.at(0).at(1).toString().contains("CANCELLED"));
        QVERIFY(cancelSpy.at(0).at(1).toString().startsWith("Vessel: Sea Hawk (PLN LK123)"));

        QSignalSpy shareSpy(&plan, &SailPlan::shareRequested);
        plan.evaluateCheckinsAt(eta.addSecs(-15 * 60));
        QCOMPARE(shareSpy.count(), 0);
    }

    void arrivalWithin100mEndsPlanAndShares()
    {
        SailPlan plan;
        plan.setEnabled(true);
        plan.setDeparturePoint(56.4, -5.9);
        const QDateTime eta(QDate(2026, 6, 1), QTime(14, 0));
        plan.setDepartureTime(eta.addSecs(-4 * 3600));
        plan.setDestinationPoint(57.0, -6.5);
        plan.setDestinationTime(eta);
        QVERIFY(plan.start());

        QSignalSpy shareSpy(&plan, &SailPlan::shareRequested);
        // Inside the radius before ever leaving it: must not count as arrival.
        plan.updatePosition(57.0, -6.5, 0, false, true, 5.0);
        QVERIFY(plan.active());
        plan.updatePosition(56.7, -6.2, 0, false, true, 5.0);
        QVERIFY(plan.active());
        // Within 100 m but with a poor fix: ignored.
        plan.updatePosition(57.0003, -6.5, 0, false, true, 500.0);
        QVERIFY(plan.active());
        plan.updatePosition(57.0005, -6.5, 0, false, true, 5.0);
        QVERIFY(!plan.active());
        QCOMPARE(shareSpy.count(), 1);
        QVERIFY(shareSpy.at(0).at(1).toString().contains("ARRIVED"));
    }

    void farFromDestinationDoesNotArrive()
    {
        SailPlan plan;
        plan.setEnabled(true);
        plan.setDeparturePoint(56.4, -5.9);
        const QDateTime eta(QDate(2026, 6, 1), QTime(14, 0));
        plan.setDepartureTime(eta.addSecs(-4 * 3600));
        plan.setDestinationPoint(57.0, -6.5);
        plan.setDestinationTime(eta);
        QVERIFY(plan.start());
        plan.updatePosition(56.7, -6.2, 0, false, true, 5.0);
        plan.updatePosition(57.002, -6.5, 0, false, true, 5.0);
        QVERIFY(plan.active());
    }
};

QTEST_GUILESS_MAIN(SailPlanTests)
#include "SailPlanTests.moc"
