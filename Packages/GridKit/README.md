# GridKit

A layout grid for SwiftUI: columns, rows and a baseline, plus a check that tells you when a
view has left them.

## The contract

Adding GridKit to a project means the whole layout sits on the grid, in both directions,
from the first pass. Not columns now and rows later.

1. **Columns.** Wrap the screen in `GridContainer`. Size every part in whole columns with
   `grid.span(n)` or `UnitRow`. A part fills its columns; nothing is centred in a space wider
   than itself, and no span is divided by eye.
2. **Rows.** Every height, gap and line height is a multiple of `Rhythm.unit` (4pt). Write
   `Rhythm.u(n)`. Text uses `.rhythm(spec)`, which locks its line box.
3. **Shared rows.** When parts sit side by side in different panes, lay them out on one
   `RowGrid`, so they start and end on the same lines.
4. **Flexible space is snapped.** A layout that fills the screen snaps its total height to
   8pt and hangs from the top (`Rhythm.snapDown`). Otherwise everything below the flexible
   part drifts off the baseline.
5. **Checked.** Put `.gridChecked()` on every part that should be on the grid. Then prove it:
   show the overlay and assert there are no faults (below). Do this for every layout the
   screen has: each size class and each orientation.

If a part cannot be on the grid (a circle centred in its pane), say so in code with
`.gridChecked(columns: false)` and a comment. An unchecked part is an unverified part.

## What's in the box

| Type | What it does |
| --- | --- |
| `Rhythm` | The baseline unit and snapping: `u(n)`, `snap`, `snapDown`, `isOnGrid`. |
| `TypeSpec`, `.rhythm()` | A type style with its line height locked to the baseline. |
| `ColumnGrid` | Columns, margin and gutter for a width: `adaptive(width:)`, `span(n)`, `x(ofColumn:)`. |
| `RowGrid` | Bands of equal height for a given height: `fitting(height:rows:)`, `span(n)`, `y(ofRow:)`. |
| `GridContainer` | Measures the width, publishes the `ColumnGrid` in the environment, applies the margins, draws the overlay. |
| `UnitRow` | A row whose children each take a whole number of columns. |
| `.gridChecked()` | Marks a view as required to be on the grid. |
| `GridOverlay` | The columns and baselines drawn over the screen. |

## Checking

`GridContainer(showsOverlay: true)` draws the grid and switches the checks on. Any checked
view whose sides are off a column edge, whose top is off a baseline, or whose height is not a
whole number of units is outlined in red.

Each fault is also an accessibility element with the identifier `grid-fault`, so a UI test
can fail the build when a layout slips:

```swift
let faults = app.descendants(matching: .any).matching(identifier: "grid-fault")
XCTAssertEqual(faults.count, 0, faults.allElementsBoundByIndex.map(\.label).joined(separator: "; "))
```

Run that test in every orientation and on every device class the app supports.

`ColumnGrid.fault(of:)` is the same check as a pure function, for unit tests.

## The same rules outside SwiftUI

GridKit is Swift, but the contract applies to anything laid out alongside the app (a web
page, for instance). There:

- Use the same numbers: twelve columns, the app's margins and gutters, rows a multiple of
  the unit apart (8px works well for running text).
- Make every line height, gap and block height a multiple of the row. Pictures included:
  round their heights to the row, or everything after them drifts.
- Build an overlay that draws the columns and the rows.
- Measure, don't eyeball: script a check of each block's top and height against the row,
  at every breakpoint.
