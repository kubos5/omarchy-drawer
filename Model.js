// Pure logic for the Drawer widget: the glyph table, the shell.json
// transforms that stow and restore a bar widget, and the small amount of UI
// state that has to outlive the widget itself.
//
// Everything here is plain JS with no QML dependencies so it can be exercised
// with node against fixtures.
.pragma library

var SECTIONS = ["left", "center", "right"]

// Nerd Font glyphs are written as codepoints rather than pasted characters:
// private-use-area bytes do not survive every editor round-trip, and a lost
// glyph renders as nothing rather than as an error.
var GLYPH = {
  grid:         String.fromCodePoint(0xf00a),
  squares:      String.fromCodePoint(0xf009),
  tiles:        String.fromCodePoint(0xf0570),
  apps:         String.fromCodePoint(0xf003b),
  hamburger:    String.fromCodePoint(0xf0c9),
  kebab:        String.fromCodePoint(0xf01d9),
  dots:         String.fromCodePoint(0xf141),
  inbox:        String.fromCodePoint(0xf0687),
  folder:       String.fromCodePoint(0xf07b),
  layers:       String.fromCodePoint(0xf0136),
  brick:        String.fromCodePoint(0xf1288),
  puzzle:       String.fromCodePoint(0xf0431),
  list:         String.fromCodePoint(0xf0279),
  chevronDown:  String.fromCodePoint(0xf0140),
  chevronUp:    String.fromCodePoint(0xf0143),
  chevronLeft:  String.fromCodePoint(0xf053),
  chevronRight: String.fromCodePoint(0xf054),
  gear:         String.fromCodePoint(0xf0493),
  eye:          String.fromCodePoint(0xf06e),
  eyeOff:       String.fromCodePoint(0xf070),
  warn:         String.fromCodePoint(0xf0026),
  check:        String.fromCodePoint(0xf00c)
}

// The bar icon the user can pick from. `chevron` is resolved against the bar
// position at paint time, so it always points away from the bar edge.
var ICON_CHOICES = [
  { value: "grid",      label: "Grid",      glyph: GLYPH.grid },
  { value: "squares",   label: "Squares",   glyph: GLYPH.squares },
  { value: "tiles",     label: "Tiles",     glyph: GLYPH.tiles },
  { value: "apps",      label: "Apps",      glyph: GLYPH.apps },
  { value: "hamburger", label: "Menu",      glyph: GLYPH.hamburger },
  { value: "kebab",     label: "More",      glyph: GLYPH.kebab },
  { value: "dots",      label: "Dots",      glyph: GLYPH.dots },
  { value: "inbox",     label: "Inbox",     glyph: GLYPH.inbox },
  { value: "folder",    label: "Folder",    glyph: GLYPH.folder },
  { value: "layers",    label: "Layers",    glyph: GLYPH.layers },
  { value: "brick",     label: "Brick",     glyph: GLYPH.brick },
  { value: "puzzle",    label: "Plugin",    glyph: GLYPH.puzzle },
  { value: "chevron",   label: "Chevron",   glyph: GLYPH.chevronDown }
]

var LAYOUT_MODES = ["list", "grid"]
var MIN_COLUMNS = 2
var MAX_COLUMNS = 8

function normalizeLayoutMode(value) {
  return LAYOUT_MODES.indexOf(String(value)) === -1 ? "list" : String(value)
}

function clampColumns(value) {
  var columns = Math.round(Number(value))
  if (!isFinite(columns)) return 4
  return Math.max(MIN_COLUMNS, Math.min(MAX_COLUMNS, columns))
}

function iconGlyph(name, barPosition) {
  if (String(name) === "chevron") {
    switch (String(barPosition)) {
      case "bottom": return GLYPH.chevronUp
      case "left":   return GLYPH.chevronRight
      case "right":  return GLYPH.chevronLeft
      default:       return GLYPH.chevronDown
    }
  }
  for (var i = 0; i < ICON_CHOICES.length; i++)
    if (ICON_CHOICES[i].value === String(name)) return ICON_CHOICES[i].glyph
  return GLYPH.grid
}

// UI state that has to survive the widget being rebuilt.
//
// Any layout change to shell.json — including the ones this plugin makes —
// reassigns the bar's Repeater models, which destroys and recreates every
// widget. Without somewhere outside the widget to remember it, clicking
// "Hide" would make the popup the user clicked in disappear. A `.pragma
// library` script is shared per QML engine and outlives the widget, so this
// object is that place. It is keyed by screen name so a rebuild reopens the
// drawer only on the monitor it was open on.
var ui = {
  openScreen: "",
  manage: false
}

function arrayFrom(value) {
  if (!value) return []
  if (Array.isArray(value)) return value.slice()
  // Values crossing from C++ arrive as QVariantList, which is array-like but
  // fails Array.isArray. Reading them positionally is the only safe path.
  var length = Number(value.length)
  if (!isFinite(length) || length <= 0) return []
  var out = []
  for (var i = 0; i < length; i++) out.push(value[i])
  return out
}

function entryId(entry) {
  if (!entry) return ""
  if (typeof entry === "string") return String(entry)
  return String(entry.id || "")
}

// One stowed widget: which widget, which section it came from, and the id of
// the widget it sat in front of. `before` is what makes "show" put it back
// exactly where it was rather than at the end of the section.
function normalizeItems(rawItems) {
  var list = arrayFrom(rawItems)
  var out = []
  var seen = {}
  for (var i = 0; i < list.length; i++) {
    var raw = list[i]
    var id = typeof raw === "string" ? String(raw) : String(raw && raw.id || "")
    if (!id || seen[id]) continue
    seen[id] = true
    var home = raw && typeof raw === "object" ? String(raw.home || "") : ""
    if (SECTIONS.indexOf(home) === -1) home = "right"
    out.push({
      id: id,
      home: home,
      before: raw && typeof raw === "object" ? String(raw.before || "") : ""
    })
  }
  return out
}

function itemIds(rawItems) {
  return normalizeItems(rawItems).map(function (item) { return item.id })
}

function ensureShape(config) {
  if (!config.bar || typeof config.bar !== "object") config.bar = {}
  if (!config.bar.layout || typeof config.bar.layout !== "object") config.bar.layout = {}
  for (var i = 0; i < SECTIONS.length; i++)
    if (!Array.isArray(config.bar.layout[SECTIONS[i]])) config.bar.layout[SECTIONS[i]] = []
  if (!Array.isArray(config.plugins)) config.plugins = []
  return config
}

// The drawer's own layout entry, upgraded to object form so settings can be
// written onto it. Returns null when the drawer is not in the bar at all.
function drawerEntry(config, drawerId) {
  for (var s = 0; s < SECTIONS.length; s++) {
    var arr = config.bar.layout[SECTIONS[s]]
    for (var i = 0; i < arr.length; i++) {
      if (entryId(arr[i]) !== drawerId) continue
      if (typeof arr[i] === "string") arr[i] = { id: drawerId }
      return arr[i]
    }
  }
  return null
}

function findInLayout(config, id) {
  for (var s = 0; s < SECTIONS.length; s++) {
    var arr = config.bar.layout[SECTIONS[s]]
    for (var i = 0; i < arr.length; i++)
      if (entryId(arr[i]) === id) return { section: SECTIONS[s], index: i }
  }
  return null
}

function asEntryObject(entry, id) {
  if (!entry || typeof entry === "string") return { id: id }
  var copy = {}
  for (var key in entry) copy[key] = entry[key]
  copy.id = id
  return copy
}

// Every widget the bar is currently showing, in layout order, minus the
// drawer itself. This is the "what could be hidden" list.
function barRows(config, drawerId) {
  // Read-only: this runs on every config change to build the manage list, so
  // it must not reshape the live config object the way the mutators do.
  var layout = config && config.bar && config.bar.layout ? config.bar.layout : {}
  var out = []
  for (var s = 0; s < SECTIONS.length; s++) {
    var arr = arrayFrom(layout[SECTIONS[s]])
    for (var i = 0; i < arr.length; i++) {
      var id = entryId(arr[i])
      if (!id || id === drawerId) continue
      out.push({ id: id, section: SECTIONS[s], index: i })
    }
  }
  return out
}

// Move a widget out of the bar and into the drawer.
//
// The widget's inline settings are parked in the top-level `plugins[]` array
// rather than inside the drawer's own entry, for two reasons: a third-party
// widget is only enabled — and so only present in the widget registry — while
// its id appears somewhere in shell.json, and the shell writes a widget's own
// saved state to its `plugins[]` entry once it is out of the layout. Keeping
// the entry there means a stowed widget that saves settings keeps working.
function stow(config, drawerId, id) {
  var shaped = ensureShape(config)
  if (!id || id === drawerId) return false

  var drawer = drawerEntry(shaped, drawerId)
  if (!drawer) return false

  var location = findInLayout(shaped, id)
  if (!location) return false

  var section = shaped.bar.layout[location.section]
  var entry = asEntryObject(section[location.index], id)

  // The neighbour this widget sat in front of, so it can be put back between
  // the same two widgets later.
  var before = ""
  for (var i = location.index + 1; i < section.length; i++) {
    var neighbour = entryId(section[i])
    if (neighbour) { before = neighbour; break }
  }

  section.splice(location.index, 1)
  shaped.plugins.push(entry)

  var items = normalizeItems(drawer.items).filter(function (item) { return item.id !== id })
  items.push({ id: id, home: location.section, before: before })
  drawer.items = items
  return true
}

// Walk `before` through the drawer's own records until it names a widget that
// is actually in the section right now. A widget whose neighbour was itself
// hidden still lands in the right place, and the visited set keeps a pair of
// records that point at each other from looping forever.
function restoreIndex(section, items, before) {
  var visited = {}
  var target = String(before || "")
  while (target && !visited[target]) {
    visited[target] = true
    for (var i = 0; i < section.length; i++)
      if (entryId(section[i]) === target) return i
    var next = ""
    for (var j = 0; j < items.length; j++)
      if (items[j].id === target) { next = items[j].before; break }
    target = next
  }
  return section.length
}

// Move a widget out of the drawer and back into the bar, at the spot it left.
function unstow(config, drawerId, id) {
  var shaped = ensureShape(config)
  var drawer = drawerEntry(shaped, drawerId)
  if (!drawer) return false

  var items = normalizeItems(drawer.items)
  var record = null
  for (var i = 0; i < items.length; i++) if (items[i].id === id) { record = items[i]; break }
  if (!record) return false

  var remaining = items.filter(function (item) { return item.id !== id })
  drawer.items = remaining

  // Reclaim the parked entry so the widget comes back with its settings.
  var entry = { id: id }
  for (var p = 0; p < shaped.plugins.length; p++) {
    if (entryId(shaped.plugins[p]) !== id) continue
    entry = asEntryObject(shaped.plugins[p], id)
    shaped.plugins.splice(p, 1)
    break
  }

  // Already back in the bar somehow: drop the record and leave the bar alone.
  if (findInLayout(shaped, id)) return true

  var section = shaped.bar.layout[record.home] || shaped.bar.layout.right
  section.splice(restoreIndex(section, remaining, record.before), 0, entry)
  return true
}

function unstowAll(config, drawerId) {
  var shaped = ensureShape(config)
  var drawer = drawerEntry(shaped, drawerId)
  if (!drawer) return false
  var ids = itemIds(drawer.items)
  for (var i = 0; i < ids.length; i++) unstow(shaped, drawerId, ids[i])
  return ids.length > 0
}

// Drop a record for a widget that is no longer installed. The parked entry
// goes with it, so an uninstalled plugin does not keep a phantom enabled bit.
function forget(config, drawerId, id) {
  var shaped = ensureShape(config)
  var drawer = drawerEntry(shaped, drawerId)
  if (!drawer) return false
  var items = normalizeItems(drawer.items)
  var next = items.filter(function (item) { return item.id !== id })
  if (next.length === items.length) return false
  drawer.items = next
  for (var p = shaped.plugins.length - 1; p >= 0; p--)
    if (entryId(shaped.plugins[p]) === id) shaped.plugins.splice(p, 1)
  return true
}

// Reorder within the drawer. Purely cosmetic — it decides the order of the
// rows in the popup, not where a widget goes when it is shown again.
function reorder(config, drawerId, id, delta) {
  var shaped = ensureShape(config)
  var drawer = drawerEntry(shaped, drawerId)
  if (!drawer) return false
  var items = normalizeItems(drawer.items)
  var from = -1
  for (var i = 0; i < items.length; i++) if (items[i].id === id) { from = i; break }
  if (from === -1) return false
  var to = from + (Number(delta) < 0 ? -1 : 1)
  if (to < 0 || to >= items.length) return false
  var moved = items.splice(from, 1)[0]
  items.splice(to, 0, moved)
  drawer.items = items
  return true
}

function setOption(config, drawerId, key, value) {
  var shaped = ensureShape(config)
  var drawer = drawerEntry(shaped, drawerId)
  if (!drawer) return false
  drawer[key] = value
  return true
}

// A short human summary for the bar tooltip.
function tooltip(names) {
  var list = arrayFrom(names)
  if (list.length === 0) return "Drawer — nothing hidden"
  if (list.length <= 4) return "Drawer — " + list.join(", ")
  return "Drawer — " + list.slice(0, 3).join(", ") + " and " + (list.length - 3) + " more"
}

if (typeof module !== "undefined") {
  module.exports = {
    SECTIONS: SECTIONS,
    GLYPH: GLYPH,
    ICON_CHOICES: ICON_CHOICES,
    LAYOUT_MODES: LAYOUT_MODES,
    MIN_COLUMNS: MIN_COLUMNS,
    MAX_COLUMNS: MAX_COLUMNS,
    normalizeLayoutMode: normalizeLayoutMode,
    clampColumns: clampColumns,
    iconGlyph: iconGlyph,
    arrayFrom: arrayFrom,
    entryId: entryId,
    normalizeItems: normalizeItems,
    itemIds: itemIds,
    ensureShape: ensureShape,
    drawerEntry: drawerEntry,
    findInLayout: findInLayout,
    barRows: barRows,
    stow: stow,
    unstow: unstow,
    unstowAll: unstowAll,
    forget: forget,
    reorder: reorder,
    setOption: setOption,
    restoreIndex: restoreIndex,
    tooltip: tooltip
  }
}
