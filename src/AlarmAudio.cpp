#include "AlarmAudio.h"

#ifdef Q_OS_ANDROID
#include <QCoreApplication>
#include <QJniObject>

namespace {
constexpr jint StreamMusic = 3;
constexpr jint AdjustUnmute = 100;

QJniObject audioManager()
{
    const QJniObject context = QNativeInterface::QAndroidApplication::context();
    if (!context.isValid())
        return {};
    return context.callObjectMethod(
        "getSystemService", "(Ljava/lang/String;)Ljava/lang/Object;",
        QJniObject::fromString(QStringLiteral("audio")).object<jstring>());
}
}

void AlarmAudio::boost()
{
    QJniObject audio = audioManager();
    if (!audio.isValid())
        return;
    if (m_savedVolume < 0)
        m_savedVolume = audio.callMethod<jint>("getStreamVolume", "(I)I", StreamMusic);
    audio.callMethod<void>("adjustStreamVolume", "(III)V", StreamMusic, AdjustUnmute, jint(0));
    const jint maximum = audio.callMethod<jint>("getStreamMaxVolume", "(I)I", StreamMusic);
    audio.callMethod<void>("setStreamVolume", "(III)V", StreamMusic, maximum, jint(0));
}

void AlarmAudio::restore()
{
    if (m_savedVolume < 0)
        return;
    QJniObject audio = audioManager();
    if (audio.isValid())
        audio.callMethod<void>("setStreamVolume", "(III)V", StreamMusic, jint(m_savedVolume), jint(0));
    m_savedVolume = -1;
}
#else
void AlarmAudio::boost() {}
void AlarmAudio::restore() {}
#endif
