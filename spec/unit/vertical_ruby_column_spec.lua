--[[--
Vertical-rl ruby column position regression test.

In vertical-rl, each ruby inline box must pass y0 = x + node_y to the inner
DrawDocument call so that the ruby base column is placed at the correct
screen-X offset (clip.right − node_y − annot_width).

BUG: y0 and doc_y_ib were not initialised in the vertical branch of the
inline-box draw path in LFormattedText::Draw().  In practice y0 ≈ 0 on the
stack, which makes every ruby group draw at column clip.right − annot_width
regardless of its accumulated column advance (node_y).  Ruby groups in later
columns appear shifted several columns to the right.

DETECTION: ltext_vert_bleed_count fires when a ruby inline-box's screen-Y
start (draw_x_inner) is less than the preceding character's screen-Y end
(preceding_end), meaning the ruby group overlaps the preceding character.
With the bug (y0 = 0) most ruby groups in columns > 0 would bleed into the
character above them.

FIX: set y0 = x + node_y and doc_y_ib = 0 − node_y in the vertical branch.

Run via:
  ./kodev test front -f "Vertical text"
--]]

describe("Vertical text: ruby inline-box column position", function()
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

    it("ruby groups do not bleed into preceding characters #ruby_column", function()
        if not epub_path then pending("sanshiro.epub not found"); return end

        -- Reset the bleed diagnostic, then render several pages.
        -- Each page visit calls Draw() which fires ltext_vert_bleed_count when a
        -- ruby inline-box's draw_x_inner < preceding character's slot end.
        doc._document:resetVertBleedCounters()

        local pages_to_visit = math.min(doc:getPageCount(), 20)
        local sw, sh = Screen:getWidth(), Screen:getHeight()

        for pg = 1, pages_to_visit do
            readerui.rolling:onGotoPage(pg)
            fastforward_ui_events()
            -- Tap several positions to trigger Draw().
            for _, fx in ipairs({0.80, 0.50, 0.20}) do
                pcall(function()
                    doc:getWordFromPosition({x = math.floor(sw * fx),
                                            y = math.floor(sh * 0.5)})
                end)
            end
        end

        local bleed_count, bleed_max_px = doc._document:getVertBleedStats()

        print(string.format(
            "[ruby_column] pages=%d  ruby_bleed_count=%d  max_px=%d",
            pages_to_visit, bleed_count, bleed_max_px))

        -- THE KEY ASSERTION: no ruby group may start before the preceding character ends.
        -- With the column-position bug (y0 = 0) ruby groups in later columns have
        -- draw_x_inner far below the correct position, bleeding into preceding chars.
        assert.are.equal(0, bleed_count,
            string.format(
                "%d ruby IB draw(s) bled into preceding character (max %d px). "
                .. "Fix: set y0 = x + node_y and doc_y_ib = 0 - node_y in the "
                .. "vertical inline-box branch of LFormattedText::Draw().",
                bleed_count, bleed_max_px))
    end)
end)
