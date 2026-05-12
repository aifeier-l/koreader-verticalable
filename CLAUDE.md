# KOReader Vertical Text (vertical-rl) Implementation

## Project Goal

Implement Japanese vertical-rl text rendering in KOReader/crengine.
Target: 縦書き (tategumi) for Japanese novels in EPUB format.

## Build & Test

```bash
# Build
nix develop --command ./kodev build -d emulator

# Run emulator
nix develop --command ./kodev run emulator

# Run unit tests
nix develop --command make -j1 testfront

# Run vertical text tests only
nix develop --command ./kodev test front -f "Vertical text"
```

Test fixture: `spec/front/unit/data/fixtures/vertical_text/simple_ja_noruby.epub`

## Architecture: Y=X Coordinate Swap

The core design decision is to re-use the existing horizontal rendering pipeline
by swapping X and Y roles. All rendering stores horizontal progression in Y-axis
fields so that the page splitter (which splits on Y) naturally splits on columns.

### Coordinate mapping (doc space → screen)

```
doc_y  = page_y + (horizontal offset from right edge)  →  screen_x = page_right - (doc_y - page_y)
doc_x  = vertical pixel position in column             →  screen_y = doc_x
```

### FlowState (lvrend.cpp)

- `c_x` = accumulated horizontal advance (column progression, for vertical)
- `c_y` = same value as c_x for vertical (advanced in sync in `addContentLine`)
- `l_x`, `l_y` = saved at `newBlockLevel`, both equal at each level entry
- `page_h` is swapped to `page_width` at FlowState constructor for vertical mode
- `context.AddLine(c_x, c_x+height, ...)` feeds horizontal offsets to page splitter

### Block rendering (lvrend.cpp `renderBlockElementEnhanced`)

```cpp
fmt.setX( x );                              // left margin (= vertical body margin on screen)
fmt.setY( flow->getCurrentRelativeY() );   // horizontal advance (= doc_y offset from parent)
```

`getCurrentRelativeY() = c_y - l_y == c_x - l_x` in vertical mode (they always advance together).

### Formatted text draw (lvtextfm_layout_h.cpp `LFormattedText::Draw`)

At entry, x and y are swapped back to screen coordinates:
```cpp
if (is_vertical) { int tmp = x; x = y; y = tmp; }
int line_x = is_vertical ? (clip.right - x) : x;
int line_y = y;
```

Per-glyph positioning in vertical mode:
```cpp
x0 = line_x - frmline->height - word->y;   // screen X (horizontal position)
y0 = y + frmline->x + clamped_x;           // screen Y (vertical position)
```

Column progression: `line_x -= frmline->height` after each line.

### Coordinate conversion (lvdocview.cpp, cre.cpp)

`windowToDocPoint` (screen → doc):
```cpp
pt.y = page_y + (page_right - screen_x);   // doc_y = horizontal advance
pt.x = screen_y;                            // doc_x = vertical position
```

`docToWindowPoint` (doc → screen):
```cpp
screen_x = page_right - (doc_y - page_y_val);
screen_y = doc_x;   // = pt.x before conversion
pt.x = screen_x;
pt.y = doc_x;
```

`docToWindowRect` normalizes left/right after conversion (since increasing doc_y → decreasing screen_x).
Off-screen rejection: returns false if `screen_x < page_left - 50 || screen_x > page_right + 50`.

`isVerticalText()` heuristic (lvdocview.cpp):
```cpp
bool LVDocView::isVerticalText() const {
    if (m_pages.length() == 0) return false;
    int page_h = m_pages[0]->height;
    return (page_h > 0 && page_h <= m_dx + 32);
}
```
(DOM writing_mode traversal unreliable; page_h == page_width only in vertical mode.)

## Implemented (Phase 1 complete)

### crengine submodule (base/)

| File | Change |
|------|--------|
| `lvrend.cpp` | FlowState: `c_x`, `l_x`, `isVertical()`, `addContentLine` dual advance, `page_h` swap, `getCurrentFlowAdvance/RelativeAdvance`, `newBlockLevel`/`leaveBlockLevel` c_x save/restore |
| `lvrend.cpp` | `renderBlockElementEnhanced`: uses `getCurrentRelativeY()` for Y (not vertical special case) |
| `lvrend.cpp` | `DrawDocument`: removed `vert_shift` hack; uses plain `doc_x+x0+padding_left, doc_y+y0+padding_top` |
| `lvtextfm_layout_h.cpp` | `Draw()`: swap x/y at entry; `line_x = clip.right - x`; column draw with `word->y` for x/y; per-column clip; monotonic `vert_min_next_x` guard |
| `lvtextfm_layout_h.cpp` | `Draw()`: sets `LFNT_HINT_IS_VERTICAL` in drawFlags for vertical text |
| `lvtextfm.cpp` | `measureText()`: ruby inline box uses `lastFont->getSize()` as advance per char; counts base chars from DOM to compute multi-char ruby advance |
| `lvfntman.cpp` | `DrawTextString()`: calls `setupHBFeatures(is_vertical)` before `hb_shape` to enable `+vert`/`+vrt2` OpenType features |

### cre.cpp (KOReader bridge)

- `isVerticalText()` added to `lvdocview.h`
- `getWordFromPosition`: skip margin adjustment for vertical text
- `docToWindowRect`: normalize left/right for vertical-rl (swap if left > right)
- `docToWindowPoint`: off-screen rejection for out-of-range screen_x

### lvdocview.cpp

- `windowToDocPoint`: vertical branch with Y=X swap
- `docToWindowPoint`: vertical branch with reverse mapping + off-screen rejection
- `isVerticalText()`: page-height heuristic

### Formal tests

`spec/unit/vertical_text_spec.lua` — 14 tests:
- Word lookup (sbox positive, round-trip coverage)
- Multi-column selection sboxes all positive
- Vertical in-column selection height check
- Horizontal mode regression
- Ruby annotation sboxes: on-screen Y bounds (2 tests, `simple_ja_ruby.epub`)

## Known Issues / Next (Phase 2)

### Off-screen sboxes near ruby annotations — defensive fix in place; root cause queued

**Symptom suppressed** by `docToWindowPoint` screen_y bounds check
(`lvdocview.cpp:2748-2768`). When `screen_y = doc_x` falls outside
`[page_top - 50, page_bottom + 50]`, the conversion returns false and
`docToWindowRect` drops the segment — no visible off-screen sbox.

**Regression test:** `Ruby annotation sboxes #ruby` in
`spec/unit/vertical_text_spec.lua` (2 tests using `simple_ja_ruby.epub`).

**Root cause not yet localized.** Suspect `getRect`/`getAbsRect`
(`lvtinydom.cpp:10716-10718`) for `<rt>`-descendant text nodes in vertical mode:
rt's formatted text uses `page_h = getDocument()->getPageHeight()` (≈800px), so
`getAvailableWidthAtY` returns the full page height as column length, and the rt's
internal `frmline->x + word->x` (vertical offset within rt column) gets added on
top of `rc.left` (= inlineBox.X = base char doc_x). When rt chars stack deeply the
sum exceeds page_height and `screen_y` lands off-screen.

**Phase 2 task:** Uncomment the diagnostic `print` in the spec, run
`./kodev test front -f "Ruby annotation"`, and capture sbox.y values. Then patch
`getRect` to use the correct doc_x formula for inline-box-descendant (rt) nodes in
vertical mode.

### **[Phase 2 BUG]** Ruby boxing crash (SIGSEGV) — blocks real-EPUB use

**Severity: HIGH.** Any EPUB that contains `<ruby>` elements with default
`display: ruby` will SIGSEGV crengine. This affects all standard Japanese
novels with ruby annotations (the target use case for this project).

**Crash location:** `lvtinydom.cpp:8186–8582` — ruby boxing code triggered when
`BLOCK_RENDERING_ENHANCED` is set (always set for new documents). The crash is a
SIGSEGV in the C++ layer; it cannot be caught by Lua `pcall`.

**Root cause: identified by `git bisect`.** Regressing commit:
`b539a238 Phase 1a: Add CSS writing-mode and text-orientation property support`

Adding `writing-mode` as an inherited CSS property caused `<ruby>` and its
children (including boxing-generated `<rubyBox>`, `<rt>` cells) to inherit
`writing-mode: vertical-rl` when vertical CSS is applied. This puts the ruby
inline box through the vertical-mode re-render path where
`m_pbuffer->width ≈ 1352px` is used as the column height. The CCRTable (ruby
table) or its cells crash with this oversized width.

(Note: the crash triggers on vertical CSS application, not on initial open.)

**Current state:** `simple_ja_ruby.epub` fixture uses `ruby { display: inline }`
as a temporary bypass so tests can run. Real EPUBs are still broken.

**Bisect reproducer:** `spec/unit/bisect_ruby_crash_spec.lua` +
`test/fixtures/vertical_text/crash_ruby.epub` (untracked, recreate if needed).

**Required fix (Phase 2):**
Prevent ruby boxing-generated elements from entering the wrong vertical-mode
formatting path. Options:
- Add explicit `writing-mode: horizontal-tb !important` to the ruby UA stylesheet
  for `ruby`, `rt`, `rp`, `rubyBox` boxing elements (CSS shielding)
- OR guard the vertical `Format()` path against being called on inline-table ruby
  cells that should not re-flow as vertical columns
- OR fix the `render_w` used for ruby inline boxes to not be `m_pbuffer->width`
  when in vertical mode — this would prevent the oversized CCRTable width

### Phase 2 glyph issues (lower priority)

- 。/、 clipping at column bottom (glyph placed near em-square bottom)
- Characters needing rotation: ー、…、「」brackets (currently drawn upright)
- Per-element writing mode (mixed horizontal/vertical blocks)
- Floats in vertical mode (currently disabled)
- Ruby sbox positions in それから.epub with real ruby content

## Key File Locations

```
base/                                           crengine submodule
  cre.cpp                                       KOReader↔crengine bridge
  thirdparty/kpvcrlib/crengine/crengine/src/
    lvrend.cpp                                  Block rendering, FlowState
    lvtextfm_layout_h.cpp                       Text formatter draw & layout
    lvtextfm.cpp                                measureText, ruby inline box
    lvdocview.cpp                               windowToDocPoint, docToWindowPoint, isVerticalText
    lvfntman.cpp                                HarfBuzz font shaping, +vert features
    lvtinydom.cpp                               DOM, getAbsRect, getRect, getSegmentRects
frontend/document/credocument.lua               Lua wrappers: getWordFromPosition, getTextFromPositions
spec/unit/vertical_text_spec.lua                Formal regression tests
```

## Test EPUB

`それから.epub` (Soseki, has ruby annotations) — used for manual testing.
`simple_ja_noruby.epub` — used for formal tests (no ruby, simpler).

Both require CSS `body { writing-mode: vertical-rl !important; }` applied via style tweak.
