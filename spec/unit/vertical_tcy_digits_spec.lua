--[[--
Vertical text: text-combine-upright digit limits.

CSS `digits N` combines only ASCII digit runs of N characters or fewer.  It
must not turn a longer number or non-digit text into tate-chu-yoko.  Geometry
from getWordFromPosition is the observable layout contract: a TCY run occupies
one em slot, while a longer rotated run occupies several ems.
--]]

describe("Vertical text: tate-chu-yoko digit limits #tcy_digits", function()
    local DocumentRegistry, ReaderUI, Screen, UIManager
    local readerui
    local html_path = "/tmp/koreader_vertical_tcy_digits.xhtml"

    setup(function()
        require("commonrequire")
        disable_plugins()
        require("document/canvascontext"):init(require("device"))
        DocumentRegistry = require("document/documentregistry")
        ReaderUI = require("apps/reader/readerui")
        Screen = require("device").screen
        UIManager = require("ui/uimanager")
    end)

    local function fixture()
        local f = assert(io.open(html_path, "wb"))
        f:write([[<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml"><head><style>
body { writing-mode: vertical-rl; font-size: 32px; margin: 0; }
p { margin: 0 1em 0 0; }
.d2 { text-combine-upright: digits 2; }
.d3 { text-combine-upright: digits 3; }
</style></head><body>
<p>甲<span class="d2">12</span>乙</p>
<p>丙<span class="d2">123</span>丁</p>
<p>戊<span class="d3">123</span>己</p>
<p>庚<span class="d2">AB</span>辛</p>
</body></html>]])
        f:close()
        return html_path
    end

    local function find_word(doc, target)
        local seen = {}
        for x = Screen:getWidth() - 4, 4, -4 do
            for y = 4, Screen:getHeight() - 4, 4 do
                local word = doc:getWordFromPosition({ x = x, y = y })
                if word and word.word == target and word.sbox then
                    local sb = word.sbox
                    local key = string.format("%d:%d:%d:%d", sb.x, sb.y, sb.w, sb.h)
                    if not seen[key] then
                        seen[key] = { x = sb.x, y = sb.y, w = sb.w, h = sb.h }
                    end
                end
            end
        end
        local found = {}
        for _, sb in pairs(seen) do table.insert(found, sb) end
        table.sort(found, function(a, b) return a.x > b.x end)
        return found
    end

    it("honours digits 2 and digits 3 without combining non-digits", function()
        readerui = ReaderUI:new{
            dimen = Screen:getSize(),
            document = DocumentRegistry:openDocument(fixture()),
        }
        UIManager:show(readerui)
        fastforward_ui_events()
        local doc = readerui.document
        local two = assert(find_word(doc, "12")[1], "digits 2 run missing")
        local threes = find_word(doc, "123")
        local long = assert(threes[1], "digits 2 three-digit run missing")
        local letter = assert(find_word(doc, "AB")[1], "non-digit run missing")
        local combined_three = assert(threes[2], "digits 3 run missing")
        local d2_next = assert(find_word(doc, "丁")[1], "digits 2 following character missing")
        local d3_next = assert(find_word(doc, "己")[1], "digits 3 following character missing")
        print(string.format("[tcy_digits] 12=%dx%d 123(d2)=%dx%d 123(d3)=%dx%d AB=%dx%d",
            two.w, two.h, long.w, long.h,
            combined_three.w, combined_three.h, letter.w, letter.h))
        print(string.format("[tcy_digits] d2=(%d,%d)->丁(%d,%d) d3=(%d,%d)->己(%d,%d)",
            long.x, long.y, d2_next.x, d2_next.y,
            combined_three.x, combined_three.y, d3_next.x, d3_next.y))
        assert.is_true(two.h < long.h, "digits 2 must not combine a three-digit run")
        assert.is_true(d3_next.y - combined_three.y < d2_next.y - long.y,
            "digits 3 must advance less than an uncombined three-digit run")
        assert.is_true(letter.h > two.h, "digits must not combine non-digit text")
    end)

    teardown(function()
        if readerui then readerui:onClose() end
    end)
end)
