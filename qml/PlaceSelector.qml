import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ColumnLayout {
    id: root

    property string title
    property var places: []
    property string pointName: ""
    property bool hasPoint: false
    property string pointText: ""
    property bool canUseGps: false

    signal placeChosen(real latitude, real longitude, string name)
    signal dropPinRequested()
    signal useGpsRequested()
    signal saveRequested()
    signal deleteRequested(int placeId)

    spacing: 6

    Label { text: root.title; font.bold: true }

    ComboBox {
        id: combo
        Layout.fillWidth: true
        model: root.places
        textRole: "name"
        currentIndex: -1
        displayText: root.pointName !== "" ? root.pointName : qsTr("Choose a saved place…")
        onActivated: (index) => {
            const place = root.places[index]
            root.placeChosen(place.latitude, place.longitude, place.name)
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 6

        Button {
            Layout.fillWidth: true
            text: root.hasPoint && root.pointName === ""
                  ? root.pointText : qsTr("Drop pin on map…")
            onClicked: root.dropPinRequested()
        }
        Button {
            visible: root.canUseGps
            text: qsTr("GPS")
            onClicked: root.useGpsRequested()
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 6
        visible: root.hasPoint

        Button {
            Layout.fillWidth: true
            visible: root.pointName === ""
            text: qsTr("Save as named place…")
            onClicked: root.saveRequested()
        }
        Button {
            Layout.fillWidth: true
            visible: root.pointName !== ""
            text: qsTr("Remove from saved places")
            onClicked: {
                for (let i = 0; i < root.places.length; ++i) {
                    if (root.places[i].name === root.pointName) {
                        root.deleteRequested(root.places[i].id)
                        break
                    }
                }
            }
        }
    }
}
