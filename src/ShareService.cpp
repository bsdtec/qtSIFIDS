#include "ShareService.h"

#if defined(Q_OS_ANDROID)
#include <QJniObject>
#include <QtCore/qcoreapplication_platform.h>
#include <QtCore/qnativeinterface.h>
#elif defined(Q_OS_IOS)
void sifidsPresentShareSheet(const QString &subject, const QString &body);
#else
#include <QClipboard>
#include <QGuiApplication>
#endif

ShareService::ShareService(QObject *parent)
    : QObject(parent)
{
}

void ShareService::shareText(const QString &subject, const QString &body)
{
#if defined(Q_OS_ANDROID)
    // Build and start an ACTION_SEND chooser on the Android UI thread so any
    // installed messaging/email/chat app can be picked, with its own contact list.
    QNativeInterface::QAndroidApplication::runOnAndroidMainThread([subject, body] {
        QJniObject activity = QNativeInterface::QAndroidApplication::context();
        if (!activity.isValid())
            return;

        QJniObject intent("android/content/Intent", "()V");
        intent.callObjectMethod(
            "setAction", "(Ljava/lang/String;)Landroid/content/Intent;",
            QJniObject::getStaticObjectField("android/content/Intent", "ACTION_SEND",
                                             "Ljava/lang/String;").object<jstring>());
        intent.callObjectMethod(
            "setType", "(Ljava/lang/String;)Landroid/content/Intent;",
            QJniObject::fromString(QStringLiteral("text/plain")).object<jstring>());
        intent.callObjectMethod(
            "putExtra", "(Ljava/lang/String;Ljava/lang/String;)Landroid/content/Intent;",
            QJniObject::getStaticObjectField("android/content/Intent", "EXTRA_TEXT",
                                             "Ljava/lang/String;").object<jstring>(),
            QJniObject::fromString(body).object<jstring>());
        intent.callObjectMethod(
            "putExtra", "(Ljava/lang/String;Ljava/lang/String;)Landroid/content/Intent;",
            QJniObject::getStaticObjectField("android/content/Intent", "EXTRA_SUBJECT",
                                             "Ljava/lang/String;").object<jstring>(),
            QJniObject::fromString(subject).object<jstring>());

        QJniObject chooser = QJniObject::callStaticObjectMethod(
            "android/content/Intent", "createChooser",
            "(Landroid/content/Intent;Ljava/lang/CharSequence;)Landroid/content/Intent;",
            intent.object<jobject>(), QJniObject::fromString(subject).object<jstring>());
        chooser.callObjectMethod("addFlags", "(I)Landroid/content/Intent;",
                                 0x10000000 /* FLAG_ACTIVITY_NEW_TASK */);

        activity.callMethod<void>("startActivity", "(Landroid/content/Intent;)V",
                                  chooser.object<jobject>());
    });
#elif defined(Q_OS_IOS)
    sifidsPresentShareSheet(subject, body);
#else
    // Desktop builds have no standard share sheet; copy the message so it can be
    // pasted into whatever app the user wants to send it from.
    QGuiApplication::clipboard()->setText(body);
    emit shareUnavailable(body);
#endif
}
