--[[--
Vertical-rl plain character overlap (文字が被る) detection test.

In vertical-rl, each character occupies a "slot" of height = effective_width
(≥ font_size).  A character must start at or after the previous character's
slot END (prev_y0 + prev_effective_width).  When it starts BEFORE that
point the two characters visually overlap — the "文字が被る" bug.

DETECTION: for every CJK/plain-text character drawn in vertical mode,
ltext_vert_char_overlap_count is incremented when
  y0_current < vert_prev_plain_y0 + vert_prev_effective_width
and ltext_vert_char_overlap_max_px records the worst overlap in pixels.

Run via:
  ./kodev test front -f "Vertical text"
--]]

local lfs = require("libs/libkoreader-lfs")

describe("Vertical text: plain character overlap (文字が被る)", function()
    local epub_candidates = {
        "spec/front/unit/data/fixtures/vertical_text/sanshiro.epub",
    }
    local epub_path
    for _, p in ipairs(epub_candidates) do
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

    it("consecutive plain characters do not overlap in the column direction #no_overlap", function()
        if not epub_path then pending("no epub found"); return end

        doc._document:resetVertCharOverlapCounters()

        local pages_to_visit = math.min(doc:getPageCount(), 200)
        local sw, sh = Screen:getWidth(), Screen:getHeight()
        local sample_xs = {
            math.floor(sw * 0.80),
            math.floor(sw * 0.50),
            math.floor(sw * 0.20),
        }

        for pg = 1, pages_to_visit do
            readerui.rolling:onGotoPage(pg)
            fastforward_ui_events()
            for _, x in ipairs(sample_xs) do
                pcall(function()
                    doc:getWordFromPosition({ x = x, y = math.floor(sh * 0.5) })
                end)
            end
        end

        local count, max_px = doc._document:getVertCharOverlapStats()

        print(string.format(
            "[char_overlap] pages=%d  overlap_events=%d  max_overlap=%d px",
            pages_to_visit, count, max_px))

        assert.are.equal(0, count,
            string.format(
                "%d plain-character overlap event(s) detected (worst: %d px). "
                .. "Consecutive CJK characters in a column must not share Y space. "
                .. "Check vert_min_next_x and effective_width accounting in Draw().",
                count, max_px))
    end)
end)
