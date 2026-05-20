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

#### Entry and page-level call

`drawPageTo` calls `DrawDocument(buf, root, draw_x0, draw_y0, ...)` with:
- `draw_x0 = clip.top` (screen-Y origin of the text area)
- `draw_y0 = 0` (block-direction origin: "column 0 starts at clip.right")

DrawDocument eventually calls `f->Draw(buf, draw_x0, draw_y0, ...)`.

At Draw() entry, x and y are swapped back to screen coordinates:
```cpp
if (is_vertical) { int tmp = x; x = y; y = tmp; }
// After swap: x = draw_y0 = 0,  y = draw_x0 = clip.top
int line_x = is_vertical ? (clip.right - x) : x;
// line_x = clip.right - 0 = clip.right  (for page-level call)
int line_y = y;  // = clip.top
```

#### Per-column drawing (frmlines)

`line_x` starts at `clip.right` and decreases by `frmline->height` after each frmline.

- Plain column: `frmline->height = strut_height`
- Ruby-inflated column: `frmline->height = strut + annot_width`

#### Plain character positioning

```cpp
x0 = line_x - frmline->height;          // left edge of column
// Center on the column axis:
if (em < strut) x0 += (strut - em) / 2; // (strut - em) / 2 centering
y0 = y + frmline->x + clamped_x;        // screen Y = clip.top + indent + char advance
// Glyph center = x0 + em/2 = line_x - strut/2  ✓
```

#### Inline box (ruby group) DrawDocument call

When Draw() encounters an inline box (LTEXT_WORD_IS_OBJECT) word in vertical mode:

```
node_x = node_fmt.getX()  // inline-start offset (screen-Y direction)
node_y = node_fmt.getY()  // block-direction offset (= accumulated column advance in block)
x      = draw_y0 = 0      // current block's column-start offset from page-start

x0     = y + node_x + clamp_delta   // screen-Y start of inner content
y0     = x + node_y = 0 + node_y    // column offset of inline box (block-direction)
doc_x_ib = 0 - node_x
doc_y_ib = 0 - node_y               // ← needed to cancel inline box's own getY() (see below)
DrawDocument(buf, node, x0, y0, dx, dy, doc_x_ib, doc_y_ib, ...)
```

#### DrawDocument recursion and doc_y accumulation

**Critical**: DrawDocument FIRST applies `doc_x += fmt.getX()` and `doc_y += fmt.getY()` for
the **current node** it was called on, before recursing into children.

So when DrawDocument is called on the inline box node with `doc_y_ib = -node_y`:

```
Level 0: DrawDocument(inline_box)
  doc_y += inline_box.getY()  → doc_y = -node_y + node_y = 0

  Level 1: DrawDocument(ruby_table)   ruby_table.getY() = 0
    doc_y += 0  → doc_y = 0

    Level 2: DrawDocument(ruby_row)   row.getY() = 0
      doc_y += 0  → doc_y = 0

      Level 3a: DrawDocument(base_cell)   base_cell.getY() = annot_width
        doc_y += annot_width  → doc_y = annot_width
        f->Draw(buf, x0+doc_x, y0+doc_y=node_y+annot_width, ...)
        → inner Draw: x_new = node_y + annot_width
        → inner_line_x = clip.right − (node_y + annot_width)  ✓

      Level 3b: DrawDocument(annot_cell)  annot_cell.getY() = 0
        doc_y += 0  → doc_y = 0
        f->Draw(buf, x0+doc_x, y0+doc_y=node_y, ...)
        → inner Draw: x_new = node_y
        → inner_line_x = clip.right − node_y  ✓
```

So `doc_y_ib = -node_y` is correct: it cancels the inline box's own `getY()` so the
inner formatters receive the correct absolute column offsets.

#### Ruby cell column positions (vertical-rl)

For a ruby group with `node_y = N` (= accumulated column advance in block):

| Cell | `cell.getY()` | `inner_line_x` | Glyph center |
|------|--------------|----------------|--------------|
| annotation | 0 | `clip.right − N` | annotation zone |
| base text | `annot_width` | `clip.right − N − annot_width` | base text column |

The base text column is `annot_width` to the left of `clip.right − N` (the annotation zone),
which places it correctly: annotation occupies the inter-column space to the right of the base.

#### Ruby column position

`y0 = x + node_y` and `doc_y_ib = 0 − node_y` ensure each ruby group draws
at the correct accumulated column advance `node_y`, not always at `clip.right − annot_width`.
Regression test: `vertical_ruby_column_spec.lua`.

#### Latin base text column depth

`fmt.getWidth()` after `renderBlockElement` is TTB-based (≈ `char_count × font_size`)
for Latin words rendered as a rotated block. The actual visual column depth is the
horizontal advance of the word. Fix (lvtextfm.cpp `measureText`):

```cpp
// Collect horizontal advance via getCharWidth() during ruby cell scan
base_horiz_advance_pre += base_font->getCharWidth(c);  // per base char
// Override advance with measured value (annotation depth if longer)
advance = max(base_horiz_advance_pre, annot_depth);
```

`o.width` and `letter_spacing` both use this value, so frmline layout and
`vert_min_next_x` tracking in Draw() are both corrected.

Also: `vert_layout_min_x` (post-layout pass) applied `eff_w = max(word->width, font_size)`
to all words including spaces. For a U+0020 before an inline box this inflated
`ib_word_x` by `font_size − space_advance`, creating a gap above the box. Fix
(lvtextfm_layout_h.cpp `alignLineHorizontal`): apply the font_size minimum only
for CJK words (where compressed punctuation needs it).

```cpp
bool is_cjk = (wi->flags & (LTEXT_WORD_IS_CJK | LTEXT_WORD_IS_FLEXIBLE_WIDTH_CJK)) != 0;
int eff_w = (is_cjk && (int)wi->width < font_sz) ? font_sz : (int)wi->width;
```

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

### Frontend (Lua)

| Feature | Location |
|---------|----------|
| Text selection: `onHold` uses Lua sboxes for vertical rolling docs | `readerhighlight.lua` |
| Underline highlight: vertical line on right edge of column | `readerview.lua` |
| Strikeout highlight: vertical line through column center | `readerview.lua` |
| Vertical footer: progress bar fills right→left, TOC ticks mirrored | `readerfooter.lua` |

**Note on whitespace**: some EPUBs have U+0020 spaces adjacent to ruby groups (e.g. `と Nachbild《…》 という`). These render as narrow gaps proportional to the space glyph's advance width (≈ ¼ em). This is expected — the space is in the EPUB source.

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

`test/fixtures/vertical_text/sanshiro.epub` (三四郎, Natsume Soseki) — main test EPUB with ruby annotations.
`test/fixtures/vertical_text/simple_ja_noruby.epub` — formal unit tests (no ruby, simpler structure).

`sanshiro.epub` has its own `writing-mode: vertical-rl` CSS; no style tweak needed.
Other EPUBs require: `body { writing-mode: vertical-rl !important; }` via style tweak.
