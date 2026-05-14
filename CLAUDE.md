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
| Body char centering in ruby-inflated columns: only apply `(strut-em)/2` when `frmline->height <= strut`; in inflated columns x0=line_x-frmh is already correct (debug-verified 4px fix) | `lvtextfm_layout_h.cpp:~3602` |
| **Page gap FIXED**: content missing/duplicated between pages in vertical-rl | 7 fixes across `lvdocview.cpp`, `lvrend.cpp`, `lvpagesplitter.{h,cpp}`, `lvtinydom.cpp` — see "Px" entry below |

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

### Px — Content gap between pages (FIXED)

Five interrelated bugs combined to make trailing columns of every
page invisible on real EPUBs (verified with 三四郎.epub).  All needed
together:

1. `drawPageTo` (lvdocview.cpp) — Y=X swap mismatch.  After the X/Y
   swap in `LFormattedText::Draw`, draw_x→y (row) and draw_y→x→line_x
   (column).  Old code passed x0=left_margin, y0=clip.top, so clip.top
   got subtracted from every line_x, pushing the last clip.top pixels
   of each page off the left clip edge.  For vertical mode, swap to
   x0=clip.top, y0=0.

2. `drawPageTo` clip.bottom — page.height is the column-progression
   stride in vertical mode, NOT the vertical extent.  Using it for
   clip.bottom truncated each column at clip.top + ~page_width on
   screen and left the bottom of every page empty.  Use
   `pageRect->bottom - bottom_margin` for vertical.

3. `drawPageTo` clip.left — `LFormattedText::Draw` checks per-frmline
   visibility purely from line_x ∈ [clip.left, clip.right] and
   doesn't know page boundaries.  When a block straddled the page
   boundary, frmlines past the boundary were still drawn (same column
   appearing on page N and again on page N+1 — duplicate content).
   Set clip.left = clip.right - page.height for vertical to clip
   past-boundary frmlines.

4. `isVerticalText` (lvdocview.cpp) — heuristic checked only
   `m_pages[0]->height`, which can be a tall cover page.  Now: try
   the body element's writing-mode style first, then scan all pages
   for any with height ≤ m_dx + 32 as fallback.

5. `renderBlockElement` (lvrend.cpp) — writing_mode descendant scan.
   crengine stores the CSS specified value, not the cascaded value;
   for elements that inherit writing-mode (root, body), this returns
   css_wm_inherit (=0).  Walk descendants (DFS, depth ≤ 6, ≤ 64
   nodes) to find any element whose stored writing_mode resolved to
   vertical.

6. `addContentSpace` (lvrend.cpp) — c_y double-advance.  The vertical
   branch advanced c_y by height; the trailing `moveDown(height)`
   advanced it again.  Move `moveDown()` into the horizontal-only
   else branch.

7. `LVRendPageContext` (lvpagesplitter.{h,cpp}) — page-split stride
   was coupled to the text formatter's column length (both came from
   `page_h`).  Setting `page_h = page_width` for the page splitter
   broke the text formatter (columns clipped to ~half the screen,
   the bottom empty with floating characters).  Add a separate
   `vert_split_page_h` field used only by `split()` via
   `getEffectivePageHeight()`; FlowState calls
   `setVerticalSplitPageHeight(page_width)` so page_h stays at
   _page_height.

`FORMATTING_VERSION_ID` 0x0034 → 0x0036 invalidates caches with
stale page boundaries.

### P2 — Character rotation (ー 。「」… etc.) ← IMPLEMENTED, needs testing

Characters that need vertical glyph forms or 90° rotation:
- ー (KATAKANA-HIRAGANA PROLONGED SOUND MARK) — should rotate to vertical dash
- 。、 sentence-end punctuation — shifted to upper-right in vertical glyph
- 「」『』 brackets — should rotate 90°
- … ‥ ellipsis marks — should rotate

**Approach**: +vert/+vrt2 OpenType substitution is active for fonts that have it
(Noto CJK). For fonts WITHOUT a +vert variant for a character, explicit 90° CW
rotation is applied in `DrawTextString` (`lvfntman.cpp`).

**Detection**: after HarfBuzz shaping with +vert features, compare each shaped
glyph ID against the cmap nominal glyph (`hb_font_get_glyph`).  If unchanged,
+vert did not substitute → rotate explicitly.  If the ID differs, the font
already provided a vertical form → draw normally.

**Characters with explicit rotation** (when +vert absent):
  U+30FC ー, U+301C 〜, U+2014 —, U+2015 ―, U+2025 ‥, U+2026 …

**Not handled by explicit rotation** (rely on +vert or PLANNED):
  。、 (U+3002, U+3001) — position shift, not rotation; handled by +vert vertical glyphs
  「」『』 brackets — dedicated +vert forms in most CJK fonts; no fallback rotation yet

**Implementation**: `needsVerticalRotation90CW()` + `drawGlyphItemRotated90CW()`
in `lvfntman.cpp` after `drawGlyphItem()`.

**Ruby annotation centering fix** (same branch): `alignLineHorizontal` inner-cell
fix now uses `max(m_pbuffer->width, frmline->width)` as slot width; eliminates
~360 px centering error when HarfBuzz advance slightly exceeds `render_w` estimate.

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

### P7 — ページ進行方向が左→右固定

vertical-rl では本来ページは右→左に進む（第1列が画面右端、次ページへは左方向）。
現状のページ送り・タップゾーン・スワイプ方向などが水平モードと同じ左→右前提に
なっている可能性がある。調査・修正が必要。

関連箇所: `frontend/` のタップ/スワイプハンドラ、`ReaderPaging` / `ReaderView`、
`lvdocview.cpp` のページナビゲーション API。

### P8 — 列末位置の不統一（行末がバラバラ）

各列の最後の文字の垂直位置が列によって大きくばらつき、見た目の統一感がない。
考えられる原因：
- 句読点の advance クランプ（`vert_min_next_x`）が列充填を乱す
- `word->width` の実測値とフォントサイズの差
- 段落末尾の余白処理が垂直モード非対応

### P9 — 回転グリフの bearing/position 補正欠落

（旧タスク #1）`drawGlyphItemRotated90CW` で 90° 回転後の glyph に
bearing/origin 補正が入っていないため、回転グリフが列内でずれる可能性。

### P10 — ルビインラインボックスの実 advance と word->x 不整合

（旧タスク #2）measureText で計算したルビ inline box の advance と、
Draw 時の word->x が整合していない場合に位置ズレが生じる。

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
