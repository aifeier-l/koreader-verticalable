--[[--
Vertical-rl character overlap detection test.

In vertical-rl, each character must start at or after the preceding
character ends ("上にめりこむ" = a character bleeding into the one above).

DETECTION (P14-style overlap):
  In Draw(), before calling DrawDocument for a ruby inline box, compute
    draw_x_inner = x0 + doc_x_ib + node_x
  which is the effective screen-Y start of the inner formatter content.
  Compare to:
    expected_min = y + frmline->x + vert_min_next_x
  If draw_x_inner < expected_min, the ruby group starts before the
  preceding character ends.  ltext_vert_bleed_count / ltext_vert_bleed_max_px
  accumulate these events (reset via resetVertBleedCounters(),
  read via getVertBleedStats()).

BUG (P14): the vert_min_next_x clamp for inline boxes was applied to both
  x0 and doc_x_ib, cancelling out in DrawDocument accumulation, so the
  ruby group always drew at its unclamped position.

FIX: shift only x0 by the clamping delta; keep doc_x_ib = -node_x.

Run via:
  ./kodev test front -f "Vertical text"
--]]

local lfs = require("libs/libkoreader-lfs")

describe("Vertical text: character overlap (no 上にめりこむ)", function()
    local epub_candidates = {
        "spec/front/unit/data/fixtures/vertical_text/sanshiro.epub",
        "spec/front/unit/data/fixtures/vertical_text/simple_ja_ruby.epub",
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
        if readerui.styletweak then
            readerui.styletweak.book_style_tweak =
                "body { writing-mode: vertical-rl !important; }"
            readerui.styletweak.book_style_tweak_enabled = true
            readerui.styletweak:updateCssText(true)
        end
        fastforward_ui_events()
        doc = readerui.document
    end)

    after_each(function()
        if readerui then readerui:onClose() end
        UIManager:quit()
    end)

    it("ruby inline boxes do not overlap the preceding character #no_overlap", function()
        if not epub_path then pending("no epub found"); return end

        -- Reset bleed counters, then render several pages.
        -- Each page visit triggers Draw() which records any P14-type overlaps.
        doc._document:resetVertBleedCounters()

        local pages_to_visit = math.min(doc:getPageCount(), 20)
        local sw, sh = Screen:getWidth(), Screen:getHeight()
        local sample_xs = {
            math.floor(sw * 0.80),
            math.floor(sw * 0.50),
            math.floor(sw * 0.20),
        }

        for pg = 1, pages_to_visit do
            readerui.rolling:onGotoPage(pg)
            fastforward_ui_events()
            -- Tap a few positions to ensure Draw() runs on this page.
            for _, x in ipairs(sample_xs) do
                pcall(function()
                    doc:getWordFromPosition({ x = x, y = math.floor(sh * 0.5) })
                end)
            end
        end

        local count, max_px = doc._document:getVertBleedStats()

        print(string.format(
            "[no_overlap] pages=%d  overlap_events=%d  max_overlap=%d px",
            pages_to_visit, count, max_px))

        -- THE KEY ASSERTION: no ruby inline box must start before the
        -- preceding character ends.  P14 caused ~10-12 px overlaps.
        assert.are.equal(0, count,
            string.format(
                "%d overlap event(s) detected (worst: %d px).  "
                .. "The ruby inline box is not clamped to vert_min_next_x.  "
                .. "Fix: shift only x0 by the clamping delta in Draw(); "
                .. "keep doc_x_ib = -node_x.",
                count, max_px))
    end)
end)
