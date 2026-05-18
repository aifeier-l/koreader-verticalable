describe("Screenshot test", function()
    it("takes screenshot of vertical EPUB", function()
        require("commonrequire")
        require("document/canvascontext"):init(require("device"))
        local DocumentRegistry = require("document/documentregistry")
        local ReaderUI = require("apps/reader/readerui")
        local UIManager = require("ui/uimanager")
        local Screen = require("device").screen

        local epub_path = "/tmp/test_vertical_inline.epub"
        local output_path = "/tmp/vertical_screenshot.png"

        print("Opening: " .. epub_path)

        local readerui = ReaderUI:new{
            dimen = Screen:getSize(),
        }

        local doc = DocumentRegistry:openDocument(epub_path)
        assert(doc, "Failed to open document")
        print("Document opened")

        readerui:setupReader()
        readerui.document = doc
        readerui:showPage(1)

        -- Wait for rendering
        UIManager:nextTick(function()
            print("Taking screenshot: " .. output_path)
            Screen:shot(output_path)
            print("Screenshot saved")
            UIManager:quit()
        end)

        UIManager:run()
        print("Done")

        -- Verify screenshot exists
        local f = io.open(output_path, "r")
        assert(f, "Screenshot was not created")
        f:close()
        print("Screenshot verified: " .. output_path)
    end)
end)
