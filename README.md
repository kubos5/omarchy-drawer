# Drawer

One bar icon that hides other bar widgets behind a popup menu, and hands them
back with their panels and click actions intact.

```
omarchy bar move romeo.drawer --section right
```

## Using it

- **Left click** the drawer icon — the menu of hidden widgets.
- **Right click** it — straight to the hide/show list.
- Inside the menu, **click a widget** to close the drawer and open that
  widget's own panel. Right click and middle click are forwarded too, and so
  is the scroll wheel, so scrolling the Audio row still changes the volume.
- The gear in the popup header switches between the drawer and the list;
  `e` does the same from the keyboard, arrows move, Enter opens, Esc closes.
  In grid view left/right step one tile and up/down cross a whole row.

## List or grid

`View` in the drawer's settings switches the menu between **list** — one row
per widget, icon and name — and **grid**, a block of icon tiles. The grid takes
`Icons per row` (2 to 8) and sizes the popup to fit; ask for more columns than
the screen has room for and it quietly drops to what fits, with the tiles
sharing the row evenly either way.

Names are **off** in the grid by default, which is the point of it — hovering a
tile shows the name instead. `Show names under the icons` puts them back
under each tile, and widens the tiles to suit.

Hiding a widget takes it out of `bar.layout` in `~/.config/omarchy/shell.json`
and records the section and the neighbour it sat in front of. Showing it again
puts it back between the same two widgets, with its settings, even if that
neighbour is itself hidden at the time.

## Settings

Editable from the drawer's own list, or inline on the entry in `shell.json`:

| Key | Default | What it does |
|---|---|---|
| `items` | `[]` | The hidden widgets. Managed by the drawer; each record is `{id, home, before}`. |
| `layout` | `"list"` | `list` or `grid`. |
| `gridColumns` | `4` | Tiles per row in the grid, 2 to 8. |
| `gridLabels` | `false` | Names under the tiles in the grid. Off shows them on hover instead. |
| `icon` | `"grid"` | `grid`, `squares`, `tiles`, `apps`, `hamburger`, `kebab`, `dots`, `inbox`, `folder`, `layers`, `brick`, `puzzle`, or `chevron` (which follows the bar edge). |
| `showCount` | `true` | Paints the number of hidden widgets next to the icon. |
| `closeOnActivate` | `true` | Off keeps the drawer open behind the widget's panel. |
| `hideWhenEmpty` | `false` | Takes the icon off the bar until something is hidden. |

## IPC

```bash
omarchy-shell romeo.drawer toggle          # open / close the menu
omarchy-shell romeo.drawer open
omarchy-shell romeo.drawer close
omarchy-shell romeo.drawer manage          # open on the hide/show list
omarchy-shell romeo.drawer list            # JSON: what is hidden, what is in the bar
omarchy-shell romeo.drawer hide omarchy.bluetooth
omarchy-shell romeo.drawer show omarchy.bluetooth
omarchy-shell romeo.drawer showAll
```

`omarchy-shell shell toggle <id>` and the panel hotkeys still reach a hidden
widget — it registers with the bar the same way a visible one does.

## How it works

A hidden widget is not re-created inside the popup. It stays mounted **in the
bar window**, inside a zero-sized clipping Item parked exactly on top of the
drawer's icon. That is not an optimization, it is a requirement: a bar
widget's tooltip goes through `Bar.targetBelongsToWindow` and its popup
anchors through `anchorItem.QsWindow.window`, and both reject a target that
lives in another window, so a widget re-hosted inside this plugin's popup
would lose every panel it owns. Parking it on the drawer's icon also means its
panel opens directly under the drawer.

The popup therefore shows a *proxy* row per hidden widget. The row finds the
widget's own `WidgetButton` and binds its glyph, so a muted speaker or a
ticking clock still reads correctly, and a click calls that button's
`triggerPress` — which is what makes the row behave exactly like the bar icon
it replaced.

Three details worth knowing before editing this:

- **A hidden widget's settings are parked in shell.json's top-level
  `plugins[]`, not inside the drawer's entry.** A third-party widget is only in
  the widget registry while its id appears somewhere in shell.json, and the
  shell writes a widget's own saved state to its `plugins[]` entry once it is
  out of the layout. Keeping the entry there is what lets a hidden widget go on
  saving its own settings.
- **The slot the drawer registers with the bar is a bare `QtObject`.** That is
  enough for `Bar.findPanelWidget()` to reach a hidden widget, while
  `Bar.moduleDropAtScene()` skips it — that one filters on `slot.visible`,
  which a `QtObject` does not have, so drawer contents never become
  drag-reorder targets in the bar.
- **`Model.ui` is deliberately mutable module state.** Any layout change
  rebuilds every bar widget, this one included, so clicking "Hide" destroys the
  popup the click came from. A `.pragma library` object is shared per QML
  engine and outlives the widget, so the replacement can pick the popup back
  up on the monitor it was open on.

## Limits

The drawer works best for widgets that own a panel — audio, network,
bluetooth, power, clock, weather, display, agents, and third-party panels all
behave normally from inside it. Container widgets that paint *many* buttons
(the system tray, workspaces, indicators) degrade: the row shows and forwards
to the first of those buttons only, so they are better left in the bar.

Editing `Model.js` needs a full `omarchy restart shell`; QML under
`~/.config/omarchy/plugins/` hot-reloads, but an imported `.js` library stays
cached, and a hot reload also leaves the old `IpcHandler` registered.
