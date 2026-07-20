describe("Readerpaging module", function()
    local sample_pdf = "spec/front/unit/data/sample.pdf"
    local readerui, BD, Event, DocumentRegistry, ReaderUI, Screen
    local paging

    setup(function()
        require("commonrequire")
        disable_plugins()
        BD = require("ui/bidi")
        Event = require("ui/event")
        DocumentRegistry = require("document/documentregistry")
        ReaderUI = require("apps/reader/readerui")
        Screen = require("device").screen
    end)

    describe("Page mode", function()
        setup(function()
            readerui = ReaderUI:new{
                dimen = Screen:getSize(),
                document = DocumentRegistry:openDocument(sample_pdf),
            }
            paging = readerui.paging
        end)
        teardown(function()
            readerui:closeDocument()
            readerui:onClose()
        end)

        it("should emit EndOfBook event at the end", function()
            readerui:handleEvent(Event:new("SetScrollMode", false))
            readerui.zooming:setZoomMode("pageheight")
            paging:onGotoPage(readerui.document:getPageCount())
            local called = false
            readerui.onEndOfBook = function()
                called = true
            end
            paging:onGotoViewRel(1)
            assert.is.truthy(called)
            readerui.onEndOfBook = nil
        end)

        it("should bind spatial arrow keys to the RTL page direction", function()
            paging.view.inverse_reading_order = true
            paging:registerKeyEvents()

            local next_keys = paging.key_events.GotoNextPage[1][1]
            local prev_keys = paging.key_events.GotoPrevPage[1][1]
            local expected_next = BD.mirroredUILayout() and "Right" or "Left"
            local expected_prev = BD.mirroredUILayout() and "Left" or "Right"

            assert.is_truthy(require("util").arrayContains(next_keys, expected_next))
            assert.is_truthy(require("util").arrayContains(prev_keys, expected_prev))
        end)

        it("should retain the spatial LTR arrow-key direction", function()
            paging.view.inverse_reading_order = false
            paging:registerKeyEvents()

            local next_keys = paging.key_events.GotoNextPage[1][1]
            local prev_keys = paging.key_events.GotoPrevPage[1][1]
            local expected_next = BD.mirroredUILayout() and "Left" or "Right"
            local expected_prev = BD.mirroredUILayout() and "Right" or "Left"

            assert.is_truthy(require("util").arrayContains(next_keys, expected_next))
            assert.is_truthy(require("util").arrayContains(prev_keys, expected_prev))
        end)
    end)

    describe("Scroll mode", function()
        setup(function()
            local purgeDir = require("ffi/util").purgeDir
            local DocSettings = require("docsettings")
            purgeDir(DocSettings:getSidecarDir(sample_pdf))
            os.remove(DocSettings:getHistoryPath(sample_pdf))

            readerui = ReaderUI:new{
                dimen = Screen:getSize(),
                document = DocumentRegistry:openDocument(sample_pdf),
            }
            paging = readerui.paging
        end)
        teardown(function()
            readerui:closeDocument()
            readerui:onClose()
        end)

        it("should emit EndOfBook event at the end", function()
            paging.page_positions = {}
            readerui:handleEvent(Event:new("SetScrollMode", true))
            paging:onGotoPage(readerui.document:getPageCount())
            readerui.zooming:setZoomMode("pageheight")
            local called = false
            readerui.onEndOfBook = function()
                called = true
            end
            paging:onGotoViewRel(1)
            paging:onGotoViewRel(1)
            assert.is.truthy(called)
            readerui.onEndOfBook = nil
        end)
    end)

    describe("Scroll mode", function()

        setup(function()
            readerui = ReaderUI:new{
                dimen = Screen:getSize(),
                document = DocumentRegistry:openDocument("spec/front/unit/data/djvu3spec.djvu"),
            }
            paging = readerui.paging
        end)

        teardown(function()
            readerui:closeDocument()
            readerui:onClose()
        end)

        it("should scroll backward on the first page without crash", function()
            paging:onScrollPanRel(-100)
        end)

        it("should scroll forward on the last page without crash", function()
            paging:onGotoPage(readerui.document:getPageCount())
            paging:onScrollPanRel(120)
            paging:onScrollPanRel(-1)
            paging:onScrollPanRel(120)
        end)
    end)
end)
