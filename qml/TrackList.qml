import QtQuick
import QtQuick.Controls.Basic
import org.imelodiae

// The song list: sortable, resizable columns over pale-blue striped rows
Rectangle {
    id: root

    required property var tracks
    // The focused song (keyboard moves from here) and every selected song
    property int selectedId: -1
    property var selectedIds: []
    readonly property var selectedSet: {
        const set = {}
        for (const id of selectedIds)
            set[id] = true
        return set
    }
    // Where Shift-click and Shift-arrow selections start from
    property int anchorId: -1
    property int playingId: -1
    property bool playing: false
    // Column widths by role, persisted by the window
    property var widths: ({})
    // Shown columns by role, left to right (the status column always comes first)
    property var order: defaultOrder
    // Set before an update that shouldn't move the list (play counts, imports)
    property bool preserveScroll: false

    signal activated(int trackId)
    signal selectionEdited(var trackIds, int current)
    signal widthsEdited(var widths)
    signal orderEdited(var order)
    signal infoRequested(var trackIds)

    color: "white"
    clip: true

    // Every column the list can show, in the order the header's menu lists them
    readonly property var catalog: [
        { role: "title", title: qsTr("Song Name"), width: 0 },
        { role: "time", title: qsTr("Time"), width: 52, align: Text.AlignRight },
        { role: "artist", title: qsTr("Artist"), width: 140 },
        { role: "album", title: qsTr("Album"), width: 150 },
        { role: "genre", title: qsTr("Genre"), width: 90 },
        { role: "year", title: qsTr("Year"), width: 46, align: Text.AlignRight },
        { role: "trackNumber", title: qsTr("Track #"), width: 56, align: Text.AlignRight },
        { role: "kind", title: qsTr("Kind"), width: 140 },
        { role: "bitRate", title: qsTr("Bit Rate"), width: 80, align: Text.AlignRight },
        { role: "sampleRate", title: qsTr("Sample Rate"), width: 84, align: Text.AlignRight },
        { role: "playCount", title: qsTr("Play Count"), width: 72, align: Text.AlignRight },
        { role: "lastPlayed", title: qsTr("Last Played"), width: 130 },
        { role: "dateAdded", title: qsTr("Date Added"), width: 130 }
    ]
    readonly property var defaultOrder: ["title", "time", "artist", "album", "genre", "kind", "bitRate", "playCount"]
    readonly property var statusColumn: ({ role: "status", title: "", width: 20, fixed: true })

    // Shown columns, status first. Song Name is always shown; unknown roles are dropped.
    readonly property var columns: {
        const byRole = {}
        for (const c of catalog)
            byRole[c.role] = c
        const roles = order.filter((r, i) => byRole[r] && order.indexOf(r) === i)
        if (!roles.includes("title"))
            roles.unshift("title")
        return [statusColumn].concat(roles.map(r => byRole[r]))
    }
    // Position of each shown column by role
    readonly property var columnIndex: {
        const out = {}
        columns.forEach((c, i) => out[c.role] = i)
        return out
    }
    function shownRoles() {
        return columns.slice(1).map(c => c.role)
    }

    function toggleColumn(role) {
        const roles = shownRoles()
        const i = roles.indexOf(role)
        if (i >= 0)
            roles.splice(i, 1)
        else
            roles.push(role)
        orderEdited(roles)
    }

    // Header drag-to-rearrange: the column being dragged, how far, and where it would land
    property string dragRole: ""
    property real dragOffset: 0
    property int dropSlot: -1

    // Where a column dropped at content x would go, as an index into the other shown
    // columns: the number of them whose middle is left of x
    function slotAt(x) {
        let slot = 0
        for (let i = 1; i < columns.length; ++i) {
            if (columns[i].role === dragRole)
                continue
            if (layout[i].x + layout[i].width / 2 < x)
                ++slot
        }
        return slot
    }
    function moveColumn(role, slot) {
        const roles = shownRoles().filter(r => r !== role)
        roles.splice(slot, 0, role)
        orderEdited(roles)
    }
    // Content x of the drop marker for a slot
    function slotX(slot) {
        const others = []
        for (let i = 1; i < columns.length; ++i)
            if (columns[i].role !== dragRole)
                others.push(i)
        return slot >= 0 && slot < others.length ? layout[others[slot]].x : totalWidth
    }

    FontMetrics {
        id: cellMetrics
        font.family: Theme.font
        font.pixelSize: Theme.listFontSize
    }

    // Widen or narrow a column to its widest entry in the current view, or its heading
    function fitColumn(col) {
        let samples
        if (col.role === "dateAdded" || col.role === "lastPlayed") {
            // Dates all format alike; the widest has two-digit day, month and hour
            samples = [formatDate(new Date(2026, 11, 28, 23, 58).getTime() / 1000)]
        } else {
            // The longest few by characters; proportional fonts can reorder those slightly
            samples = tracks.longestValues(col.role, 40)
        }
        let widest = 0
        for (const text of samples)
            widest = Math.max(widest, cellMetrics.advanceWidth(text))
        // Cell text has 5px on the left and 6px on the right; headings leave room for the
        // sort arrow
        const cell = Math.ceil(widest) + 11 + 2
        const heading = Math.ceil(cellMetrics.advanceWidth(col.title)) + 5 + 4 + 13
        const next = Object.assign({}, widths)
        next[col.role] = Math.max(36, cell, heading)
        widthsEdited(next)
    }

    function formatDate(secs) {
        return secs > 0 ? new Date(secs * 1000).toLocaleString(Qt.locale(), Locale.ShortFormat) : ""
    }

    function widthOf(col) {
        if (col.role === "title") {
            let others = 0
            for (const c of columns)
                if (c.role !== "title")
                    others += widthOf(c)
            const fitted = list.width - gutter - others
            return Math.max(widths.title ?? 140, fitted)
        }
        return col.fixed ? col.width : (widths[col.role] ?? col.width)
    }

    // The scroll bars float over the list, so leave room for them beside the last column
    // and below the last row while they're showing (they show whenever there's overflow)
    readonly property real gutter: vbar.size < 1.0 ? vbar.width : 0
    readonly property real footer: hbar.size < 1.0 ? hbar.height : 0

    // Every column's x and width, computed once per resize rather than in every cell
    readonly property var layout: {
        void widths; void list.width; void gutter
        let x = 0
        const out = []
        for (const c of columns) {
            const w = widthOf(c)
            out.push({ x: x, width: w })
            x += w
        }
        return out
    }

    readonly property real totalWidth: {
        // Depend on widths and list width so this re-evaluates on resize
        void widths; void list.width; void gutter
        let sum = 0
        for (const c of columns)
            sum += widthOf(c)
        return sum
    }

    function select(row) {
        const count = list.count
        if (count === 0)
            return
        row = Math.max(0, Math.min(count - 1, row))
        const id = root.tracks.idAt(row)
        anchorId = id
        root.selectionEdited([id], id)
        list.positionViewAtIndex(row, ListView.Contain)
    }

    // Select from the anchor to a row (Shift), optionally adding to the selection (Ctrl)
    function extendTo(row, adding) {
        const count = list.count
        if (count === 0)
            return
        row = Math.max(0, Math.min(count - 1, row))
        const from = root.tracks.rowOfId(anchorId)
        if (from < 0)
            return select(row)
        const ids = adding ? selectedIds.slice() : []
        const have = adding ? Object.assign({}, selectedSet) : {}
        for (let r = Math.min(from, row); r <= Math.max(from, row); ++r) {
            const id = root.tracks.idAt(r)
            if (!have[id]) {
                have[id] = true
                ids.push(id)
            }
        }
        root.selectionEdited(ids, root.tracks.idAt(row))
        list.positionViewAtIndex(row, ListView.Contain)
    }

    function toggle(id) {
        anchorId = id
        if (selectedSet[id])
            root.selectionEdited(selectedIds.filter(i => i !== id), id)
        else
            root.selectionEdited(selectedIds.concat([id]), id)
    }

    function selectAll() {
        const ids = []
        for (let r = 0; r < list.count; ++r)
            ids.push(root.tracks.idAt(r))
        root.selectionEdited(ids, selectedId)
    }

    function clickRow(id, modifiers) {
        list.forceActiveFocus()
        if (modifiers & Qt.ShiftModifier)
            extendTo(root.tracks.rowOfId(id), modifiers & Qt.ControlModifier)
        else if (modifiers & Qt.ControlModifier)
            toggle(id)
        else
            select(root.tracks.rowOfId(id))
    }

    function reveal(trackId) {
        const row = root.tracks.rowOfId(trackId)
        if (row >= 0)
            list.positionViewAtIndex(row, ListView.Center)
    }

    function focusList() {
        list.forceActiveFocus()
    }

    // Header
    Item {
        id: headerRow
        width: parent.width
        height: 17
        clip: true
        z: 2

        Row {
            id: headerContent
            x: -list.contentX
            Repeater {
                model: root.columns
                delegate: ListHeader {
                    id: cell
                    required property var modelData
                    width: root.widthOf(modelData)
                    height: 17
                    text: modelData.title
                    alignment: modelData.align ?? Text.AlignLeft
                    sorted: modelData.role !== "status" && root.tracks.sortColumn === modelData.role
                    ascending: root.tracks.sortAscending

                    readonly property bool dragging: root.dragRole === modelData.role
                    z: dragging ? 1 : 0
                    opacity: dragging ? 0.75 : 1
                    transform: Translate { x: cell.dragging ? root.dragOffset : 0 }

                    // Click to sort, drag sideways to move, right-click for the column menu
                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        property real startX
                        onPressed: mouse => {
                            if (mouse.button === Qt.RightButton) {
                                columnMenu.popupAt(cell, mouse.x, mouse.y)
                                return
                            }
                            startX = mapToItem(root, mouse.x, 0).x
                        }
                        onPositionChanged: mouse => {
                            if (cell.modelData.role === "status")
                                return
                            const dx = mapToItem(root, mouse.x, 0).x - startX
                            if (!cell.dragging && Math.abs(dx) < 5)
                                return
                            root.dragRole = cell.modelData.role
                            root.dragOffset = dx
                            root.dropSlot = root.slotAt(mapToItem(headerContent, mouse.x, 0).x)
                        }
                        onReleased: mouse => {
                            if (mouse.button !== Qt.LeftButton)
                                return
                            if (cell.dragging) {
                                root.moveColumn(root.dragRole, root.dropSlot)
                                root.dragRole = ""
                            } else if (cell.modelData.role !== "status" && containsMouse) {
                                root.tracks.sortBy(cell.modelData.role)
                            }
                        }
                        onCanceled: root.dragRole = ""
                    }

                    // Drag the right edge to resize
                    MouseArea {
                        visible: !cell.modelData.fixed
                        anchors.right: parent.right
                        width: 6
                        height: parent.height
                        cursorShape: Qt.SplitHCursor
                        property real startX
                        property real startWidth
                        onPressed: mouse => {
                            startX = mapToItem(root, mouse.x, 0).x
                            startWidth = cell.width
                        }
                        onPositionChanged: mouse => {
                            const dx = mapToItem(root, mouse.x, 0).x - startX
                            const next = Object.assign({}, root.widths)
                            next[cell.modelData.role] = Math.max(36, Math.round(startWidth + dx))
                            root.widthsEdited(next)
                        }
                        // Double-click the edge to fit the column to its contents
                        onDoubleClicked: root.fitColumn(cell.modelData)
                    }
                }
            }
        }
        // Filler to the right of the last column
        ListHeader {
            id: filler
            x: root.totalWidth - list.contentX
            width: Math.max(0, parent.width - x)
            height: 17
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.RightButton
                onPressed: mouse => columnMenu.popupAt(filler, mouse.x, mouse.y)
            }
        }

        // Where a dragged column will land
        Rectangle {
            visible: root.dragRole !== ""
            x: root.slotX(root.dropSlot) - list.contentX - 1
            width: 3
            height: parent.height
            z: 3
            color: Theme.selection
        }
    }

    ContextMenu {
        id: columnMenu
        items: {
            const shown = root.columnIndex
            return root.catalog.map(c => ({
                label: c.title, action: c.role, checked: shown[c.role] !== undefined,
                enabled: c.role !== "title"
            })).concat([{ separator: true }, { label: qsTr("Restore Default Columns"), action: "reset" }])
        }
        onTriggered: action => {
            if (action === "reset")
                root.orderEdited(root.defaultOrder)
            else
                root.toggleColumn(action)
        }
    }

    ContextMenu {
        id: songMenu
        property int trackId: -1
        items: [
            { label: qsTr("Play"), action: "play" },
            {
                label: root.selectedIds.length > 1
                       ? qsTr("Get Info for %1 Songs").arg(root.selectedIds.length) : qsTr("Get Info"),
                action: "info"
            },
            { separator: true },
            { label: qsTr("Show in Folder"), action: "folder" }
        ]
        onTriggered: action => {
            if (action === "play") {
                root.activated(trackId)
            } else if (action === "info") {
                root.infoRequested(root.selectedIds)
            } else if (action === "folder") {
                const uri = root.tracks.uriOf(trackId)
                if (uri)
                    Qt.openUrlExternally(uri.substring(0, uri.lastIndexOf("/")))
            }
        }
    }

    ListView {
        id: list
        anchors.top: headerRow.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        clip: true
        model: root.tracks
        reuseItems: true
        // Don't pre-build off-screen rows: every search rebuilds the list, and scrolling
        // reuses rows anyway
        cacheBuffer: 0
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.AutoFlickIfNeeded
        contentWidth: root.totalWidth + root.gutter
        bottomMargin: root.footer
        keyNavigationEnabled: false
        activeFocusOnTab: true
        ScrollBar.vertical: AquaScrollBar { id: vbar }
        ScrollBar.horizontal: AquaScrollBar { id: hbar }

        // Stripes continue below the last song, like a real Aqua table
        Rectangle {
            parent: list
            z: -1
            y: list.contentHeight - list.contentY
            width: list.width
            height: Math.max(0, list.height - y)
            color: "white"
            clip: true
            Column {
                y: 0
                Repeater {
                    model: Math.max(0, Math.ceil(list.height / 17) + 1)
                    Rectangle {
                        required property int index
                        width: list.width
                        height: 17
                        color: (list.count + index) % 2 ? Theme.rowOdd : Theme.rowEven
                    }
                }
            }
        }

        // Kept deliberately light: on an older machine, rebuilding rows is the slowest
        // part of searching, so each row is one rectangle with plain text cells
        delegate: Rectangle {
            id: row
            required property var model
            required property int index
            readonly property bool isSelected: root.selectedSet[model.trackId] === true
            readonly property bool isPlaying: model.trackId === root.playingId

            width: Math.max(root.totalWidth, ListView.view.width)
            height: 17
            color: isSelected ? Theme.selection : (index % 2 ? Theme.rowOdd : Theme.rowEven)

            // One cell per catalog column; hidden columns' cells stay empty and invisible
            component Cell: Text {
                property string role
                readonly property int column: root.columnIndex[role] ?? -1
                visible: column >= 0
                x: visible ? root.layout[column].x + 5 : 0
                width: visible ? root.layout[column].width - 11 : 0
                height: row.height
                verticalAlignment: Text.AlignVCenter
                textFormat: Text.PlainText
                font.family: Theme.font
                font.pixelSize: Theme.listFontSize
                color: row.isSelected ? Theme.selectionText : Theme.text
                elide: Text.ElideRight
            }
            Cell { role: "title"; text: row.model.title }
            Cell { role: "time"; text: visible ? row.model.time : ""; horizontalAlignment: Text.AlignRight }
            Cell { role: "artist"; text: visible ? row.model.artist : "" }
            Cell { role: "album"; text: visible ? row.model.album : "" }
            Cell { role: "genre"; text: visible ? row.model.genre : "" }
            Cell { role: "year"; text: visible ? row.model.year : ""; horizontalAlignment: Text.AlignRight }
            Cell { role: "trackNumber"; text: visible ? row.model.trackNumber : ""; horizontalAlignment: Text.AlignRight }
            Cell { role: "kind"; text: visible ? row.model.kind : "" }
            Cell { role: "bitRate"; text: visible ? row.model.bitRate : ""; horizontalAlignment: Text.AlignRight }
            Cell { role: "sampleRate"; text: visible ? row.model.sampleRate : ""; horizontalAlignment: Text.AlignRight }
            Cell { role: "playCount"; text: visible ? row.model.playCount : ""; horizontalAlignment: Text.AlignRight }
            Cell { role: "lastPlayed"; text: visible ? root.formatDate(row.model.lastPlayed) : "" }
            Cell { role: "dateAdded"; text: visible ? root.formatDate(row.model.dateAdded) : "" }

            // Speaker icon, only built for the playing song
            Loader {
                active: row.isPlaying
                width: root.layout[0].width
                height: row.height
                sourceComponent: Item {
                    GlyphIcon {
                        anchors.centerIn: parent
                        width: 13
                        height: 11
                        kind: root.playing ? "speaker" : "speakerLow"
                        color: row.isSelected ? "white" : "#1a1a1a"
                        engraved: false
                    }
                }
            }

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onPressed: mouse => {
                    if (mouse.button === Qt.RightButton) {
                        // Right-clicking inside the selection acts on all of it
                        if (!row.isSelected)
                            root.clickRow(row.model.trackId, 0)
                        list.forceActiveFocus()
                        songMenu.trackId = row.model.trackId
                        songMenu.popupAt(row, mouse.x, mouse.y)
                    } else {
                        root.clickRow(row.model.trackId, mouse.modifiers)
                    }
                }
                onDoubleClicked: mouse => {
                    if (mouse.button === Qt.LeftButton)
                        root.activated(row.model.trackId)
                }
            }
        }

        // Column grid lines, drawn once over the whole list instead of in every cell
        Repeater {
            model: root.layout
            delegate: Rectangle {
                required property var modelData
                parent: list
                z: 1
                x: modelData.x + modelData.width - 1 - list.contentX
                width: 1
                height: Math.min(list.height, list.contentHeight - list.contentY)
                color: Qt.rgba(0, 0, 0, 0.13)
            }
        }

        Keys.onUpPressed: event => {
            const row = root.tracks.rowOfId(root.selectedId) - 1
            if (event.modifiers & Qt.ShiftModifier)
                root.extendTo(row, false)
            else
                root.select(row)
        }
        Keys.onDownPressed: event => {
            const row = root.tracks.rowOfId(root.selectedId) + 1
            if (event.modifiers & Qt.ShiftModifier)
                root.extendTo(row, false)
            else
                root.select(row)
        }
        Keys.onPressed: event => {
            if (event.matches(StandardKey.SelectAll)) {
                root.selectAll()
            } else if (event.key === Qt.Key_Home) {
                root.select(0)
            } else if (event.key === Qt.Key_End) {
                root.select(count - 1)
            } else if (event.key === Qt.Key_PageDown) {
                root.select(root.tracks.rowOfId(root.selectedId) + Math.floor(height / 17))
            } else if (event.key === Qt.Key_PageUp) {
                root.select(root.tracks.rowOfId(root.selectedId) - Math.floor(height / 17))
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                if (root.selectedId >= 0)
                    root.activated(root.selectedId)
            } else {
                return
            }
            event.accepted = true
        }

        property real savedY: 0
        Connections {
            target: root.tracks
            function onModelAboutToBeReset() {
                list.savedY = list.contentY
            }
            function onModelReset() {
                const keep = root.preserveScroll || root.tracks.scanning || root.tracks.updating
                root.preserveScroll = false
                Qt.callLater(() => {
                    if (keep) {
                        list.contentY = Math.min(list.savedY, Math.max(list.originY, list.contentHeight - list.height + list.originY))
                    } else {
                        const row = root.tracks.rowOfId(root.selectedId)
                        if (row >= 0)
                            list.positionViewAtIndex(row, ListView.Contain)
                        else
                            list.positionViewAtBeginning()
                    }
                })
            }
        }
    }

    Text {
        anchors.centerIn: list
        width: Math.min(360, list.width - 40)
        visible: root.tracks.totalCount === 0
        text: root.tracks.scanning
              ? qsTr("Importing your music…")
              : qsTr("Your library is empty.\n\nClick the + button below to add a music folder, or drag a folder onto this window.")
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        font.family: Theme.font
        font.pixelSize: 12
        color: Theme.dimText
    }
}
