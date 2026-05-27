# KOReader Vertical Text (vertical-rl) Implementation

## Soft Fork Policy

This project is a soft fork of koreader/koreader + koreader/koreader-base +
crengine, maintained as m-tky/koreader-tategumi, m-tky/koreader-base, and
m-tky/crengine. Upstreaming is not the goal, but the fork must remain easy
to rebase onto upstream updates. Therefore:

- **Minimal, targeted changes**: Modify only the functions and files necessary
  for the fix. Preserve upstream style, naming conventions, and comment culture.
- **Do not touch upstream code unnecessarily**: Do not clean up commented-out
  debug code or reorganize existing comments — this widens the diff for no gain.
- **No debug code in commits**: Remove all diagnostic `fprintf(stderr, ...)`
  and similar instrumentation before committing.
- **Issues and PRs go to m-tky repos only**: Never open issues or PRs against
  upstream repositories (koreader/koreader, etc.) by mistake.
- **All written communication in English**: Code, comments, commit messages,
  issues, PRs, and documentation must all be written in English.

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

```mermaid
graph LR
    subgraph doc["Formatter / Doc Space  (Y=X swapped)"]
        FY["c_y / fmt.setY()\nblock-direction advance\n= column progression"]
        FX["c_x / fmt.setX()\ninline-start\n= glyph position in column"]
    end
    subgraph draw["Draw() — after swap(x,y) at entry"]
        LX["line_x = clip.right − x\ncolumn screen-X  (right → left)"]
        LY["y + frmline->x + advance\nglyph screen-Y  (top → bottom)"]
    end
    FY -->|"→ x after swap"| LX
    FX -->|"→ y after swap"| LY
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

### Formatted text draw (lvtextfm.cpp `LFormattedText::Draw`)

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

#### Inline box (ruby group) draw

`doc_y_ib = −node_y` cancels the inline box's own `getY() = node_y`, so by the time
DrawDocument reaches the ruby cells `doc_y` holds only the cell's own offset.
`x0 = y + node_x + clamp_delta` positions the group's screen-Y start after the preceding
character (clamping prevents overlap with the previous glyph's visual end).

```mermaid
flowchart TD
    CALL["outer Draw() — on inline box word\nx0 = y + node_x + clamp_delta\ny0 = x + node_y\ndoc_x_ib = −node_x,  doc_y_ib = −node_y"]
    L0["DrawDoc(inline_box)  getY()=node_y\ndoc_y = −node_y + node_y = 0"]
    L2["DrawDoc(ruby_row)  getY()=0\ndoc_y = 0"]
    L3a["DrawDoc(base_cell)  getY()=annot_width\ndoc_y = annot_width\nf→Draw(x0, y0+annot_width)\nline_x = clip.right − (node_y+annot_width)  ✓"]
    L3b["DrawDoc(annot_cell)  getY()=0\ndoc_y = 0\nf→Draw(x0, y0)\nline_x = clip.right − node_y  ✓"]

    CALL --> L0 --> L2
    L2 --> L3a
    L2 --> L3b
```

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
(lvtextfm.cpp `alignLineHorizontal`): apply the font_size minimum only
for CJK words (where compressed punctuation needs it).

```cpp
bool is_cjk = (wi->flags & (LTEXT_WORD_IS_CJK | LTEXT_WORD_IS_FLEXIBLE_WIDTH_CJK)) != 0;
int eff_w = (is_cjk && (int)wi->width < font_sz) ? font_sz : (int)wi->width;
```

### Glyph placement in vertical mode (lvfntman.cpp + lvfntman_vert.{h,cpp})

HarfBuzz is shaped with `HB_DIRECTION_TTB` so `y_advance` carries the vertical advance.
Glyph (gx, gy) is then computed by **JLReq character class** (LuaTeX-ja jfm-ujisv.lua
port), with two fork-only deviations from strict LuaTeX-ja semantics: (a) half-em
compaction is NOT applied — every glyph keeps em advance, and (b) the in-slot
positioning anchors the bitmap to the slot edge instead of trusting the font's vBY.
Both deviations address the same root cause: Noto / Hiragino +vert form vmtx values
reflect horizontal-mode design choices and place brackets/punctuation several px off
JLReq's prescribed slot edges when the strict LuaTeX-ja math is applied.

#### Character classes (lvfntman_vert.{h,cpp}: `getJLReqVertClass`)

Ten classes mirror jfm-ujisv.lua's class table; verified line-by-line against
`luatexja/src/jfm-ujisv.lua`:

| Class                    | Chars                                          | width  | align  |
|--------------------------|------------------------------------------------|--------|--------|
| `CJK_BODY` [0]           | ideographs, hiragana, katakana, Hangul, ー〜～ | em     | middle |
| `OPEN_BRACKET` [1]       | ‘ “ 〈 《 「 『 【 〔 〖 〘 〝 （ ［ ｛ ｟        | em/2  | right  |
| `CLOSE_BRACKET_COMMA` [2]| ’ ” 〉 》 」 』 】 〕 〗 〙 〟 ） ］ ｝ ｠ 、 ，| em/2  | left   |
| `MIDDLE_DOT` [3]         | ・ ： ； ·                                     | em/2  | middle |
| `PERIOD` [4]             | 。 ．                                          | em/2  | left   |
| `DASH` [5]               | — ― ‥ … 〳 〴 〵                                | em     | left   |
| `EXCLAM_QUEST` [6]       | ？ ！ ‼ ⁇ ⁈ ⁉                                  | em     | left   |
| `HALF_KANA` [7]          | U+FF61..U+FF9F (halfwidth katakana)            | em/2  | left   |
| `VERT_MARK`              | — fork-only, signalled by `LFNT_HINT_VERTICAL_MARK` (ー — ‥ … 〜 ～ ―) | em | middle |
| `OTHER`                  | Latin/numerals/etc.                            | em     | middle |

#### Placement formulas (lvfntman.cpp `DrawTextString` is_vertical_draw block)

1. **Body CJK & vert marks** (use_uniform_body = `isUniformVerticalIdeograph(c) ||
   is_vert_mark`):
   - X: font's vBX from vmtx cache when present (optical centre, corrects
     asymmetric-glyph ink-vs-rect-centre mismatch on し ら っ).  Falls back to
     `bitmap_width / 2` centering for vert marks (Hiragino-style fonts leave
     +vert form vBX = 0; bitmap-centre works font-independently).
   - Y: bitmap-centred for body CJK; 75 % biased toward slot bottom for vert marks
     (`(em - bmh) * 3/4`) so ー / … get ~5 px gap from the preceding glyph
     instead of ~3 px (preceding glyph descent + 3 px reads as visual overlap).

2. **Half-em JFM classes** (brackets, punctuation, halfwidth kana — anchored to
   slot edge via `getJLReqVertHalfEmYOffset`):
   - The bitmap is anchored to the **em slot** (not half-em) per layout.align:
     - `LEFT`  → gy = y + 0 (bitmap top at slot top — 」』、，。 cluster close
                 to the preceding char in the column)
     - `MIDDLE`→ gy = y + (em - bmh)/2 (centred — ・)
     - `RIGHT` → gy = y + (em - bmh) (bitmap bottom at slot bottom — 「『〈《【〔〘
                 cluster close to the next char in the column)
   - This **ignores the font's vBY** for these classes; vBY values in Noto and
     Hiragino represent horizontal-mode design (e.g. 「 has vBY ≈ 0.63 em) and
     wouldn't land the bitmap on JLReq's prescribed edge.
   - The advance stays em (no half-em compaction): the goal is JLReq-style
     in-slot anchoring without LuaTeX-ja's column compaction, which visually
     shifts subsequent characters up by em/2 per preceding half-em char and
     was rejected as visually wrong in screenshot review.

3. **Fall-through** (no JFM class match, no vmtx, no `LFNT_HINT_VERTICAL_MARK`):
   font's vmtx vBY-based, with em-top alignment fallback when no vhea.

#### Why these deviations from LuaTeX-ja

LuaTeX-ja is designed for high-end print typography with carefully-tuned fonts
(Kozuka, Hiragino).  Its half-em compaction + cwa shift mathematics assumes the
font's vBY positions the glyph at the right spot within its half-em slot.

For e-book reader fonts (Noto Serif JP, Noto Sans CJK SC):

  - vBY of 「 is ≈ 0.63 em rather than the 0.5 em that LuaTeX-ja's math implicitly
    expects, leaving 「 in the middle of the half-em slot instead of the
    JLReq-prescribed edge.
  - Half-em compaction at the word advance level shifts every glyph downstream
    up by em/2 per compacted glyph, which visually moves brackets and punctuation
    UP — opposite of what e-book readers expect.

The fork's "em slot + JLReq-edge anchor + no compaction" gives stable JLReq
positioning regardless of font vmtx quality.

HarfBuzz TTB writes `x_offset = -vertOriginX`, `y_offset = -vertOriginY` into
`glyph_pos[]` (compensation for an LTR-style pen).  The fork places the pen at the
vertical origin directly and reads vBX/vBY from its own cache, so HarfBuzz's offsets
must NOT be added on top — that would double-displace the glyph.

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
| Glyph rotation: ー 〜 … 、。括弧類 etc. use vertical forms (`vert`/`vrt2`) | `lvfntman.cpp` |
| JLReq-class glyph placement (LuaTeX-ja jfm-ujisv port): 10-class classifier + em-slot in-slot align; brackets/punctuation anchored to JLReq slot edges | `lvfntman.cpp`, `lvfntman_vert.{h,cpp}` |
| Column bottom clipping fix: glyphs at column end no longer clipped | `lvtextfm.cpp` |
| sbox screen_y offset (P5): `windowToDocPoint`/`docToWindowPoint` account for `clip.top` | `lvdocview.cpp` |
| Character overlap fix (上にめり込む): `vert_min_next_x` correctly prevents overlap | `lvtextfm.cpp` |

**Note on whitespace**: some EPUBs have U+0020 spaces adjacent to ruby groups (e.g. `と Nachbild《…》 という`). These render as narrow gaps proportional to the space glyph's advance width (≈ ¼ em). This is expected — the space is in the EPUB source.

## Open Issues

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
    src/lvtextfm_vert.cpp                       Vertical paragraph layout (fork-only)
    src/lvtextfm.cpp                            measureText, ruby inline box
    src/lvdocview.cpp                           windowToDocPoint, docToWindowPoint, isVerticalText
    src/lvfntman.cpp                            HarfBuzz font shaping, +vert features, glyph rotation
    src/lvtinydom.cpp                           DOM, getAbsRect, getRect, getSegmentRects
frontend/document/credocument.lua               Lua wrappers: getWordFromPosition, getTextFromPositions
spec/unit/vertical_text_spec.lua                Formal regression tests
spec/unit/vertical_option_c_spec.lua            Option C: uniform column y_base test
spec/unit/ruby_annot_y_spec.lua                 Ruby cell placement regression
```

## Submodule Chain — commit correspondence

When making C++ changes (crengine), all three repos must be committed and
pushed in order. **The CI fetches each submodule by SHA; if any SHA is not
reachable from the remote's default branch the build will fail.**

```
koreader-tategumi  (github.com/m-tky/koreader-tategumi)
  └─ base          (github.com/m-tky/koreader-base)
       └─ crengine (github.com/m-tky/crengine)
```

### Workflow for crengine changes

Use `scripts/push-chain.sh` to push commits through the chain automatically:

```bash
# Push crengine → base → koreader (full chain)
./scripts/push-chain.sh

# Push from base upward (crengine already pushed)
./scripts/push-chain.sh base

# Push koreader only
./scripts/push-chain.sh koreader

# Preview what would be pushed without doing anything
./scripts/push-chain.sh --dry-run
```

The script handles detached HEAD and diverged branches by cherry-picking onto
`mytky/master`, and automatically fixes stale submodule SHAs (the common failure
mode where a local commit SHA appears in a submodule pointer but was never pushed).

Manual equivalent (if needed):

```bash
# 1. Commit in crengine, push to m-tky/crengine
cd base/thirdparty/kpvcrlib/crengine
git commit -am "..."
git push mytky HEAD:master   # or cherry-pick onto mytky/master if detached

# 2. Update base pointer, push to m-tky/koreader-base
cd ../../..                  # = base/
git add thirdparty/kpvcrlib/crengine
git commit -m "crengine: ..."
git push mytky HEAD:master   # or cherry-pick onto mytky/master if detached

# 3. Update main repo pointer, push, retag
cd ..                        # = koreader/
git add base
git commit -m "base: ..."
git push origin master
git tag -d vYYYY.MM.P && git push origin :refs/tags/vYYYY.MM.P
git tag -a vYYYY.MM.P -m "..." && git push origin vYYYY.MM.P
```

### Pitfall: detached HEAD in base/crengine

Both `base` and `crengine` are often in detached HEAD state.
Commits made in detached HEAD are NOT on any remote branch.
`push-chain.sh` handles this automatically. Manually:

```bash
git checkout mytky/master -b tmp-push
git cherry-pick <sha>
git push mytky tmp-push:master
```

## Test EPUBs

`test/fixtures/vertical_text/sanshiro.epub` (三四郎, Natsume Soseki) — main test EPUB with ruby annotations.
`test/fixtures/vertical_text/simple_ja_noruby.epub` — formal unit tests (no ruby, simpler structure).

`sanshiro.epub` has its own `writing-mode: vertical-rl` CSS; no style tweak needed.
Other EPUBs require: `body { writing-mode: vertical-rl !important; }` via style tweak.
