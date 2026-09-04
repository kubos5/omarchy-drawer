# Drawer

Hide plugins that clutter your menu bar

Install:
```bash
omarchy plugin add https://github.com/kubos5/omarchy-drawer.git --enable
```

## Get started

- Click the icon to open the drawer
- Open the settings, and select which plugins to hide
- Done! Hidden plugins show up in the drawer menu.

You can also right click the icon to go straight to the settings.

---

## How does it work?

Hiding a widget takes it out of `bar.layout` in `~/.config/omarchy/shell.json` and records the section and the neighbour it sat in front of.
Showing it again puts it back between the same two widgets, with its settings, even if that neighbour is itself hidden at the time.

## Settings

Editable from the drawer's own list, or inline on the entry in `shell.json`:

| Key | Default | What it does |
|---|---|---|
| `items` | `[]` | The hidden widgets. Managed by the drawer, each record is `{id, home, before}`. |
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

`omarchy-shell shell toggle <id>` and the panel hotkeys still reach a hidden widget, because it registers with the bar the same way a visible one does.

## Limits

The drawer works best for widgets that own a panel: audio, network, bluetooth, power, clock, weather, display, agents, and third-party panels all behave normally from inside it.
Container widgets that paint *many* buttons (the system tray, workspaces, indicators) degrade: the row shows and forwards to the first of those buttons only, so they are better left in the bar.

Editing `Model.js` needs a full `omarchy restart shell`; QML under `~/.config/omarchy/plugins/` hot-reloads, but an imported `.js` library stays cached, and a hot reload also leaves the old `IpcHandler` registered.
