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
body { writing-mode: vertical-rl; font-size: 43px; }
p { margin: 1em; }
a { border-right: 1px solid; text-decoration: underline; }
a span { font-size: 1.66667em; line-height: 1.2; }
a.plain { border-right: 0; }
</style></head><body>
<p><a href="#">第<span>１</span>章</a></p>
<p><a class="plain" href="#">甲<span>２</span>乙</a></p>
</body></html>]])
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
                if word and word.sbox and (word.word == "第" or word.word == "１"
                        or word.word == "章" or word.word == "甲"
                        or word.word == "２" or word.word == "乙") then
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
        local decorated_scan_left = math.min(first.x, found.x, last.x)
        local decorated_scan_right = math.min(Screen:getWidth() - 1,
            math.max(first.x + first.w, found.x + found.w, last.x + last.w) + 8)
        for x = decorated_scan_left, decorated_scan_right do
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
        -- The 1px authored border alone must not make this pass: at least one
        -- additional dark column from the font-derived underline must cover
        -- the complete link too (antialiasing may leave only two columns below
        -- the threshold with this test font).
        assert.is_true(#continuous_columns >= 2, "vertical underline was not continuous")
        -- The border and font-derived underline may form a thicker contiguous
        -- rule, but must not split into visibly separate rules.
        assert.is_true(#continuous_columns <= 6,
            "underline and border-right formed an abnormally wide line")
        assert.are.equal(#continuous_columns,
            continuous_columns[#continuous_columns] - continuous_columns[1] + 1,
            "underline and border-right separated into a double line")

        -- A continuous 1px authored border used to hide a broken underline:
        -- the test above would pass even when the thicker underline stopped
        -- and restarted at every descendant text node.  Sample only the
        -- whitespace gaps between the three glyph boxes, where glyph ink
        -- cannot affect the measured rule thickness.  The combined rule must
        -- retain the same thickness while crossing both text-node boundaries.
        local function dark_run_at(y)
            local best = 0
            local run = 0
            local scan_left = math.max(first.x, found.x, last.x)
            local scan_right = math.max(first.x + first.w,
                found.x + found.w, last.x + last.w) + 8
            for x = scan_left, math.min(scan_right, Screen:getWidth() - 1) do
                local px = Screen.bb:getPixel(x, y)
                if px and px:getR() < 200 then
                    run = run + 1
                    if run > best then best = run end
                else
                    run = 0
                end
            end
            return best
        end
        local first_end = first.y + first.h
        local digit_end = found.y + found.h
        local gap1_y = math.floor((first_end + found.y) / 2)
        local gap2_y = math.floor((digit_end + last.y) / 2)
        local gap1_thickness = dark_run_at(gap1_y)
        local gap2_thickness = dark_run_at(gap2_y)
        print(string.format(
            "[vertical_fullwidth_border] boundary_thickness=%d,%d at y=%d,%d",
            gap1_thickness, gap2_thickness, gap1_y, gap2_y))
        assert.is_true(gap1_thickness >= #continuous_columns
                and gap2_thickness >= #continuous_columns,
            "underline was interrupted at a descendant text-node boundary")

        -- A line displaced only alongside the larger descendant is shorter
        -- than the whole anchor, so the paragraph-wide scan above cannot see
        -- it. Compare the continuous columns in each glyph's own inline span.
        local function line_columns(box)
            local columns = {}
            local scan_left = box.x + math.floor(box.w * 0.55)
            for x = scan_left, box.x + box.w - 1 do
                local dark = 0
                for y = box.y, box.y + box.h - 1 do
                    local px = Screen.bb:getPixel(x, y)
                    if px and px:getR() < 200 then dark = dark + 1 end
                end
                if dark >= box.h * 0.75 then
                    columns[x] = true
                end
            end
            return columns
        end
        local outer = line_columns(first)
        local digit = line_columns(found)
        local displaced = {}
        for x in pairs(digit) do
            if not outer[x] then table.insert(displaced, x) end
        end
        table.sort(displaced)
        print(string.format("[vertical_fullwidth_border] digit_only_line_columns=%s",
            table.concat(displaced, ",")))
        assert.are.same({}, displaced,
            "larger descendant moved only its portion of the decoration line")

        -- Isolate the mutable-pen regression from border painting. FreeType's
        -- vertical glyph loop advances its y pen; the underline must retain
        -- the run's original y rather than starting one glyph too late.
        local plain_first = assert(words["甲"], "plain first character was not rendered")
        local plain_digit = assert(words["２"], "plain fullwidth digit was not rendered")
        local plain_last = assert(words["乙"], "plain last character was not rendered")
        local plain_y0 = math.min(plain_first.y, plain_digit.y, plain_last.y)
        local plain_y1 = math.max(plain_first.y + plain_first.h,
            plain_digit.y + plain_digit.h, plain_last.y + plain_last.h)
        local plain_span = plain_y1 - plain_y0
        local plain_continuous = {}
        local plain_scan_left = math.min(plain_first.x, plain_digit.x, plain_last.x)
        local plain_scan_right = math.min(Screen:getWidth() - 1,
            math.max(plain_first.x + plain_first.w,
                plain_digit.x + plain_digit.w, plain_last.x + plain_last.w) + 8)
        for x = plain_scan_left, plain_scan_right do
            local dark = 0
            for y = plain_y0, plain_y1 - 1 do
                local px = Screen.bb:getPixel(x, y)
                if px and px:getR() < 200 then dark = dark + 1 end
            end
            if dark >= plain_span * 0.8 then
                table.insert(plain_continuous, x)
            end
        end
        print(string.format("[vertical_fullwidth_border] plain_continuous_line_columns=%s",
            table.concat(plain_continuous, ",")))
        assert.is_true(#plain_continuous >= 1,
            "vertical underline used the post-glyph y pen instead of the run origin")
    end)

    teardown(function()
        if readerui then readerui:onClose() end
    end)
end)
