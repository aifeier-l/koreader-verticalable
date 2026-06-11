--[[--
Vertical-rl float image overlap regression.

A CSS `float` element has no positioning implementation for vertical writing
modes (the float placement math is all horizontal-axis), so a floated
illustration used to be drawn on top of the column text — the body text ended
up hidden behind the image (e.g. Momo's div.leftfig laundry illustration).

FIX (lvrend.cpp): in vertical mode floats are rendered as in-flow blocks, so
the illustration occupies its own column band and the text flows in the
neighbouring columns instead of being overdrawn.

Oracle: render the fixture (a float:left 360px-wide image between two text
paragraphs) and look at the screen-X coverage of the selectable text.
  - FIXED:  the image reserves its own ~360px column band, so the text boxes
            leave a large screen-X gap (~image width) and ALL the body text is
            present/selectable.
  - BROKEN: the image overdraws the text columns, so most of the text is hidden
            (only a sliver is selectable) and there is no reserved gap.

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

    it("reserves a column band for the float and keeps all text visible", function()
        if not lfs.attributes(epub_path) then
            pending("float_image_test.epub fixture missing from test-data submodule")
            return
        end
        -- The fixture declares writing-mode: vertical-rl in its own CSS.
        assert.is_true(doc._document:isVerticalText(),
            "fixture should render in vertical-rl")

        local sw, sh = Screen:getWidth(), Screen:getHeight()
        local t = doc:getTextFromPositions({x=0, y=0}, {x=sw-1, y=sh-1}, true)
        assert.is_truthy(t and t.text, "page should expose selectable text")

        -- All body text must remain selectable (not hidden behind the image).
        -- The fixture body is ~356 chars; if the float overdrew the columns only
        -- a small sliver (~70 chars) would be reachable.
        assert.is_true(#t.text >= 300,
            "most body text is hidden behind the float image (got "..#t.text.." chars)")

        -- The image must occupy its own screen-X band: the selectable text boxes
        -- should leave a contiguous horizontal gap close to the image width
        -- (360px). A float overdrawing the text leaves no such gap.
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
        assert.is_true(largest_gap >= 300,
            "no reserved column band for the float image (largest text gap "..largest_gap.."px)")
    end)
end)
