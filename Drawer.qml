import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Drawer — one bar icon that hides other bar widgets behind a popup menu.
//
// A hidden ("stowed") widget is removed from `bar.layout` in shell.json, so
// the bar stops drawing it, and is mounted here instead — inside `hostBay`,
// a zero-sized clipping Item sitting exactly on top of the drawer's own icon.
// It has to stay mounted *in the bar window*: a bar widget's tooltip goes
// through `Bar.targetBelongsToWindow` and its popup anchors through
// `anchorItem.QsWindow.window`, and both reject a target that lives in
// another window. Re-hosting the widget inside this plugin's popup would
// break every panel it owns. Parking it on the drawer's icon has a second
// payoff: when it opens, its panel appears directly under the drawer.
//
// The popup therefore shows a *proxy* row per stowed widget rather than the
// widget itself. The row's icon is bound live to the widget's own bar button
// (so a muted speaker or a ticking clock still reads correctly), and clicking
// the row forwards the click straight to that button — which is what makes
// the widget behave exactly as it did in the bar, panel and all.
Panel {
  id: root
  moduleName: "romeo.drawer"
  ipcTarget: "romeo.drawer"
  // manageIpc: false so this widget can own the one IpcHandler the target
  // permits; the base class methods are re-declared below alongside the
  // stow/unstow calls.
  manageIpc: false

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight
  visible: !hideWhenEmpty || stowedIds.length > 0

  // ------------------------------------------------------------- shell state

  readonly property var shellRef: bar ? bar.shell : null
  readonly property var shellConfig: shellRef && shellRef.shellConfig ? shellRef.shellConfig : ({})
  readonly property var registry: bar ? bar.barWidgetRegistry : null
  // Reading `widgets` (not calling a helper) is what makes the bindings below
  // re-evaluate when a plugin is enabled, disabled, or hot-reloaded.
  readonly property var registryWidgets: registry ? registry.widgets : ({})

  readonly property var stowed: Model.normalizeItems(setting("items", []))
  readonly property var stowedIds: stowed.map(function (item) { return item.id })
  readonly property var stowedNames: stowedIds.map(function (id) { return root.displayName(id) })
  readonly property var barRows: Model.barRows(shellConfig, root.moduleName)

  readonly property string iconName: String(setting("icon", "grid"))
  readonly property bool showCount: setting("showCount", true) === true
  readonly property bool closeOnActivate: setting("closeOnActivate", true) === true
  readonly property bool hideWhenEmpty: setting("hideWhenEmpty", false) === true

  // "list" — one row per widget, icon and name. "grid" — icon tiles, names
  // off by default because the point of the grid is a compact block of icons.
  readonly property string layoutMode: Model.normalizeLayoutMode(setting("layout", "list"))
  readonly property bool gridMode: layoutMode === "grid"
  readonly property bool gridLabels: setting("gridLabels", false) === true
  readonly property int gridColumns: Model.clampColumns(setting("gridColumns", 4))

  readonly property int gridCellMinWidth: Style.space(gridLabels ? 74 : 52)
  readonly property int gridCellHeight: Style.space(gridLabels ? 66 : 48)

  // Width of the drawer view, published by the Flickable below so the cells
  // can size themselves against it. The chain only runs one way — the popup's
  // width comes from `desiredWidth`, which uses the *minimum* cell width — so
  // there is no loop back into the geometry the cells are measuring.
  property real viewWidth: 0
  // A column count the popup could not fit is dropped rather than squeezed.
  readonly property int gridColumnCount: Math.max(1, Math.min(gridColumns,
    Math.floor(Math.max(0, viewWidth) / Math.max(1, gridCellMinWidth))))
  // Cells then share the row evenly, so the block spans the card instead of
  // leaving a margin that grows with every column the user removes.
  readonly property int gridCellWidth: viewWidth > 0
    ? Math.max(gridCellMinWidth, Math.floor(viewWidth / gridColumnCount))
    : gridCellMinWidth

  // The grid decides how wide the popup wants to be; the list and the manage
  // view keep a fixed comfortable width. fittedContentWidth clamps whatever
  // comes out of this to what the screen actually has.
  readonly property int desiredWidth: gridMode && !manageMode
    // The slack covers the card's padding and borders, so a grid asked for N
    // columns actually gets N rather than losing one to a few pixels.
    ? Math.max(Style.space(236), gridColumns * gridCellMinWidth + Style.space(34))
    : Style.space(344)

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.45)
  readonly property color faint: Qt.darker(foreground, 2.0)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  // manage = the hide/show list; false = the drawer itself.
  property bool manageMode: false
  property int cursor: -1

  // ------------------------------------------------- surviving a bar rebuild

  // Any layout change to shell.json rebuilds every bar widget, this one
  // included — which means clicking "Hide" destroys the popup the click came
  // from. Model.ui is a `.pragma library` object shared per QML engine, so it
  // outlives the widget and the replacement can pick the popup back up.
  readonly property string screenName: {
    var window = QsWindow ? QsWindow.window : null
    return window && window.screen ? String(window.screen.name || "") : ""
  }
  property bool uiRestored: false

  function tryRestoreUi() {
    if (uiRestored || !screenName) return
    uiRestored = true
    if (Model.ui.openScreen !== screenName) return
    manageMode = Model.ui.manage === true
    open()
  }

  onScreenNameChanged: tryRestoreUi()
  onOpenedChanged: {
    if (opened) {
      Model.ui.openScreen = screenName
      Model.ui.manage = manageMode
      refreshButtons()
    } else {
      cursor = -1
      if (Model.ui.openScreen === screenName) Model.ui.openScreen = ""
    }
  }
  onManageModeChanged: {
    cursor = -1
    if (opened) Model.ui.manage = manageMode
  }

  Component.onCompleted: Qt.callLater(tryRestoreUi)

  // ------------------------------------------------------------ config edits

  function mutate(fn) {
    if (!shellRef || typeof shellRef.mutateShellConfig !== "function") return false
    var changed = false
    shellRef.mutateShellConfig(function (config) { changed = fn(config) === true })
    return changed
  }

  function stow(id) { return mutate(function (c) { return Model.stow(c, root.moduleName, id) }) }
  function unstow(id) { return mutate(function (c) { return Model.unstow(c, root.moduleName, id) }) }
  function unstowAll() { return mutate(function (c) { return Model.unstowAll(c, root.moduleName) }) }
  function forget(id) { return mutate(function (c) { return Model.forget(c, root.moduleName, id) }) }
  function reorder(id, delta) { return mutate(function (c) { return Model.reorder(c, root.moduleName, id, delta) }) }
  function setOption(key, value) { return mutate(function (c) { return Model.setOption(c, root.moduleName, key, value) }) }

  function toggleStow(id) { return stowedIds.indexOf(id) === -1 ? stow(id) : unstow(id) }

  function openDrawer() {
    manageMode = false
    open()
  }

  // ------------------------------------------------------------- name lookup

  function displayName(id) {
    var entry = registryWidgets ? registryWidgets[id] : null
    var metadata = entry ? entry.metadata : null
    var name = metadata ? String(metadata.displayName || "") : ""
    if (name) return name
    var dot = String(id).indexOf(".")
    return dot === -1 ? String(id) : String(id).substring(dot + 1)
  }

  function isInstalled(id) { return !!(registryWidgets && registryWidgets[id]) }

  // A stowed widget's inline settings live in shell.json's top-level
  // `plugins[]` rather than inside this widget's entry: a third-party widget
  // is only in the widget registry while its id appears somewhere in
  // shell.json, and the shell writes a widget's own saved state to its
  // `plugins[]` entry once it is out of the layout.
  function settingsFor(id) {
    var plugins = Model.arrayFrom(shellConfig ? shellConfig.plugins : [])
    for (var i = 0; i < plugins.length; i++) {
      if (Model.entryId(plugins[i]) !== id) continue
      var out = ({})
      for (var key in plugins[i]) if (key !== "id") out[key] = plugins[i][key]
      return out
    }
    return ({})
  }

  // ---------------------------------------------------------- hosted widgets

  // widgetId -> the HostedWidget cell mounted in hostBay.
  property var cells: ({})

  function registerCell(id, cell) {
    var next = ({})
    for (var key in cells) next[key] = cells[key]
    next[id] = cell
    cells = next
  }

  function unregisterCell(id, cell) {
    if (cells[id] !== cell) return
    var next = ({})
    for (var key in cells) if (key !== id) next[key] = cells[key]
    cells = next
  }

  // The widget's own clickable bar button, found by walking its item tree for
  // the WidgetButton signature. That button is the whole interface a bar
  // widget exposes: its glyph is what the bar paints, and `triggerPress` is
  // what the bar calls when the user clicks it. Reusing it is what lets a
  // drawer row behave exactly like the bar icon it replaced.
  function primaryButton(item, depth) {
    if (!item) return null
    var level = depth === undefined ? 0 : depth
    if (typeof item.triggerPress === "function" && item.visible !== false && item.hasVisualContent !== false)
      return item
    if (level > 6) return null
    var kids = item.children
    if (!kids) return null
    for (var i = 0; i < kids.length; i++) {
      var found = primaryButton(kids[i], level + 1)
      if (found) return found
    }
    return null
  }

  function refreshButtons() {
    for (var id in cells) if (cells[id] && cells[id].resolveButton) cells[id].resolveButton()
  }

  // A stowed widget's button registers itself as a bar click target at the
  // same screen position as the drawer's own icon (they are stacked). An open
  // panel forwards bar clicks to the last matching target, so re-registering
  // this button after the stowed ones keeps a click on the drawer icon
  // landing on the drawer.
  function refreshClickOrder() {
    if (button && typeof button.syncClickRegistration === "function") button.syncClickRegistration()
  }

  function activate(id, mouseButton) {
    var cell = cells[id]
    var target = cell ? cell.button : null
    if (target && typeof target.triggerPress === "function") {
      // Opening the widget's own panel makes the bar hand the single-popout
      // slot over, which closes this one with a cross-fade. Widgets with no
      // panel need the explicit close below.
      target.triggerPress(mouseButton)
    } else if (cell && cell.item && typeof cell.item.toggle === "function") {
      cell.item.toggle()
    } else if (cell && cell.item && typeof cell.item.open === "function") {
      cell.item.open()
    } else {
      return false
    }
    if (closeOnActivate) close()
    return true
  }

  function scrollOn(id, delta) {
    var cell = cells[id]
    var target = cell ? cell.button : null
    if (target && target.wheelMoved) target.wheelMoved(delta)
  }

  // A widget can replace the button behind its icon while it is stowed — an
  // indicator that starts reporting, a tray item that arrives. The glyph is
  // bound to the button, but which object *is* the button is not, so re-walk
  // the hosted items for as long as the drawer is on screen.
  Timer {
    running: root.opened
    interval: 1000
    repeat: true
    onTriggered: root.refreshButtons()
  }

  // --------------------------------------------------------------- bar icon

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: Model.iconGlyph(root.iconName, root.bar ? root.bar.position : "top")
    active: root.opened
    tooltipText: Model.tooltip(root.stowedNames)
    onPressed: function (mouseButton) {
      if (mouseButton === Qt.RightButton) {
        root.manageMode = true
        root.open()
        return
      }
      if (!root.opened) root.manageMode = false
      root.toggle()
    }
  }

  Text {
    id: countBadge
    visible: root.showCount && root.stowedIds.length > 0
    text: String(root.stowedIds.length)
    color: Color.accent
    font.family: root.fontFamily
    font.pixelSize: Math.max(8, Style.font.caption - 1)
    font.bold: true
    renderType: Text.NativeRendering
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.rightMargin: Style.space(1)
    anchors.topMargin: Style.space(2)
    z: 5
  }

  // ------------------------------------------------------- stowed widget bay

  Item {
    id: hostBay
    x: 0
    y: 0
    width: 0
    height: 0
    clip: true

    Repeater {
      model: root.stowedIds
      delegate: HostedWidget {}
    }
  }

  component HostedWidget: Item {
    id: cell

    required property string modelData
    readonly property string widgetId: modelData
    readonly property var registryEntry: {
      var widgets = root.registryWidgets
      return widgets && widgets[cell.widgetId] ? widgets[cell.widgetId] : null
    }
    readonly property var hostedSettings: root.settingsFor(cell.widgetId)

    property var item: loader.item
    property var button: null
    // Held here on purpose: in Component.onDestruction the outer ids are
    // already gone, so anything the teardown needs has to live on the child.
    property var hostBar: root.bar
    property var hostRoot: root

    width: item ? item.implicitWidth : 0
    height: item ? item.implicitHeight : 0

    function inject() {
      var target = loader.item
      if (!target) return
      if ("bar" in target) target.bar = root.bar
      if ("moduleName" in target) target.moduleName = cell.widgetId
      if ("settings" in target) target.settings = cell.hostedSettings
      cell.resolveButton()
    }

    function resolveButton() {
      cell.button = root.primaryButton(loader.item)
    }

    onHostedSettingsChanged: inject()
    onItemChanged: Qt.callLater(inject)

    Loader {
      id: loader
      anchors.fill: parent
      active: !!cell.registryEntry
      sourceComponent: cell.registryEntry ? cell.registryEntry.component : null
      onLoaded: {
        cell.inject()
        Qt.callLater(cell.inject)
        settleTimer.restart()
      }
    }

    // Widgets build their button behind async loaders of their own, so the
    // first walk can come up empty. One late retry is enough in practice, and
    // opening the popup re-walks every cell anyway.
    Timer {
      id: settleTimer
      interval: 150
      onTriggered: cell.resolveButton()
    }

    // Registering with the bar is what lets `omarchy-shell shell toggle
    // <id>` and the panel hotkeys still reach a stowed widget. It is a bare
    // QtObject rather than an Item on purpose: Bar.findPanelWidget() only
    // needs moduleName/activeItem, while the drag-reorder hit test filters on
    // `slot.visible`, which a QtObject does not have — so drawer contents
    // never become drop targets in the bar.
    QtObject {
      id: proxySlot
      property string moduleName: cell.widgetId
      property string region: "drawer"
      property var activeItem: loader.item
    }

    Component.onCompleted: {
      if (cell.hostBar && cell.hostBar.registerModuleSlot) cell.hostBar.registerModuleSlot(proxySlot)
      if (cell.hostRoot) cell.hostRoot.registerCell(cell.widgetId, cell)
      Qt.callLater(function () { if (cell.hostRoot) cell.hostRoot.refreshClickOrder() })
    }

    // A cell is usually destroyed *with* the drawer — every layout change
    // rebuilds the whole bar — and by then reading anything off the drawer
    // throws, because the outer object goes first and its children after. The
    // bar outlives us and must be told; the drawer's cell map dies with it and
    // does not need to be.
    Component.onDestruction: {
      try {
        if (cell.hostBar && cell.hostBar.unregisterModuleSlot) cell.hostBar.unregisterModuleSlot(proxySlot)
      } catch (barError) {
      }
      try {
        cell.hostRoot.unregisterCell(cell.widgetId, cell)
      } catch (rootError) {
      }
    }
  }

  // ------------------------------------------------------------------ popup

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(root.desiredWidth)
    contentHeight: panel.fittedContentHeight(content.implicitHeight, Style.space(720))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent

      onCloseRequested: root.close()
      onTabRequested: function (direction) { root.switchPanel(direction) }
      onMoveRequested: function (dx, dy) {
        if (root.manageMode || root.stowedIds.length === 0) return
        // In the grid, up/down should cross a whole row; in the list every
        // direction is one step, because there is only one column.
        var step = root.gridMode ? (dx !== 0 ? dx : dy * root.gridColumns) : (dy !== 0 ? dy : dx)
        if (step === 0) return
        var count = root.stowedIds.length
        if (root.cursor < 0) {
          root.cursor = step > 0 ? 0 : count - 1
          return
        }
        root.cursor = ((root.cursor + step) % count + count) % count
      }
      onActivateRequested: {
        if (root.manageMode || root.cursor < 0 || root.cursor >= root.stowedIds.length) return
        root.activate(root.stowedIds[root.cursor], Qt.LeftButton)
      }
      onTextKey: function (text) {
        switch (text) {
          case "e": case "E": case "m": case "M": root.manageMode = !root.manageMode; break
        }
      }

      ColumnLayout {
        id: content
        anchors.fill: parent
        spacing: Style.space(10)

        // ------------------------------------------------------------- hero

        Item {
          Layout.fillWidth: true
          implicitHeight: hero.implicitHeight

          PanelHero {
            id: hero
            width: parent.width
            title: root.manageMode ? "Bar widgets" : "Drawer"
            meta: root.manageMode
              ? "HIDE OR SHOW"
              : (root.stowedIds.length === 0
                 ? "NOTHING HIDDEN"
                 : root.stowedIds.length + (root.stowedIds.length === 1 ? " WIDGET HIDDEN" : " WIDGETS HIDDEN"))
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconComponent: Component {
              Text {
                text: root.manageMode ? Model.GLYPH.gear : Model.iconGlyph(root.iconName, root.bar ? root.bar.position : "top")
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
              }
            }
            trailingControl: Component {
              PanelActionButton {
                iconText: root.manageMode ? Model.GLYPH.chevronLeft : Model.GLYPH.gear
                tooltipText: root.manageMode ? "Back to the drawer  ·  e" : "Choose what to hide  ·  e"
                foreground: root.foreground
                fontFamily: root.fontFamily
                onClicked: root.manageMode = !root.manageMode
              }
            }
          }
        }

        PanelSeparator { Layout.fillWidth: true; foreground: root.foreground }

        // ------------------------------------------------------------ views

        Item {
          Layout.fillWidth: true
          Layout.fillHeight: true
          implicitHeight: root.manageMode ? manageColumn.implicitHeight : drawerColumn.implicitHeight

          // ---- the drawer itself ----------------------------------------

          Flickable {
            id: drawerFlick
            anchors.fill: parent
            visible: !root.manageMode
            onWidthChanged: root.viewWidth = width
            Component.onCompleted: root.viewWidth = width
            contentWidth: width
            contentHeight: drawerColumn.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            interactive: contentHeight > height
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            ColumnLayout {
              id: drawerColumn
              width: drawerFlick.width
              spacing: Style.space(2)

              Text {
                Layout.fillWidth: true
                Layout.topMargin: Style.space(6)
                visible: root.stowedIds.length === 0
                text: "Nothing is hidden yet. Open the list and hide a widget — it moves off the bar and shows up here."
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                wrapMode: Text.WordWrap
              }

              Button {
                Layout.topMargin: Style.space(8)
                visible: root.stowedIds.length === 0
                iconText: Model.GLYPH.eyeOff
                text: "Choose widgets to hide"
                foreground: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.bodySmall
                onClicked: root.manageMode = true
              }

              Repeater {
                model: root.gridMode ? [] : root.stowed
                delegate: DrawerRow {}
              }

              // Grid mode. The cells are fixed-width, so the Grid is centered
              // in whatever the popup ended up being — a column count the
              // screen could not fit still lands on a tidy block.
              Grid {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: Style.space(4)
                Layout.bottomMargin: Style.space(4)
                visible: root.gridMode && root.stowedIds.length > 0
                columns: root.gridColumnCount
                spacing: 0

                Repeater {
                  model: root.gridMode ? root.stowed : []
                  delegate: GridCell {}
                }
              }
            }
          }

          // ---- the hide/show list ---------------------------------------

          Flickable {
            id: manageFlick
            anchors.fill: parent
            visible: root.manageMode
            contentWidth: width
            contentHeight: manageColumn.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            interactive: contentHeight > height
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            ColumnLayout {
              id: manageColumn
              width: manageFlick.width
              spacing: Style.space(4)

              PanelSectionHeader {
                Layout.fillWidth: true
                text: "IN THE BAR"
                foreground: root.foreground
                fontFamily: root.fontFamily
              }

              Text {
                Layout.fillWidth: true
                visible: root.barRows.length === 0
                text: "The bar has no other widgets."
                color: root.faint
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.italic: true
              }

              Repeater {
                model: root.barRows
                delegate: ManageRow { stowedRow: false }
              }

              PanelSeparator {
                Layout.fillWidth: true
                Layout.topMargin: Style.space(6)
                foreground: root.foreground
              }

              PanelSectionHeader {
                Layout.fillWidth: true
                text: "IN THE DRAWER"
                foreground: root.foreground
                fontFamily: root.fontFamily
              }

              Text {
                Layout.fillWidth: true
                visible: root.stowedIds.length === 0
                text: "Nothing hidden."
                color: root.faint
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.italic: true
              }

              Repeater {
                model: root.stowed
                delegate: ManageRow { stowedRow: true }
              }

              Button {
                Layout.topMargin: Style.space(6)
                visible: root.stowedIds.length > 1
                iconText: Model.GLYPH.eye
                text: "Show all again"
                foreground: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.bodySmall
                onClicked: root.unstowAll()
              }

              PanelSeparator {
                Layout.fillWidth: true
                Layout.topMargin: Style.space(8)
                foreground: root.foreground
              }

              PanelSectionHeader {
                Layout.fillWidth: true
                text: "DRAWER"
                foreground: root.foreground
                fontFamily: root.fontFamily
              }

              RowLayout {
                Layout.fillWidth: true
                spacing: Style.space(8)

                Text {
                  text: "View"
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                }

                Item { Layout.fillWidth: true; implicitHeight: 1 }

                ButtonGroup {
                  focusable: false
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  fontSize: Style.font.bodySmall
                  value: root.layoutMode
                  options: [
                    { value: "list", label: "List" },
                    { value: "grid", label: "Grid" }
                  ]
                  onChanged: function (value) { root.setOption("layout", value) }
                }
              }

              RowLayout {
                Layout.fillWidth: true
                visible: root.gridMode
                spacing: Style.space(8)

                Text {
                  text: "Icons per row"
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                }

                Item { Layout.fillWidth: true; implicitHeight: 1 }

                NumberField {
                  value: root.gridColumns
                  from: Model.MIN_COLUMNS
                  to: Model.MAX_COLUMNS
                  stepSize: 1
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  fontSize: Style.font.bodySmall
                  fieldWidth: Style.space(96)
                  onModified: function (value) { root.setOption("gridColumns", Model.clampColumns(value)) }
                }
              }

              Toggle {
                Layout.fillWidth: true
                visible: root.gridMode
                label: "Show names under the icons"
                description: "Off keeps the grid to bare icons."
                checked: root.gridLabels
                foreground: root.foreground
                fontFamily: root.fontFamily
                onClicked: root.setOption("gridLabels", !root.gridLabels)
              }

              RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: Style.space(4)
                spacing: Style.space(8)

                Text {
                  text: "Bar icon"
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                }

                Item { Layout.fillWidth: true; implicitHeight: 1 }
              }

              // A wrapping strip rather than a ButtonGroup: thirteen icons in
              // one row would be wider than the popup.
              Flow {
                Layout.fillWidth: true
                spacing: Style.space(2)

                Repeater {
                  model: Model.ICON_CHOICES

                  delegate: Button {
                    required property var modelData
                    iconText: modelData.value === "chevron"
                      ? Model.iconGlyph("chevron", root.bar ? root.bar.position : "top")
                      : modelData.glyph
                    tooltipText: modelData.label
                    selected: root.iconName === modelData.value
                    foreground: root.foreground
                    fontFamily: root.fontFamily
                    iconSize: Style.font.icon
                    horizontalPadding: Style.space(7)
                    verticalPadding: Style.space(4)
                    onClicked: root.setOption("icon", modelData.value)
                  }
                }
              }

              Toggle {
                Layout.fillWidth: true
                Layout.topMargin: Style.space(6)
                label: "Close when a widget is opened"
                description: "Off keeps the drawer open behind the widget's own panel."
                checked: root.closeOnActivate
                foreground: root.foreground
                fontFamily: root.fontFamily
                onClicked: root.setOption("closeOnActivate", !root.closeOnActivate)
              }

              Toggle {
                Layout.fillWidth: true
                label: "Show how many are hidden"
                description: "A small count next to the drawer icon."
                checked: root.showCount
                foreground: root.foreground
                fontFamily: root.fontFamily
                onClicked: root.setOption("showCount", !root.showCount)
              }

              Toggle {
                Layout.fillWidth: true
                label: "Hide the drawer when it is empty"
                description: "The icon disappears from the bar until something is hidden — reach the list again with omarchy-shell romeo.drawer manage."
                checked: root.hideWhenEmpty
                foreground: root.foreground
                fontFamily: root.fontFamily
                onClicked: root.setOption("hideWhenEmpty", !root.hideWhenEmpty)
              }
            }
          }
        }
      }
    }
  }

  // ------------------------------------------------------------- popup rows

  // One hidden widget, as it appears inside the drawer. Everything visible
  // here is bound to the widget's real bar button, so the row tracks the
  // widget's live state instead of a snapshot taken when it was hidden.
  component DrawerRow: Item {
    id: drawerRow

    required property var modelData
    required property int index

    readonly property string widgetId: String(modelData.id)
    readonly property var cell: root.cells[widgetId] || null
    readonly property var srcButton: cell ? cell.button : null
    readonly property bool installed: root.isInstalled(widgetId)
    readonly property bool hot: rowMouse.containsMouse || root.cursor === drawerRow.index

    readonly property string iconText: {
      var text = srcButton ? String(srcButton.text || "") : ""
      if (text) return text
      return installed ? Model.GLYPH.puzzle : Model.GLYPH.warn
    }
    readonly property bool iconIsGlyph: iconText.length <= 2

    Layout.fillWidth: true
    implicitHeight: Style.space(34)

    Rectangle {
      anchors.fill: parent
      anchors.leftMargin: -Style.space(4)
      anchors.rightMargin: -Style.space(4)
      radius: Style.cornerRadius > 0 ? Style.cornerRadius : 0
      color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, drawerRow.hot ? 0.10 : 0)

      Behavior on color { ColorAnimation { duration: 110 } }
    }

    Item {
      id: iconSlot
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(30)
      height: parent.height

      Text {
        anchors.centerIn: parent
        visible: !iconLoader.active
        text: drawerRow.iconText
        color: drawerRow.installed
          ? (drawerRow.srcButton && drawerRow.srcButton.active ? Color.urgent : root.foreground)
          : Color.urgent
        font.family: root.fontFamily
        font.pixelSize: drawerRow.iconIsGlyph ? Style.font.icon : Style.font.bodySmall
        renderType: Text.NativeRendering
        elide: Text.ElideRight
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
      }

      // Widgets that paint an image instead of a glyph hand the bar a
      // Component; instantiating the same one here keeps their icon intact.
      Loader {
        id: iconLoader
        anchors.centerIn: parent
        active: !!(drawerRow.srcButton && drawerRow.srcButton.iconComponent)
        sourceComponent: drawerRow.srcButton ? drawerRow.srcButton.iconComponent : null
      }
    }

    Column {
      anchors.left: iconSlot.right
      anchors.leftMargin: Style.space(8)
      anchors.right: parent.right
      anchors.rightMargin: Style.space(6)
      anchors.verticalCenter: parent.verticalCenter
      spacing: 0

      Text {
        width: parent.width
        text: root.displayName(drawerRow.widgetId)
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        elide: Text.ElideRight
      }

      Text {
        width: parent.width
        visible: !drawerRow.installed
        text: "not installed — remove it from the drawer"
        color: Color.urgent
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }
    }

    MouseArea {
      id: rowMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
      onEntered: root.cursor = drawerRow.index
      // The whole point of the row: hand the click to the widget's own bar
      // button, so left/right/middle keep doing what they do in the bar.
      onClicked: function (mouse) {
        if (!drawerRow.installed) { root.forget(drawerRow.widgetId); return }
        root.activate(drawerRow.widgetId, mouse.button)
      }
      onWheel: function (wheel) { root.scrollOn(drawerRow.widgetId, wheel.angleDelta.y) }
    }
  }

  // The same hidden widget as a grid tile. It reads its icon from, and
  // forwards its clicks to, exactly what DrawerRow does — only the geometry
  // and the optional name below the glyph differ.
  component GridCell: Item {
    id: gridCell

    required property var modelData
    required property int index

    readonly property string widgetId: String(modelData.id)
    readonly property var cell: root.cells[widgetId] || null
    readonly property var srcButton: cell ? cell.button : null
    readonly property bool installed: root.isInstalled(widgetId)
    readonly property bool hot: gridMouse.containsMouse || root.cursor === gridCell.index

    readonly property string iconText: {
      var text = srcButton ? String(srcButton.text || "") : ""
      if (text) return text
      return installed ? Model.GLYPH.puzzle : Model.GLYPH.warn
    }
    readonly property bool iconIsGlyph: iconText.length <= 2

    width: root.gridCellWidth
    height: root.gridCellHeight

    Rectangle {
      anchors.fill: parent
      anchors.margins: Style.space(2)
      radius: Style.cornerRadius > 0 ? Style.cornerRadius : 0
      color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, gridCell.hot ? 0.10 : 0)

      Behavior on color { ColorAnimation { duration: 110 } }
    }

    Column {
      anchors.centerIn: parent
      width: parent.width - Style.space(8)
      spacing: Style.space(3)

      Item {
        width: parent.width
        height: Style.space(22)

        Text {
          anchors.centerIn: parent
          visible: !gridIconLoader.active
          width: parent.width
          text: gridCell.iconText
          color: gridCell.installed
            ? (gridCell.srcButton && gridCell.srcButton.active ? Color.urgent : root.foreground)
            : Color.urgent
          font.family: root.fontFamily
          font.pixelSize: gridCell.iconIsGlyph ? Style.font.iconLarge : Style.font.bodySmall
          renderType: Text.NativeRendering
          elide: Text.ElideRight
          horizontalAlignment: Text.AlignHCenter
        }

        Loader {
          id: gridIconLoader
          anchors.centerIn: parent
          active: !!(gridCell.srcButton && gridCell.srcButton.iconComponent)
          sourceComponent: gridCell.srcButton ? gridCell.srcButton.iconComponent : null
        }
      }

      Text {
        visible: root.gridLabels
        width: parent.width
        text: root.displayName(gridCell.widgetId)
        color: gridCell.installed ? root.dim : Color.urgent
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
        horizontalAlignment: Text.AlignHCenter
        maximumLineCount: 1
      }
    }

    MouseArea {
      id: gridMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
      onEntered: root.cursor = gridCell.index
      onClicked: function (mouse) {
        if (!gridCell.installed) { root.forget(gridCell.widgetId); return }
        root.activate(gridCell.widgetId, mouse.button)
      }
      onWheel: function (wheel) { root.scrollOn(gridCell.widgetId, wheel.angleDelta.y) }
    }

    // Name-on-hover, for a grid with the labels turned off. It is painted
    // inside the popup rather than through bar.showTooltip, which only draws
    // in the bar's own window, and it is pinned inside the tile so the
    // Flickable can never clip it off the bottom row.
    Rectangle {
      visible: !root.gridLabels && gridMouse.containsMouse && gridCell.installed
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      anchors.bottomMargin: -Style.space(2)
      width: Math.min(parent.width + Style.space(16), hoverName.implicitWidth + Style.space(10))
      height: hoverName.implicitHeight + Style.space(5)
      radius: Style.cornerRadius > 0 ? Style.cornerRadius : 0
      color: Color.tooltip.background
      border.width: Math.max(1, Style.normalBorderWidth)
      border.color: Color.tooltip.border
      z: 20

      Text {
        id: hoverName
        anchors.fill: parent
        anchors.margins: Style.space(3)
        text: root.displayName(gridCell.widgetId)
        color: Color.tooltip.text
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
      }
    }
  }

  // One row of the hide/show list, for a widget on either side of the fence.
  component ManageRow: Item {
    id: manageRow

    required property var modelData
    property bool stowedRow: false

    readonly property string widgetId: String(modelData.id)
    readonly property bool installed: root.isInstalled(widgetId)

    Layout.fillWidth: true
    implicitHeight: Style.space(30)

    Text {
      id: manageName
      anchors.left: parent.left
      anchors.right: manageActions.left
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      text: root.displayName(manageRow.widgetId)
      color: manageRow.installed ? root.foreground : Color.urgent
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      elide: Text.ElideRight
    }

    Row {
      id: manageActions
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(4)

      PanelActionButton {
        visible: manageRow.stowedRow
        iconText: Model.GLYPH.chevronUp
        tooltipText: "Move up in the drawer"
        foreground: root.foreground
        fontFamily: root.fontFamily
        fontSize: Style.font.iconSmall
        onClicked: root.reorder(manageRow.widgetId, -1)
      }

      PanelActionButton {
        visible: manageRow.stowedRow
        iconText: Model.GLYPH.chevronDown
        tooltipText: "Move down in the drawer"
        foreground: root.foreground
        fontFamily: root.fontFamily
        fontSize: Style.font.iconSmall
        onClicked: root.reorder(manageRow.widgetId, 1)
      }

      Button {
        iconText: manageRow.stowedRow ? Model.GLYPH.eye : Model.GLYPH.eyeOff
        text: manageRow.stowedRow ? "Show" : "Hide"
        foreground: root.foreground
        fontFamily: root.fontFamily
        horizontalPadding: Style.space(8)
        verticalPadding: Style.space(3)
        iconSize: Style.font.bodySmall
        fontSize: Style.font.bodySmall
        onClicked: root.toggleStow(manageRow.widgetId)
      }
    }
  }

  // -------------------------------------------------------------------- IPC

  IpcHandler {
    target: "romeo.drawer"

    function open(): void { root.openDrawer() }
    function close(): void { root.close() }
    function toggle(): void { if (root.opened) root.close(); else root.openDrawer() }
    function manage(): void { root.manageMode = true; root.open() }

    function hide(id: string): string {
      return root.stow(String(id)) ? "ok" : "not in the bar: " + id
    }

    function show(id: string): string {
      return root.unstow(String(id)) ? "ok" : "not in the drawer: " + id
    }

    function showAll(): string {
      return root.unstowAll() ? "ok" : "nothing hidden"
    }

    function list(): string {
      var hidden = root.stowed.map(function (item) {
        return { id: item.id, name: root.displayName(item.id), home: item.home, before: item.before, installed: root.isInstalled(item.id) }
      })
      var visible = root.barRows.map(function (row) {
        return { id: row.id, name: root.displayName(row.id), section: row.section }
      })
      return JSON.stringify({ hidden: hidden, bar: visible }, null, 2)
    }
  }
}
