--[[--
Vertical inline borders next to upright fullwidth text.

The text decoration belongs to the anchor's inline box. A descendant fullwidth
digit may have a larger font, but it must not move only its portion of the
decoration or the coincident border-right line.
--]]

describe("Vertical text: fullwidth inline border #vertical_fullwidth_border", function()
    local DocumentRegistry, ReaderUI, Screen, UIManager
    local readerui
    local path = "/tmp/koreader_vertical_fullwidth_border.xhtml"

    setup(function()
        require("commonrequire")
        disable_plugins()
        require("document/canvascontext"):init(require("device"))
        DocumentRegistry = require("document/documentregistry")
        ReaderUI = require("apps/reader/readerui")
        Screen = require("device").screen
        UIManager = require("ui/uimanager")
    end)

    it("draws an underlined bordered link without treating padding as text", function()
        local f = assert(io.open(path, "wb"))
        f:write([[<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml"><head><style>
html, body { margin: 0; padding: 0; }
body { writing-mode: vertical-rl; font-size: 48px; }
p { margin: 1em; }
a { border-right: 2px solid; text-decoration: underline; }
a span { font-size: 1.66667em; }
</style></head><body><p><a href="#">第<span>１</span>章</a></p></body></html>]])
        f:close()

        readerui = ReaderUI:new{
            dimen = Screen:getSize(),
            document = DocumentRegistry:openDocument(path),
        }
        UIManager:show(readerui)
        fastforward_ui_events()

        local words = {}
        for x = Screen:getWidth() - 4, 4, -4 do
            for y = 4, Screen:getHeight() - 4, 4 do
                local word = readerui.document:getWordFromPosition({x=x, y=y})
                if word and word.sbox
                        and (word.word == "第" or word.word == "１" or word.word == "章") then
                    words[word.word] = word.sbox
                end
            end
        end
        local found = assert(words["１"], "fullwidth digit was not rendered")
        print(string.format("[vertical_fullwidth_border] digit=(%d,%d %dx%d)",
            found.x, found.y, found.w, found.h))

        local first = assert(words["第"], "first anchor character was not rendered")
        local last = assert(words["章"], "last anchor character was not rendered")
        local y0 = math.min(first.y, found.y, last.y)
        local y1 = math.max(first.y + first.h, found.y + found.h, last.y + last.h)
        local span = y1 - y0
        local continuous_columns = {}
        for x = 0, Screen:getWidth() - 1 do
            local dark = 0
            for y = y0, y1 - 1 do
                local px = Screen.bb:getPixel(x, y)
                if px and px:getR() < 200 then dark = dark + 1 end
            end
            if dark >= span * 0.8 then
                table.insert(continuous_columns, x)
            end
        end
        print(string.format("[vertical_fullwidth_border] continuous_line_columns=%s",
            table.concat(continuous_columns, ",")))
        assert.is_true(#continuous_columns >= 1, "vertical decoration line was not continuous")
        assert.is_true(#continuous_columns <= 3,
            "underline and border-right separated into an abnormally wide/double line")
    end)

    teardown(function()
        if readerui then readerui:onClose() end
    end)
end)
