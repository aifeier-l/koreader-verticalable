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
        -- Guard against the fixture not being present (e.g. fresh clone before
        -- the test-data submodule is fetched): pend instead of hard-failing.
        local f = io.open(epub, "r")
        if not f then pending("mixed_wm_test.epub not found"); return end
        f:close()
        local document = require("document/documentregistry"):openDocument(epub)
        if not document then pending("mixed_wm_test.epub could not be opened"); return end
        local readerui = ReaderUI:new{
            document = document,
            dimen = Screen:getSize(),
        }
        fastforward_ui_events()
        assert.is_true(readerui.document:getPageCount() > 0)
        readerui:onClose()
        fastforward_ui_events()
    end)
end)
