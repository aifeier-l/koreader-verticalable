--[[--
Vertical-rl glyph Y position regression test.

In vertical-rl DrawTextString(), the glyph screen-Y was computed as:
    gy = y + _baseline - origin_y - y_offset

where y = slot top (advance start), _baseline = horizontal font baseline
distance, and origin_y = horizontal glyph bearing-Y.  The term
(_baseline − origin_y) shifts every glyph DOWN from its slot top by
~1/5 em, causing the rendered glyph to appear below the highlight sbox.

FIX: for vertical draws, skip the horizontal baseline adjustment:
    gy = y - y_offset

DETECTION: lfnt_vert_gy_offset_sum accumulates (gy − y) for all
non-rotated vertical glyph draws.  With the broken formula, each CJK
glyph contributes (_baseline − origin_y) > 0, so the sum is large
positive.  With the fix, each contributes −y_offset ≈ 0, so sum ≈ 0.

The test asserts that the average per-glyph offset is within ±2 px,
which passes after the fix and fails with the old code (~5-6 px average).

Run via:
  ./kodev test front -f "Vertical text"
--]]

local lfs = require("libs/libkoreader-lfs")

describe("Vertical text: glyph Y position (no horizontal baseline shift)", function()
    local epub_path
    for _, p in ipairs({
        "spec/front/unit/data/fixtures/vertical_text/sanshiro.epub",
    }) do
        if lfs.attributes(p) then epub_path = p; break end
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

    it("rendered glyph Y equals slot top (no ~1/5 em horizontal baseline shift) #glyph_y", function()
        if not epub_path then pending("sanshiro.epub not found"); return end
        if not (doc.isVerticalText and doc:isVerticalText()) then
            pending("document is not vertical-rl")
            return
        end

        -- Reset diagnostic, then render several pages to accumulate draws.
        doc._document:resetVertGlyphYDiag()

        local pages_to_visit = math.min(doc:getPageCount(), 10)
        local sw, sh = Screen:getWidth(), Screen:getHeight()

        for pg = 1, pages_to_visit do
            readerui.rolling:onGotoPage(pg)
            fastforward_ui_events()
            for _, fx in ipairs({0.8, 0.5, 0.2}) do
                pcall(function()
                    doc:getWordFromPosition({x = math.floor(sw * fx),
                                            y = math.floor(sh * 0.5)})
                end)
            end
        end

        local count, sum = doc._document:getVertGlyphYDiag()

        if count == 0 then
            pending("no vertical glyph draws recorded")
            return
        end

        local avg = sum / count

        print(string.format(
            "[glyph_y] pages=%d  glyph_draws=%d  total_gy_offset=%d  avg=%.2f px",
            pages_to_visit, count, sum, avg))

        -- THE KEY ASSERTION: average (gy − y) per glyph must be within ±2 px.
        -- With the broken formula (gy = y + _baseline − origin_y − y_offset):
        --   avg ≈ (_baseline − origin_y) ≈ 5-6 px (~1/5 em) → test FAILS.
        -- With the fix (gy = y − y_offset):
        --   avg ≈ −y_offset ≈ 0 px → test PASSES.
        local TOLERANCE = 2  -- px; much smaller than the ~5-6 px broken shift
        assert.is_true(math.abs(avg) <= TOLERANCE,
            string.format(
                "Average vertical glyph Y offset = %.2f px (tolerance ±%d px). "
                .. "The horizontal _baseline − origin_y correction is being applied "
                .. "in vertical mode, shifting every glyph ~1/5 em below its slot top. "
                .. "Fix: use gy = y − y_offset (no horizontal baseline term) "
                .. "in DrawTextString for vertical draws.",
                avg, TOLERANCE))
    end)
end)
