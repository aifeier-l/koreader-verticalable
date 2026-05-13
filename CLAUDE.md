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

### Phase 2 fixes applied

| Fix | Location |
|-----|----------|
| `docToWindowPoint` screen_y bounds check (ruby sbox defensive) | `lvdocview.cpp:2748-2768` |
| Ruby boxing SIGSEGV: `if(needs_wrapping)` guard in `initNodeRendMethod` | `lvtinydom.cpp:~8580` |
| CSS shield removed (`ruby { writing-mode: horizontal-tb }` was the old workaround) | `cr3gui/data/html5.css` |
| Code-level writing-mode shield removed from `renderBlockElement` | `lvrend.cpp` |
| `render_w` pre-computation: `base_char_count × font_size` for correct column depth | `lvtextfm.cpp` |
| `base_char_count_pre` traversal: distinguish rbox2_base vs rbox2_annot by first child nodeId | `lvtextfm.cpp:~2247` |
| Ruby render-method preservation on re-render (special case in `css_d_inline` branch) | `lvtinydom.cpp:~7513` |
| Inline-box advance = actual rendered width (Latin-in-ruby fix) | `lvtextfm.cpp:~2369` |
| `processParagraphVertical` SIGSEGV: skip object sources when reading t.font | `lvtextfm_layout_v.cpp:~104` |
| `alignLineHorizontal` uses block width for inner cells in vertical mode | `lvtextfm_layout_h.cpp:~10-22` |
| `col_width` grows for ruby (`= max(strut, max_inline_box_h)`) | `lvtextfm_layout_h.cpp:~2120` |
| Inline-box `setY` shift `(col_w - box_h)` aligns base char with column left | `lvtextfm_layout_h.cpp:~545-575` |
| **P1 FIXED**: Ruby base characters now align with body text in vertical-rl, annotations overhang into inter-column gap (per JLReq) | visually verified with sanshiro.epub and sorekara.epub |

**Known limitation**: some EPUBs (e.g. `それから.epub`) have stray U+0020
whitespace in their HTML between `</ruby>` and the next character (from
source-side newlines/indentation). With `white-space: normal` this renders
as a visible ~1-char gap. This appears in horizontal mode too — it is a
property of the EPUB source, not a rendering bug.

### Formal tests

`spec/unit/vertical_text_spec.lua` — 14 tests:
- Word lookup (sbox positive, round-trip coverage)
- Multi-column selection sboxes all positive
- Vertical in-column selection height check
- Horizontal mode regression
- Ruby annotation sboxes: on-screen Y bounds (2 tests, `simple_ja_ruby.epub`)

`spec/unit/bisect_ruby_crash_spec.lua` — 1 test (pending when `crash_ruby.epub` absent):
- Ruby boxing: no SIGSEGV with vertical CSS on ruby EPUB

## Phase 2 Remaining Issues (prioritized)

### P2 — Character rotation (ー 。「」… etc.) not implemented ← NEXT

Characters that need vertical glyph forms or 90° rotation currently draw upright:
- ー (KATAKANA-HIRAGANA PROLONGED SOUND MARK) — should rotate to vertical dash
- 。、 sentence-end punctuation — shifted to upper-right in vertical glyph
- 「」『』 brackets — should rotate 90°
- … ‥ ellipsis marks — should rotate

Note: +vert/+vrt2 OpenType substitution is active for fonts that have it (Noto CJK).
The remaining cases are glyphs that need explicit rotation in the draw code.

### P3 — 。/、 clipping at column bottom

Sentence-end punctuation glyph may clip at the last character's column boundary.
Deferred until P2 (rotation) is in place.

### P4 — Ruby sbox root cause (getRect/getAbsRect for rt-descendant nodes)

**Symptom suppressed** by `docToWindowPoint` screen_y bounds check
(`lvdocview.cpp:2748-2768`). Regression-guarded by `Ruby annotation sboxes #ruby`
tests in `spec/unit/vertical_text_spec.lua`.

**Root cause:** `getRect` for text inside `<rt>` adds `frmline->x + word->x` (vertical
offset within the annotation cell) onto `rc.left` (= inlineBox.X = base doc_x). For
deeply-stacked annotation chars, this sum exceeds page_height → off-screen sbox.

To investigate: uncomment the `print(...)` line in the ruby annotation sbox test,
run `./kodev test front -f "Ruby annotation"`, and capture sbox.y values.

### P5 — docToWindowPoint screen_y offset (~9px)

`sbox.y` is off by approximately `m_pageMargins.left ≈ 9px`. The formatter's
coordinate origin differs from screen Y=0. Low impact; noted as a known inaccuracy.

### P6 (low) — Per-element writing mode, floats

- Mixed horizontal/vertical blocks in one document
- Floats in vertical mode (currently disabled)

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
