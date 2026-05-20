--[[--
Vertical-rl: space before ruby group does not create a gap above it.

In vertical-rl, a U+0020 space before an inline box (e.g. "と Nachbild《…》")
should contribute only its natural advance width to the column; the ruby
group starts immediately after.

BUG: vert_layout_min_x (post-layout pass, alignLineHorizontal) applied
  eff_w = max(word->width, font_size)
to ALL non-inline-box words, including spaces.  For a space (advance ≈ 8 px)
this inflated vert_layout_min_x by (font_size − space_advance ≈ 24 px).
The resulting ib_word_x (layout) exceeded vert_min_next_x (draw tracking),
creating a gap equal to font_size − space_advance above the inline box.

FIX: apply the font_size minimum only for CJK words (compressed punctuation
needs it); Latin/space words use their actual advance.

DETECTION: ltext_vert_ib_layout_gap_total accumulates
  max(0, ib_word_x − vert_min_next_x)
for each vertical inline box draw.  With the fix the layout and draw trackers
agree (gap = 0).  Without it, every space-preceded inline box contributes
≈ (font_size − space_advance) px.

Run via:
  ./kodev test front -f "Vertical text"
--]]

local lfs = require("libs/libkoreader-lfs")

describe("Vertical text: space before ruby does not cause gap #ruby_space_gap", function()
    -- This EPUB contains "と<ruby>Nachbild<rt>ナハビルド</rt></ruby>と" —
    -- a space before the ruby group previously inflated vert_layout_min_x.
    -- sanshiro.epub has the same pattern but uses《》notation (not <ruby> tags).
    local epub_path = "spec/front/unit/data/fixtures/vertical_text/ruby_latin_base.epub"
    if not lfs.attributes(epub_path) then
        epub_path = nil
    end

    local DocumentRegistry, ReaderUI, Screen, UIManager
    local readerui, doc

    setup(function()
        require("commonrequire")
        disable_plugins()
        require("document/canvascontext"):init(require("device"))
        DocumentRegistry = require("document/documentregistry")
        ReaderUI         = require("apps/reader/readerui")
        Screen           = require("device").screen
        UIManager        = require("ui/uimanager")
    end)

    before_each(function()
        if not epub_path then return end
        readerui = ReaderUI:new{
            dimen = Screen:getSize(),
            document = DocumentRegistry:openDocument(epub_path),
        }
        UIManager:show(readerui)
        fastforward_ui_events()
        doc = readerui.document
    end)

    after_each(function()
        if readerui then readerui:onClose() end
        UIManager:quit()
    end)

    it("layout/draw position mismatch for vertical inline boxes is zero #no_layout_gap", function()
        if not epub_path then pending("sanshiro.epub not found"); return end

        -- Navigate pages, triggering Draw() which records ib_word_x vs vert_min_next_x.
        -- Reset first so any counter from initial page load doesn't pollute results.
        -- sanshiro.epub has "と Nachbild《ナハビルド》 という" where the space
        -- before the ruby group previously caused ib_word_x > vert_min_next_x.
        doc._document:resetVertIbLayoutGap()

        local pages_to_visit = math.min(doc:getPageCount(), 20)
        local sw, sh = Screen:getWidth(), Screen:getHeight()

        for pg = 1, pages_to_visit do
            readerui.rolling:onGotoPage(pg)
            fastforward_ui_events()
            for _, fx in ipairs({0.80, 0.50, 0.20}) do
                pcall(function()
                    doc:getWordFromPosition({x = math.floor(sw * fx),
                                            y = math.floor(sh * 0.5)})
                end)
            end
        end

        local total_px, max_px = doc._document:getVertIbLayoutGap()

        print(string.format(
            "[ruby_space_gap] pages=%d  layout_gap_total=%d px  layout_gap_max=%d px",
            pages_to_visit, total_px, max_px))

        -- With the fix: vert_layout_min_x mirrors vert_min_next_x for all word types,
        -- so ib_word_x == vert_min_next_x and no gap is recorded.
        -- Without the fix: each space-preceded inline box adds
        -- ≈ font_size − space_advance ≈ 24 px to the total.
        assert.are.equal(0, max_px,
            string.format(
                "Largest layout/draw gap for a vertical inline box is %d px "
                .. "(expected 0).  ib_word_x exceeded vert_min_next_x, meaning "
                .. "vert_layout_min_x was inflated beyond what the draw phase "
                .. "tracked.  Check that non-CJK words (spaces, Latin) use their "
                .. "actual advance in alignLineHorizontal's vert_layout_min_x loop.",
                max_px))
    end)
end)
