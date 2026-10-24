import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import QtQuick.Shapes
import QtLocation
import QtPositioning
import Sifids

ApplicationWindow {
    id: window

    width: 1100
    height: 760
    minimumWidth: 360
    minimumHeight: 540
    objectName: "mainWindow"
    visible: true
    title: qsTr("SIFIDS")
    color: "#f4f6f5"

    // The window extends under Android's system bars but contentItem does not, so size dialogs from it.
    readonly property real dialogMaxHeight: contentItem.height - 24

    AppStore {
        id: appStore
    }

    LocationTracker {
        id: locationTracker
    }

    Plugin {
        id: osmPlugin
        name: "osm"
        PluginParameter { name: "osm.mapping.custom.host"; value: "https://tile.openstreetmap.org/" }
        PluginParameter { name: "osm.useragent"; value: "qtSIFIDS/0.1 (com.bsdtec.qtSIFIDS)" }
    }

    property var animals: [
        "Seal", "Whale", "Dolphin", "Porpoise", "John Dory",
        "Basking Shark", "Wrasse", "Triggerfish", "Octopus"
    ]

    header: ColumnLayout {
        spacing: 0

        ToolBar {
            Layout.fillWidth: true
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 16

                Label {
                    text: qsTr("SIFIDS")
                    font.pixelSize: 20
                    font.bold: true
                }

                Label {
                    Layout.fillWidth: true
                    text: appStore.status
                    color: "#58635f"
                    elide: Text.ElideRight
                }

                Button {
                    text: qsTr("Upload pending")
                    enabled: !appStore.uploading
                    onClicked: appStore.uploadPending(appStore.settings().pln || "")
                }
            }
        }

        TabBar {
            id: tabs
            Layout.fillWidth: true
            currentIndex: pages.currentIndex

            TabButton { text: qsTr("Map & tracking") }
            TabButton { text: qsTr("FISH1 forms") }
            TabButton { text: qsTr("Observations") }
            TabButton { text: qsTr("Settings") }

            onCurrentIndexChanged: pages.currentIndex = currentIndex
        }
    }

    StackLayout {
        id: pages
        anchors.fill: parent
        currentIndex: tabs.currentIndex

        Item {
            Map {
                id: map
                anchors.fill: parent
                plugin: osmPlugin
                zoomLevel: 8
                minimumZoomLevel: 2
                maximumZoomLevel: 19
                property geoCoordinate startCentroid
                property bool autoZoomed: false
                property bool following: true

                Component.onCompleted: {
                    for (let i = 0; i < supportedMapTypes.length; ++i) {
                        if (supportedMapTypes[i].style === MapType.CustomMap) {
                            activeMapType = supportedMapTypes[i]
                            break
                        }
                    }
                }

                Connections {
                    target: locationTracker
                    function onPositionChanged() {
                        if (!locationTracker.hasPosition)
                            return
                        if (!map.autoZoomed) {
                            map.autoZoomed = true
                            map.zoomLevel = 14
                        }
                        if (map.following)
                            map.center = QtPositioning.coordinate(locationTracker.latitude,
                                                                  locationTracker.longitude)
                    }
                }

                PinchHandler {
                    id: pinch
                    target: null
                    onActiveChanged: if (active) {
                        map.following = false
                        map.startCentroid = map.toCoordinate(pinch.centroid.position, false)
                    }
                    onScaleChanged: (delta) => {
                        map.zoomLevel += Math.log2(delta)
                        map.alignCoordinateToPoint(map.startCentroid, pinch.centroid.position)
                    }
                    grabPermissions: PointerHandler.TakeOverForbidden
                }

                WheelHandler {
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    onWheel: (event) => map.zoomLevel += event.angleDelta.y / 240
                }

                DragHandler {
                    target: null
                    onTranslationChanged: (delta) => {
                        map.following = false
                        map.pan(-delta.x, -delta.y)
                    }
                }
                center: QtPositioning.coordinate(56.3, -2.8)

                MapQuickItem {
                    visible: locationTracker.hasPosition
                    coordinate: QtPositioning.coordinate(locationTracker.latitude,
                                                        locationTracker.longitude)
                    anchorPoint.x: marker.width / 2
                    anchorPoint.y: marker.height / 2
                    sourceItem: Rectangle {
                        id: marker
                        width: 16
                        height: 16
                        radius: 8
                        color: "#d8493e"
                        border.color: "white"
                        border.width: 2
                    }
                }

                Label {
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: 8
                    text: qsTr("© OpenStreetMap contributors")
                    padding: 5
                    background: Rectangle {
                        color: "#eaffffff"
                        radius: 3
                    }
                    font.pixelSize: 11
                }
            }

            Item {
                id: trackOverlay
                anchors.fill: map
                // Screen-space runs of consecutive track points with the same fishing state.
                property var runs: {
                    map.center; map.zoomLevel; map.bearing; map.tilt; map.width; map.height
                    const cutoff = trackRange.currentIndex === 0 ? Date.now() - 86400000 : 0
                    const points = appStore.locations.filter(p => p.timestamp >= cutoff)
                    const result = []
                    let current = null
                    for (let n = 1; n < points.length; ++n) {
                        const a = points[n - 1], b = points[n]
                        if (b.timestamp - a.timestamp > 600000) {
                            current = null
                            continue
                        }
                        const fishing = b.fishing === 1 || b.fishing === true
                        if (!current || current.fishing !== fishing) {
                            current = { fishing: fishing,
                                        points: [map.fromCoordinate(QtPositioning.coordinate(a.latitude, a.longitude), false)] }
                            result.push(current)
                        }
                        current.points.push(map.fromCoordinate(QtPositioning.coordinate(b.latitude, b.longitude), false))
                    }
                    return result
                }

                Repeater {
                    model: trackOverlay.runs
                    delegate: Shape {
                        required property var modelData
                        anchors.fill: parent
                        ShapePath {
                            strokeColor: modelData.fishing ? "#ff8c00" : "#d8493e"
                            strokeWidth: modelData.fishing ? 4 : 3
                            fillColor: "transparent"
                            capStyle: ShapePath.RoundCap
                            strokeStyle: modelData.fishing ? ShapePath.SolidLine : ShapePath.DashLine
                            dashPattern: [1.5, 2.5]
                            PathPolyline { path: modelData.points }
                        }
                    }
                }
            }

            Button {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.margins: 10
                text: locationTracker.tracking ? qsTr("Tracking ●") : qsTr("Tracking")
                onClicked: trackingDialog.open()
            }

            Button {
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 10
                visible: !map.following && locationTracker.hasPosition
                text: qsTr("Follow")
                onClicked: {
                    map.following = true
                    map.center = QtPositioning.coordinate(locationTracker.latitude,
                                                          locationTracker.longitude)
                }
            }
        }

        Item {
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 16

                RowLayout {
                    Layout.fillWidth: true
                    Label {
                        Layout.fillWidth: true
                        text: qsTr("FISH1 forms")
                        font.pixelSize: 20
                        font.bold: true
                    }
                    Button {
                        text: qsTr("New form")
                        onClicked: {
                            formDialog.formId = 0
                            formDialog.formData = ({})
                            formDialog.open()
                        }
                    }
                }

                ListView {
                    id: formsList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 8
                    clip: true
                    model: appStore.forms

                    delegate: Rectangle {
                        required property var modelData
                        width: formsList.width
                        height: 74
                        radius: 8
                        color: "white"
                        border.color: "#d9e0dc"

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 12
                            Label {
                                Layout.fillWidth: true
                                text: qsTr("%1 — %2\n%3")
                                    .arg(modelData.pln || qsTr("No vessel PLN"))
                                    .arg(modelData.vessel_name || qsTr("Unnamed vessel"))
                                    .arg(modelData.port_of_departure || qsTr("Ports not set"))
                                elide: Text.ElideRight
                            }
                            Button {
                                text: qsTr("Rows")
                                onClicked: {
                                    activeFormId = modelData.id
                                    activeFormTitle = modelData.pln || qsTr("FISH1 form")
                                    rowsDialog.open()
                                }
                            }
                            ToolButton {
                                text: "\u22EE"
                                font.pixelSize: 24
                                onClicked: formMenu.popup()
                                Menu {
                                    id: formMenu
                                    MenuItem {
                                        text: qsTr("Edit")
                                        onTriggered: {
                                            formDialog.formId = modelData.id
                                            formDialog.formData = modelData
                                            formDialog.open()
                                        }
                                    }
                                    MenuItem {
                                        text: qsTr("Export CSV")
                                        onTriggered: {
                                            csvSaveDialog.exportingTrack = false
                                            csvSaveDialog.formId = modelData.id
                                            csvSaveDialog.currentFile = (modelData.pln || "FISH1") + ".csv"
                                            csvSaveDialog.open()
                                        }
                                    }
                                    MenuItem {
                                        text: qsTr("Upload")
                                        enabled: !appStore.uploading && appStore.consented
                                        onTriggered: appStore.uploadFormCsv(
                                                         modelData.id,
                                                         appStore.settings().pln || modelData.pln || "")
                                    }
                                    MenuItem {
                                        text: qsTr("Delete")
                                        onTriggered: {
                                            deleteFormDialog.formId = modelData.id
                                            deleteFormDialog.open()
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        Item {
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 16

                RowLayout {
                    Layout.fillWidth: true
                    Label {
                        Layout.fillWidth: true
                        text: qsTr("Wildlife observations")
                        font.pixelSize: 20
                        font.bold: true
                    }
                    Button {
                        text: qsTr("Record observation")
                        enabled: appStore.consented
                        onClicked: observationDialog.open()
                    }
                }

                ListView {
                    id: observationsList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 8
                    clip: true
                    model: appStore.observations

                    delegate: Rectangle {
                        required property var modelData
                        width: observationsList.width
                        height: 78
                        radius: 8
                        color: "white"
                        border.color: "#d9e0dc"

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 12
                            Label {
                                Layout.fillWidth: true
                                text: qsTr("%1 %2\n%3 • %4 at %5, %6")
                                    .arg(modelData.animal)
                                    .arg(modelData.species ? "— " + modelData.species : "")
                                    .arg(modelData.count)
                                    .arg(new Date(modelData.timestamp).toLocaleString())
                                    .arg(Number(modelData.latitude).toFixed(5))
                                    .arg(Number(modelData.longitude).toFixed(5))
                                elide: Text.ElideRight
                            }
                            Button {
                                text: qsTr("Delete")
                                onClicked: appStore.deleteObservation(modelData.id)
                            }
                        }
                    }
                }
            }
        }

        Item {
            Flickable {
                anchors.fill: parent
                contentWidth: width
                contentHeight: settingsColumn.implicitHeight + 32
                clip: true

                ColumnLayout {
                    id: settingsColumn
                    width: Math.min(parent.width - 32, 640)
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top
                    anchors.topMargin: 16
                    spacing: 12

                    Label {
                        text: qsTr("Vessel and owner defaults")
                        font.pixelSize: 20
                        font.bold: true
                    }

                    TextField { inputMethodHints: Qt.ImhNoPredictiveText; id: prefPln; Layout.fillWidth: true; placeholderText: qsTr("Vessel PLN") }
                    TextField { inputMethodHints: Qt.ImhNoPredictiveText; id: prefVessel; Layout.fillWidth: true; placeholderText: qsTr("Vessel name") }
                    TextField { inputMethodHints: Qt.ImhNoPredictiveText; id: prefOwner; Layout.fillWidth: true; placeholderText: qsTr("Owner/Master name") }
                    TextField { inputMethodHints: Qt.ImhNoPredictiveText; id: prefAddress; Layout.fillWidth: true; placeholderText: qsTr("Owner/Master address") }
                    TextField { inputMethodHints: Qt.ImhNoPredictiveText; id: prefOwnerEmail; Layout.fillWidth: true; placeholderText: qsTr("Owner/Master email") }
                    TextField { inputMethodHints: Qt.ImhNoPredictiveText; id: prefFisheryOffice; Layout.fillWidth: true; placeholderText: qsTr("Fishery office") }
                    TextField { inputMethodHints: Qt.ImhNoPredictiveText; id: prefOfficeEmail; Layout.fillWidth: true; placeholderText: qsTr("Fishery office email") }

                    Label {
                        Layout.fillWidth: true
                        text: qsTr("Consent and privacy: location recording and uploads must only be enabled after the participant has reviewed the project information and consented. Consent capture and withdrawal workflows still need to be ported.")
                        wrapMode: Text.Wrap
                        color: "#58635f"
                    }

                    Button {
                        text: qsTr("Save defaults")
                        onClicked: appStore.saveSettings({
                            pln: prefPln.text,
                            vessel_name: prefVessel.text,
                            owner_master: prefOwner.text,
                            address: prefAddress.text,
                            owner_email: prefOwnerEmail.text,
                            fishery_office: prefFisheryOffice.text,
                            fishery_office_email: prefOfficeEmail.text,
                            consent_name: consentName.text,
                            consent_email: consentEmail.text,
                            consent_phone: consentPhone.text,
                            consent_confirmed: consentConfirmed.checked
                        })
                    }

                    Button {
                        text: qsTr("Import Android database (version 15)…")
                        onClicked: legacyDatabasePicker.open()
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: consentColumn.implicitHeight + 24
                        color: "white"
                        radius: 8
                        border.color: "#d9e0dc"

                        ColumnLayout {
                            id: consentColumn
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 10

                            Label {
                                text: qsTr("Participant information and consent")
                                font.bold: true
                            }
                            Label {
                                Layout.fillWidth: true
                                text: qsTr("SIFIDS records catch activity, wildlife observations, and (when enabled) fishing locations. Location records are stored on this device and are uploaded with the vessel PLN to the SIFIDS service. Review the complete project information and privacy terms before consenting.")
                                wrapMode: Text.Wrap
                            }
                            TextField { inputMethodHints: Qt.ImhNoPredictiveText; id: consentName; Layout.fillWidth: true; placeholderText: qsTr("Participant name") }
                            TextField { inputMethodHints: Qt.ImhNoPredictiveText; id: consentEmail; Layout.fillWidth: true; placeholderText: qsTr("Participant email") }
                            TextField { inputMethodHints: Qt.ImhNoPredictiveText; id: consentPhone; Layout.fillWidth: true; placeholderText: qsTr("Participant phone") }
                            CheckBox {
                                id: consentConfirmed
                                Layout.fillWidth: true
                                text: qsTr("I have read the information and consent to take part, including location recording when I enable tracking.")
                            }
                        }
                    }
                }
            }
        }
    }

    property int activeFormId: 0
    property string activeFormTitle: ""
    property var currentFormRows: []

    Connections {
        target: locationTracker
        function onLocationReceived(latitude, longitude, accuracy, timestamp) {
            appStore.recordLocation(latitude, longitude, accuracy, timestamp, fishingToggle.checked)
        }
    }

    Connections {
        target: appStore
        function onDataChanged() {
            if (!appStore.consented) {
                locationTracker.tracking = false
                fishingToggle.checked = false
            }
        }
    }

    Timer {
        interval: 30 * 60 * 1000
        repeat: true
        running: appStore.consented
        onTriggered: appStore.uploadPending(appStore.settings().pln || "")
    }

    Component.onCompleted: {
        const saved = appStore.settings()
        prefPln.text = saved.pln || ""
        prefVessel.text = saved.vessel_name || ""
        prefOwner.text = saved.owner_master || ""
        prefAddress.text = saved.address || ""
        prefOwnerEmail.text = saved.owner_email || ""
        prefFisheryOffice.text = saved.fishery_office || ""
        prefOfficeEmail.text = saved.fishery_office_email || ""
        consentName.text = saved.consent_name || ""
        consentEmail.text = saved.consent_email || ""
        consentPhone.text = saved.consent_phone || ""
        consentConfirmed.checked = saved.consent_confirmed === "true"
    }

    Dialog {
        id: trackingDialog
        modal: true
        title: qsTr("Location tracking")
        standardButtons: Dialog.Close
        anchors.centerIn: parent
        topMargin: 12
        bottomMargin: 12
        width: Math.min(parent.width - 24, 420)

        contentItem: ColumnLayout {
            spacing: 12
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 12

                Label {
                    Layout.fillWidth: true
                    text: locationTracker.status
                    wrapMode: Text.Wrap
                }

                Button {
                    Layout.fillWidth: true
                    text: locationTracker.tracking
                          ? qsTr("Stop tracking")
                          : qsTr("Start tracking")
                    enabled: appStore.consented || locationTracker.tracking
                    onClicked: locationTracker.tracking = !locationTracker.tracking
                }

                Switch {
                    id: fishingToggle
                    text: qsTr("Currently fishing")
                    enabled: locationTracker.tracking && appStore.consented
                }

                ComboBox {
                    id: trackRange
                    Layout.fillWidth: true
                    model: [qsTr("Last 24 hours"), qsTr("All saved history")]
                }

                Button {
                    Layout.fillWidth: true
                    text: qsTr("Export track to CSV")
                    onClicked: {
                        trackingDialog.close()
                        csvSaveDialog.exportingTrack = true
                        csvSaveDialog.currentFile = "SIFIDS-track.csv"
                        csvSaveDialog.open()
                    }
                }

                Label {
                    Layout.fillWidth: true
                    visible: !appStore.consented
                    text: qsTr("Complete the consent details in Settings before recording location.")
                    color: "#8b3a32"
                    wrapMode: Text.Wrap
                }

                Label {
                    Layout.fillWidth: true
                    visible: locationTracker.hasPosition
                    text: qsTr("Latitude: %1\nLongitude: %2\nAccuracy: %3 m")
                        .arg(locationTracker.latitude.toFixed(6))
                        .arg(locationTracker.longitude.toFixed(6))
                        .arg(locationTracker.accuracy.toFixed(0))
                    wrapMode: Text.Wrap
                }

                Label {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    text: qsTr("Location history is stored locally on this device.")
                    color: "#58635f"
                    wrapMode: Text.Wrap
                }
            }

        }
    }

    Dialog {
        id: formDialog
        property int formId: 0
        property var formData: ({})
        modal: true
        title: formId ? qsTr("Edit FISH1 form") : qsTr("New FISH1 form")
        standardButtons: Dialog.Save | Dialog.Cancel
        anchors.centerIn: parent
        topMargin: 12
        bottomMargin: 12
        height: Math.min(implicitHeight, window.dialogMaxHeight)
        width: Math.min(parent.width - 32, 560)

        onOpened: {
            const defaults = appStore.settings()
            officeField.text = formData.fishery_office || defaults.fishery_office || ""
            officeEmailField.text = formData.email || defaults.fishery_office_email || ""
            plnField.text = formData.pln || defaults.pln || ""
            vesselField.text = formData.vessel_name || defaults.vessel_name || ""
            ownerField.text = formData.owner_master || defaults.owner_master || ""
            addressField.text = formData.address || defaults.address || ""
            departureField.editText = formData.port_of_departure || ""
            landingField.editText = formData.port_of_landing || ""
            potsField.text = formData.total_pots_fishing || "0"
            commentsField.text = formData.comments || ""
        }

        onAccepted: {
            const id = appStore.saveForm({
                id: formId,
                fishery_office: officeField.text,
                email: officeEmailField.text,
                port_of_departure: departureField.editText,
                port_of_landing: landingField.editText,
                pln: plnField.text,
                vessel_name: vesselField.text,
                owner_master: ownerField.text,
                address: addressField.text,
                total_pots_fishing: Number(potsField.text) || 0,
                comments: commentsField.text
            })
            if (id > 0)
                formData = ({})
        }

        Flickable {
            width: parent.width
            height: parent.height
            implicitHeight: formFields.implicitHeight
            contentHeight: formFields.implicitHeight
            clip: true
            ColumnLayout {
                id: formFields
                width: parent.width
                Label { text: qsTr("Fishery office"); font.bold: true; Layout.topMargin: 4 }
                TextField { inputMethodHints: Qt.ImhNoPredictiveText; id: officeField; Layout.fillWidth: true; placeholderText: qsTr("Fishery office") }
                Label { text: qsTr("Fishery office email"); font.bold: true; Layout.topMargin: 4 }
                TextField { inputMethodHints: Qt.ImhNoPredictiveText; id: officeEmailField; Layout.fillWidth: true; placeholderText: qsTr("Fishery office email") }
                Label { text: qsTr("Vessel PLN"); font.bold: true; Layout.topMargin: 4 }
                TextField { inputMethodHints: Qt.ImhNoPredictiveText; id: plnField; Layout.fillWidth: true; placeholderText: qsTr("Vessel PLN") }
                Label { text: qsTr("Vessel name"); font.bold: true; Layout.topMargin: 4 }
                TextField { inputMethodHints: Qt.ImhNoPredictiveText; id: vesselField; Layout.fillWidth: true; placeholderText: qsTr("Vessel name") }
                Label { text: qsTr("Owner/Master"); font.bold: true; Layout.topMargin: 4 }
                TextField { inputMethodHints: Qt.ImhNoPredictiveText; id: ownerField; Layout.fillWidth: true; placeholderText: qsTr("Owner/Master") }
                Label { text: qsTr("Address"); font.bold: true; Layout.topMargin: 4 }
                TextField { inputMethodHints: Qt.ImhNoPredictiveText; id: addressField; Layout.fillWidth: true; placeholderText: qsTr("Address") }
                Label { text: qsTr("Port of departure"); font.bold: true; Layout.topMargin: 4 }
                ComboBox { inputMethodHints: Qt.ImhNoPredictiveText; id: departureField; Layout.fillWidth: true; editable: true; model: appStore.ports; currentIndex: -1; onActiveFocusChanged: if (activeFocus) popup.open() }
                Label { text: qsTr("Port of landing"); font.bold: true; Layout.topMargin: 4 }
                ComboBox { inputMethodHints: Qt.ImhNoPredictiveText; id: landingField; Layout.fillWidth: true; editable: true; model: appStore.ports; currentIndex: -1; onActiveFocusChanged: if (activeFocus) popup.open() }
                Label { text: qsTr("Total pots fishing"); font.bold: true; Layout.topMargin: 4 }
                TextField { id: potsField; Layout.fillWidth: true; placeholderText: qsTr("Total pots fishing"); inputMethodHints: Qt.ImhDigitsOnly | Qt.ImhNoPredictiveText }
                Label { text: qsTr("Comments and buyers information"); font.bold: true; Layout.topMargin: 4 }
                TextArea { inputMethodHints: Qt.ImhNoPredictiveText; id: commentsField; Layout.fillWidth: true; placeholderText: qsTr("Comments and buyers information"); wrapMode: TextEdit.Wrap }
            }
        }
    }

    Dialog {
        id: deleteFormDialog
        property int formId: 0
        modal: true
        title: qsTr("Delete this form and its rows?")
        standardButtons: Dialog.Yes | Dialog.No
        anchors.centerIn: parent
        topMargin: 12
        bottomMargin: 12
        onAccepted: appStore.deleteForm(formId)
    }

    Dialog {
        id: rowsDialog
        modal: true
        title: qsTr("FISH1 rows — %1").arg(activeFormTitle)
        standardButtons: Dialog.Close
        anchors.centerIn: parent
        width: Math.min(parent.width - 24, 800)
        topMargin: 12
        bottomMargin: 12
        height: Math.min(window.dialogMaxHeight, 650)

        onOpened: currentFormRows = appStore.rowsForForm(activeFormId)

        contentItem: ColumnLayout {
            Button {
                Layout.alignment: Qt.AlignRight
                text: qsTr("Add row")
                onClicked: {
                    rowDialog.rowId = 0
                    rowDialog.rowData = ({})
                    rowDialog.open()
                }
            }
            ListView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 6
                clip: true
                model: currentFormRows
                delegate: Rectangle {
                    required property var modelData
                    width: ListView.view.width
                    height: 56
                    radius: 6
                    color: "#f4f6f5"
                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 8
                        Label {
                            Layout.fillWidth: true
                            text: qsTr("%1 — %2, %3 kg\n%4, %5")
                                .arg(modelData.fishing_activity_date || qsTr("Date not set"))
                                .arg(modelData.species || qsTr("Species not set"))
                                .arg(modelData.weight)
                                .arg(modelData.latitude)
                                .arg(modelData.longitude)
                            elide: Text.ElideRight
                        }
                        ToolButton {
                            text: "\u22EE"
                            font.pixelSize: 24
                            onClicked: rowMenu.popup()
                            Menu {
                                id: rowMenu
                                MenuItem {
                                    text: qsTr("Edit")
                                    onTriggered: {
                                        rowDialog.rowId = modelData.id
                                        rowDialog.rowData = modelData
                                        rowDialog.open()
                                    }
                                }
                                MenuItem {
                                    text: qsTr("Delete")
                                    onTriggered: {
                                        appStore.deleteFormRow(modelData.id)
                                        currentFormRows = appStore.rowsForForm(activeFormId)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    Dialog {
        id: rowDialog
        property int rowId: 0
        property var rowData: ({})
        modal: true
        title: rowId ? qsTr("Edit FISH1 row") : qsTr("Add FISH1 row")
        standardButtons: Dialog.Save | Dialog.Cancel
        anchors.centerIn: parent
        topMargin: 12
        bottomMargin: 12
        height: Math.min(implicitHeight, window.dialogMaxHeight)
        width: Math.min(parent.width - 24, 560)

        onOpened: {
            rowDate.text = rowData.fishing_activity_date || new Date().toISOString().slice(0, 10)
            const fillFromGps = rowId === 0 && locationTracker.hasPosition
            rowLatitude.text = rowData.latitude || (fillFromGps ? locationTracker.latitude.toFixed(6) : "")
            rowLongitude.text = rowData.longitude || (fillFromGps ? locationTracker.longitude.toFixed(6) : "")
            rowIces.text = rowData.ices_area || ""
            rowGear.editText = rowData.gear || ""
            rowMesh.text = rowData.mesh_size || ""
            rowSpecies.editText = rowData.species || ""
            rowState.editText = rowData.state || ""
            rowPresentation.editText = rowData.presentation || ""
            rowWeight.text = rowData.weight || ""
            rowPots.text = rowData.number_of_pots_hauled || ""
            rowDis.checked = rowData.dis === true || rowData.dis === 1
            rowBms.checked = rowData.bms === true || rowData.bms === 1
            rowLanding.text = rowData.landing_or_discard_date || ""
            rowTransporter.text = rowData.transporter_reg_etc || ""
        }

        onAccepted: {
            const saved = appStore.saveFormRow({
                id: rowId,
                form_id: activeFormId,
                fishing_activity_date: rowDate.text,
                latitude: Number(rowLatitude.text) || 0,
                longitude: Number(rowLongitude.text) || 0,
                ices_area: rowIces.text,
                gear: rowGear.editText,
                mesh_size: Number(rowMesh.text) || 0,
                species: rowSpecies.editText,
                state: rowState.editText,
                presentation: rowPresentation.editText,
                weight: Number(rowWeight.text) || 0,
                dis: rowDis.checked,
                bms: rowBms.checked,
                number_of_pots_hauled: Number(rowPots.text) || 0,
                landing_or_discard_date: rowLanding.text,
                transporter_reg_etc: rowTransporter.text
            })
            if (saved > 0)
                currentFormRows = appStore.rowsForForm(activeFormId)
        }

        Flickable {
            width: parent.width
            height: parent.height
            implicitHeight: rowFields.implicitHeight
            contentHeight: rowFields.implicitHeight
            clip: true
            ColumnLayout {
                id: rowFields
                width: parent.width
                Label { text: qsTr("Fishing date (YYYY-MM-DD)"); font.bold: true; Layout.topMargin: 4 }
                TextField { inputMethodHints: Qt.ImhNoPredictiveText; id: rowDate; Layout.fillWidth: true; placeholderText: qsTr("Fishing date (YYYY-MM-DD)") }
                Label { text: qsTr("Latitude (decimal degrees)"); font.bold: true; Layout.topMargin: 4 }
                TextField { id: rowLatitude; Layout.fillWidth: true; placeholderText: qsTr("Latitude (decimal degrees)"); inputMethodHints: Qt.ImhFormattedNumbersOnly | Qt.ImhNoPredictiveText }
                Label { text: qsTr("Longitude (decimal degrees)"); font.bold: true; Layout.topMargin: 4 }
                TextField { id: rowLongitude; Layout.fillWidth: true; placeholderText: qsTr("Longitude (decimal degrees)"); inputMethodHints: Qt.ImhFormattedNumbersOnly | Qt.ImhNoPredictiveText }
                Label { text: qsTr("ICES area"); font.bold: true; Layout.topMargin: 4 }
                TextField { inputMethodHints: Qt.ImhNoPredictiveText; id: rowIces; Layout.fillWidth: true; placeholderText: qsTr("ICES area") }
                Label { text: qsTr("Gear"); font.bold: true; Layout.topMargin: 4 }
                ComboBox { inputMethodHints: Qt.ImhNoPredictiveText; id: rowGear; Layout.fillWidth: true; editable: true; model: appStore.gears; currentIndex: -1; onActiveFocusChanged: if (activeFocus) popup.open() }
                Label { text: qsTr("Mesh size (mm)"); font.bold: true; Layout.topMargin: 4 }
                TextField { id: rowMesh; Layout.fillWidth: true; placeholderText: qsTr("Mesh size (mm)"); inputMethodHints: Qt.ImhDigitsOnly | Qt.ImhNoPredictiveText }
                Label { text: qsTr("Species"); font.bold: true; Layout.topMargin: 4 }
                ComboBox { inputMethodHints: Qt.ImhNoPredictiveText; id: rowSpecies; Layout.fillWidth: true; editable: true; model: appStore.species; currentIndex: -1; onActiveFocusChanged: if (activeFocus) popup.open() }
                Label { text: qsTr("State"); font.bold: true; Layout.topMargin: 4 }
                ComboBox { inputMethodHints: Qt.ImhNoPredictiveText; id: rowState; Layout.fillWidth: true; editable: true; model: appStore.states; currentIndex: -1; onActiveFocusChanged: if (activeFocus) popup.open() }
                Label { text: qsTr("Presentation"); font.bold: true; Layout.topMargin: 4 }
                ComboBox { inputMethodHints: Qt.ImhNoPredictiveText; id: rowPresentation; Layout.fillWidth: true; editable: true; model: appStore.presentations; currentIndex: -1; onActiveFocusChanged: if (activeFocus) popup.open() }
                Label { text: qsTr("Weight (kg)"); font.bold: true; Layout.topMargin: 4 }
                TextField { id: rowWeight; Layout.fillWidth: true; placeholderText: qsTr("Weight (kg)"); inputMethodHints: Qt.ImhFormattedNumbersOnly | Qt.ImhNoPredictiveText }
                CheckBox { id: rowDis; text: qsTr("DIS") }
                CheckBox { id: rowBms; text: qsTr("BMS") }
                Label { text: qsTr("Number of pots hauled"); font.bold: true; Layout.topMargin: 4 }
                TextField { id: rowPots; Layout.fillWidth: true; placeholderText: qsTr("Number of pots hauled"); inputMethodHints: Qt.ImhDigitsOnly | Qt.ImhNoPredictiveText }
                Label { text: qsTr("Landing/discard date (YYYY-MM-DD)"); font.bold: true; Layout.topMargin: 4 }
                TextField { inputMethodHints: Qt.ImhNoPredictiveText; id: rowLanding; Layout.fillWidth: true; placeholderText: qsTr("Landing/discard date (YYYY-MM-DD)") }
                Label { text: qsTr("Transporter registration etc."); font.bold: true; Layout.topMargin: 4 }
                TextField { inputMethodHints: Qt.ImhNoPredictiveText; id: rowTransporter; Layout.fillWidth: true; placeholderText: qsTr("Transporter registration etc.") }
            }
        }
    }

    Dialog {
        id: observationDialog
        modal: true
        title: qsTr("Record wildlife observation")
        standardButtons: Dialog.Save | Dialog.Cancel
        anchors.centerIn: parent
        topMargin: 12
        bottomMargin: 12
        width: Math.min(parent.width - 24, 520)

        onOpened: {
            obsLatitude.text = locationTracker.hasPosition ? locationTracker.latitude : ""
            obsLongitude.text = locationTracker.hasPosition ? locationTracker.longitude : ""
            obsDate.text = new Date().toISOString()
        }

        onAccepted: appStore.saveObservation({
            animal: animalBox.currentText,
            species: obsSpecies.text,
            timestamp: Date.parse(obsDate.text) || Date.now(),
            latitude: Number(obsLatitude.text) || 0,
            longitude: Number(obsLongitude.text) || 0,
            count: Number(obsCount.text) || 1,
            notes: obsNotes.text
        })

        ColumnLayout {
            width: parent.width
            Label { text: qsTr("Animal") }
            ComboBox {
                id: animalBox
                Layout.fillWidth: true
                model: window.animals
            }
            TextField { inputMethodHints: Qt.ImhNoPredictiveText; id: obsSpecies; Layout.fillWidth: true; placeholderText: qsTr("Species (optional)") }
            TextField { inputMethodHints: Qt.ImhNoPredictiveText; id: obsDate; Layout.fillWidth: true; placeholderText: qsTr("Date and time (ISO format)") }
            TextField { id: obsLatitude; Layout.fillWidth: true; placeholderText: qsTr("Latitude"); inputMethodHints: Qt.ImhFormattedNumbersOnly | Qt.ImhNoPredictiveText }
            TextField { id: obsLongitude; Layout.fillWidth: true; placeholderText: qsTr("Longitude"); inputMethodHints: Qt.ImhFormattedNumbersOnly | Qt.ImhNoPredictiveText }
            TextField { id: obsCount; Layout.fillWidth: true; placeholderText: qsTr("Number seen"); text: "1"; inputMethodHints: Qt.ImhDigitsOnly | Qt.ImhNoPredictiveText }
            TextArea { inputMethodHints: Qt.ImhNoPredictiveText; id: obsNotes; Layout.fillWidth: true; placeholderText: qsTr("Notes"); wrapMode: TextEdit.Wrap }
        }
    }

    FileDialog {
        id: csvSaveDialog
        property bool exportingTrack: false
        property int formId: 0
        fileMode: FileDialog.SaveFile
        defaultSuffix: "csv"
        nameFilters: [qsTr("CSV files (*.csv)")]
        onAccepted: {
            if (exportingTrack)
                appStore.exportTrackCsv(trackRange.currentIndex === 0, selectedFile.toString())
            else
                appStore.exportFormCsv(formId, selectedFile.toString())
        }
    }

    FileDialog {
        id: legacyDatabasePicker
        title: qsTr("Select an exported SIFIDS Android database")
        nameFilters: [qsTr("SQLite databases (*.sqlite *.db *database*)"), qsTr("All files (*)")]
        onAccepted: appStore.importAndroidDatabase(selectedFile.toString())
    }
}
