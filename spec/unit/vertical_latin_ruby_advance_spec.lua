--[[--
Vertical-rl: Latin ruby inline box uses horizontal advance, not TTB advance.

In vertical-rl, Latin words (e.g. "Nachbild", "Geschehen") are rendered as
rotated blocks whose visual column depth equals their horizontal advance
(≈ 3–4 em), NOT the TTB-based estimate (char_count × font_size ≈ 8–9 em).

BUG: before the fix, measureText() used fmt.getWidth() after
renderBlockElement(), which returned the TTB-based depth.  This created a
large blank gap (≈ render_w − horiz_advance) in the column after each Latin
ruby group.

FIX: collect the horizontal advance of each base-text glyph via
base_font->getCharWidth() and use max(base_horiz_advance, annot_depth) as
the inline-box advance (o.width / letter_spacing).

DETECTION: ltext_vert_ruby_adv_diff_total accumulates (render_w − advance)
for every vertical ruby inline box where render_w > advance.  A positive
total proves that Latin content was detected and the narrower horizontal
advance was substituted.  Under the old code advance ≈ render_w so the
diff is zero.

Run via:
  ./kodev test front -f "Vertical text"
--]]

local lfs = require("libs/libkoreader-lfs")

describe("Vertical text: Latin ruby uses horizontal advance #latin_ruby_advance", function()
    -- This EPUB contains <ruby>Nachbild<rt>ナハビルド</rt></ruby> etc. —
    -- proper ruby markup with Latin base text.
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

    it("advance of Latin ruby groups is narrower than render_w (getCharWidth path active) #latin_advance", function()
        if not epub_path then pending("sanshiro.epub not found"); return end

        -- Navigate pages to trigger measureText (layout) for each paragraph.
        -- sanshiro.epub contains Nachbild《ナハビルド》 and Geschehen《ゲシェーヘン》;
        -- those ruby groups have Latin base text whose horizontal advance is well
        -- below char_count × font_size.
        -- The process is fresh so the counter starts at 0 — no explicit reset needed.
        local pages_to_visit = math.min(doc:getPageCount(), 20)

        for pg = 1, pages_to_visit do
            readerui.rolling:onGotoPage(pg)
            fastforward_ui_events()
        end

        local total_px, max_px = doc._document:getVertRubyAdvDiff()

        print(string.format(
            "[latin_ruby_advance] pages=%d  adv_diff_total=%d px  adv_diff_max=%d px",
            pages_to_visit, total_px, max_px))

        -- With the fix: advance = max(horiz_advance, annot_depth) < render_w for
        -- Latin base text, so total_px > 0.
        -- Without the fix: advance ≈ render_w (fmt.getWidth() is TTB-based),
        -- so total_px ≈ 0.
        assert.is_true(total_px > 0,
            string.format(
                "render_w − advance diff is %d px (expected > 0). "
                .. "Latin ruby groups should use getCharWidth-based horizontal "
                .. "advance, not TTB-based fmt.getWidth().  If this is 0 the fix "
                .. "in measureText() (base_horiz_advance_pre path) is not active.",
                total_px))
    end)
end)
