#include "AppStore.h"

#include <QDir>
#include <QTimeZone>
#include <QFile>
#include <QFileInfo>
#include <QHash>
#include <QSaveFile>
#include <QDateTime>
#include <QHttpMultiPart>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QRegularExpression>
#include <QSqlDatabase>
#include <QSqlError>
#include <QSqlQuery>
#include <QSqlRecord>
#include <QStandardPaths>
#include <QSet>
#include <QTemporaryFile>
#include <QVariant>
#include <QUrl>

#include <cmath>

namespace {

QString csvField(const QVariant &value, bool quote = false)
{
    if (!value.isValid() || value.isNull())
        return {};
    QString text = value.toString();
    if (quote || text.contains(QLatin1Char(',')) || text.contains(QLatin1Char('"'))
        || text.contains(QLatin1Char('\n')) || text.contains(QLatin1Char('\r'))) {
        text.replace(QLatin1Char('"'), QStringLiteral("\"\""));
        return QStringLiteral("\"") + text + QStringLiteral("\"");
    }
    return text;
}

QVariantList stringList(const QStringList &values)
{
    QVariantList result;
    result.reserve(values.size());
    for (const QString &value : values)
        result.append(value);
    return result;
}

QString coordinateDms(double latitude, double longitude)
{
    auto component = [](double value, bool isLatitude) {
        int degrees = static_cast<int>(std::floor(std::abs(value)));
        int minutes = qRound((std::abs(value) - degrees) * 60.0);
        if (minutes == 60) {
            ++degrees;
            minutes = 0;
        }
        return QStringLiteral("%1 %2 %3")
            .arg(degrees, isLatitude ? 2 : 3, 10, QLatin1Char('0'))
            .arg(minutes, 2, 10, QLatin1Char('0'))
            .arg(value < 0.0 ? (isLatitude ? QLatin1Char('S') : QLatin1Char('W'))
                             : (isLatitude ? QLatin1Char('N') : QLatin1Char('E')));
    };
    return component(latitude, true) + QLatin1Char(' ') + component(longitude, false);
}

} // namespace

AppStore::AppStore(QObject *parent)
    : QObject(parent)
{
    m_network = new QNetworkAccessManager(this);
    const QString connectionName = QStringLiteral("sifids-%1").arg(
        reinterpret_cast<quintptr>(this));
    m_database = new QSqlDatabase(QSqlDatabase::addDatabase(
        QStringLiteral("QSQLITE"), connectionName));

    const QString dataDirectory = QStandardPaths::writableLocation(
        QStandardPaths::AppDataLocation);
    if (!QDir().mkpath(dataDirectory)) {
        setStatus(tr("Could not create the application data directory."), true);
        return;
    }
    m_database->setDatabaseName(dataDirectory + QStringLiteral("/sifids.sqlite"));
    if (!m_database->open()) {
        setStatus(tr("Could not open local database: %1").arg(m_database->lastError().text()), true);
        return;
    }
    initialize();
}

AppStore::~AppStore()
{
    if (!m_database)
        return;
    const QString connectionName = m_database->connectionName();
    m_database->close();
    delete m_database;
    m_database = nullptr;
    QSqlDatabase::removeDatabase(connectionName);
}

bool AppStore::initialize()
{
    const QStringList schema{
        QStringLiteral("PRAGMA foreign_keys = ON"),
        QStringLiteral("CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)"),
        QStringLiteral("CREATE TABLE IF NOT EXISTS forms ("
                       "id INTEGER PRIMARY KEY AUTOINCREMENT, created_at INTEGER NOT NULL, "
                       "fishery_office TEXT, email TEXT, port_of_departure TEXT, "
                       "port_of_landing TEXT, pln TEXT, vessel_name TEXT, owner_master TEXT, "
                       "address TEXT, total_pots_fishing INTEGER NOT NULL DEFAULT 0, comments TEXT)"),
        QStringLiteral("CREATE TABLE IF NOT EXISTS form_rows ("
                       "id INTEGER PRIMARY KEY AUTOINCREMENT, form_id INTEGER NOT NULL "
                       "REFERENCES forms(id) ON DELETE CASCADE, fishing_activity_date TEXT, "
                       "latitude REAL NOT NULL DEFAULT 0, longitude REAL NOT NULL DEFAULT 0, "
                       "ices_area TEXT, gear TEXT, mesh_size INTEGER NOT NULL DEFAULT 0, "
                       "species TEXT, state TEXT, presentation TEXT, weight REAL NOT NULL DEFAULT 0, "
                       "dis INTEGER NOT NULL DEFAULT 0, bms INTEGER NOT NULL DEFAULT 0, "
                       "number_of_pots_hauled INTEGER NOT NULL DEFAULT 0, "
                       "landing_or_discard_date TEXT, transporter_reg_etc TEXT)"),
        QStringLiteral("CREATE TABLE IF NOT EXISTS observations ("
                       "id INTEGER PRIMARY KEY AUTOINCREMENT, animal TEXT NOT NULL, species TEXT, "
                       "timestamp INTEGER NOT NULL, latitude REAL NOT NULL, longitude REAL NOT NULL, "
                       "count INTEGER NOT NULL DEFAULT 1, notes TEXT, submitted INTEGER NOT NULL DEFAULT 0)"),
        QStringLiteral("CREATE TABLE IF NOT EXISTS places ("
                       "id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, "
                       "latitude REAL NOT NULL, longitude REAL NOT NULL)"),
        QStringLiteral("CREATE TABLE IF NOT EXISTS locations ("
                       "id INTEGER PRIMARY KEY AUTOINCREMENT, timestamp INTEGER NOT NULL, "
                       "latitude REAL NOT NULL, longitude REAL NOT NULL, accuracy REAL, "
                       "fishing INTEGER NOT NULL DEFAULT 0, uploaded INTEGER NOT NULL DEFAULT 0)")
    };

    for (const QString &statement : schema) {
        if (!execute(statement))
            return false;
    }
    // Records created from the map's + menu carry a pin; older databases lack the column.
    for (const QString &table : {QStringLiteral("form_rows"), QStringLiteral("observations")}) {
        QSqlQuery info(*m_database);
        bool hasColumn = false;
        if (info.exec(QStringLiteral("PRAGMA table_info(%1)").arg(table))) {
            while (info.next()) {
                if (info.value(1).toString() == QStringLiteral("on_map"))
                    hasColumn = true;
            }
        }
        if (!hasColumn && !execute(QStringLiteral(
                "ALTER TABLE %1 ADD COLUMN on_map INTEGER NOT NULL DEFAULT 0").arg(table)))
            return false;
    }
    setStatus(tr("Local data is ready."), false);
    return true;
}

bool AppStore::execute(const QString &sql) const
{
    QSqlQuery query(*m_database);
    if (query.exec(sql))
        return true;
    const_cast<AppStore *>(this)->setStatus(
        tr("Database error: %1").arg(query.lastError().text()), true);
    return false;
}

void AppStore::setStatus(const QString &status, bool needsAttention)
{
    if (m_status == status && m_statusNeedsAttention == needsAttention)
        return;
    m_status = status;
    m_statusNeedsAttention = needsAttention;
    emit statusChanged();
}

QString AppStore::status() const { return m_status; }
bool AppStore::statusNeedsAttention() const { return m_statusNeedsAttention; }
bool AppStore::uploading() const { return m_uploading; }

bool AppStore::consented() const
{
    const QVariantMap saved = settings();
    const QString name = saved.value(QStringLiteral("consent_name")).toString().trimmed();
    const QString email = saved.value(QStringLiteral("consent_email")).toString().trimmed();
    const QString phone = saved.value(QStringLiteral("consent_phone")).toString().trimmed();
    const QString confirmation = saved.value(QStringLiteral("consent_confirmed")).toString();
    return !name.isEmpty() && !email.isEmpty() && !phone.isEmpty()
        && (confirmation.compare(QStringLiteral("true"), Qt::CaseInsensitive) == 0
            || confirmation == QStringLiteral("1"));
}

QString AppStore::defaultUploadUrl()
{
    return QStringLiteral("https://arts.st-andrews.ac.uk/sifids/");
}

bool AppStore::uploadEnabled() const
{
    return settings().value(QStringLiteral("upload_enabled")).toString()
        == QStringLiteral("true");
}

QString AppStore::uploadUrl() const
{
    const QString saved = settings().value(QStringLiteral("upload_url")).toString().trimmed();
    if (saved.isEmpty())
        return defaultUploadUrl();
    const QUrl url(saved);
    const QString scheme = url.scheme().toLower();
    if (!url.isValid() || url.host().isEmpty()
        || (scheme != QStringLiteral("http") && scheme != QStringLiteral("https")))
        return QString();
    return saved;
}

bool AppStore::uploadAllowed()
{
    if (!uploadEnabled()) {
        setStatus(tr("Uploads are turned off in Settings."), true);
        return false;
    }
    if (!consented()) {
        setStatus(tr("Complete participant consent in Settings before uploading."), true);
        return false;
    }
    if (uploadUrl().isEmpty()) {
        setStatus(tr("The upload URL in Settings is not a valid http(s) address."), true);
        return false;
    }
    return true;
}

QVariantList AppStore::queryRows(const QString &sql) const
{
    QVariantList result;
    if (!m_database || !m_database->isOpen())
        return result;

    QSqlQuery query(*m_database);
    if (!query.exec(sql)) {
        const_cast<AppStore *>(this)->setStatus(
            tr("Database error: %1").arg(query.lastError().text()));
        return result;
    }
    while (query.next()) {
        QVariantMap row;
        const QSqlRecord record = query.record();
        for (int column = 0; column < record.count(); ++column)
            row.insert(record.fieldName(column), query.value(column));
        result.append(row);
    }
    return result;
}

QVariantList AppStore::forms() const
{
    return queryRows(QStringLiteral("SELECT * FROM forms ORDER BY created_at DESC"));
}

QVariantList AppStore::observations() const
{
    return queryRows(QStringLiteral("SELECT * FROM observations ORDER BY timestamp DESC"));
}

QVariantList AppStore::mapPins() const
{
    return queryRows(QStringLiteral(
        "SELECT 'row' AS kind, id, latitude, longitude, COALESCE(species, '') AS label "
        "FROM form_rows WHERE on_map = 1 "
        "UNION ALL "
        "SELECT 'observation', id, latitude, longitude, animal FROM observations WHERE on_map = 1"));
}

QVariantList AppStore::places() const
{
    return queryRows(QStringLiteral("SELECT * FROM places ORDER BY name COLLATE NOCASE"));
}

QVariantList AppStore::locations() const
{
    return queryRows(QStringLiteral("SELECT * FROM locations ORDER BY timestamp"));
}

QVariantList AppStore::rowsForForm(int formId) const
{
    QSqlQuery query(*m_database);
    query.prepare(QStringLiteral("SELECT * FROM form_rows WHERE form_id = ? ORDER BY fishing_activity_date"));
    query.addBindValue(formId);
    if (!query.exec()) {
        const_cast<AppStore *>(this)->setStatus(
            tr("Database error: %1").arg(query.lastError().text()));
        return {};
    }

    QVariantList result;
    while (query.next()) {
        QVariantMap row;
        const QSqlRecord record = query.record();
        for (int column = 0; column < record.count(); ++column)
            row.insert(record.fieldName(column), query.value(column));
        result.append(row);
    }
    return result;
}

QVariantMap AppStore::settings() const
{
    QVariantMap result;
    QSqlQuery query(*m_database);
    if (!query.exec(QStringLiteral("SELECT key, value FROM settings"))) {
        const_cast<AppStore *>(this)->setStatus(
            tr("Database error: %1").arg(query.lastError().text()));
        return result;
    }
    while (query.next())
        result.insert(query.value(0).toString(), query.value(1));
    return result;
}

bool AppStore::saveSettings(const QVariantMap &values)
{
    QSqlQuery query(*m_database);
    query.prepare(QStringLiteral("INSERT INTO settings(key, value) VALUES(?, ?) "
                                 "ON CONFLICT(key) DO UPDATE SET value = excluded.value"));
    for (auto it = values.cbegin(); it != values.cend(); ++it) {
        query.bindValue(0, it.key());
        query.bindValue(1, it.value().toString());
        if (!query.exec()) {
            setStatus(tr("Could not save settings: %1").arg(query.lastError().text()));
            return false;
        }
    }
    setStatus(tr("Settings saved."), false);
    emit dataChanged();
    return true;
}

int AppStore::saveForm(const QVariantMap &form)
{
    if (form.value(QStringLiteral("total_pots_fishing"), 0).toInt() < 0) {
        setStatus(tr("Total pots fishing cannot be negative."));
        return 0;
    }
    QSqlQuery query(*m_database);
    const QVariant id = form.value(QStringLiteral("id"));
    if (id.isValid() && id.toInt() > 0) {
        query.prepare(QStringLiteral(
            "UPDATE forms SET fishery_office=?, email=?, port_of_departure=?, port_of_landing=?, "
            "pln=?, vessel_name=?, owner_master=?, address=?, total_pots_fishing=?, comments=? WHERE id=?"));
        query.addBindValue(form.value(QStringLiteral("fishery_office")));
        query.addBindValue(form.value(QStringLiteral("email")));
        query.addBindValue(form.value(QStringLiteral("port_of_departure")));
        query.addBindValue(form.value(QStringLiteral("port_of_landing")));
        query.addBindValue(form.value(QStringLiteral("pln")));
        query.addBindValue(form.value(QStringLiteral("vessel_name")));
        query.addBindValue(form.value(QStringLiteral("owner_master")));
        query.addBindValue(form.value(QStringLiteral("address")));
        query.addBindValue(form.value(QStringLiteral("total_pots_fishing"), 0));
        query.addBindValue(form.value(QStringLiteral("comments")));
        query.addBindValue(id);
        if (!query.exec()) {
            setStatus(tr("Could not save FISH1 form: %1").arg(query.lastError().text()));
            return 0;
        }
        setStatus(tr("FISH1 form saved."), false);
        emit dataChanged();
        return id.toInt();
    }

    query.prepare(QStringLiteral(
        "INSERT INTO forms(created_at, fishery_office, email, port_of_departure, port_of_landing, "
        "pln, vessel_name, owner_master, address, total_pots_fishing, comments) "
        "VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"));
    query.addBindValue(QDateTime::currentMSecsSinceEpoch());
    query.addBindValue(form.value(QStringLiteral("fishery_office")));
    query.addBindValue(form.value(QStringLiteral("email")));
    query.addBindValue(form.value(QStringLiteral("port_of_departure")));
    query.addBindValue(form.value(QStringLiteral("port_of_landing")));
    query.addBindValue(form.value(QStringLiteral("pln")));
    query.addBindValue(form.value(QStringLiteral("vessel_name")));
    query.addBindValue(form.value(QStringLiteral("owner_master")));
    query.addBindValue(form.value(QStringLiteral("address")));
    query.addBindValue(form.value(QStringLiteral("total_pots_fishing"), 0));
    query.addBindValue(form.value(QStringLiteral("comments")));
    if (!query.exec()) {
        setStatus(tr("Could not create FISH1 form: %1").arg(query.lastError().text()));
        return 0;
    }
    setStatus(tr("FISH1 form created."), false);
    emit dataChanged();
    return query.lastInsertId().toInt();
}

bool AppStore::deleteForm(int formId)
{
    QSqlQuery query(*m_database);
    query.prepare(QStringLiteral("DELETE FROM forms WHERE id = ?"));
    query.addBindValue(formId);
    if (!query.exec()) {
        setStatus(tr("Could not delete FISH1 form: %1").arg(query.lastError().text()));
        return false;
    }
    emit dataChanged();
    setStatus(tr("FISH1 form deleted."), false);
    return true;
}

int AppStore::saveFormRow(const QVariantMap &row)
{
    const QVariantMap defaults{
        {QStringLiteral("latitude"), 0.0},
        {QStringLiteral("longitude"), 0.0},
        {QStringLiteral("mesh_size"), 0},
        {QStringLiteral("weight"), 0.0},
        {QStringLiteral("dis"), false},
        {QStringLiteral("bms"), false},
        {QStringLiteral("number_of_pots_hauled"), 0},
        {QStringLiteral("on_map"), 0}
    };
    QStringList columns{
        QStringLiteral("form_id"), QStringLiteral("fishing_activity_date"),
        QStringLiteral("latitude"), QStringLiteral("longitude"),
        QStringLiteral("ices_area"), QStringLiteral("gear"),
        QStringLiteral("mesh_size"), QStringLiteral("species"),
        QStringLiteral("state"), QStringLiteral("presentation"),
        QStringLiteral("weight"), QStringLiteral("dis"), QStringLiteral("bms"),
        QStringLiteral("number_of_pots_hauled"), QStringLiteral("landing_or_discard_date"),
        QStringLiteral("transporter_reg_etc")
    };
    if (row.contains(QStringLiteral("on_map")))
        columns.append(QStringLiteral("on_map"));
    const double latitude = row.value(QStringLiteral("latitude"), 0.0).toDouble();
    const double longitude = row.value(QStringLiteral("longitude"), 0.0).toDouble();
    if (row.value(QStringLiteral("form_id")).toInt() <= 0
        || latitude < -90.0 || latitude > 90.0
        || longitude < -180.0 || longitude > 180.0
        || row.value(QStringLiteral("weight"), 0.0).toDouble() < 0.0
        || row.value(QStringLiteral("number_of_pots_hauled"), 0).toInt() < 0) {
        setStatus(tr("Check the FISH1 row form, coordinates, weight and pot count."));
        return 0;
    }
    QSqlQuery query(*m_database);
    const QVariant id = row.value(QStringLiteral("id"));
    QStringList placeholders;
    QStringList assignments;
    for (const QString &column : columns) {
        placeholders.append(QStringLiteral("?"));
        assignments.append(column + QStringLiteral(" = ?"));
    }

    if (id.isValid() && id.toInt() > 0) {
        query.prepare(QStringLiteral("UPDATE form_rows SET ") + assignments.join(QLatin1Char(','))
                      + QStringLiteral(" WHERE id = ?"));
    } else {
        query.prepare(QStringLiteral("INSERT INTO form_rows(") + columns.join(QLatin1Char(','))
                      + QStringLiteral(") VALUES(") + placeholders.join(QLatin1Char(',')) + QLatin1Char(')'));
    }
    for (const QString &column : columns)
        query.addBindValue(row.value(column, defaults.value(column)));
    if (id.isValid() && id.toInt() > 0)
        query.addBindValue(id);
    if (!query.exec()) {
        setStatus(tr("Could not save FISH1 row: %1").arg(query.lastError().text()));
        return 0;
    }
    setStatus(tr("FISH1 row saved."), false);
    emit dataChanged();
    return id.isValid() && id.toInt() > 0 ? id.toInt() : query.lastInsertId().toInt();
}

bool AppStore::deleteFormRow(int rowId)
{
    QSqlQuery query(*m_database);
    query.prepare(QStringLiteral("DELETE FROM form_rows WHERE id = ?"));
    query.addBindValue(rowId);
    if (!query.exec()) {
        setStatus(tr("Could not delete FISH1 row: %1").arg(query.lastError().text()));
        return false;
    }
    emit dataChanged();
    setStatus(tr("FISH1 row deleted."), false);
    return true;
}

int AppStore::saveObservation(const QVariantMap &observation)
{
    const QString animal = observation.value(QStringLiteral("animal")).toString().trimmed();
    const double latitude = observation.value(QStringLiteral("latitude")).toDouble();
    const double longitude = observation.value(QStringLiteral("longitude")).toDouble();
    if (animal.isEmpty() || latitude < -90.0 || latitude > 90.0
        || longitude < -180.0 || longitude > 180.0
        || observation.value(QStringLiteral("count"), 1).toInt() < 1) {
        setStatus(tr("Enter an animal, valid coordinates and a count greater than zero."));
        return 0;
    }
    QSqlQuery query(*m_database);
    const QVariant id = observation.value(QStringLiteral("id"));
    const bool update = id.isValid() && id.toInt() > 0;
    const bool withPin = observation.contains(QStringLiteral("on_map"));
    if (update) {
        query.prepare(QStringLiteral(
            "UPDATE observations SET animal=?, species=?, timestamp=?, latitude=?, longitude=?, count=?, notes=?")
            + (withPin ? QStringLiteral(", on_map=?") : QString()) + QStringLiteral(" WHERE id=?"));
    } else {
        query.prepare(QStringLiteral(
            "INSERT INTO observations(animal, species, timestamp, latitude, longitude, count, notes")
            + (withPin ? QStringLiteral(", on_map") : QString()) + QStringLiteral(") VALUES(?, ?, ?, ?, ?, ?, ?")
            + (withPin ? QStringLiteral(", ?") : QString()) + QLatin1Char(')'));
    }
    query.addBindValue(observation.value(QStringLiteral("animal")));
    query.addBindValue(observation.value(QStringLiteral("species")));
    query.addBindValue(observation.value(QStringLiteral("timestamp"), QDateTime::currentMSecsSinceEpoch()));
    query.addBindValue(observation.value(QStringLiteral("latitude")));
    query.addBindValue(observation.value(QStringLiteral("longitude")));
    query.addBindValue(observation.value(QStringLiteral("count"), 1));
    query.addBindValue(observation.value(QStringLiteral("notes")));
    if (withPin)
        query.addBindValue(observation.value(QStringLiteral("on_map")).toBool() ? 1 : 0);
    if (update)
        query.addBindValue(id);
    if (!query.exec()) {
        setStatus(tr("Could not save observation: %1").arg(query.lastError().text()));
        return 0;
    }
    emit dataChanged();
    setStatus(tr("Observation saved."), false);
    return id.isValid() && id.toInt() > 0 ? id.toInt() : query.lastInsertId().toInt();
}

bool AppStore::deleteObservation(int observationId)
{
    QSqlQuery query(*m_database);
    query.prepare(QStringLiteral("DELETE FROM observations WHERE id = ?"));
    query.addBindValue(observationId);
    if (!query.exec()) {
        setStatus(tr("Could not delete observation: %1").arg(query.lastError().text()));
        return false;
    }
    emit dataChanged();
    setStatus(tr("Observation deleted."), false);
    return true;
}

int AppStore::savePlace(const QString &name, double latitude, double longitude)
{
    const QString trimmed = name.trimmed();
    if (trimmed.isEmpty()) {
        setStatus(tr("Enter a name for the place."));
        return -1;
    }
    QSqlQuery query(*m_database);
    query.prepare(QStringLiteral("INSERT INTO places(name, latitude, longitude) VALUES(?, ?, ?)"));
    query.addBindValue(trimmed);
    query.addBindValue(latitude);
    query.addBindValue(longitude);
    if (!query.exec()) {
        setStatus(tr("Could not save place: %1").arg(query.lastError().text()));
        return -1;
    }
    emit placesChanged();
    setStatus(tr("Place saved."), false);
    return query.lastInsertId().toInt();
}

bool AppStore::deletePlace(int placeId)
{
    QSqlQuery query(*m_database);
    query.prepare(QStringLiteral("DELETE FROM places WHERE id = ?"));
    query.addBindValue(placeId);
    if (!query.exec()) {
        setStatus(tr("Could not delete place: %1").arg(query.lastError().text()));
        return false;
    }
    emit placesChanged();
    return true;
}

void AppStore::recordLocation(double latitude, double longitude, double accuracy,
                              qint64 timestamp, bool fishing)
{
    QSqlQuery query(*m_database);
    query.prepare(QStringLiteral(
        "INSERT INTO locations(timestamp, latitude, longitude, accuracy, fishing) VALUES(?, ?, ?, ?, ?)"));
    query.addBindValue(timestamp);
    query.addBindValue(latitude);
    query.addBindValue(longitude);
    query.addBindValue(accuracy);
    query.addBindValue(fishing);
    if (!query.exec()) {
        setStatus(tr("Could not save location: %1").arg(query.lastError().text()));
        return;
    }
    emit dataChanged();
}

QString AppStore::writeExportFile(const QString &destination, const QString &defaultName,
                                  const QString &contents)
{
    QString target;
    if (destination.isEmpty()) {
        const QString exportDirectory = QStandardPaths::writableLocation(QStandardPaths::DocumentsLocation);
        if (!QDir().mkpath(exportDirectory)) {
            setStatus(tr("Could not create the documents directory."));
            return {};
        }
        target = exportDirectory + QLatin1Char('/') + defaultName;
    } else {
        const QUrl url(destination);
        target = url.isLocalFile() ? url.toLocalFile() : destination;
    }

    // Android content:// documents cannot be written through QSaveFile's temp-file rename.
    QFile file(target);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Truncate)
        || file.write(contents.toUtf8()) < 0) {
        setStatus(tr("Could not write CSV: %1").arg(file.errorString()));
        return {};
    }
    file.close();
    return target;
}

QString AppStore::exportTrackCsv(bool lastDayOnly, const QString &destination)
{
    QSqlQuery query(*m_database);
    query.prepare(QStringLiteral(
        "SELECT timestamp, latitude, longitude, accuracy, fishing FROM locations "
        "WHERE timestamp >= ? ORDER BY timestamp"));
    query.addBindValue(lastDayOnly
        ? QDateTime::currentMSecsSinceEpoch() - 24LL * 60 * 60 * 1000
        : 0LL);
    if (!query.exec()) {
        setStatus(tr("Could not export track: %1").arg(query.lastError().text()));
        return {};
    }

    QString csv = QStringLiteral("Timestamp (UTC),Latitude,Longitude,Accuracy (m),Fishing\n");
    int count = 0;
    while (query.next()) {
        const QString time = QDateTime::fromMSecsSinceEpoch(query.value(0).toLongLong(), QTimeZone::UTC)
                                 .toString(Qt::ISODate);
        csv += QStringLiteral("%1,%2,%3,%4,%5\n")
                   .arg(time)
                   .arg(query.value(1).toDouble(), 0, 'f', 6)
                   .arg(query.value(2).toDouble(), 0, 'f', 6)
                   .arg(query.value(3).toDouble(), 0, 'f', 0)
                   .arg(query.value(4).toInt() ? QStringLiteral("Yes") : QStringLiteral("No"));
        ++count;
    }
    if (count == 0) {
        setStatus(tr("There are no track points to export."));
        return {};
    }

    const QString defaultName = QStringLiteral("SIFIDS-track-%1.csv")
        .arg(QDateTime::currentDateTime().toString(QStringLiteral("yyyyMMdd-HHmmss")));
    const QString filePath = writeExportFile(destination, defaultName, csv);
    if (filePath.isEmpty())
        return {};
    setStatus(tr("Track CSV (%1 points) exported to %2").arg(count).arg(filePath), false);
    return filePath;
}

QString AppStore::exportFormCsv(int formId, const QString &destination)
{
    QSqlQuery formQuery(*m_database);
    formQuery.prepare(QStringLiteral("SELECT * FROM forms WHERE id = ?"));
    formQuery.addBindValue(formId);
    if (!formQuery.exec() || !formQuery.next()) {
        setStatus(tr("Could not find the FISH1 form to export."));
        return {};
    }

    const QSqlRecord form = formQuery.record();
    QString csv;
    auto comment = [&csv](const QString &label, const QVariant &value, bool quoted = false) {
        csv += QStringLiteral("# %1: %2\n").arg(label, csvField(value, quoted));
    };
    comment(tr("Fishery Office"), formQuery.value(form.indexOf(QStringLiteral("fishery_office"))), true);
    comment(tr("Email"), formQuery.value(form.indexOf(QStringLiteral("email"))));
    comment(tr("Port of Departure"), formQuery.value(form.indexOf(QStringLiteral("port_of_departure"))));
    comment(tr("Port of Landing"), formQuery.value(form.indexOf(QStringLiteral("port_of_landing"))));
    comment(QStringLiteral("PLN"), formQuery.value(form.indexOf(QStringLiteral("pln"))));
    comment(tr("Vessel Name"), formQuery.value(form.indexOf(QStringLiteral("vessel_name"))));
    comment(tr("Owner/Master"), formQuery.value(form.indexOf(QStringLiteral("owner_master"))));
    comment(tr("Address"), formQuery.value(form.indexOf(QStringLiteral("address"))));
    comment(tr("Total Pots Fishing"), formQuery.value(form.indexOf(QStringLiteral("total_pots_fishing"))));
    comment(tr("Comment and Buyers Information"), formQuery.value(form.indexOf(QStringLiteral("comments"))));
    csv += QLatin1Char('\n');
    csv += QStringLiteral("Fishing Activity Date,Lat/Long,Stat Rect / ICES Area,Gear,Mesh Size,Species,State,Presentation,Weight,DIS,BMS,Number of Pots Hauled,Landing or Discard Date,\"Transporter Reg, Not Transported or Landed to Keeps\"\n");

    QSqlQuery rows(*m_database);
    rows.prepare(QStringLiteral(
        "SELECT fishing_activity_date, latitude, longitude, ices_area, gear, mesh_size, species, "
        "state, presentation, weight, dis, bms, number_of_pots_hauled, landing_or_discard_date, "
        "transporter_reg_etc FROM form_rows WHERE form_id = ? ORDER BY fishing_activity_date"));
    rows.addBindValue(formId);
    if (!rows.exec()) {
        setStatus(tr("Could not export FISH1 rows: %1").arg(rows.lastError().text()));
        return {};
    }
    while (rows.next()) {
        const QString coordinates = coordinateDms(
            rows.value(1).toDouble(), rows.value(2).toDouble());
        QStringList fields{
            csvField(rows.value(0)), csvField(coordinates), csvField(rows.value(3), true),
            csvField(rows.value(4), true), csvField(rows.value(5)), csvField(rows.value(6), true),
            csvField(rows.value(7), true), csvField(rows.value(8), true), csvField(rows.value(9)),
            csvField(rows.value(10)), csvField(rows.value(11)), csvField(rows.value(12)),
            csvField(rows.value(13)), csvField(rows.value(14), true)
        };
        csv += fields.join(QLatin1Char(',')) + QLatin1Char('\n');
    }

    QString fileName = formQuery.value(form.indexOf(QStringLiteral("pln"))).toString();
    if (fileName.isEmpty())
        fileName = QStringLiteral("FISH1-%1").arg(formId);
    fileName.replace(QRegularExpression(QStringLiteral("[^A-Za-z0-9_-]")), QStringLiteral("_"));
    const QString filePath = writeExportFile(destination, fileName + QStringLiteral(".csv"), csv);
    if (filePath.isEmpty())
        return {};
    setStatus(tr("FISH1 CSV exported to %1").arg(filePath), false);
    return filePath;
}

bool AppStore::importAndroidDatabase(const QString &filePath)
{
    const QUrl sourceUrl(filePath);
    const QString localPath = sourceUrl.isLocalFile() ? sourceUrl.toLocalFile() : filePath;
    if (localPath.trimmed().isEmpty() || !QFileInfo::exists(localPath)) {
        setStatus(tr("Select an existing Android SIFIDS database file."));
        return false;
    }

    const QString connectionName = QStringLiteral("legacy-sifids-%1").arg(
        reinterpret_cast<quintptr>(this));
    {
        QSqlDatabase source = QSqlDatabase::addDatabase(
            QStringLiteral("QSQLITE"), connectionName);
        source.setDatabaseName(localPath);
        source.setConnectOptions(QStringLiteral("QSQLITE_OPEN_READONLY"));
        if (!source.open()) {
            const QString error = source.lastError().text();
            source = QSqlDatabase();
            QSqlDatabase::removeDatabase(connectionName);
            setStatus(tr("Could not open Android database: %1").arg(error));
            return false;
        }

        int sourceVersion = 0;
        {
            QSqlQuery versionQuery(source);
            if (versionQuery.exec(QStringLiteral("PRAGMA user_version"))
                && versionQuery.next())
                sourceVersion = versionQuery.value(0).toInt();
        }
        if (sourceVersion != 15) {
            source.close();
            source = QSqlDatabase();
            QSqlDatabase::removeDatabase(connectionName);
            setStatus(tr("This importer currently supports Android database version 15."));
            return false;
        }

        const QStringList requiredTables{
            QStringLiteral("fish_1_form"), QStringLiteral("fish_1_form_row"),
            QStringLiteral("location"), QStringLiteral("Observation"),
            QStringLiteral("observation_class"), QStringLiteral("observation_species")
        };
        QSet<QString> tables;
        QString tableError;
        {
            QSqlQuery tableQuery(source);
            if (!tableQuery.exec(QStringLiteral("SELECT name FROM sqlite_master WHERE type='table'"))) {
                tableError = tableQuery.lastError().text();
            } else {
                while (tableQuery.next())
                    tables.insert(tableQuery.value(0).toString().toLower());
            }
        }
        if (!tableError.isEmpty()) {
            source.close();
            source = QSqlDatabase();
            QSqlDatabase::removeDatabase(connectionName);
            setStatus(tr("Could not inspect Android database: %1").arg(tableError));
            return false;
        }
        for (const QString &required : requiredTables) {
            if (!tables.contains(required.toLower())) {
                source.close();
                source = QSqlDatabase();
                QSqlDatabase::removeDatabase(connectionName);
                setStatus(tr("The selected file is missing the %1 table.").arg(required));
                return false;
            }
        }

        if (!m_database->transaction()) {
            const QString error = m_database->lastError().text();
            source.close();
            source = QSqlDatabase();
            QSqlDatabase::removeDatabase(connectionName);
            setStatus(tr("Could not begin the import transaction: %1").arg(error));
            return false;
        }

        QString failure;
        QHash<int, int> formIds;
        {
        QSqlQuery sourceForms(source);
        QSqlQuery targetForm(*m_database);
        sourceForms.prepare(QStringLiteral(
            "SELECT id, created_at, fishery_office, email, port_of_departure, port_of_landing, "
            "pln, vessel_name, owner_master, address, total_pots_fishing, "
            "comments_and_buyers_information FROM fish_1_form ORDER BY id"));
        targetForm.prepare(QStringLiteral(
            "INSERT INTO forms(created_at, fishery_office, email, port_of_departure, port_of_landing, "
            "pln, vessel_name, owner_master, address, total_pots_fishing, comments) "
            "VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"));
        if (!sourceForms.exec()) {
            failure = sourceForms.lastError().text();
        } else {
            while (sourceForms.next()) {
                targetForm.bindValue(0, sourceForms.value(1));
                for (int i = 2; i <= 10; ++i)
                    targetForm.bindValue(i - 1, sourceForms.value(i));
                targetForm.bindValue(10, sourceForms.value(11));
                if (!targetForm.exec()) {
                    failure = targetForm.lastError().text();
                    break;
                }
                formIds.insert(sourceForms.value(0).toInt(),
                               targetForm.lastInsertId().toInt());
            }
        }

        QSqlQuery sourceRows(source);
        QSqlQuery targetRow(*m_database);
        sourceRows.prepare(QStringLiteral(
            "SELECT r.id, r.form_id, r.fishing_activity_date, r.latitude, r.longitude, r.ices_area, "
            "g.name, r.mesh_size, "
            "CASE WHEN s.id IS NULL THEN NULL ELSE s.species_name || ' (' || s.species_code || ')' END, "
            "st.name, p.name, r.weight, r.dis, r.bms, r.number_of_pots_hauled, "
            "r.landing_or_discard_date, r.transporter_reg_etc "
            "FROM fish_1_form_row r "
            "LEFT JOIN gear g ON g.id = r.gear_id "
            "LEFT JOIN catch_species s ON s.id = r.species_id "
            "LEFT JOIN catch_state st ON st.id = r.state_id "
            "LEFT JOIN catch_presentation p ON p.id = r.presentation_id "
            "ORDER BY r.id"));
        targetRow.prepare(QStringLiteral(
            "INSERT INTO form_rows(form_id, fishing_activity_date, latitude, longitude, ices_area, "
            "gear, mesh_size, species, state, presentation, weight, dis, bms, "
            "number_of_pots_hauled, landing_or_discard_date, transporter_reg_etc) "
            "VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"));
        if (failure.isEmpty() && !sourceRows.exec())
            failure = sourceRows.lastError().text();
        while (failure.isEmpty() && sourceRows.next()) {
            const int legacyFormId = sourceRows.value(1).toInt();
            if (!formIds.contains(legacyFormId)) {
                failure = tr("A FISH1 row refers to a missing form.");
                break;
            }
            targetRow.bindValue(0, formIds.value(legacyFormId));
            targetRow.bindValue(1, sourceRows.value(2).isNull()
                               ? QVariant() : QDateTime::fromMSecsSinceEpoch(
                                     sourceRows.value(2).toLongLong()).toUTC().toString(Qt::ISODate));
            for (int i = 3; i <= 14; ++i)
                targetRow.bindValue(i - 1, sourceRows.value(i));
            targetRow.bindValue(14, sourceRows.value(15).isNull()
                                ? QVariant() : QDateTime::fromMSecsSinceEpoch(
                                      sourceRows.value(15).toLongLong()).toUTC().toString(Qt::ISODate));
            targetRow.bindValue(15, sourceRows.value(16));
            if (!targetRow.exec())
                failure = targetRow.lastError().text();
        }

        QSqlQuery sourceLocations(source);
        QSqlQuery targetLocation(*m_database);
        sourceLocations.prepare(QStringLiteral(
            "SELECT timestamp, latitude, longitude, accuracy, fishing, uploaded "
            "FROM location ORDER BY timestamp"));
        targetLocation.prepare(QStringLiteral(
            "INSERT INTO locations(timestamp, latitude, longitude, accuracy, fishing, uploaded) "
            "VALUES(?, ?, ?, ?, ?, ?)"));
        if (failure.isEmpty() && !sourceLocations.exec())
            failure = sourceLocations.lastError().text();
        while (failure.isEmpty() && sourceLocations.next()) {
            for (int i = 0; i < 6; ++i)
                targetLocation.bindValue(i, sourceLocations.value(i));
            if (!targetLocation.exec())
                failure = targetLocation.lastError().text();
        }

        QSqlQuery sourceObservations(source);
        QSqlQuery targetObservation(*m_database);
        sourceObservations.prepare(QStringLiteral(
            "SELECT c.name, s.name, o.timestamp, o.latitude, o.longitude, o.count, o.notes, o.submitted "
            "FROM Observation o "
            "JOIN observation_class c ON c.id = o.observation_class_id "
            "LEFT JOIN observation_species s ON s.id = o.observation_species_id "
            "ORDER BY o.id"));
        targetObservation.prepare(QStringLiteral(
            "INSERT INTO observations(animal, species, timestamp, latitude, longitude, count, notes, submitted) "
            "VALUES(?, ?, ?, ?, ?, ?, ?, ?)"));
        if (failure.isEmpty() && !sourceObservations.exec())
            failure = sourceObservations.lastError().text();
        while (failure.isEmpty() && sourceObservations.next()) {
            for (int i = 0; i < 8; ++i)
                targetObservation.bindValue(i, sourceObservations.value(i));
            if (!targetObservation.exec())
                failure = targetObservation.lastError().text();
        }
        }

        source.close();
        source = QSqlDatabase();
        QSqlDatabase::removeDatabase(connectionName);
        if (!failure.isEmpty()) {
            m_database->rollback();
            setStatus(tr("Android data import failed; no records were imported: %1").arg(failure));
            return false;
        }
        if (!m_database->commit()) {
            const QString error = m_database->lastError().text();
            m_database->rollback();
            setStatus(tr("Could not commit Android data import: %1").arg(error));
            return false;
        }
    }

    emit dataChanged();
    setStatus(tr("Android forms, rows, observations and track history were imported. "
                 "Review Settings and consent details separately."), false);
    return true;
}

void AppStore::uploadPending(const QString &vesselPln)
{
    if (m_uploading) {
        setStatus(tr("An upload is already in progress."));
        return;
    }
    if (!uploadAllowed())
        return;
    if (vesselPln.trimmed().isEmpty()) {
        setStatus(tr("Set the vessel PLN in Settings before uploading."));
        return;
    }

    QSqlQuery locationsQuery(*m_database);
    if (!locationsQuery.exec(QStringLiteral(
            "SELECT id, timestamp, latitude, longitude, accuracy, fishing "
            "FROM locations WHERE uploaded = 0 ORDER BY timestamp LIMIT 999"))) {
        setStatus(tr("Could not read pending locations: %1").arg(locationsQuery.lastError().text()));
        return;
    }
    QVariantList locationIds;
    QString locationCsv;
    while (locationsQuery.next()) {
        locationIds.append(locationsQuery.value(0));
        const QDateTime timestamp = QDateTime::fromMSecsSinceEpoch(locationsQuery.value(1).toLongLong());
        locationCsv += timestamp.toUTC().toString(QStringLiteral("yyyy-MM-dd'T'HH:mm:ss.zzz'Z'"));
        locationCsv += QLatin1Char(',');
        locationCsv += locationsQuery.value(5).toBool() ? QStringLiteral("1") : QStringLiteral("0");
        locationCsv += QLatin1Char(',');
        locationCsv += QString::number(locationsQuery.value(2).toDouble(), 'f', 8);
        locationCsv += QLatin1Char(',');
        locationCsv += QString::number(locationsQuery.value(3).toDouble(), 'f', 8);
        locationCsv += QLatin1Char(',');
        locationCsv += QString::number(locationsQuery.value(4).toDouble(), 'f', 2);
        locationCsv += QLatin1Char('\n');
    }

    QSqlQuery observationsQuery(*m_database);
    if (!observationsQuery.exec(QStringLiteral(
            "SELECT id, animal, species, timestamp, latitude, longitude, count, notes "
            "FROM observations WHERE submitted = 0 ORDER BY timestamp"))) {
        setStatus(tr("Could not read pending observations: %1").arg(observationsQuery.lastError().text()));
        return;
    }
    QVariantList pendingObservations;
    while (observationsQuery.next()) {
        QVariantMap item;
        item.insert(QStringLiteral("id"), observationsQuery.value(0));
        item.insert(QStringLiteral("animal"), observationsQuery.value(1));
        item.insert(QStringLiteral("species"), observationsQuery.value(2));
        item.insert(QStringLiteral("timestamp"), observationsQuery.value(3));
        item.insert(QStringLiteral("latitude"), observationsQuery.value(4));
        item.insert(QStringLiteral("longitude"), observationsQuery.value(5));
        item.insert(QStringLiteral("count"), observationsQuery.value(6));
        item.insert(QStringLiteral("notes"), observationsQuery.value(7));
        pendingObservations.append(item);
    }

    if (locationIds.isEmpty() && pendingObservations.isEmpty()) {
        setStatus(tr("There is no data waiting to upload."));
        return;
    }

    m_uploading = true;
    emit uploadingChanged();
    setStatus(tr("Uploading pending data…"), false);

    const QUrl endpoint(uploadUrl());
    if (!locationIds.isEmpty()) {
        auto *multipart = new QHttpMultiPart(QHttpMultiPart::FormDataType);
        QHttpPart vesselPart;
        vesselPart.setHeader(QNetworkRequest::ContentDispositionHeader,
                             QVariant(QStringLiteral("form-data; name=\"vessel_name\"")));
        vesselPart.setBody(vesselPln.toUtf8());
        multipart->append(vesselPart);

        QHttpPart tracksPart;
        tracksPart.setHeader(QNetworkRequest::ContentDispositionHeader,
                             QVariant(QStringLiteral("form-data; name=\"tracks\"")));
        tracksPart.setHeader(QNetworkRequest::ContentTypeHeader,
                             QVariant(QStringLiteral("text/plain; charset=utf-8")));
        tracksPart.setBody(locationCsv.toUtf8());
        multipart->append(tracksPart);

        QNetworkRequest request(endpoint);
        QNetworkReply *reply = m_network->post(request, multipart);
        multipart->setParent(reply);
        connect(reply, &QNetworkReply::finished, this, [this, reply, locationIds] {
            const bool success = reply->error() == QNetworkReply::NoError
                && reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt() < 400;
            const QString error = reply->errorString();
            if (success) {
                QSqlQuery mark(*m_database);
                if (!mark.prepare(QStringLiteral("UPDATE locations SET uploaded = 1 WHERE id = ?"))) {
                    setStatus(tr("Upload succeeded, but local status could not be prepared: %1")
                                  .arg(mark.lastError().text()));
                } else {
                    for (const QVariant &id : locationIds) {
                        mark.bindValue(0, id);
                        if (!mark.exec()) {
                            setStatus(tr("Upload succeeded, but a location could not be marked as uploaded: %1")
                                          .arg(mark.lastError().text()));
                            break;
                        }
                    }
                    emit dataChanged();
                }
            } else {
                setStatus(tr("Location upload failed: %1").arg(error));
            }
            reply->deleteLater();
            --m_pendingUploads;
            if (m_pendingUploads == 0)
                finishUploads();
        });
        ++m_pendingUploads;
    }

    for (const QVariant &value : pendingObservations) {
        const QVariantMap observation = value.toMap();
        QJsonObject body{
            {QStringLiteral("pln"), vesselPln},
            {QStringLiteral("animal"), observation.value(QStringLiteral("animal")).toString()},
            {QStringLiteral("species"), observation.value(QStringLiteral("species")).toString()},
            {QStringLiteral("timestamp"), QDateTime::fromMSecsSinceEpoch(
                 observation.value(QStringLiteral("timestamp")).toLongLong())
                 .toUTC().toString(QStringLiteral("yyyy-MM-dd'T'HH:mm'Z'"))},
            {QStringLiteral("latitude"), observation.value(QStringLiteral("latitude")).toDouble()},
            {QStringLiteral("longitude"), observation.value(QStringLiteral("longitude")).toDouble()},
            {QStringLiteral("count"), observation.value(QStringLiteral("count")).toInt()},
            {QStringLiteral("notes"), observation.value(QStringLiteral("notes")).toString()}
        };
        QNetworkRequest request(endpoint);
        request.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("application/json"));
        QNetworkReply *reply = m_network->post(
            request, QJsonDocument(body).toJson(QJsonDocument::Compact));
        const QVariant observationId = observation.value(QStringLiteral("id"));
        connect(reply, &QNetworkReply::finished, this, [this, reply, observationId] {
            const bool success = reply->error() == QNetworkReply::NoError
                && reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt() < 400;
            const QString error = reply->errorString();
            if (success) {
                QSqlQuery mark(*m_database);
                mark.prepare(QStringLiteral("UPDATE observations SET submitted = 1 WHERE id = ?"));
                mark.addBindValue(observationId);
                if (!mark.exec()) {
                    setStatus(tr("Observation uploaded, but local status could not be saved: %1")
                                  .arg(mark.lastError().text()));
                } else {
                    emit dataChanged();
                }
            } else {
                setStatus(tr("Observation upload failed: %1").arg(error));
            }
            reply->deleteLater();
            --m_pendingUploads;
            if (m_pendingUploads == 0)
                finishUploads();
        });
        ++m_pendingUploads;
    }
}

void AppStore::finishUploads()
{
    m_uploading = false;
    emit uploadingChanged();
    if (m_status == tr("Uploading pending data…"))
        setStatus(tr("Pending data upload complete."), false);
}

void AppStore::uploadFormCsv(int formId, const QString &vesselPln)
{
    if (m_uploading) {
        setStatus(tr("An upload is already in progress."));
        return;
    }
    if (!uploadAllowed())
        return;
    if (vesselPln.trimmed().isEmpty()) {
        setStatus(tr("Set the vessel PLN in Settings before uploading."));
        return;
    }
    const QString filePath = exportFormCsv(formId);
    if (filePath.isEmpty())
        return;

    QFile file(filePath);
    if (!file.open(QIODevice::ReadOnly)) {
        setStatus(tr("Could not read exported FISH1 CSV: %1").arg(file.errorString()));
        return;
    }

    auto *multipart = new QHttpMultiPart(QHttpMultiPart::FormDataType);
    QHttpPart vesselPart;
    vesselPart.setHeader(QNetworkRequest::ContentDispositionHeader,
                         QVariant(QStringLiteral("form-data; name=\"vessel_name\"")));
    vesselPart.setBody(vesselPln.toUtf8());
    multipart->append(vesselPart);

    QHttpPart formPart;
    formPart.setHeader(QNetworkRequest::ContentDispositionHeader,
                       QVariant(QStringLiteral("form-data; name=\"fish_1_form\"; filename=\"%1\"")
                                    .arg(QFileInfo(filePath).fileName())));
    formPart.setHeader(QNetworkRequest::ContentTypeHeader,
                       QVariant(QStringLiteral("text/csv; charset=utf-8")));
    formPart.setBody(file.readAll());
    multipart->append(formPart);

    m_uploading = true;
    m_pendingUploads = 1;
    emit uploadingChanged();
    setStatus(tr("Uploading FISH1 form…"), false);

    QNetworkRequest request{QUrl(uploadUrl())};
    QNetworkReply *reply = m_network->post(request, multipart);
    multipart->setParent(reply);
    connect(reply, &QNetworkReply::finished, this, [this, reply] {
        const bool success = reply->error() == QNetworkReply::NoError
            && reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt() < 400;
        if (success)
            setStatus(tr("FISH1 form uploaded."), false);
        else
            setStatus(tr("FISH1 form upload failed: %1").arg(reply->errorString()));
        reply->deleteLater();
        --m_pendingUploads;
        finishUploads();
    });
}

QVariantList AppStore::lookupValues(const QString &table, const QString &nameColumn) const
{
    return queryRows(QStringLiteral("SELECT id, %1 AS name FROM %2 ORDER BY name")
                         .arg(nameColumn, table));
}

QVariantList AppStore::ports() const
{
    return stringList({QStringLiteral("Aberdeen"), QStringLiteral("Anstruther"),
                       QStringLiteral("Ayr"), QStringLiteral("Buckie"),
                       QStringLiteral("Campbeltown"), QStringLiteral("Eyemouth"),
                       QStringLiteral("Fraserburgh"), QStringLiteral("Kirkwall"),
                       QStringLiteral("Lerwick"), QStringLiteral("Mallaig"),
                       QStringLiteral("Oban"), QStringLiteral("Peterhead"),
                       QStringLiteral("Portree"), QStringLiteral("Scrabster"),
                       QStringLiteral("St Andrews"), QStringLiteral("Stornoway"),
                       QStringLiteral("Ullapool"), QStringLiteral("Wick")});
}

QVariantList AppStore::gears() const
{
    return stringList({QStringLiteral("Beam trawls"), QStringLiteral("Boat dredges"),
                       QStringLiteral("Cast nets"), QStringLiteral("Danish seines"),
                       QStringLiteral("Diving"), QStringLiteral("Drifting longlines"),
                       QStringLiteral("Driftnets"), QStringLiteral("Encircling gillnets"),
                       QStringLiteral("Fyke nets"), QStringLiteral("Gillnets"),
                       QStringLiteral("Hand dredges"), QStringLiteral("Hooks and lines"),
                       QStringLiteral("Longlines"), QStringLiteral("Nephrops trawls"),
                       QStringLiteral("Otter trawls"), QStringLiteral("Pots creels"),
                       QStringLiteral("Scottish seines"), QStringLiteral("Trammel nets")});
}

QVariantList AppStore::species() const
{
    return stringList({QStringLiteral("Ballan wrasse (USB)"), QStringLiteral("Brill (BLL)"),
                       QStringLiteral("Brown Crab (CRE)"), QStringLiteral("Cod (COD)"),
                       QStringLiteral("Corkwing Wrasse (YFM)"), QStringLiteral("Haddock (HAD)"),
                       QStringLiteral("Hake (HKE)"), QStringLiteral("Herring (HER)"),
                       QStringLiteral("King Scallop (SCE)"), QStringLiteral("Lobster (LBE)"),
                       QStringLiteral("Mackerel (MAC)"), QStringLiteral("Monkfish (MON)"),
                       QStringLiteral("Nephrops (NEP)"), QStringLiteral("Pollock (POL)"),
                       QStringLiteral("Saithe (POK)"), QStringLiteral("Squid (SQU)"),
                       QStringLiteral("Turbot (TUR)"), QStringLiteral("Whiting (WHG)")});
}

QVariantList AppStore::states() const
{
    return stringList({QStringLiteral("Alive"), QStringLiteral("Boiled"),
                       QStringLiteral("Dried"), QStringLiteral("Fresh"),
                       QStringLiteral("Frozen"), QStringLiteral("Salted"),
                       QStringLiteral("Smoked")});
}

QVariantList AppStore::presentations() const
{
    return stringList({QStringLiteral("Whole"), QStringLiteral("Gutted"),
                       QStringLiteral("Parts"), QStringLiteral("Tails")});
}
