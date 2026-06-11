--[[--
Vertical-rl float image overlap regression.

A CSS `float` element used to have no positioning implementation for vertical
writing modes, so a floated illustration was either drawn on top of the column
text or forced into a full in-flow column band.

FIX: vertical mode reuses the float footprint machinery with swapped semantics:
the float's X/width are the in-column screen-Y exclusion, and Y/height are the
right-to-left column advance. Text columns that intersect the float start after
the float's in-column exclusion and continue in the same screen-X band.

Oracle: render the fixture (a float:left 360px-wide image between two text
paragraphs) and look at the screen-X coverage of the selectable text.
  - FIXED:  all body text is present/selectable, and the text boxes do NOT leave
            a full image-width screen-X gap because text wraps below the image.
  - BROKEN: overdraw hides most of the body text, or the in-flow fallback leaves
            a large reserved column band.

Run via:
  ./kodev test front -f "Vertical text: float image"
--]]

local lfs = require("libs/libkoreader-lfs")

describe("Vertical text: float image does not overlap text", function()
    local epub_path = "spec/front/unit/data/fixtures/vertical_text/float_image_test.epub"
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
        if not lfs.attributes(epub_path) then return end
        readerui = ReaderUI:new{
            dimen = Screen:getSize(),
            document = DocumentRegistry:openDocument(epub_path),
        }
        UIManager:show(readerui)
        fastforward_ui_events()
        doc = readerui.document
    end)

    after_each(function()
        if readerui then
            readerui:closeDocument()
            readerui:onClose()
            readerui = nil
        end
    end)

    it("wraps text around the float and keeps all text visible", function()
        if not lfs.attributes(epub_path) then
            pending("float_image_test.epub fixture missing from test-data submodule")
            return
        end
        -- The fixture declares writing-mode: vertical-rl in its own CSS.
        assert.is_true(doc._document:isVerticalText(),
            "fixture should render in vertical-rl")

        local sw, sh = Screen:getWidth(), Screen:getHeight()
        local t = doc:getTextFromPositions({x=sw-1, y=0}, {x=0, y=sh-1}, true)
        assert.is_truthy(t and t.text, "page should expose selectable text")

        -- All body text must remain selectable (not hidden behind the image).
        -- If the float overdraws the columns only a small sliver (~70 chars)
        -- is reachable with this fixture.
        assert.is_true(#t.text >= 300,
            "most body text is hidden behind the float image (got "..#t.text.." chars)")

        assert.matches("マーカーあとぶんしょうかいし", t.text,
            "text after the floated image should be present on the page")

        -- The image should no longer force its own full-height column band:
        -- text wraps into the same screen-X band below the float, so selectable
        -- text boxes should not leave a contiguous horizontal gap close to the
        -- image width (360px). A pure in-flow fallback would leave that gap.
        local covered, minx, maxx = {}, math.huge, -math.huge
        for _, b in ipairs(t.sboxes or {}) do
            local x0, x1 = b.x, b.x + b.w
            if x0 < minx then minx = x0 end
            if x1 > maxx then maxx = x1 end
            for x = math.floor(x0), math.ceil(x1) do covered[x] = true end
        end
        local gap, largest_gap = 0, 0
        for x = math.floor(minx), math.ceil(maxx) do
            if covered[x] then gap = 0 else gap = gap + 1; if gap > largest_gap then largest_gap = gap end end
        end
        assert.is_true(largest_gap < 300,
            "float image did not wrap text into its column band (largest text gap "..largest_gap.."px)")
    end)
end)
