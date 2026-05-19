--[[--
Vertical-rl glyph Y formula regression test.

The correct vertical glyph-Y formula is:
    gy = y + _baseline - origin_y - y_offset

The (_baseline − origin_y) term is a per-font constant (≈ |descender|, 4-10 px)
that is approximately uniform for full-width CJK characters.  Its presence
ensures visually consistent inter-character spacing.

If someone removes the term (e.g. using gy = y − y_offset or gy = y), the
average (gy − y) drops to ≈ 0, which this test detects.

DETECTION: lfnt_vert_gy_diag records (gy − y) per draw.
  Correct formula: avg ≈ |descender| ≈ 4-10 px → PASSES.
  Missing baseline term: avg ≈ 0 px → FAILS.

Run via:
  ./kodev test front -f "Vertical text"
--]]

local lfs = require("libs/libkoreader-lfs")

describe("Vertical text: glyph Y formula correctness", function()
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

    it("avg glyph Y offset includes baseline term (not zero) #glyph_y", function()
        if not epub_path then pending("sanshiro.epub not found"); return end
        if not (doc.isVerticalText and doc:isVerticalText()) then
            pending("document is not vertical-rl")
            return
        end

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

        -- Returns: count, sum, sum_sq, min, max
        local count, sum, _, mn, mx = doc._document:getVertGlyphYDiag()

        if count == 0 then
            pending("no vertical glyph draws recorded")
            return
        end

        local avg = sum / count

        print(string.format(
            "[glyph_y] pages=%d  draws=%d  avg=%.2f  min=%d  max=%d",
            pages_to_visit, count, avg, mn, mx))

        -- THE KEY ASSERTION: avg(gy − y) must be positive (the baseline term exists).
        -- With gy = y + _baseline − origin_y − y_offset: avg ≈ 4-10 px (|descender|).
        -- With gy = y or gy = y − y_offset: avg ≈ 0 → FAILS.
        local MIN_AVG = 2  -- px; well below the expected ~4-10 px
        assert.is_true(avg >= MIN_AVG,
            string.format(
                "Average glyph Y offset %.2f px < %d px. "
                .. "The (_baseline − origin_y) term appears missing from gy. "
                .. "Using gy = y or gy = y − y_offset causes irregular spacing "
                .. "because y_offset varies per character. "
                .. "Correct formula: gy = y + _baseline − origin_y − y_offset.",
                avg, MIN_AVG))
    end)
end)
