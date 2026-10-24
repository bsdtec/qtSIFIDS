import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
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

    AppStore {
        id: appStore
    }

    LocationTracker {
        id: locationTracker
    }

    Plugin {
        id: osmPlugin
        name: "osm"
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
            RowLayout {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 14

                Rectangle {
                    Layout.preferredWidth: 270
                    Layout.fillHeight: true
                    Layout.minimumWidth: 210
                    radius: 12
                    color: "white"
                    border.color: "#d9e0dc"

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 16
                        spacing: 12

                        Label {
                            text: qsTr("Location tracking")
                            font.pixelSize: 18
                            font.bold: true
                        }

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
                            verticalAlignment: Text.AlignBottom
                            text: qsTr("Location history is stored locally on this device.")
                            color: "#58635f"
                            wrapMode: Text.Wrap
                        }
                    }
                }

                Map {
                    id: map
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumWidth: 150
                    plugin: osmPlugin
                    zoomLevel: 8
                    center: locationTracker.hasPosition
                            ? QtPositioning.coordinate(locationTracker.latitude,
                                                       locationTracker.longitude)
                            : QtPositioning.coordinate(56.3, -2.8)

                    MapPolyline {
                        line.width: 3
                        line.color: "#d8493e"
                        path: appStore.locations.filter(function(point) {
                            return trackRange.currentIndex !== 0
                                   || point.timestamp >= Date.now() - 86400000
                        }).map(function(point) {
                            return QtPositioning.coordinate(point.latitude, point.longitude)
                        })
                    }

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
                            Button {
                                text: qsTr("Edit")
                                onClicked: {
                                    formDialog.formId = modelData.id
                                    formDialog.formData = modelData
                                    formDialog.open()
                                }
                            }
                            Button {
                                text: qsTr("CSV")
                                onClicked: {
                                    appStore.exportFormCsv(modelData.id)
                                }
                            }
                            Button {
                                text: qsTr("Upload")
                                enabled: !appStore.uploading && appStore.consented
                                onClicked: appStore.uploadFormCsv(
                                               modelData.id,
                                               appStore.settings().pln || modelData.pln || "")
                            }
                            Button {
                                text: qsTr("Delete")
                                onClicked: {
                                    deleteFormDialog.formId = modelData.id
                                    deleteFormDialog.open()
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

                    TextField { id: prefPln; Layout.fillWidth: true; placeholderText: qsTr("Vessel PLN") }
                    TextField { id: prefVessel; Layout.fillWidth: true; placeholderText: qsTr("Vessel name") }
                    TextField { id: prefOwner; Layout.fillWidth: true; placeholderText: qsTr("Owner/Master name") }
                    TextField { id: prefAddress; Layout.fillWidth: true; placeholderText: qsTr("Owner/Master address") }
                    TextField { id: prefOwnerEmail; Layout.fillWidth: true; placeholderText: qsTr("Owner/Master email") }
                    TextField { id: prefFisheryOffice; Layout.fillWidth: true; placeholderText: qsTr("Fishery office") }
                    TextField { id: prefOfficeEmail; Layout.fillWidth: true; placeholderText: qsTr("Fishery office email") }

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
                            TextField { id: consentName; Layout.fillWidth: true; placeholderText: qsTr("Participant name") }
                            TextField { id: consentEmail; Layout.fillWidth: true; placeholderText: qsTr("Participant email") }
                            TextField { id: consentPhone; Layout.fillWidth: true; placeholderText: qsTr("Participant phone") }
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
        id: formDialog
        property int formId: 0
        property var formData: ({})
        modal: true
        title: formId ? qsTr("Edit FISH1 form") : qsTr("New FISH1 form")
        standardButtons: Dialog.Save | Dialog.Cancel
        anchors.centerIn: parent
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
                port_of_departure: departureField.currentText,
                port_of_landing: landingField.currentText,
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
            height: Math.min(parent.height, 500)
            contentHeight: formFields.implicitHeight
            clip: true
            ColumnLayout {
                id: formFields
                width: parent.width
                TextField { id: officeField; Layout.fillWidth: true; placeholderText: qsTr("Fishery office") }
                TextField { id: officeEmailField; Layout.fillWidth: true; placeholderText: qsTr("Fishery office email") }
                TextField { id: plnField; Layout.fillWidth: true; placeholderText: qsTr("Vessel PLN") }
                TextField { id: vesselField; Layout.fillWidth: true; placeholderText: qsTr("Vessel name") }
                TextField { id: ownerField; Layout.fillWidth: true; placeholderText: qsTr("Owner/Master") }
                TextField { id: addressField; Layout.fillWidth: true; placeholderText: qsTr("Address") }
                ComboBox { id: departureField; Layout.fillWidth: true; editable: true; model: appStore.ports; currentIndex: -1 }
                ComboBox { id: landingField; Layout.fillWidth: true; editable: true; model: appStore.ports; currentIndex: -1 }
                TextField { id: potsField; Layout.fillWidth: true; placeholderText: qsTr("Total pots fishing"); inputMethodHints: Qt.ImhDigitsOnly }
                TextArea { id: commentsField; Layout.fillWidth: true; placeholderText: qsTr("Comments and buyers information"); wrapMode: TextEdit.Wrap }
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
        onAccepted: appStore.deleteForm(formId)
    }

    Dialog {
        id: rowsDialog
        modal: true
        title: qsTr("FISH1 rows — %1").arg(activeFormTitle)
        standardButtons: Dialog.Close
        anchors.centerIn: parent
        width: Math.min(parent.width - 24, 800)
        height: Math.min(parent.height - 24, 650)

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
                        Button {
                            text: qsTr("Edit")
                            onClicked: {
                                rowDialog.rowId = modelData.id
                                rowDialog.rowData = modelData
                                rowDialog.open()
                            }
                        }
                        Button {
                            text: qsTr("Delete")
                            onClicked: {
                                appStore.deleteFormRow(modelData.id)
                                currentFormRows = appStore.rowsForForm(activeFormId)
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
        width: Math.min(parent.width - 24, 560)

        onOpened: {
            rowDate.text = rowData.fishing_activity_date || new Date().toISOString().slice(0, 10)
            rowLatitude.text = rowData.latitude || ""
            rowLongitude.text = rowData.longitude || ""
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
                gear: rowGear.currentText,
                mesh_size: Number(rowMesh.text) || 0,
                species: rowSpecies.currentText,
                state: rowState.currentText,
                presentation: rowPresentation.currentText,
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
            height: Math.min(parent.height, 520)
            contentHeight: rowFields.implicitHeight
            clip: true
            ColumnLayout {
                id: rowFields
                width: parent.width
                TextField { id: rowDate; Layout.fillWidth: true; placeholderText: qsTr("Fishing date (YYYY-MM-DD)") }
                TextField { id: rowLatitude; Layout.fillWidth: true; placeholderText: qsTr("Latitude (decimal degrees)"); inputMethodHints: Qt.ImhFormattedNumbersOnly }
                TextField { id: rowLongitude; Layout.fillWidth: true; placeholderText: qsTr("Longitude (decimal degrees)"); inputMethodHints: Qt.ImhFormattedNumbersOnly }
                TextField { id: rowIces; Layout.fillWidth: true; placeholderText: qsTr("ICES area") }
                ComboBox { id: rowGear; Layout.fillWidth: true; editable: true; model: appStore.gears; currentIndex: -1 }
                TextField { id: rowMesh; Layout.fillWidth: true; placeholderText: qsTr("Mesh size (mm)"); inputMethodHints: Qt.ImhDigitsOnly }
                ComboBox { id: rowSpecies; Layout.fillWidth: true; editable: true; model: appStore.species; currentIndex: -1 }
                ComboBox { id: rowState; Layout.fillWidth: true; editable: true; model: appStore.states; currentIndex: -1 }
                ComboBox { id: rowPresentation; Layout.fillWidth: true; editable: true; model: appStore.presentations; currentIndex: -1 }
                TextField { id: rowWeight; Layout.fillWidth: true; placeholderText: qsTr("Weight (kg)"); inputMethodHints: Qt.ImhFormattedNumbersOnly }
                CheckBox { id: rowDis; text: qsTr("DIS") }
                CheckBox { id: rowBms; text: qsTr("BMS") }
                TextField { id: rowPots; Layout.fillWidth: true; placeholderText: qsTr("Number of pots hauled"); inputMethodHints: Qt.ImhDigitsOnly }
                TextField { id: rowLanding; Layout.fillWidth: true; placeholderText: qsTr("Landing/discard date (YYYY-MM-DD)") }
                TextField { id: rowTransporter; Layout.fillWidth: true; placeholderText: qsTr("Transporter registration etc.") }
            }
        }
    }

    Dialog {
        id: observationDialog
        modal: true
        title: qsTr("Record wildlife observation")
        standardButtons: Dialog.Save | Dialog.Cancel
        anchors.centerIn: parent
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
            TextField { id: obsSpecies; Layout.fillWidth: true; placeholderText: qsTr("Species (optional)") }
            TextField { id: obsDate; Layout.fillWidth: true; placeholderText: qsTr("Date and time (ISO format)") }
            TextField { id: obsLatitude; Layout.fillWidth: true; placeholderText: qsTr("Latitude"); inputMethodHints: Qt.ImhFormattedNumbersOnly }
            TextField { id: obsLongitude; Layout.fillWidth: true; placeholderText: qsTr("Longitude"); inputMethodHints: Qt.ImhFormattedNumbersOnly }
            TextField { id: obsCount; Layout.fillWidth: true; placeholderText: qsTr("Number seen"); text: "1"; inputMethodHints: Qt.ImhDigitsOnly }
            TextArea { id: obsNotes; Layout.fillWidth: true; placeholderText: qsTr("Notes"); wrapMode: TextEdit.Wrap }
        }
    }

    FileDialog {
        id: legacyDatabasePicker
        title: qsTr("Select an exported SIFIDS Android database")
        nameFilters: [qsTr("SQLite databases (*.sqlite *.db *database*)"), qsTr("All files (*)")]
        onAccepted: appStore.importAndroidDatabase(selectedFile.toString())
    }
}
