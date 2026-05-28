describe("Screenshot test", function()
    it("takes screenshot of vertical EPUB", function()
        require("commonrequire")
        require("document/canvascontext"):init(require("device"))
        local DocumentRegistry = require("document/documentregistry")
        local ReaderUI = require("apps/reader/readerui")
        local UIManager = require("ui/uimanager")
        local Screen = require("device").screen

        local epub_path = "spec/front/unit/data/fixtures/vertical_text/sanshiro.epub"
        local output_path = "/tmp/vertical_screenshot.png"

        print("Opening: " .. epub_path)

        -- Open the document BEFORE constructing ReaderUI: ReaderUI:init()
        -- dereferences self.document.file, so the document must be supplied
        -- in the :new{} table (matching all other reader specs).  The
        -- previous code created ReaderUI without a document and assigned it
        -- afterwards, which crashed in init().
        local doc = DocumentRegistry:openDocument(epub_path)
        assert(doc, "Failed to open document")
        print("Document opened")

        local readerui = ReaderUI:new{
            dimen = Screen:getSize(),
            document = doc,
        }
        -- ReaderUI:new renders the first page during setup; navigate to
        -- page 1 explicitly via the rolling module (cre/epub documents use
        -- ReaderRolling, not a non-existent ReaderUI:showPage method).
        if readerui.rolling then
            readerui.rolling:onGotoPage(1)
        end

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
