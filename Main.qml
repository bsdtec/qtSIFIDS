import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
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
    color: bgColor

    // The window background is custom, so tell the controls style which theme to use for text and fields.
    Material.theme: dark ? Material.Dark : Material.Light
    Material.background: bgColor
    palette.window: bgColor
    palette.windowText: dark ? "#e6ebe8" : "#1e2321"
    palette.text: palette.windowText
    palette.buttonText: palette.windowText
    palette.base: dark ? "#2b312e" : "white"
    palette.placeholderText: mutedText

    readonly property bool dark: Application.styleHints.colorScheme === Qt.ColorScheme.Dark
    readonly property color bgColor: dark ? "#1e2321" : "#f4f6f5"
    readonly property color cardColor: dark ? "#2b312e" : "white"
    readonly property color cardBorder: dark ? "#434b47" : "#d9e0dc"
    readonly property color mutedText: dark ? "#aab5b0" : "#58635f"
    readonly property color errorText: dark ? "#ff9a90" : "#8b3a32"

    // The window extends under Android's system bars but contentItem does not, so size dialogs from it.
    readonly property real dialogMaxHeight: contentItem.height - 24

    AppStore {
        id: appStore
    }

    LocationTracker {
        id: locationTracker
    }

    SailPlan {
        id: sailPlan
        onErrorOccurred: (message) => sailPlanErrorDialog.showError(message)
        onShareRequested: (subject, body) => shareService.shareText(subject, body)
    }

    ShareService {
        id: shareService
        onShareUnavailable: (body) => shareCopiedDialog.open()
    }

    Plugin {
        id: osmPlugin
        name: "osm"
        PluginParameter { name: "osm.mapping.custom.host"; value: "https://tile.openstreetmap.org/" }
        PluginParameter { name: "osm.useragent"; value: "qtSIFIDS/0.1 (com.bsdtec.qtSIFIDS)" }
    }

    // Fishing is only meaningful while tracking, so it resets when tracking stops.
    property bool fishing: false
    property bool addMenuOpen: false
    readonly property bool dialogOpen: sailPlanDialog.visible || simulatorDialog.visible
        || rowDialog.visible || observationDialog.visible
        || statusDialog.visible || mapNoticeDialog.visible || potDialog.visible

    function showNotice(message) {
        mapNoticeLabel.text = message
        mapNoticeDialog.open()
    }

    // Active form: the one last opened from the forms tab, else the newest.
    function activeFormForMap() {
        const forms = appStore.forms
        for (let i = 0; i < forms.length; ++i) {
            if (forms[i].id === activeFormId)
                return forms[i]
        }
        return forms.length > 0 ? forms[0] : null
    }

    function addFishRowFromMap() {
        const form = activeFormForMap()
        if (!form) {
            showNotice(qsTr("Create a FISH1 form in the FISH1 forms tab first."))
            return
        }
        if (!locationTracker.hasPosition) {
            showNotice(qsTr("Waiting for a location fix before a pin can be dropped."))
            return
        }
        activeFormId = form.id
        activeFormTitle = form.pln || qsTr("FISH1 form")
        rowDialog.rowId = 0
        rowDialog.rowData = ({})
        rowDialog.pinOnSave = true
        rowDialog.open()
    }

    function editFishRowFromMap(rowId) {
        const row = appStore.pinRecord("row", rowId)
        if (!row.id)
            return
        activeFormId = row.form_id
        const form = activeFormForMap()
        activeFormTitle = form ? (form.pln || qsTr("FISH1 form")) : qsTr("FISH1 form")
        rowDialog.rowId = row.id
        rowDialog.rowData = row
        rowDialog.open()
    }

    function editObservationFromMap(observationId) {
        const observation = appStore.pinRecord("observation", observationId)
        if (!observation.id)
            return
        observationDialog.obsId = observation.id
        observationDialog.obsData = observation
        observationDialog.open()
    }

    function dropPotFromMap() {
        if (!locationTracker.hasPosition) {
            showNotice(qsTr("Waiting for a location fix before a pot can be marked."))
            return
        }
        appStore.dropPot(locationTracker.latitude, locationTracker.longitude)
    }

    function addObservationFromMap() {
        if (!appStore.consented) {
            showNotice(qsTr("Complete the participant consent details in Settings before recording observations."))
            return
        }
        if (!locationTracker.hasPosition) {
            showNotice(qsTr("Waiting for a location fix before a pin can be dropped."))
            return
        }
        observationDialog.pinOnSave = true
        observationDialog.open()
    }

    Connections {
        target: locationTracker
        function onTrackingChanged() {
            if (!locationTracker.tracking)
                window.fishing = false
        }
    }

    // Small translucent round map button; children are drawn centred using glyphColor.
    component MapButton: AbstractButton {
        id: control
        property bool active: false
        property color activeColor: "#1976d2"
        readonly property color glyphColor: active ? "white" : (window.dark ? "#e6ebe8" : "#37413d")
        default property alias glyph: glyphHolder.data

        implicitWidth: 48
        implicitHeight: 48

        background: Rectangle {
            radius: width / 2
            color: control.active
                   ? Qt.rgba(control.activeColor.r, control.activeColor.g, control.activeColor.b, 0.85)
                   : (window.dark ? "#992b312e" : "#b3ffffff")
            border.width: 1
            border.color: control.active ? "white" : (window.dark ? "#66ffffff" : "#33000000")
            scale: control.down ? 0.92 : 1
        }
        contentItem: Item {
            id: glyphHolder
        }
    }

    component MapPin: Item {
        property color pinColor: "#ff8c00"
        property string letter: ""
        signal tapped()
        width: 28
        height: 40
        Rectangle {
            width: 14; height: 14
            x: 7; y: 24
            rotation: 45
            color: parent.pinColor
        }
        Rectangle {
            width: 28; height: 28
            radius: 14
            color: parent.pinColor
            border.color: "white"
            border.width: 2
            Text {
                anchors.centerIn: parent
                text: parent.parent.letter
                color: "white"
                font.bold: true
                font.pixelSize: 14
            }
        }
        TapHandler {
            onTapped: parent.tapped()
        }
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

                Button {
                    text: qsTr("Upload pending")
                    visible: appStore.uploadEnabled
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
                property string pickingMode: ""

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
                            map.following = true
                        }
                        if (map.following)
                            map.center = QtPositioning.coordinate(locationTracker.latitude,
                                                                  locationTracker.longitude)
                    }
                }

                PinchHandler {
                    id: pinch
                    enabled: !window.dialogOpen
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
                    enabled: !window.dialogOpen
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    onWheel: (event) => map.zoomLevel += event.angleDelta.y / 240
                }

                DragHandler {
                    enabled: !window.dialogOpen
                    target: null
                    onTranslationChanged: (delta) => {
                        map.following = false
                        map.pan(-delta.x, -delta.y)
                    }
                }
                TapHandler {
                    acceptedDevices: PointerDevice.Mouse
                    acceptedButtons: Qt.LeftButton
                    onDoubleTapped: (point) => map.zoomAt(point.position, 1)
                }

                TapHandler {
                    acceptedDevices: PointerDevice.Mouse
                    acceptedButtons: Qt.RightButton
                    onDoubleTapped: (point) => map.zoomAt(point.position, -1)
                }

                TapHandler {
                    id: pointPicker
                    enabled: map.pickingMode !== ""
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchScreen
                    onTapped: (point) => {
                        const coordinate = map.toCoordinate(point.position, false)
                        if (map.pickingMode === "departure")
                            sailPlan.setDeparturePoint(coordinate.latitude, coordinate.longitude)
                        else if (map.pickingMode === "destination")
                            sailPlan.setDestinationPoint(coordinate.latitude, coordinate.longitude)
                        const picked = map.pickingMode
                        map.pickingMode = ""
                        if (picked === "simulator") {
                            locationTracker.startSimulation(coordinate.latitude, coordinate.longitude)
                            map.following = true
                            simulatorDialog.open()
                        } else {
                            sailPlanDialog.open()
                        }
                    }
                }

                function zoomAt(pos, step) {
                    const anchor = map.toCoordinate(pos, false)
                    following = false
                    zoomLevel += step
                    alignCoordinateToPoint(anchor, pos)
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

                MapItemView {
                    model: appStore.mapPins
                    delegate: MapQuickItem {
                        required property var modelData
                        coordinate: QtPositioning.coordinate(modelData.latitude, modelData.longitude)
                        anchorPoint.x: 14
                        anchorPoint.y: 40
                        sourceItem: MapPin {
                            pinColor: modelData.kind === "row" ? "#ff8c00"
                                      : modelData.kind === "pot" ? "#6d4c41" : "#00838f"
                            letter: modelData.kind === "row" ? "F"
                                    : modelData.kind === "pot" ? "P" : "O"
                            onTapped: {
                                if (modelData.kind === "row")
                                    window.editFishRowFromMap(modelData.id)
                                else if (modelData.kind === "observation")
                                    window.editObservationFromMap(modelData.id)
                                else if (modelData.kind === "pot") {
                                    potDialog.potId = modelData.id
                                    potDialog.potTime = new Date(Number(modelData.label))
                                    potDialog.potLatitude = modelData.latitude
                                    potDialog.potLongitude = modelData.longitude
                                    potDialog.open()
                                }
                            }
                        }
                    }
                }

                MapQuickItem {
                    visible: sailPlan.hasDeparturePoint
                    coordinate: QtPositioning.coordinate(sailPlan.departureLatitude, sailPlan.departureLongitude)
                    anchorPoint.x: departurePin.width / 2
                    anchorPoint.y: departurePin.height
                    sourceItem: Item {
                        id: departurePin
                        width: 28
                        height: 40
                        Rectangle {
                            width: 14; height: 14
                            x: 7; y: 24
                            rotation: 45
                            color: "#2e7d32"
                        }
                        Rectangle {
                            width: 28; height: 28
                            radius: 14
                            color: "#2e7d32"
                            border.color: "white"
                            border.width: 2
                            Text {
                                anchors.centerIn: parent
                                text: "D"
                                color: "white"
                                font.bold: true
                                font.pixelSize: 14
                            }
                        }
                    }
                }

                MapQuickItem {
                    visible: sailPlan.hasDestinationPoint
                    coordinate: QtPositioning.coordinate(sailPlan.destinationLatitude, sailPlan.destinationLongitude)
                    anchorPoint.x: destinationPin.width / 2
                    anchorPoint.y: destinationPin.height
                    sourceItem: Item {
                        id: destinationPin
                        width: 28
                        height: 40
                        Rectangle {
                            width: 14; height: 14
                            x: 7; y: 24
                            rotation: 45
                            color: "#c62828"
                        }
                        Rectangle {
                            width: 28; height: 28
                            radius: 14
                            color: "#c62828"
                            border.color: "white"
                            border.width: 2
                            Text {
                                anchors.centerIn: parent
                                text: "A"
                                color: "white"
                                font.bold: true
                                font.pixelSize: 14
                            }
                        }
                    }
                }

                Label {
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: 8
                    text: qsTr("© OpenStreetMap contributors")
                    padding: 5
                    color: "#222222"
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

            Column {
                visible: window.addMenuOpen
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.rightMargin: 68
                anchors.bottomMargin: 44
                spacing: 10

                MapButton {
                    id: addFishButton
                    active: true
                    activeColor: "#ff8c00"
                    onClicked: window.addFishRowFromMap()

                    // Fish outline: body, tail and eye.
                    Shape {
                        anchors.centerIn: parent
                        width: 26; height: 24
                        preferredRendererType: Shape.CurveRenderer
                        ShapePath {
                            strokeColor: addFishButton.glyphColor
                            strokeWidth: 2
                            fillColor: "transparent"
                            joinStyle: ShapePath.RoundJoin
                            capStyle: ShapePath.RoundCap
                            PathSvg { path: "M 2 12 Q 9 3 17 12 Q 9 21 2 12 Z M 17 12 L 24 6 L 24 18 Z" }
                        }
                        ShapePath {
                            strokeColor: "transparent"
                            fillColor: addFishButton.glyphColor
                            PathSvg { path: "M 6 10 a 1.3 1.3 0 1 0 0.01 0 Z" }
                        }
                    }
                }

                MapButton {
                    id: addObservationButton
                    active: true
                    activeColor: "#00838f"
                    onClicked: window.addObservationFromMap()

                    // Binoculars outline: two eyepieces over two barrels joined by a bridge.
                    Item {
                        anchors.centerIn: parent
                        width: 24; height: 24
                        Repeater {
                            model: [1, 14]
                            Item {
                                required property int modelData
                                Rectangle {
                                    x: modelData + 1; y: 2
                                    width: 7; height: 6
                                    radius: 1.5
                                    color: "transparent"
                                    border.width: 2
                                    border.color: addObservationButton.glyphColor
                                }
                                Rectangle {
                                    x: modelData; y: 8
                                    width: 9; height: 14
                                    radius: 4
                                    color: "transparent"
                                    border.width: 2
                                    border.color: addObservationButton.glyphColor
                                }
                            }
                        }
                        Rectangle {
                            x: 9; y: 13
                            width: 6; height: 2
                            color: addObservationButton.glyphColor
                        }
                    }
                }

                MapButton {
                    id: addPotButton
                    active: true
                    activeColor: "#6d4c41"
                    onClicked: window.dropPotFromMap()

                    // Fishing creel outline: lid, tapered woven body, strap and latch.
                    Shape {
                        anchors.centerIn: parent
                        width: 26; height: 24
                        preferredRendererType: Shape.CurveRenderer
                        ShapePath {
                            strokeColor: addPotButton.glyphColor
                            strokeWidth: 2
                            fillColor: "transparent"
                            joinStyle: ShapePath.RoundJoin
                            capStyle: ShapePath.RoundCap
                            PathSvg { path: "M 5 9 L 3 22 L 23 22 L 21 9 Z" }
                            PathSvg { path: "M 4 9 Q 13 1 22 9" }
                            PathSvg { path: "M 8 5 Q 13 -2 18 5" }
                        }
                        ShapePath {
                            strokeColor: addPotButton.glyphColor
                            strokeWidth: 1.5
                            fillColor: "transparent"
                            capStyle: ShapePath.RoundCap
                            PathSvg { path: "M 4.4 14 L 21.6 14 M 3.7 18 L 22.3 18 M 10 9 L 9 22 M 16 9 L 17 22" }
                        }
                        ShapePath {
                            strokeColor: "transparent"
                            fillColor: addPotButton.glyphColor
                            PathSvg { path: "M 13 10.5 a 1.5 1.5 0 1 0 0.01 0 Z" }
                        }
                    }
                }
            }

            Column {
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.rightMargin: 10
                anchors.bottomMargin: 44
                spacing: 10

                MapButton {
                    id: followButton
                    visible: locationTracker.hasPosition && !map.following
                    active: false
                    activeColor: "#1976d2"
                    onClicked: {
                        map.following = true
                        map.center = QtPositioning.coordinate(locationTracker.latitude,
                                                              locationTracker.longitude)
                    }

                    Rectangle {
                        anchors.centerIn: parent
                        width: 22; height: 22
                        radius: 11
                        color: "transparent"
                        border.width: 2
                        border.color: followButton.glyphColor
                        Rectangle {
                            anchors.centerIn: parent
                            width: 8; height: 8
                            radius: 4
                            color: parent.border.color
                        }
                    }
                }

                MapButton {
                    id: sailButton
                    visible: sailPlan.enabled
                    active: sailPlan.active
                    activeColor: "#1976d2"
                    onClicked: sailPlanDialog.open()

                    Shape {
                        anchors.centerIn: parent
                        width: 22; height: 22
                        ShapePath {
                            strokeColor: "transparent"
                            fillColor: sailButton.glyphColor
                            startX: 11; startY: 1
                            PathLine { x: 11; y: 15 }
                            PathLine { x: 3; y: 15 }
                            PathLine { x: 11; y: 1 }
                        }
                        ShapePath {
                            strokeColor: "transparent"
                            fillColor: sailButton.glyphColor
                            startX: 13; startY: 5
                            PathLine { x: 20; y: 15 }
                            PathLine { x: 13; y: 15 }
                            PathLine { x: 13; y: 5 }
                        }
                        ShapePath {
                            strokeColor: "transparent"
                            fillColor: sailButton.glyphColor
                            startX: 2; startY: 17
                            PathLine { x: 21; y: 17 }
                            PathLine { x: 18; y: 21 }
                            PathLine { x: 5; y: 21 }
                            PathLine { x: 2; y: 17 }
                        }
                    }
                }

                MapButton {
                    id: simulatorButton
                    visible: locationTracker.simulatorAvailable
                    active: locationTracker.simulating
                    activeColor: "#00838f"
                    onClicked: simulatorDialog.open()

                    Label {
                        anchors.centerIn: parent
                        text: "S"
                        font.pixelSize: 20
                        font.bold: true
                        color: simulatorButton.glyphColor
                    }
                }

                MapButton {
                    id: fishingButton
                    active: window.fishing
                    activeColor: "#ff8c00"
                    enabled: locationTracker.tracking
                    opacity: enabled ? 1 : 0.5
                    onClicked: window.fishing = !window.fishing

                    Label {
                        anchors.centerIn: parent
                        text: "F"
                        font.pixelSize: 20
                        font.bold: true
                        color: fishingButton.glyphColor
                    }
                }

                MapButton {
                    id: trackingButton
                    active: locationTracker.tracking
                    activeColor: "#2e7d32"
                    onClicked: locationTracker.tracking = !locationTracker.tracking
                    onPressAndHold: trackingDialog.open()

                    Shape {
                        anchors.centerIn: parent
                        width: 20; height: 20
                        visible: !locationTracker.tracking
                        ShapePath {
                            strokeColor: "transparent"
                            fillColor: trackingButton.glyphColor
                            startX: 4; startY: 1
                            PathLine { x: 19; y: 10 }
                            PathLine { x: 4; y: 19 }
                            PathLine { x: 4; y: 1 }
                        }
                    }
                    Rectangle {
                        anchors.centerIn: parent
                        width: 16; height: 16
                        radius: 3
                        visible: locationTracker.tracking
                        color: trackingButton.glyphColor
                    }
                }

                MapButton {
                    id: addButton
                    active: window.addMenuOpen
                    activeColor: "#6a1b9a"
                    onClicked: window.addMenuOpen = !window.addMenuOpen

                    Item {
                        anchors.centerIn: parent
                        width: 22; height: 22
                        rotation: window.addMenuOpen ? 45 : 0
                        Behavior on rotation { NumberAnimation { duration: 120 } }
                        Rectangle { anchors.centerIn: parent; width: 22; height: 3; radius: 1.5; color: addButton.glyphColor }
                        Rectangle { anchors.centerIn: parent; width: 3; height: 22; radius: 1.5; color: addButton.glyphColor }
                    }
                }
            }

            Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.margins: 10
                visible: locationTracker.tracking && locationTracker.hasPosition
                width: osdColumn.implicitWidth + 20
                height: osdColumn.implicitHeight + 12
                radius: 8
                color: window.dark ? "#cc1c2421" : "#ccffffff"
                border.color: window.cardBorder

                Column {
                    id: osdColumn
                    anchors.centerIn: parent
                    spacing: 2
                    Label {
                        text: qsTr("SOG  %1 kts").arg(locationTracker.hasMotion
                                                       ? locationTracker.speedKnots.toFixed(1) : "--")
                        font.pixelSize: 18
                        font.bold: true
                    }
                    Label {
                        text: qsTr("COG  %1°").arg(locationTracker.hasCourse
                                                    ? Math.round(locationTracker.courseDegrees).toString().padStart(3, "0")
                                                    : "---")
                        font.pixelSize: 18
                        font.bold: true
                    }
                }
            }

            Rectangle {
                anchors.top: parent.top
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.margins: 10
                visible: map.pickingMode !== ""
                width: pickingRow.implicitWidth + 24
                height: pickingRow.implicitHeight + 16
                radius: 8
                color: window.cardColor
                border.color: window.cardBorder

                RowLayout {
                    id: pickingRow
                    anchors.centerIn: parent
                    spacing: 12

                    Label {
                        text: map.pickingMode === "departure"
                              ? qsTr("Tap the map to set the departure point")
                              : map.pickingMode === "simulator"
                                ? qsTr("Tap the map to drop the simulated vessel")
                                : qsTr("Tap the map to set the destination point")
                    }
                    Button {
                        text: qsTr("Cancel")
                        onClicked: {
                            const cancelled = map.pickingMode
                            map.pickingMode = ""
                            if (cancelled === "simulator")
                                simulatorDialog.open()
                            else
                                sailPlanDialog.open()
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
                        color: window.cardColor
                        border.color: window.cardBorder

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
                        color: window.cardColor
                        border.color: window.cardBorder

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
                        text: qsTr("Consent and privacy: data is always stored on this device. Uploading it to a server only happens after the participant has consented and ticked the upload option.")
                        wrapMode: Text.Wrap
                        color: window.mutedText
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: consentColumn.implicitHeight + 24
                        color: window.cardColor
                        radius: 8
                        border.color: window.cardBorder

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
                                text: qsTr("I have read the information and consent to take part, including sending my data off this device.")
                            }
                            CheckBox {
                                id: uploadEnabled
                                Layout.fillWidth: true
                                text: qsTr("Upload my data to the server below")
                            }
                            TextField {
                                id: uploadUrl
                                Layout.fillWidth: true
                                inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhUrlCharactersOnly
                                placeholderText: qsTr("Upload URL")
                            }
                            Button {
                                text: qsTr("Reset URL to St Andrews default")
                                onClicked: uploadUrl.text = "https://arts.st-andrews.ac.uk/sifids/"
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: sailPlanColumn.implicitHeight + 24
                        color: window.cardColor
                        radius: 8
                        border.color: window.cardBorder

                        ColumnLayout {
                            id: sailPlanColumn
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 10

                            Label {
                                text: qsTr("Sail plan safety check-ins")
                                font.bold: true
                            }
                            Label {
                                Layout.fillWidth: true
                                text: qsTr("When enabled, the Sail plan button on the Map tab lets you share a departure/destination plan with a contact of your choice, then automatically prompts you to share your current position at 15, 10 and 5 minutes before, and at, your ETA — so a shore contact knows if you're overdue.")
                                wrapMode: Text.Wrap
                            }
                            CheckBox {
                                id: sailPlanEnabled
                                Layout.fillWidth: true
                                text: qsTr("Enable sail plan check-ins")
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: backupColumn.implicitHeight + 24
                        color: window.cardColor
                        radius: 8
                        border.color: window.cardBorder

                        ColumnLayout {
                            id: backupColumn
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 10

                            Label {
                                text: qsTr("Backup")
                                font.bold: true
                            }
                            Label {
                                Layout.fillWidth: true
                                text: qsTr("Save a copy of the whole database, or restore one. Restoring replaces all data currently on this device.")
                                wrapMode: Text.Wrap
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                Button {
                                    Layout.fillWidth: true
                                    text: qsTr("Export database…")
                                    onClicked: {
                                        databaseExportDialog.currentFile = "qtSIFIDS-db-"
                                            + Qt.formatDate(new Date(), "yyyyMMdd") + ".sqlite"
                                        databaseExportDialog.open()
                                    }
                                }
                                Button {
                                    Layout.fillWidth: true
                                    text: qsTr("Import database…")
                                    onClicked: databaseImportDialog.open()
                                }
                            }
                        }
                    }

                    Button {
                        Layout.fillWidth: true
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
                            consent_confirmed: consentConfirmed.checked,
                            upload_enabled: uploadEnabled.checked,
                            upload_url: uploadUrl.text.trim(),
                            sail_plan_enabled: sailPlanEnabled.checked
                        })
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
            appStore.recordLocation(latitude, longitude, accuracy, timestamp, window.fishing)
        }
        function onPositionChanged() {
            sailPlan.updatePosition(locationTracker.latitude, locationTracker.longitude,
                                    locationTracker.direction, locationTracker.hasDirection,
                                    locationTracker.hasPosition, locationTracker.accuracy)
        }
    }

    Connections {
        target: appStore
        function onDataChanged() {
            const current = appStore.settings()
            sailPlan.enabled = current.sail_plan_enabled === "true"
            sailPlan.setVesselInfo(current.pln || "", current.vessel_name || "")
        }
    }

    Timer {
        interval: 30 * 60 * 1000
        repeat: true
        running: appStore.consented && appStore.uploadEnabled
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
        uploadEnabled.checked = saved.upload_enabled === "true"
        uploadUrl.text = saved.upload_url || "https://arts.st-andrews.ac.uk/sifids/"
        locationTracker.tracking = true
        sailPlanEnabled.checked = saved.sail_plan_enabled === "true"
        sailPlan.enabled = sailPlanEnabled.checked
        sailPlan.setVesselInfo(saved.pln || "", saved.vessel_name || "")
        if (appStore.statusNeedsAttention)
            statusDialog.open()
    }

    Connections {
        target: appStore
        function onStatusChanged() {
            if (appStore.statusNeedsAttention)
                statusDialog.open()
        }
    }

    Dialog {
        id: statusDialog
        modal: true
        title: qsTr("Notice")
        standardButtons: Dialog.Ok
        anchors.centerIn: parent
        topMargin: 12
        bottomMargin: 12
        width: Math.min(parent.width - 24, 480)

        contentItem: Label {
            text: appStore.status
            font.pixelSize: 18
            wrapMode: Text.Wrap
        }
    }

    Dialog {
        id: mapNoticeDialog
        modal: true
        title: qsTr("Notice")
        standardButtons: Dialog.Ok
        anchors.centerIn: parent
        width: Math.min(parent.width - 48, 420)

        contentItem: Label {
            id: mapNoticeLabel
            font.pixelSize: 18
            wrapMode: Text.Wrap
        }
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

                Label {
                    Layout.fillWidth: true
                    text: qsTr("Use the map buttons to start or stop tracking and to mark when you are fishing. Long-press the tracking button to open this panel.")
                    color: window.mutedText
                    wrapMode: Text.Wrap
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
                    text: qsTr("Location is saved on this device only. Complete the consent details in Settings to enable uploads.")
                    color: window.errorText
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
                    color: window.mutedText
                    wrapMode: Text.Wrap
                }
            }

        }
    }

    Dialog {
        id: potDialog
        property int potId: 0
        property date potTime
        property real potLatitude: 0
        property real potLongitude: 0
        modal: true
        title: qsTr("Pot")
        anchors.centerIn: parent
        width: Math.min(parent.width - 24, 340)
        standardButtons: Dialog.Close

        contentItem: ColumnLayout {
            spacing: 10
            Label {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                text: qsTr("Dropped %1\n%2, %3")
                    .arg(potDialog.potTime.toLocaleString())
                    .arg(potDialog.potLatitude.toFixed(5))
                    .arg(potDialog.potLongitude.toFixed(5))
            }
            Button {
                Layout.fillWidth: true
                text: qsTr("Delete pot")
                onClicked: {
                    appStore.deletePot(potDialog.potId)
                    potDialog.close()
                }
            }
        }
    }

    Dialog {
        id: simulatorDialog
        title: qsTr("Vessel simulator (debug)")
        modal: true
        anchors.centerIn: parent
        topMargin: 12
        bottomMargin: 12
        width: Math.min(parent.width - 24, 380)
        height: Math.min(implicitHeight, window.dialogMaxHeight)
        property real heading: 0
        property real speed: 5

        function apply() {
            locationTracker.setSimulation(heading, speed)
        }
        onOpened: {
            if (locationTracker.simulating) {
                heading = locationTracker.simHeading
                speed = locationTracker.simSpeed
            }
            compass.requestPaint()
        }
        onHeadingChanged: compass.requestPaint()

        contentItem: ColumnLayout {
            spacing: 10

            Canvas {
                id: compass
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: Math.min(240, simulatorDialog.width - 60)
                Layout.preferredHeight: Layout.preferredWidth

                onPaint: {
                    const ctx = getContext("2d")
                    ctx.reset()
                    const cx = width / 2, cy = height / 2, r = width / 2 - 22
                    const fg = window.dark ? "#e6ebe8" : "#37413d"
                    ctx.strokeStyle = fg
                    ctx.fillStyle = fg
                    ctx.lineWidth = 2
                    ctx.beginPath()
                    ctx.arc(cx, cy, r, 0, 2 * Math.PI)
                    ctx.stroke()
                    for (let d = 0; d < 360; d += 10) {
                        const a = (d - 90) * Math.PI / 180
                        const len = d % 90 === 0 ? 14 : (d % 30 === 0 ? 9 : 5)
                        ctx.beginPath()
                        ctx.moveTo(cx + Math.cos(a) * r, cy + Math.sin(a) * r)
                        ctx.lineTo(cx + Math.cos(a) * (r - len), cy + Math.sin(a) * (r - len))
                        ctx.stroke()
                    }
                    ctx.font = "bold 16px sans-serif"
                    ctx.textAlign = "center"
                    ctx.textBaseline = "middle"
                    const names = ["N", "E", "S", "W"]
                    for (let i = 0; i < 4; ++i) {
                        const a = (i * 90 - 90) * Math.PI / 180
                        ctx.fillText(names[i], cx + Math.cos(a) * (r + 13), cy + Math.sin(a) * (r + 13))
                    }
                    const h = (simulatorDialog.heading - 90) * Math.PI / 180
                    ctx.strokeStyle = "#d8493e"
                    ctx.fillStyle = "#d8493e"
                    ctx.lineWidth = 4
                    ctx.beginPath()
                    ctx.moveTo(cx - Math.cos(h) * r * 0.3, cy - Math.sin(h) * r * 0.3)
                    ctx.lineTo(cx + Math.cos(h) * (r - 16), cy + Math.sin(h) * (r - 16))
                    ctx.stroke()
                    ctx.beginPath()
                    ctx.moveTo(cx + Math.cos(h) * (r - 2), cy + Math.sin(h) * (r - 2))
                    ctx.lineTo(cx + Math.cos(h + 0.25) * (r - 24), cy + Math.sin(h + 0.25) * (r - 24))
                    ctx.lineTo(cx + Math.cos(h - 0.25) * (r - 24), cy + Math.sin(h - 0.25) * (r - 24))
                    ctx.closePath()
                    ctx.fill()
                }

                function setFromPoint(x, y) {
                    const deg = Math.atan2(x - width / 2, -(y - height / 2)) * 180 / Math.PI
                    simulatorDialog.heading = Math.round((deg + 360) % 360)
                    simulatorDialog.apply()
                }
                TapHandler { onTapped: (point) => compass.setFromPoint(point.position.x, point.position.y) }
                DragHandler {
                    target: null
                    onCentroidChanged: if (active) compass.setFromPoint(centroid.position.x, centroid.position.y)
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Label { text: qsTr("Heading (°)") }
                SpinBox {
                    Layout.fillWidth: true
                    from: 0; to: 359
                    editable: true
                    wrap: true
                    value: Math.round(simulatorDialog.heading)
                    onValueModified: {
                        simulatorDialog.heading = value
                        simulatorDialog.apply()
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Label { text: qsTr("Speed (kts)") }
                Slider {
                    Layout.fillWidth: true
                    from: 0; to: 30; stepSize: 0.5
                    value: simulatorDialog.speed
                    onMoved: {
                        simulatorDialog.speed = value
                        simulatorDialog.apply()
                    }
                }
                Label { text: simulatorDialog.speed.toFixed(1); Layout.preferredWidth: 36 }
            }

            Label {
                Layout.fillWidth: true
                visible: locationTracker.simulating
                text: qsTr("Position %1, %2")
                    .arg(locationTracker.latitude.toFixed(5))
                    .arg(locationTracker.longitude.toFixed(5))
                color: window.mutedText
                wrapMode: Text.Wrap
            }

            RowLayout {
                Layout.fillWidth: true
                Button {
                    Layout.fillWidth: true
                    text: locationTracker.simulating ? qsTr("Move vessel…") : qsTr("Drop vessel on map…")
                    onClicked: {
                        simulatorDialog.apply()
                        simulatorDialog.close()
                        map.pickingMode = "simulator"
                    }
                }
                Button {
                    Layout.fillWidth: true
                    text: qsTr("Stop")
                    enabled: locationTracker.simulating
                    onClicked: locationTracker.stopSimulation()
                }
            }
        }
        standardButtons: Dialog.Close
    }

    Dialog {
        id: sailPlanDialog
        modal: true
        title: qsTr("Sail plan")
        standardButtons: Dialog.Close
        anchors.centerIn: parent
        topMargin: 12
        bottomMargin: 12
        height: Math.min(implicitHeight, window.dialogMaxHeight)
        width: Math.min(parent.width - 24, 460)

        function formatPoint(latitude, longitude) {
            return latitude.toFixed(5) + ", " + longitude.toFixed(5)
        }
        function formatWhen(date) {
            return isNaN(date.getTime()) ? qsTr("Tap to set…") : Qt.formatDateTime(date, "d MMM yyyy, HH:mm")
        }

        Component.onCompleted: {
            // "Time... default to now" for departure only; destination/ETA is left
            // for the user to pick.
            if (isNaN(sailPlan.departureTime.getTime()))
                sailPlan.setDepartureTime(new Date())
        }

        contentItem: Flickable {
            id: sailPlanScroll
            clip: true
            flickableDirection: Flickable.VerticalFlick
            boundsBehavior: Flickable.StopAtBounds
            contentWidth: width
            contentHeight: planColumn.implicitHeight
            implicitHeight: planColumn.implicitHeight
            ScrollIndicator.vertical: ScrollIndicator {}
            ColumnLayout {
                id: planColumn
                width: sailPlanScroll.width
                spacing: 12

                Label {
                    Layout.fillWidth: true
                    visible: !sailPlan.enabled
                    text: qsTr("Enable sail plan check-ins in Settings to use this feature.")
                    color: window.errorText
                    wrapMode: Text.Wrap
                }

                Label {
                    Layout.fillWidth: true
                    visible: sailPlan.active
                    text: sailPlan.summary
                    wrapMode: Text.Wrap
                }

                Button {
                    Layout.fillWidth: true
                    visible: sailPlan.active
                    text: qsTr("Cancel / clear sail plan")
                    onClicked: sailPlan.cancel()
                }

                Button {
                    Layout.fillWidth: true
                    visible: sailPlan.active
                    text: qsTr("Arrived — send arrival message")
                    onClicked: sailPlan.arrive()
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    visible: !sailPlan.active
                    spacing: 8

                    PlaceSelector {
                        Layout.fillWidth: true
                        title: qsTr("Departure point")
                        places: appStore.places
                        pointName: sailPlan.departureName
                        hasPoint: sailPlan.hasDeparturePoint
                        pointText: sailPlanDialog.formatPoint(sailPlan.departureLatitude, sailPlan.departureLongitude)
                        canUseGps: locationTracker.hasPosition
                        onPlaceChosen: (latitude, longitude, name) => sailPlan.setDeparturePoint(latitude, longitude, name)
                        onDropPinRequested: {
                            sailPlanDialog.close()
                            map.pickingMode = "departure"
                        }
                        onUseGpsRequested: sailPlan.setDeparturePoint(locationTracker.latitude, locationTracker.longitude)
                        onSaveRequested: placeNameDialog.openFor("departure")
                        onDeleteRequested: (placeId) => {
                            appStore.deletePlace(placeId)
                            sailPlan.setDeparturePoint(sailPlan.departureLatitude, sailPlan.departureLongitude)
                        }
                    }

                    Label { text: qsTr("Departure time"); font.bold: true }
                    Button {
                        Layout.fillWidth: true
                        text: sailPlanDialog.formatWhen(sailPlan.departureTime)
                        onClicked: {
                            departureTimePicker.value = isNaN(sailPlan.departureTime.getTime())
                                                         ? new Date() : sailPlan.departureTime
                            departureTimePicker.open()
                        }
                    }

                    PlaceSelector {
                        Layout.fillWidth: true
                        title: qsTr("Destination point")
                        places: appStore.places
                        pointName: sailPlan.destinationName
                        hasPoint: sailPlan.hasDestinationPoint
                        pointText: sailPlanDialog.formatPoint(sailPlan.destinationLatitude, sailPlan.destinationLongitude)
                        canUseGps: false
                        onPlaceChosen: (latitude, longitude, name) => sailPlan.setDestinationPoint(latitude, longitude, name)
                        onDropPinRequested: {
                            sailPlanDialog.close()
                            map.pickingMode = "destination"
                        }
                        onSaveRequested: placeNameDialog.openFor("destination")
                        onDeleteRequested: (placeId) => {
                            appStore.deletePlace(placeId)
                            sailPlan.setDestinationPoint(sailPlan.destinationLatitude, sailPlan.destinationLongitude)
                        }
                    }

                    Label { text: qsTr("Destination time (ETA)"); font.bold: true }
                    Button {
                        Layout.fillWidth: true
                        text: sailPlanDialog.formatWhen(sailPlan.destinationTime)
                        onClicked: {
                            destinationTimePicker.value = isNaN(sailPlan.destinationTime.getTime())
                                                           ? new Date() : sailPlan.destinationTime
                            destinationTimePicker.open()
                        }
                    }

                    Button {
                        Layout.fillWidth: true
                        text: qsTr("Start sail plan and share")
                        enabled: sailPlan.enabled
                        onClicked: {
                            if (sailPlan.start())
                                sailPlanDialog.close()
                        }
                    }
                }

                Label {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    text: qsTr("Starting a plan, and each position update as you approach the ETA, opens your device's share sheet — pick your shore contact in whatever messaging app you use.")
                    color: window.mutedText
                    wrapMode: Text.Wrap
                }
            }
        }
    }

    Dialog {
        id: placeNameDialog
        modal: true
        title: qsTr("Save place")
        standardButtons: Dialog.Ok | Dialog.Cancel
        anchors.centerIn: parent
        width: Math.min(parent.width - 24, 380)

        property string kind: "departure"

        function openFor(which) {
            kind = which
            placeNameField.text = ""
            open()
            placeNameField.forceActiveFocus()
        }

        onAccepted: {
            const departure = kind === "departure"
            const latitude = departure ? sailPlan.departureLatitude : sailPlan.destinationLatitude
            const longitude = departure ? sailPlan.departureLongitude : sailPlan.destinationLongitude
            const name = placeNameField.text.trim()
            if (name === "" || appStore.savePlace(name, latitude, longitude) < 0)
                return
            if (departure)
                sailPlan.setDeparturePoint(latitude, longitude, name)
            else
                sailPlan.setDestinationPoint(latitude, longitude, name)
        }

        contentItem: TextField {
            id: placeNameField
            placeholderText: qsTr("Place name")
            inputMethodHints: Qt.ImhNoPredictiveText
        }
    }

    DateTimePickerDialog {
        id: departureTimePicker
        label: qsTr("Departure time")
        onAccepted: sailPlan.setDepartureTime(pickedValue)
    }

    DateTimePickerDialog {
        id: destinationTimePicker
        label: qsTr("Destination time (ETA)")
        onAccepted: sailPlan.setDestinationTime(pickedValue)
    }

    Dialog {
        id: sailPlanErrorDialog
        property alias text: sailPlanErrorLabel.text
        function showError(message) {
            text = message
            open()
        }
        modal: true
        title: qsTr("Sail plan")
        standardButtons: Dialog.Ok
        anchors.centerIn: parent
        width: Math.min(parent.width - 48, 400)
        contentItem: ColumnLayout {
            Label {
                id: sailPlanErrorLabel
                Layout.fillWidth: true
                wrapMode: Text.Wrap
            }
        }
    }

    Dialog {
        id: shareCopiedDialog
        modal: true
        title: qsTr("Message copied")
        standardButtons: Dialog.Ok
        anchors.centerIn: parent
        width: Math.min(parent.width - 48, 400)
        contentItem: ColumnLayout {
            Label {
                Layout.fillWidth: true
                text: qsTr("This device has no share sheet, so the message was copied to the clipboard. Paste it into your messaging app to send it.")
                wrapMode: Text.Wrap
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
                    color: window.bgColor
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
        property bool pinOnSave: false
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

        onClosed: pinOnSave = false

        onAccepted: {
            const row = {
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
            }
            if (pinOnSave)
                row.on_map = 1
            const saved = appStore.saveFormRow(row)
            if (saved > 0) {
                currentFormRows = appStore.rowsForForm(activeFormId)
                if (pinOnSave)
                    window.addMenuOpen = false
            }
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
        property bool pinOnSave: false
        property int obsId: 0
        property var obsData: ({})
        modal: true
        title: obsId ? qsTr("Edit wildlife observation") : qsTr("Record wildlife observation")
        standardButtons: Dialog.Save | Dialog.Cancel
        anchors.centerIn: parent
        topMargin: 12
        bottomMargin: 12
        width: Math.min(parent.width - 24, 520)

        onOpened: {
            if (obsId > 0) {
                const index = window.animals.indexOf(obsData.animal)
                animalBox.currentIndex = index >= 0 ? index : 0
                obsSpecies.text = obsData.species || ""
                obsDate.text = new Date(Number(obsData.timestamp)).toISOString()
                obsLatitude.text = obsData.latitude
                obsLongitude.text = obsData.longitude
                obsCount.text = obsData.count
                obsNotes.text = obsData.notes || ""
                return
            }
            obsLatitude.text = locationTracker.hasPosition ? locationTracker.latitude : ""
            obsLongitude.text = locationTracker.hasPosition ? locationTracker.longitude : ""
            obsDate.text = new Date().toISOString()
        }

        onClosed: {
            pinOnSave = false
            obsId = 0
        }

        onAccepted: {
            const observation = {
                id: obsId,
                animal: animalBox.currentText,
                species: obsSpecies.text,
                timestamp: Date.parse(obsDate.text) || Date.now(),
                latitude: Number(obsLatitude.text) || 0,
                longitude: Number(obsLongitude.text) || 0,
                count: Number(obsCount.text) || 1,
                notes: obsNotes.text
            }
            if (pinOnSave)
                observation.on_map = 1
            if (appStore.saveObservation(observation) > 0 && pinOnSave)
                window.addMenuOpen = false
        }

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
        id: databaseExportDialog
        title: qsTr("Save database backup")
        fileMode: FileDialog.SaveFile
        defaultSuffix: "sqlite"
        nameFilters: [qsTr("SQLite databases (*.sqlite *.db)"), qsTr("All files (*)")]
        onAccepted: appStore.exportDatabase(selectedFile.toString())
    }

    FileDialog {
        id: databaseImportDialog
        title: qsTr("Select a SIFIDS database backup")
        fileMode: FileDialog.OpenFile
        nameFilters: [qsTr("SQLite databases (*.sqlite *.db)"), qsTr("All files (*)")]
        onAccepted: {
            if (appStore.importDatabase(selectedFile.toString())) {
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
                uploadEnabled.checked = saved.upload_enabled === "true"
                uploadUrl.text = saved.upload_url || "https://arts.st-andrews.ac.uk/sifids/"
                sailPlanEnabled.checked = saved.sail_plan_enabled === "true"
            }
        }
    }
}
