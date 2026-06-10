--[[--
Vertical text: do NOT misclassify a horizontal rtl-spine EPUB as vertical.

Regression for the "横書き RTL" bug: a horizontal Japanese EPUB that carries
page-progression-direction="rtl" but NO writing-mode CSS (typical of calibre
conversions) was reported as vertical by isVerticalText() — its body has no
vertical writing-mode, but the page-height fallback heuristic returned true on
a short page (title page / part divider).  ReaderRolling:onReaderReady then
forced inverse_reading_order (RTL page-turn) on horizontal text.

Fix: once the <body> style is resolved, a non-vertical writing-mode (including
unset/inherit) returns false; the page-height fallback only applies when the
style can't be read.  Genuinely vertical docs (writing-mode on body) are
unaffected — they return true via the body check.

Run via:
  ./kodev test front -f "horizontal rtl"
--]]

describe("Vertical text: horizontal rtl-spine not misdetected #horizontal_rtl", function()
    local DocumentRegistry, ReaderUI, Screen, UIManager

    setup(function()
        require("commonrequire")
        disable_plugins()
        require("document/canvascontext"):init(require("device"))
        DocumentRegistry = require("document/documentregistry")
        ReaderUI         = require("apps/reader/readerui")
        Screen           = require("device").screen
        UIManager        = require("ui/uimanager")
    end)

    local function open_and_is_vertical(epub_path)
        local f = io.open(epub_path, "r")
        if not f then return nil end
        f:close()
        local doc = DocumentRegistry:openDocument(epub_path)
        assert(doc, "failed to open " .. epub_path)
        local readerui = ReaderUI:new{ dimen = Screen:getSize(), document = doc }
        if readerui.rolling then readerui.rolling:onGotoPage(1) end
        fastforward_ui_events()
        local is_vert = doc:isVerticalText()
        readerui:onClose()
        UIManager:quit()
        return is_vert
    end

    it("a horizontal rtl-spine EPUB with no writing-mode CSS is NOT vertical #horizontal_rtl", function()
        local p = "spec/front/unit/data/fixtures/vertical_text/horizontal_rtl_test.epub"
        local is_vert = open_and_is_vertical(p)
        if is_vert == nil then pending("horizontal_rtl_test.epub not found"); return end
        assert.is_false(is_vert,
            "horizontal rtl-spine document misdetected as vertical (would force RTL page-turn on horizontal text)")
    end)

    it("a genuinely vertical EPUB (writing-mode on body) is still vertical #horizontal_rtl", function()
        local p = "spec/front/unit/data/fixtures/vertical_text/sanshiro.epub"
        local is_vert = open_and_is_vertical(p)
        if is_vert == nil then pending("sanshiro.epub not found"); return end
        assert.is_true(is_vert, "vertical document (body writing-mode) no longer detected as vertical")
    end)
end)
