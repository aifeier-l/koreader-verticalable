--[[--
Vertical-rl: line-ending Latin spaces are not rendered.

Issue #27 (m-tky/koreader-tategumi): a phrase such as "blessing software" can
wrap after the space in vertical text.  The formatter already removes the
trailing space from the word's layout width; this spec verifies the matching
render-text trim fires, using a crengine diagnostic counter instead of visual
screenshots.
--]]

describe("Vertical text: Latin trailing space trim #latin_trailing_space", function()
    local DocumentRegistry, ReaderUI, Screen, UIManager
    local html_path = "/tmp/koreader_vertical_latin_trailing_space.xhtml"

    setup(function()
        require("commonrequire")
        disable_plugins()
        require("document/canvascontext"):init(require("device"))
        DocumentRegistry = require("document/documentregistry")
        ReaderUI         = require("apps/reader/readerui")
        Screen           = require("device").screen
        UIManager        = require("ui/uimanager")
    end)

    local function ensure_html_fixture()
        local body = {}
        for _ = 1, 80 do
            table.insert(body, "これは『blessing software』の完成を確認する本文です。")
        end
        local html = [[<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="ja">
<head>
<meta charset="UTF-8"/>
<title>vertical latin trailing space</title>
<style>
html, body { margin: 0; padding: 0; }
body { writing-mode: vertical-rl; text-align: justify; font-family: serif; }
p { margin: 0; text-align: justify; }
</style>
</head>
<body><p>]] .. table.concat(body) .. [[</p></body>
</html>]]
        local f = assert(io.open(html_path, "wb"))
        f:write(html)
        f:close()
        return html_path
    end

    it("trims rendered trailing spaces from vertical Latin line ends", function()
        local readerui = ReaderUI:new{
            dimen = Screen:getSize(),
            document = DocumentRegistry:openDocument(ensure_html_fixture()),
        }
        UIManager:show(readerui)
        fastforward_ui_events()

        local doc = readerui.document
        local total_count, total_chars = 0, 0
        local font_sizes = {20, 24, 28, 32, 36}
        local vertical_margins = {
            {top = 20, bottom = 20},
            {top = 60, bottom = 60},
            {top = 100, bottom = 100},
            {top = 140, bottom = 140},
        }

        for _, fs in ipairs(font_sizes) do
            for _, margin in ipairs(vertical_margins) do
                doc._document:resetVertTrailingSpaceTrim()
                doc:setFontSize(fs)
                doc:setPageMargins(20, margin.top, 20, margin.bottom)
                readerui.rolling:onGotoPage(1)
                fastforward_ui_events()
                local count, chars = doc._document:getVertTrailingSpaceTrim()
                total_count = total_count + count
                total_chars = total_chars + chars
                print(string.format(
                    "[latin_trailing_space] fs=%d top=%d bottom=%d trim_count=%d trim_chars=%d",
                    fs, margin.top, margin.bottom, count, chars))
            end
        end

        readerui:onClose()
        UIManager:quit()

        assert.truthy(total_count > 0,
            "vertical Latin fixture did not exercise any line-ending space trim")
        assert.truthy(total_chars >= total_count,
            string.format("trim_chars=%d should be >= trim_count=%d", total_chars, total_count))
    end)
end)
