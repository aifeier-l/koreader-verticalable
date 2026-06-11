-- Regression: ruby boxing must not SIGSEGV in vertical-rl mode.
--
-- crash_ruby.epub is a minimal EPUB with <ruby>石<rt>いし</rt></ruby> and no
-- "ruby { display: inline }" CSS — it exercises the boxing path that used to
-- crash crengine when re-rendered with writing-mode: vertical-rl.

describe("Vertical ruby crash", function()
    local DocumentRegistry, ReaderUI, UIManager, Screen

    setup(function()
        require("commonrequire")
        disable_plugins()
        require("document/canvascontext"):init(require("device"))
        DocumentRegistry = require("document/documentregistry")
        ReaderUI = require("apps/reader/readerui")
        Screen = require("device").screen
        UIManager = require("ui/uimanager")
    end)

    it("opens crash_ruby.epub with vertical-rl CSS without SIGSEGV", function()
        local epub = "spec/front/unit/data/fixtures/vertical_text/crash_ruby.epub"
        local f = io.open(epub, "rb")
        assert.truthy(f, "crash_ruby.epub fixture missing from test-data submodule")
        f:close()

        local readerui = ReaderUI:new{
            dimen = Screen:getSize(),
            document = DocumentRegistry:openDocument(epub),
        }
        UIManager:show(readerui)
        fastforward_ui_events()
        if readerui.styletweak then
            readerui.styletweak.book_style_tweak = "body { writing-mode: vertical-rl !important; }"
            readerui.styletweak.book_style_tweak_enabled = true
            readerui.styletweak:updateCssText(true)
        end
        fastforward_ui_events()
        UIManager:quit()
        assert.truthy(readerui, "ReaderUI survived vertical-rl re-render with ruby content")
        readerui:onClose()
    end)
end)
