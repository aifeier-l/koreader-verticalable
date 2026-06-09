describe("Vertical text webkit mixed writing-mode", function()
    local ReaderUI, Screen
    local epub = "spec/front/unit/data/fixtures/vertical_text/mixed_wm_test.epub"

    setup(function()
        require("commonrequire")
        disable_plugins()
        require("document/canvascontext"):init(require("device"))
        ReaderUI = require("apps/reader/readerui")
        Screen = require("device").screen
    end)

    it("renders hltr/vrtl mixed EPUB without crash", function()
        local readerui = ReaderUI:new{
            document = require("document/documentregistry"):openDocument(epub),
            dimen = Screen:getSize(),
        }
        fastforward_ui_events()
        assert.is_true(readerui.document:getPageCount() > 0)
        readerui:onClose()
        fastforward_ui_events()
    end)
end)
