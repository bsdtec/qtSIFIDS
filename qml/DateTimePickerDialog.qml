import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// A simple date + time picker: a month calendar grid (there is no Qt.labs.calendar
// in this Qt build) plus two scrollable hour/minute Tumblers, nearest-minute
// resolution. Set `value` then open(); read `pickedValue` from your own onAccepted
// handler (this component intentionally does not define its own onAccepted, so
// as not to clash with the caller's handler on the same signal).
Dialog {
    id: root

    property date value: new Date()
    property string label: ""
    readonly property date pickedValue: new Date(selectedYear, selectedMonth, selectedDay,
                                                  hourTumbler.currentIndex, minuteTumbler.currentIndex)

    property int viewYear: value.getFullYear()
    property int viewMonth: value.getMonth()
    property int selectedYear: value.getFullYear()
    property int selectedMonth: value.getMonth()
    property int selectedDay: value.getDate()

    // Plain reactive scalar properties (not functions, and not a JS-array-backed
    // Repeater model) for the per-month calendar math, re-derived whenever
    // viewYear/viewMonth change. Keeping these as simple property bindings (rather
    // than calling a function, or building an array, from inside each of the 42 day
    // button delegates) is what makes the grid refresh reliably, including on first
    // open and after month navigation.
    readonly property int firstWeekdayOffset: (new Date(viewYear, viewMonth, 1).getDay()
                                                - Qt.locale().firstDayOfWeek + 7) % 7
    readonly property int daysInViewedMonth: new Date(viewYear, viewMonth + 1, 0).getDate()

    function pad2(n) { return (n < 10 ? "0" : "") + n }

    modal: true
    title: label
    standardButtons: Dialog.Ok | Dialog.Cancel
    anchors.centerIn: parent
    topMargin: 12
    bottomMargin: 12
    width: Math.min(parent ? parent.width - 24 : 340, 340)

    onOpened: {
        viewYear = value.getFullYear()
        viewMonth = value.getMonth()
        selectedYear = viewYear
        selectedMonth = viewMonth
        selectedDay = value.getDate()
        hourTumbler.currentIndex = value.getHours()
        minuteTumbler.currentIndex = value.getMinutes()

        // Workaround: on first open, the day grid can come up blank until the
        // viewed month actually changes once (seen on Android; not reproduced in
        // desktop/offscreen testing). Nudge to the previous month and back, each on
        // its own event-loop turn (like the manual "previous month, then this
        // month" fix), before the dialog is visible to the user.
        const previous = new Date(viewYear, viewMonth - 1, 1)
        viewYear = previous.getFullYear()
        viewMonth = previous.getMonth()
        restoreMonthTimer.targetYear = selectedYear
        restoreMonthTimer.targetMonth = selectedMonth
        restoreMonthTimer.start()
    }

    Timer {
        id: restoreMonthTimer
        interval: 0
        property int targetYear
        property int targetMonth
        onTriggered: {
            root.viewYear = targetYear
            root.viewMonth = targetMonth
        }
    }

    contentItem: ColumnLayout {
        spacing: 10

        RowLayout {
            Layout.fillWidth: true
            Button {
                text: "\u2039"
                onClicked: {
                    const previous = new Date(root.viewYear, root.viewMonth - 1, 1)
                    root.viewYear = previous.getFullYear()
                    root.viewMonth = previous.getMonth()
                }
            }
            Label {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                font.bold: true
                text: Qt.locale().monthName(root.viewMonth) + " " + root.viewYear
            }
            Button {
                text: "\u203a"
                onClicked: {
                    const next = new Date(root.viewYear, root.viewMonth + 1, 1)
                    root.viewYear = next.getFullYear()
                    root.viewMonth = next.getMonth()
                }
            }
        }

        GridLayout {
            Layout.fillWidth: true
            columns: 7
            columnSpacing: 2
            rowSpacing: 2

            Repeater {
                model: 7
                delegate: Label {
                    required property int index
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    font.bold: true
                    text: Qt.locale().dayName((Qt.locale().firstDayOfWeek + index) % 7, Locale.ShortFormat)
                }
            }

            Repeater {
                model: 42
                delegate: Button {
                    required property int index
                    readonly property int dayNumber: index - root.firstWeekdayOffset + 1
                    readonly property bool inMonth: dayNumber >= 1 && dayNumber <= root.daysInViewedMonth
                    readonly property bool isSelected: inMonth && dayNumber === root.selectedDay
                        && root.viewMonth === root.selectedMonth && root.viewYear === root.selectedYear

                    Layout.fillWidth: true
                    Layout.preferredHeight: 36
                    text: inMonth ? dayNumber : ""
                    enabled: inMonth
                    highlighted: isSelected
                    onClicked: {
                        root.selectedYear = root.viewYear
                        root.selectedMonth = root.viewMonth
                        root.selectedDay = dayNumber
                    }
                }
            }
        }

        Label {
            Layout.alignment: Qt.AlignHCenter
            text: qsTr("Time")
            font.bold: true
        }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 4

            Tumbler {
                id: hourTumbler
                implicitWidth: 56
                implicitHeight: 120
                model: 24
                wrap: true
                delegate: Label {
                    required property int modelData
                    required property int index
                    text: root.pad2(modelData)
                    font.pixelSize: 18
                    opacity: 1.0 - Math.abs(Tumbler.displacement) / (hourTumbler.visibleItemCount / 2)
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
            }
            Label { text: ":"; font.pixelSize: 18 }
            Tumbler {
                id: minuteTumbler
                implicitWidth: 56
                implicitHeight: 120
                model: 60
                wrap: true
                delegate: Label {
                    required property int modelData
                    required property int index
                    text: root.pad2(modelData)
                    font.pixelSize: 18
                    opacity: 1.0 - Math.abs(Tumbler.displacement) / (minuteTumbler.visibleItemCount / 2)
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
            }
        }
    }
}
