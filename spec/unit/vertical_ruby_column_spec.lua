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

DETECTION: ltext_vert_ruby_y0_total_error accumulates |y0_actual − y0_expected|
for every ruby inline-box DrawDocument call.  With y0 = 0 the error equals
node_y per draw and is > 0 for any ruby not at the very first column.

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

    it("ruby y0 column offset equals x + node_y for every inline-box draw #ruby_column", function()
        if not epub_path then pending("sanshiro.epub not found"); return end

        -- Reset the y0 diagnostic, then render several pages.
        -- Each page visit calls Draw() which accumulates |y0_actual - y0_expected|.
        doc._document:resetVertRubyY0Diag()

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

        local count, total_error = doc._document:getVertRubyY0Diag()

        print(string.format(
            "[ruby_column] pages=%d  ruby_ib_draws=%d  total_y0_error=%d px",
            pages_to_visit, count, total_error))

        assert.is_true(count > 0,
            "No ruby inline-box draws recorded — is sanshiro.epub loaded correctly?")

        -- THE KEY ASSERTION: every ruby DrawDocument call must have y0 = x + node_y.
        -- With the bug (y0 = 0) the error equals node_y per draw, which grows with
        -- each column and reaches hundreds of px for mid-page ruby groups.
        assert.are.equal(0, total_error,
            string.format(
                "%d ruby IB draw(s) had total y0 column error %d px. "
                .. "Fix: set y0 = x + node_y and doc_y_ib = 0 - node_y in the "
                .. "vertical inline-box branch of LFormattedText::Draw().",
                count, total_error))
    end)
end)
