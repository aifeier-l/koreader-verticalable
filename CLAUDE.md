# KOReader Vertical Text (vertical-rl) Implementation

## Project Goal

Implement Japanese vertical-rl text rendering in KOReader/crengine.
Target: tategumi (縦書き) for Japanese novels in EPUB format.

## Build & Test

```bash
# Build
nix develop --command ./kodev build -d emulator

# Run emulator
nix develop --command ./kodev run emulator

# Run all unit tests
nix develop --command make -j1 testfront

# Run vertical text tests only
nix develop --command ./kodev test front -f "Vertical text"
```

Test fixture: `spec/front/unit/data/fixtures/vertical_text/simple_ja_noruby.epub`

## Architecture: Y=X Coordinate Swap

The core design re-uses the existing horizontal rendering pipeline by swapping X and Y
roles. All rendering stores horizontal column progression in the Y-axis fields so the
page splitter (which splits on Y) naturally splits on columns.

### Coordinate mapping (doc space → screen)

```
doc_y  = page_y + (horizontal offset from right edge)  →  screen_x = page_right - (doc_y - page_y)
doc_x  = vertical pixel position in column             →  screen_y = doc_x
```

### FlowState (lvrend.cpp)

- `c_x` = accumulated horizontal advance (column progression)
- `c_y` = same value as c_x for vertical (advanced in sync in `addContentLine`)
- `l_x`, `l_y` = saved at `newBlockLevel`, both equal at each level entry
- `page_h` is swapped to `page_width` at FlowState constructor for vertical mode
- `context.AddLine(c_x, c_x+height, ...)` feeds horizontal offsets to page splitter

### Block rendering (lvrend.cpp `renderBlockElementEnhanced`)

```cpp
fmt.setX( x );                              // inline-start margin (screen-Y offset)
fmt.setY( flow->getCurrentRelativeY() );   // block-direction advance (screen-X offset)
```

`getCurrentRelativeY() = c_y - l_y == c_x - l_x` in vertical mode.

### CSS Logical Properties (Option C)

`lvlogical.h` provides `CSSLogical` struct mapping CSS physical property array indices
to logical directions for vertical-rl:

```cpp
CSSLogical L(style->writing_mode);
// inline-start = physical top (index 2) for vertical-rl
padding_left = style->padding[L.padIS()];   // padding-top → inline-start
// block-start  = physical right (index 1) for vertical-rl
margin_top   = style->margin[L.marBS()];    // margin-right → block-start
```

This replaces hard-coded physical indices (0,1,2,3) throughout `renderBlockElementEnhanced`
and `DrawDocument`, ensuring CSS padding/margin are applied in the correct directions.

### Formatted text draw (lvtextfm_layout_h.cpp `LFormattedText::Draw`)

At entry, x and y are swapped back to screen coordinates:
```cpp
if (is_vertical) { int tmp = x; x = y; y = tmp; }
int line_x = is_vertical ? (clip.right - x) : x;
int line_y = y;
```

Per-glyph positioning in vertical mode:
```cpp
x0 = line_x - frmline->height - word->y;   // screen X (column position)
y0 = y + frmline->x + clamped_x;           // screen Y (row position in column)
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
screen_y = doc_x;
pt.x = screen_x;
pt.y = doc_x;
```

`docToWindowRect` normalizes left/right after conversion (increasing doc_y → decreasing screen_x).
Off-screen rejection: returns false if `screen_x < page_left - 50 || screen_x > page_right + 50`.

`isVerticalText()` heuristic (lvdocview.cpp):
```cpp
bool LVDocView::isVerticalText() const {
    if (m_pages.length() == 0) return false;
    int page_h = m_pages[0]->height;
    return (page_h > 0 && page_h <= m_dx + 32);
}
```

## Implemented Features

### crengine submodule (base/)

| File | Change |
|------|--------|
| `lvrend.cpp` | FlowState: `c_x`, `l_x`, `isVertical()`, `addContentLine` dual advance, `page_h` swap, `getCurrentFlowAdvance/RelativeAdvance`, `newBlockLevel`/`leaveBlockLevel` c_x save/restore |
| `lvrend.cpp` | `renderBlockElementEnhanced`: CSSLogical for all padding/margin indices |
| `lvrend.cpp` | `DrawDocument`: plain `doc_x+x0+padding_left, doc_y+y0+padding_top` (no vert_shift hack) |
| `lvtextfm_layout_h.cpp` | `Draw()`: x/y swap; `line_x = clip.right - x`; column draw; per-column clip; monotonic `vert_min_next_x` guard |
| `lvtextfm_layout_h.cpp` | `Draw()`: sets `LFNT_HINT_IS_VERTICAL` in drawFlags |
| `lvtextfm.cpp` | `measureText()`: ruby inline box advance = `lastFont->getSize()` per base char |
| `lvfntman.cpp` | `DrawTextString()`: `setupHBFeatures(is_vertical)` enables `+vert`/`+vrt2` OpenType features |
| `lvfntman.cpp` | `drawGlyphItemRotated90CW`: bearing-correct placement for rotated glyphs (ー、…、brackets) |
| `lvlogical.h` | New file: CSS logical property index helpers for vertical-rl (Option C) |

### cre.cpp (KOReader bridge)

- `isVerticalText()` added to `lvdocview.h`
- `getWordFromPosition`: skip margin adjustment for vertical text
- `docToWindowRect`: normalize left/right for vertical-rl
- `docToWindowPoint`: off-screen rejection for out-of-range screen_x
- `resetRubyDiag()` / `getRubyDiagStats()`: ruby cell placement diagnostics

### Frontend (Lua)

| Feature | Location |
|---------|----------|
| Text selection: `onHold` uses Lua sboxes for vertical rolling docs | `readerhighlight.lua` |
| Underline highlight: vertical line on right edge of column | `readerview.lua` |
| Strikeout highlight: vertical line through column center | `readerview.lua` |
| Vertical footer: progress bar fills right→left, TOC ticks mirrored | `readerfooter.lua` |

**Known limitation**: some EPUBs (e.g. `それから.epub`) have stray U+0020 whitespace in
their HTML between `</ruby>` and the next character. With `white-space: normal` this
renders as a visible ~1-char gap. This appears in horizontal mode too — it is a property
of the EPUB source, not a rendering bug.

### Formal tests

- `spec/unit/vertical_text_spec.lua` — 14 tests: word lookup, multi-column selection, ruby annotation sboxes
- `spec/unit/vertical_option_c_spec.lua` — Option C: uniform column y_base
- `spec/unit/ruby_annot_y_spec.lua` — ruby cell placement regression (resetRubyDiag API)
- `spec/unit/bisect_ruby_crash_spec.lua` — no SIGSEGV on ruby EPUB
- `spec/unit/vertical_column_bottom_spec.lua` — no phantom chars at column bottom

## Issue History

### Px — Content gap between pages — FIXED

Seven interrelated bugs caused trailing columns to be invisible on real EPUBs:

1. `drawPageTo` (lvdocview.cpp): Y=X swap mismatch — swap to `x0=clip.top, y0=0` for vertical.
2. `drawPageTo` clip.bottom: use `pageRect->bottom - bottom_margin` for vertical.
3. `drawPageTo` clip.left: set `clip.left = clip.right - page.height` to avoid duplicate columns.
4. `isVerticalText` (lvdocview.cpp): scan all pages for height ≤ m_dx + 32 as fallback.
5. `renderBlockElement` (lvrend.cpp): walk descendants (DFS ≤ 6 deep) to find vertical writing-mode.
6. `addContentSpace` (lvrend.cpp): move `moveDown()` into horizontal-only branch to stop double-advance.
7. `LVRendPageContext` (lvpagesplitter): add separate `vert_split_page_h` field for page splitter.

### P7 — Page turn direction fixed left→right — FIXED

Auto-set RTL page turn direction for vertical documents on open. Reversed left/right arrow
key navigation to match right→left column flow.

### P8 — Uneven column bottom alignment — FIXED

Root cause: `hb_buffer_reverse_clusters()` was incorrectly called for TTB text in
`lvfntman.cpp`. RTL needs reversal because HarfBuzz reverses output; TTB does not.
The misapplied reversal broke the cluster→advance mapping: `m_advance[0..N-2] = 0`,
only the last character carried the full N×font_size advance.

Fix (`FORMATTING_VERSION_ID 0x003B → 0x003C`):
- `lvfntman.cpp`: remove `hb_buffer_reverse_clusters()` from TTB branch
- `lvtextfm_layout_v.cpp`: gate `char_count_adv` on `adv_available==false` only
- `lvtextfm_layout_h.cpp`: remove `is_neg_width > 0x8000` workaround

### P11 — Phantom characters at column bottom — FIXED

Root cause: `processParagraphVertical()` used `maxH = page_height` (≈755px) but the
actual drawable screen-Y range was `page_height - bvo` where bvo = accumulated X
positions of ancestor blocks.

Fix (`FORMATTING_VERSION_ID 0x003C → 0x003D`):
1. `lvtinydom.cpp renderFinalBlock()`: compute BVO and set `page_h -= bvo`.
2. `lvtextfm_layout_v.cpp processParagraphVertical()`: change `> maxH` to `>= maxH`
   so zero-advance punctuation (。etc.) that lands at clip.bottom goes to the next column.

### P1 — Ruby base character alignment — FIXED

Ruby base characters now align with surrounding body text in vertical-rl. Annotations
overhang into the inter-column gap per JLReq. Verified with sanshiro.epub and sorekara.epub.

### P13 — Option C: CSS logical property rewrite — DONE (merged to master)

Replaced hard-coded physical CSS property indices with `CSSLogical` logical mappings.
This fixed the column staircase that appeared when `padding-left` (physical) was
incorrectly applied as the inline-start direction offset.

Before Option C: `padding-left` → `doc-X` → screen-Y offset → staircase between columns.
After Option C: `padding-top` (physical) = inline-start → correct screen-Y; `padding-left`
= block-start → correct screen-X.

### P4 — Ruby sbox: effective writing-mode for ruby cells — FIXED

`renderCells()` used `table_style->writing_mode` which stores the CSS *specified* value,
not the cascaded value. For synthetic `<rubyBox>` nodes and inherited elements, this
returned `css_wm_inherit` (0), causing `vert_ruby = false` and applying
`fmt.setX(cell->col->x)` (wrong: displaces annotation in screen-Y direction for
multi-group ruby where `col->x != 0`).

Fix: walk up the parent chain to find the nearest ancestor with an explicit
(non-inherit) writing-mode. `FORMATTING_VERSION_ID 0x0042 → 0x0043`.

### P9 — Rotated glyph bearing correction — FIXED

`drawGlyphItemRotated90CW` used an em-square centering approximation for the post-rotation
placement. Replaced with bearing-correct formula:
```
correct_x = x + _baseline - origin_y
correct_y = y + _size - origin_x - bmp_w
```
Eliminates 2–4px misalignment for ー、…、and brackets in fonts without `+vert` substitution.

### P10 — char_count_adv undercount with ruby groups — FIXED

`processParagraphVertical` computed `char_count_adv = (i - pos + 1) * avg_char_advance`
treating each source position as 1 em. A ruby inline box at position j occupies
N×avg_char_advance column depth but counted as 1×. Body chars after a 3-kanji ruby
were underestimated by 2×em, allowing them to be formatted past `clip.bottom` and
becoming invisible (same bug class as P11).

Fix: accumulate `inline_box_extra` for each inline box encountered, add to `char_count_adv`.

## Open Issues

### P5 — docToWindowPoint screen_y offset (~9px)

`sbox.y` returned by `getWordFromPosition` is off by approximately `clip.top` pixels
(≈ page top margin + header height ≈ 9px) in vertical-rl mode. In `drawPageTo`, the
formatter receives `x0 = clip.top` as the screen-Y origin, but `windowToDocPoint` and
`docToWindowPoint` do not account for this offset when converting between screen-Y and
doc_x. The fix is to subtract/add `clip.top` in the vertical branch of these two functions.

### P6 — Per-element writing mode, floats (low priority)

- Mixed horizontal/vertical blocks within one document
- Floats in vertical mode (currently disabled)

### P14 — Rare ruby base character overlap (known issue)

The ruby group inline box starts at the same screen-Y as the preceding body character
ends (0–1px gap). For ruby groups where annotation length > base length (e.g.
かんしょう=45px > 癧症=44px), centering places the first annotation char at the
end-Y of the preceding character (は). Anti-aliasing can cause 1–2px visual overlap.

Root cause: JLReq requires 0.5px overhang spacing before such ruby groups, which is
not yet implemented. Affects only groups where annotation chars > base chars; extremely
rare in practice.

## Key File Locations

```
base/                                           crengine submodule
  cre.cpp                                       KOReader↔crengine bridge
  thirdparty/kpvcrlib/crengine/crengine/
    include/lvlogical.h                         CSS logical property index helpers
    src/lvrend.cpp                              Block rendering, FlowState
    src/lvtextfm_layout_h.cpp                   Text formatter draw & layout
    src/lvtextfm_layout_v.cpp                   Vertical paragraph layout
    src/lvtextfm.cpp                            measureText, ruby inline box
    src/lvdocview.cpp                           windowToDocPoint, docToWindowPoint, isVerticalText
    src/lvfntman.cpp                            HarfBuzz font shaping, +vert features, glyph rotation
    src/lvtinydom.cpp                           DOM, getAbsRect, getRect, getSegmentRects
frontend/document/credocument.lua               Lua wrappers: getWordFromPosition, getTextFromPositions
spec/unit/vertical_text_spec.lua                Formal regression tests
spec/unit/vertical_option_c_spec.lua            Option C: uniform column y_base test
spec/unit/ruby_annot_y_spec.lua                 Ruby cell placement regression
```

## Test EPUBs

`三四郎.epub` (Natsume Soseki, has ruby annotations) — main manual testing EPUB.
`simple_ja_noruby.epub` — formal tests (no ruby, simpler structure).
`それから.epub` — manual testing with ruby.

`三四郎.epub` has its own `writing-mode: vertical-rl` CSS; no style tweak needed.
Other EPUBs require: `body { writing-mode: vertical-rl !important; }` via style tweak.
