#include <QGuiApplication>
#include <QQmlApplicationEngine>

#include <cstdlib>

int main(int argc, char *argv[])
{
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
