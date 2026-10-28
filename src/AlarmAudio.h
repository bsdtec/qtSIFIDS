#pragma once

#include <QObject>
#include <QtQml/qqmlregistration.h>

// Raises and unmutes the device media volume while an alarm sounds, then restores it.
class AlarmAudio : public QObject
{
    Q_OBJECT
    QML_ELEMENT

public:
    explicit AlarmAudio(QObject *parent = nullptr) : QObject(parent) {}

    Q_INVOKABLE void boost();
    Q_INVOKABLE void restore();

private:
    int m_savedVolume = -1;
};
