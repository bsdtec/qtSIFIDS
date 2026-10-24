#include "AppStore.h"

#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QStandardPaths>
#include <QSqlDatabase>
#include <QSqlError>
#include <QSqlQuery>
#include <QtTest>

class AppStoreTests final : public QObject
{
    Q_OBJECT

private slots:
    void initTestCase()
    {
        QCoreApplication::setApplicationName(QStringLiteral("qtSIFIDS-tests"));
        QStandardPaths::setTestModeEnabled(true);
    }

    void init()
    {
        QDir(QStandardPaths::writableLocation(QStandardPaths::AppDataLocation))
            .removeRecursively();
    }

    void savesSettingsAndForms()
    {
        AppStore store;
        const QVariantMap settings{
            {QStringLiteral("pln"), QStringLiteral("TEST123")},
            {QStringLiteral("vessel_name"), QStringLiteral("Test vessel")},
            {QStringLiteral("consent_name"), QStringLiteral("Test user")},
            {QStringLiteral("consent_email"), QStringLiteral("test@example.org")},
            {QStringLiteral("consent_phone"), QStringLiteral("12345")},
            {QStringLiteral("consent_confirmed"), true}
        };
        QVERIFY(store.saveSettings(settings));
        QVERIFY(store.consented());
        QCOMPARE(store.settings().value(QStringLiteral("pln")).toString(),
                 QStringLiteral("TEST123"));

        const int formId = store.saveForm({
            {QStringLiteral("pln"), QStringLiteral("TEST123")},
            {QStringLiteral("vessel_name"), QStringLiteral("Test vessel")},
            {QStringLiteral("port_of_departure"), QStringLiteral("Anstruther")}
        });
        QVERIFY2(formId > 0, qPrintable(store.status()));
        QCOMPARE(store.forms().size(), 1);

        const int updatedFormId = store.saveForm({
            {QStringLiteral("id"), formId},
            {QStringLiteral("pln"), QStringLiteral("TEST123")},
            {QStringLiteral("vessel_name"), QStringLiteral("Updated vessel")}
        });
        QCOMPARE(updatedFormId, formId);
        QCOMPARE(store.forms().first().toMap().value(QStringLiteral("vessel_name")).toString(),
                 QStringLiteral("Updated vessel"));
    }

    void savesRowsAndDeletesWithParent()
    {
        AppStore store;
        const int formId = store.saveForm({
            {QStringLiteral("pln"), QStringLiteral("ROWTEST")}
        });
        QVERIFY2(formId > 0, qPrintable(store.status()));
        const int rowId = store.saveFormRow({
            {QStringLiteral("form_id"), formId},
            {QStringLiteral("fishing_activity_date"), QStringLiteral("2026-10-24")},
            {QStringLiteral("latitude"), 56.2},
            {QStringLiteral("longitude"), -2.7},
            {QStringLiteral("species"), QStringLiteral("Cod (COD)")},
            {QStringLiteral("weight"), 12.5}
        });
        QVERIFY2(rowId > 0, qPrintable(store.status()));
        QCOMPARE(store.rowsForForm(formId).size(), 1);

        const int updatedRowId = store.saveFormRow({
            {QStringLiteral("id"), rowId},
            {QStringLiteral("form_id"), formId},
            {QStringLiteral("fishing_activity_date"), QStringLiteral("2026-10-24")},
            {QStringLiteral("latitude"), 56.2},
            {QStringLiteral("longitude"), -2.7},
            {QStringLiteral("species"), QStringLiteral("Cod (COD)")},
            {QStringLiteral("weight"), 13.0}
        });
        QCOMPARE(updatedRowId, rowId);
        QCOMPARE(store.rowsForForm(formId).first().toMap()
                     .value(QStringLiteral("weight")).toDouble(), 13.0);

        const QString path = store.exportFormCsv(formId);
        QVERIFY2(!path.isEmpty(), qPrintable(store.status()));
        QFile csv(path);
        QVERIFY(csv.open(QIODevice::ReadOnly));
        const QByteArray contents = csv.readAll();
        QVERIFY(contents.contains("Fishing Activity Date,Lat/Long"));
        QVERIFY(contents.contains("Cod (COD)"));
        QVERIFY(contents.contains("56 12 N 002 42 W"));

        QVERIFY(store.deleteForm(formId));
        QCOMPARE(store.forms().size(), 0);
        QCOMPARE(store.rowsForForm(formId).size(), 0);
    }

    void savesObservationsAndLocations()
    {
        AppStore store;
        const int observationId = store.saveObservation({
            {QStringLiteral("animal"), QStringLiteral("Whale")},
            {QStringLiteral("species"), QStringLiteral("Minke whale")},
            {QStringLiteral("timestamp"), QDateTime::currentMSecsSinceEpoch()},
            {QStringLiteral("latitude"), 56.1},
            {QStringLiteral("longitude"), -2.8},
            {QStringLiteral("count"), 2},
            {QStringLiteral("notes"), QStringLiteral("Seen near the coast")}
        });
        QVERIFY(observationId > 0);
        QCOMPARE(store.observations().size(), 1);
        QVERIFY(store.deleteObservation(observationId));
        QCOMPARE(store.observations().size(), 0);

        store.recordLocation(56.1, -2.8, 4.5,
                             QDateTime::currentMSecsSinceEpoch(), true);
        QCOMPARE(store.locations().size(), 1);
        QCOMPARE(store.locations().first().toMap()
                     .value(QStringLiteral("fishing")).toInt(), 1);

        const QString path = store.exportTrackCsv(true);
        QVERIFY2(!path.isEmpty(), qPrintable(store.status()));
        QFile csv(path);
        QVERIFY(csv.open(QIODevice::ReadOnly));
        const QByteArray contents = csv.readAll();
        QVERIFY(contents.startsWith("Timestamp (UTC),Latitude,Longitude,Accuracy (m),Fishing"));
        QVERIFY(contents.contains("56.100000,-2.800000,5,Yes"));
    }

    void importsRoomVersion15Database()
    {
        QTemporaryDir temporaryDirectory;
        QVERIFY(temporaryDirectory.isValid());
        const QString legacyPath = temporaryDirectory.filePath(QStringLiteral("catch-database"));
        {
            QSqlDatabase legacy = QSqlDatabase::addDatabase(
                QStringLiteral("QSQLITE"), QStringLiteral("legacy-fixture"));
            legacy.setDatabaseName(legacyPath);
            QVERIFY(legacy.open());
            QSqlQuery query(legacy);
            const QStringList statements{
                QStringLiteral("PRAGMA user_version = 15"),
                QStringLiteral("CREATE TABLE fish_1_form (id INTEGER PRIMARY KEY, created_at INTEGER, fishery_office TEXT, email TEXT, port_of_departure TEXT, port_of_landing TEXT, pln TEXT, vessel_name TEXT, owner_master TEXT, address TEXT, total_pots_fishing INTEGER, comments_and_buyers_information TEXT)"),
                QStringLiteral("CREATE TABLE fish_1_form_row (id INTEGER PRIMARY KEY, form_id INTEGER, fishing_activity_date INTEGER, latitude REAL, longitude REAL, ices_area TEXT, gear_id INTEGER, mesh_size INTEGER, species_id INTEGER, state_id INTEGER, presentation_id INTEGER, weight REAL, dis INTEGER, bms INTEGER, number_of_pots_hauled INTEGER, landing_or_discard_date INTEGER, transporter_reg_etc TEXT)"),
                QStringLiteral("CREATE TABLE gear (id INTEGER PRIMARY KEY, name TEXT)"),
                QStringLiteral("CREATE TABLE catch_species (id INTEGER PRIMARY KEY, species_name TEXT, species_code TEXT)"),
                QStringLiteral("CREATE TABLE catch_state (id INTEGER PRIMARY KEY, name TEXT)"),
                QStringLiteral("CREATE TABLE catch_presentation (id INTEGER PRIMARY KEY, name TEXT)"),
                QStringLiteral("CREATE TABLE location (id INTEGER PRIMARY KEY, timestamp INTEGER, latitude REAL, longitude REAL, accuracy REAL, fishing INTEGER, uploaded INTEGER)"),
                QStringLiteral("CREATE TABLE observation_class (id INTEGER PRIMARY KEY, name TEXT)"),
                QStringLiteral("CREATE TABLE observation_species (id INTEGER PRIMARY KEY, name TEXT, observation_class_id INTEGER)"),
                QStringLiteral("CREATE TABLE Observation (id INTEGER PRIMARY KEY, observation_class_id INTEGER, observation_species_id INTEGER, timestamp INTEGER, latitude REAL, longitude REAL, count INTEGER, notes TEXT, submitted INTEGER)"),
                QStringLiteral("INSERT INTO fish_1_form VALUES (10, 1000, 'Office', 'office@example.org', 'Anstruther', 'Anstruther', 'LEGACY1', 'Legacy boat', 'Owner', 'Address', 12, 'notes')"),
                QStringLiteral("INSERT INTO gear VALUES (1, 'Pots creels')"),
                QStringLiteral("INSERT INTO catch_species VALUES (2, 'Cod', 'COD')"),
                QStringLiteral("INSERT INTO catch_state VALUES (3, 'Fresh')"),
                QStringLiteral("INSERT INTO catch_presentation VALUES (4, 'Whole')"),
                QStringLiteral("INSERT INTO fish_1_form_row VALUES (11, 10, 1792800000000, 56.2, -2.7, '37F3', 1, 70, 2, 3, 4, 10.5, 0, 1, 4, 1792800000000, 'ABC123')"),
                QStringLiteral("INSERT INTO location VALUES (20, 1792800000000, 56.2, -2.7, 4.5, 1, 0)"),
                QStringLiteral("INSERT INTO observation_class VALUES (5, 'Whale')"),
                QStringLiteral("INSERT INTO observation_species VALUES (6, 'Minke whale', 5)"),
                QStringLiteral("INSERT INTO Observation VALUES (30, 5, 6, 1792800000000, 56.2, -2.7, 2, 'Seen', 0)")
            };
            for (const QString &statement : statements)
                QVERIFY2(query.exec(statement), qPrintable(query.lastError().text()));
            legacy.close();
            legacy = QSqlDatabase();
            QSqlDatabase::removeDatabase(QStringLiteral("legacy-fixture"));
        }

        AppStore store;
        QVERIFY2(store.importAndroidDatabase(legacyPath), qPrintable(store.status()));
        QCOMPARE(store.forms().size(), 1);
        const int formId = store.forms().first().toMap().value(QStringLiteral("id")).toInt();
        QCOMPARE(store.rowsForForm(formId).size(), 1);
        QCOMPARE(store.rowsForForm(formId).first().toMap()
                     .value(QStringLiteral("species")).toString(), QStringLiteral("Cod (COD)"));
        QCOMPARE(store.locations().size(), 1);
        QCOMPARE(store.observations().size(), 1);
        QCOMPARE(store.observations().first().toMap()
                     .value(QStringLiteral("species")).toString(), QStringLiteral("Minke whale"));
    }
};

QTEST_GUILESS_MAIN(AppStoreTests)
#include "AppStoreTests.moc"
