#include <QGuiApplication>
#include <QQmlApplicationEngine>

#include <QtLogging>

#include <cstdlib>

namespace {
QtMessageHandler previousHandler = nullptr;

// The OSM plugin warns about Qt's optional provider repository, which is unused with the custom tile host.
void filteredMessageHandler(QtMsgType type, const QMessageLogContext &context, const QString &message)
{
    if (message.startsWith(QLatin1String("QGeoTileProviderOsm: Tileserver disabled"))
        || message.startsWith(QLatin1String("QGeoTileFetcherOsm: all providers resolved")))
        return;
    if (previousHandler)
        previousHandler(type, context, message);
}
}

int main(int argc, char *argv[])
{
    previousHandler = qInstallMessageHandler(filteredMessageHandler);
    QGuiApplication app(argc, argv);
    app.setApplicationName(QStringLiteral("qtSIFIDS"));
    app.setOrganizationName(QStringLiteral("StAResComp"));
    app.setDesktopFileName(QStringLiteral("com.bsdtec.qtSIFIDS"));

    QQmlApplicationEngine engine;
    engine.loadFromModule(QStringLiteral("Sifids"), QStringLiteral("Main"));

    if (engine.rootObjects().isEmpty())
        return EXIT_FAILURE;

    return app.exec();
}
