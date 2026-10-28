#pragma once

#include <QObject>
#include <QString>
#include <QtQml/qqmlregistration.h>

// Hands text off to the platform's native share sheet (Android's chooser, iOS's
// UIActivityViewController) so the user can pick any installed app and contact at
// send time. There is no cross-platform API for this, so the implementation is
// per-platform; see ShareService.cpp and ShareService_ios.mm.
class ShareService : public QObject
{
    Q_OBJECT
    QML_ELEMENT

public:
    explicit ShareService(QObject *parent = nullptr);

    Q_INVOKABLE void shareText(const QString &subject, const QString &body);

signals:
    // Emitted on platforms without a native share sheet (desktop builds); the text
    // has already been copied to the clipboard.
    void shareUnavailable(const QString &body);
};
