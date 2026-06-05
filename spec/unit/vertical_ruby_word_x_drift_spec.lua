--[[--
Diagnostic spec: detect whether plain CJK words' word->x (LAYOUT post-pass
position, used by getRect for highlight) disagrees with state.vert_min_next_x
(DRAW position) on vertical-rl pages with rubies.

When the two diverge, the highlight rect drawn for a CJK character will be
displaced from the actual glyph along the column axis.  Symptom: long ruby
group pushes the following character down by (annot_depth − base_advance),
but the highlight box stays at the un-pushed position (or vice-versa).

Reads the diagnostic counter exposed by crengine
(`getVertWordXDrift` → count, max_abs_px, signed_sum_px) and prints
stats per page.  No assertion: this spec just *measures*.
]]--

describe("Vertical-rl word->x vs vert_min_next_x drift", function()
    local epub_candidates = {
        "spec/front/unit/data/fixtures/vertical_text/sanshiro.epub",
    }
    local epub_path
    local lfs = require("libs/libkoreader-lfs")
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

    it("measures word->x drift across sanshiro pages #word_x_drift", function()
        if not epub_path then pending("sanshiro.epub not found"); return end

        local total_pages = doc:getPageCount()
        local pages_to_visit = math.min(total_pages, 100)
        local sw, sh = Screen:getWidth(), Screen:getHeight()

        local grand_count, grand_max_abs, grand_sum = 0, 0, 0

        for pg = 1, pages_to_visit do
            doc._document:resetVertWordXDrift()
            readerui.rolling:onGotoPage(pg)
            fastforward_ui_events()
            -- Tap a few positions to ensure Draw() runs (some refresh paths skip
            -- the full Draw if nothing requested a fresh paint).
            for _, fx in ipairs({0.85, 0.55, 0.25}) do
                pcall(function()
                    doc:getWordFromPosition({x = math.floor(sw * fx),
                                            y = math.floor(sh * 0.5)})
                end)
            end
            local cnt, max_abs, sum = doc._document:getVertWordXDrift()
            if cnt > 0 then
                print(string.format(
                    "[word_x_drift] page=%d  count=%d  max_abs=%dpx  signed_sum=%+dpx  avg=%+.1fpx",
                    pg, cnt, max_abs, sum, sum / cnt))
            end
            grand_count   = grand_count   + cnt
            grand_max_abs = math.max(grand_max_abs, max_abs)
            grand_sum     = grand_sum     + sum
        end

        print(string.format(
            "[word_x_drift] TOTAL pages=%d  count=%d  max_abs=%dpx  signed_sum=%+dpx",
            pages_to_visit, grand_count, grand_max_abs, grand_sum))

        -- Diagnostic-only: no hard assertion.  The signed sum tells us the
        -- direction of the bug (positive ⇒ highlight below glyph, negative ⇒
        -- highlight above glyph).  count = 0 means LAYOUT and DRAW are in
        -- sync for every plain CJK word visited.
    end)
end)
