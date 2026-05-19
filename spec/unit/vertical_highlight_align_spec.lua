--[[--
Vertical-rl highlight box alignment test.

In vertical-rl, the highlight box drawn by readerhighlight.lua must have its
column-center (sbox.x + sbox.w/2) at the same screen-X position as the
rendered glyph column center.

ROOT CAUSE OF MISALIGNMENT:
  commit b50f94590 added `sbox.x + margins.right` to compensate for an old
  inconsistency where drawPageTo's clip.right did NOT subtract the right margin
  while docToWindowPoint DID.  Both now subtract the margin (and the centering
  offset), so the correction is stale and shifts every highlight one right-margin
  width (≈ 15 px) to the right.

DETECTION:
  1. Get word W at tap position via getWordFromPosition → raw sbox (Geom).
  2. Simulate a Hold gesture (readerui.highlight:onHold) — this triggers the
     readerhighlight Lua code that (if the bug is present) adds margins.right.
  3. Read the displayed sbox from view.highlight.temp.
  4. Assert: displayed sbox x-center == raw sbox x-center (no extra shift).

FIX:
  Remove both `sbox.x + margins.right` shifts from readerhighlight.lua
  (onHold and onHoldPan paths).

Run via:
  ./kodev test front -f "Vertical text"
--]]

local lfs = require("libs/libkoreader-lfs")

describe("Vertical text: highlight box column alignment", function()
    local epub_path
    for _, p in ipairs({
        "spec/front/unit/data/fixtures/vertical_text/sanshiro.epub",
    }) do
        if lfs.attributes(p) then epub_path = p; break end
    end

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
        if not epub_path then return end
        readerui = ReaderUI:new{
            dimen = Screen:getSize(),
            document = DocumentRegistry:openDocument(epub_path),
        }
        UIManager:show(readerui)
        fastforward_ui_events()
        doc = readerui.document
    end)

    after_each(function()
        if readerui then readerui:onClose() end
        UIManager:quit()
    end)

    it("displayed highlight x-center matches getWordFromPosition sbox #highlight_align", function()
        if not epub_path then pending("sanshiro.epub not found"); return end
        if not (doc.isVerticalText and doc:isVerticalText()) then
            pending("document is not vertical-rl")
            return
        end

        local sw, sh = Screen:getWidth(), Screen:getHeight()
        readerui.rolling:onGotoPage(3)
        fastforward_ui_events()

        -- Find a word by scanning horizontally.
        -- credocument:getWordFromPosition returns {sbox=Geom, word=str, ...}
        local Geom = require("ui/geometry")
        local tap_x, tap_y, raw_sbox
        local mid_y = math.floor(sh * 0.5)
        for try_x = sw - 20, 30, -10 do
            local w = doc:getWordFromPosition(Geom:new{x = try_x, y = mid_y})
            if w and w.sbox and w.sbox.w > 0 and w.word and w.word ~= "" then
                tap_x = try_x
                tap_y = mid_y
                raw_sbox = w.sbox  -- Geom {x, y, w, h} in screen coords
                break
            end
        end
        if not raw_sbox then pending("no word found on page 3"); return end

        local raw_cx = raw_sbox.x + math.floor(raw_sbox.w / 2)

        -- Trigger readerhighlight.onHold (same pattern as readerhighlight_spec.lua).
        -- This populates view.highlight.temp with the displayed (possibly shifted) sboxes.
        if readerui.view and readerui.view.highlight then
            readerui.view.highlight.temp = {}
        end
        local pos0 = Geom:new{x = tap_x, y = tap_y}
        readerui.highlight:onHold(nil, {pos = pos0})
        fastforward_ui_events()

        -- Find displayed sboxes across all page entries
        local displayed_sboxes
        if readerui.view and readerui.view.highlight and readerui.view.highlight.temp then
            for _, sbs in pairs(readerui.view.highlight.temp) do
                if sbs and #sbs > 0 then
                    displayed_sboxes = sbs
                    break
                end
            end
        end
        if not displayed_sboxes then
            pending("onHold did not populate highlight.temp — no text found at tap position")
            return
        end

        local dsb = displayed_sboxes[1]
        local displayed_cx = dsb.x + math.floor(dsb.w / 2)
        local shift = displayed_cx - raw_cx

        print(string.format(
            "[highlight_align] raw_cx=%d  displayed_cx=%d  shift=%d  margins.right=%d",
            raw_cx, displayed_cx, shift,
            doc:getPageMargins() and doc:getPageMargins().right or 0))

        -- THE KEY ASSERTION: displayed highlight x-center must equal the raw sbox center.
        -- If readerhighlight.lua is applying the stale `+ margins.right` correction,
        -- displayed_cx = raw_cx + margins.right ≠ raw_cx and the test fails.
        assert.are.equal(raw_cx, displayed_cx,
            string.format(
                "Highlight shifted %+d px from glyph position (raw_cx=%d displayed_cx=%d). "
                .. "readerhighlight.lua is adding margins.right to sbox.x. "
                .. "Fix: remove the `sbox.x + dx` corrections from onHold and onHoldPan.",
                shift, raw_cx, displayed_cx))
    end)
end)
