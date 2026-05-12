-- Bisect helper: detect ruby boxing SIGSEGV in crengine.
--
-- This spec is SKIPPED (pending) unless crash_ruby.epub exists at:
--   test/fixtures/vertical_text/crash_ruby.epub
--
-- crash_ruby.epub: minimal EPUB with <ruby>石<rt>いし</rt></ruby> and no
-- "ruby { display: inline }" CSS — triggers the boxing path that crashes.
--
-- Usage for git bisect (from base repo root):
--   git bisect start
--   git bisect bad HEAD                # current HEAD: crashes
--   git bisect good d2e19c9a           # last upstream commit: no crash
--   git bisect run \
--       tests/fixtures/vertical_text/bisect-ruby-crash.sh
--   git bisect reset

describe("Ruby boxing bisect", function()
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
        if not f then
            pending("crash_ruby.epub absent — skipped in normal test runs")
            return
        end
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
