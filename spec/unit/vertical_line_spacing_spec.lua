--[[--
Vertical-rl default line spacing.

The fork maps the ordinary horizontal 100% line spacing setting to a wider
vertical-rl line pitch when the book leaves line-height at normal. Explicit
publisher line-height values must remain under CSS control.
--]]

describe("Vertical line spacing #vertical_line_spacing", function()
    local DocumentRegistry, ReaderUI, Screen, UIManager

    setup(function()
        require("commonrequire")
        disable_plugins()
        require("document/canvascontext"):init(require("device"))
        DocumentRegistry = require("document/documentregistry")
        ReaderUI = require("apps/reader/readerui")
        Screen = require("device").screen
        UIManager = require("ui/uimanager")
    end)

    local function write_fixture(path, extra_css)
        local body = {}
        for _ = 1, 180 do
            table.insert(body, "これは縦組み行間の確認です。")
        end
        local f = assert(io.open(path, "wb"))
        f:write([[<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml">
<head><meta charset="UTF-8"/><style>
html, body { margin: 0; padding: 0; }
body { writing-mode: vertical-rl; text-align: justify; font-family: serif; ]] .. extra_css .. [[ }
p { margin: 0; }
</style></head><body><p>]], table.concat(body), [[</p></body></html>]])
        f:close()
    end

    local function median_column_gap(path)
        local readerui = ReaderUI:new{
            dimen = Screen:getSize(),
            document = DocumentRegistry:openDocument(path),
        }
        UIManager:show(readerui)
        readerui.document:setFontSize(26)
        readerui.document:setInterlineSpacePercent(100)
        readerui.rolling:onGotoPage(1)
        fastforward_ui_events()

        local cols = {}
        for x = Screen:getWidth() - 5, 5, -8 do
            for y = 20, Screen:getHeight() - 20, 24 do
                local ok, w = pcall(function()
                    return readerui.document:getWordFromPosition({x = x, y = y})
                end)
                if ok and w and w.word and w.sbox and w.sbox.w >= 10 and w.sbox.w <= 90 then
                    local cx = math.floor(w.sbox.x + w.sbox.w / 2 + 0.5)
                    cols[cx] = true
                end
            end
        end
        local list = {}
        for x in pairs(cols) do table.insert(list, x) end
        table.sort(list, function(a, b) return a > b end)
        local gaps = {}
        for i = 1, #list - 1 do
            local d = list[i] - list[i + 1]
            if d >= 10 and d <= 100 then table.insert(gaps, d) end
        end
        table.sort(gaps)
        local median = gaps[math.max(1, math.floor(#gaps / 2))] or 0
        readerui:onClose()
        UIManager:quit()
        return median, #list
    end

    it("adds vertical-rl default pitch only for normal line-height", function()
        local normal_path = "/tmp/koreader_vertical_line_spacing_normal.xhtml"
        local explicit_path = "/tmp/koreader_vertical_line_spacing_explicit.xhtml"
        write_fixture(normal_path, "")
        write_fixture(explicit_path, "line-height: 1;")

        local normal_gap, normal_cols = median_column_gap(normal_path)
        local explicit_gap, explicit_cols = median_column_gap(explicit_path)
        print(string.format(
            "[vertical_line_spacing] normal_gap=%d explicit_gap=%d normal_cols=%d explicit_cols=%d",
            normal_gap, explicit_gap, normal_cols, explicit_cols))

        assert.is_true(normal_gap >= explicit_gap + 10,
            string.format("normal vertical-rl gap %d should exceed explicit line-height gap %d", normal_gap, explicit_gap))
    end)
end)
