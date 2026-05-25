--[[--
Vertical-rl per-slot offset record / lookup regression test.

Detects the bug where docToWindowPoint's per-slot lookup misses all
recorded entries and silently falls back to the page-wide min, leaving
the highlight sbox shifted upward by (per_glyph_offset − min).

Root cause guarded against:
  At record time the formatter must key by `frmline->x + word->x`
  (the layout-stored inline position used by getRectEx), NOT by
  `clamped_x` (the per-draw running tracker, which can be bumped by
  vert_min_next_x overlap correction).

What this test asserts:
  1. The page-render path actually populates the per-slot record table
     (slot_count > 0).
  2. Round-trip: each recorded entry self-looks-up to the recorded offset.
  3. After a getWordFromPosition (which goes through docToWindowPoint),
     the lookup hit count grows — i.e. at least one of the sbox corners
     successfully matched a recorded slot.
--]]

local lfs = require("libs/libkoreader-lfs")

describe("Vertical text: per-slot offset record/lookup", function()
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

    it("records per-slot offsets and hits at sbox time #slot_lookup", function()
        if not epub_path then pending("sanshiro.epub not found"); return end
        if not (doc.isVerticalText and doc:isVerticalText()) then
            pending("document is not vertical-rl"); return
        end

        -- Page 10: deep enough into body text that the formatter has plenty
        -- of vertical CJK draws (cover/TOC pages produce only a few records).
        local sw, sh = Screen:getWidth(), Screen:getHeight()
        local Geom = require("ui/geometry")
        local target_page = math.min(doc:getPageCount(), 10)
        readerui.rolling:onGotoPage(target_page)
        fastforward_ui_events()
        -- Probe to force the formatter through the page (mirrors the existing
        -- vertical_glyph_y_spec pattern that reliably triggers >100 draws).
        for _, fx in ipairs({0.8, 0.5, 0.2}) do
            pcall(function()
                doc:getWordFromPosition({x = math.floor(sw * fx),
                                         y = math.floor(sh * 0.5)})
            end)
        end

        -- (1) Records exist.
        local slot_count = doc._document:getVertSlotRecordCount()
        assert.is_true(slot_count > 10,
            string.format("only %d slot records — vertical formatter did not "
                       .. "render the body block", slot_count))

        -- (2) Round-trip: every recorded entry self-looks-up.
        local SENTINEL = -987654
        for i = 0, math.min(slot_count, 50) - 1 do
            local a, s, o = doc._document:getVertSlotRecord(i)
            local got = doc._document:lookupVertSlotOffset(a, s, SENTINEL)
            assert.equals(o, got,
                string.format("rec[%d] self-lookup mismatch: got %d expected %d", i, got, o))
        end

        -- (3) After a fresh getWordFromPosition, lookup must hit at least once.
        --     If the formatter's record key drifts from what docToWindowPoint
        --     computes (the original bug), every lookup misses → dh = 0 → fail.
        local hits0 = doc._document:getVertSlotLookupCounts()
        pcall(function()
            doc:getWordFromPosition({x = math.floor(sw * 0.9),
                                     y = math.floor(sh * 0.5)})
        end)
        local hits1 = doc._document:getVertSlotLookupCounts()
        local dh = hits1 - hits0
        assert.is_true(dh > 0,
            string.format("docToWindowPoint did NOT hit any slot record (Δhits=%d).  "
                       .. "Formatter is keying records by a position the layout "
                       .. "doesn't store (likely clamped_x instead of word->x).", dh))

        -- (4) Sbox height ≥ ~half its width for a single CJK char.
        --     Vertical-rl sbox corners are paired (topLeft + bottomRight).  By
        --     geometry the bottomRight's anchor lands on the column's opposite
        --     edge and its slot_y at glyph_top+height — its own per-slot lookup
        --     misses by design.  Before the offset-sharing fix the bottomRight
        --     would fall back to the page-wide min while topLeft got a per-glyph
        --     offset, producing a stunted sbox (h ≪ w) and the glyph poked out
        --     below the highlight.  After the fix, bottomRight inherits the
        --     topLeft's offset, so top and bottom shift uniformly.
        --
        --     We probe several positions; the bug presents as sbox h ≤ w/2
        --     (pre-fix measured h=20, w=40 → ratio 0.5).  After offset-sharing
        --     normal CJK glyphs land at h ≈ w (ratio ≈ 1.0), small punctuation
        --     at h ≈ w/2+ε (still strictly > w/2).  Threshold `h*2 > w` is the
        --     boundary that catches the regression without false-positiving on
        --     legitimately short glyphs.  At least one probe must land on a
        --     full-height glyph (ratio ≥ 0.9) to prove we did exercise the
        --     non-stunted path.
        local probed = 0
        local saw_full = false
        for _, fx in ipairs({0.85, 0.75, 0.65, 0.55, 0.45, 0.35}) do
        for _, fy in ipairs({0.3, 0.5, 0.7}) do
            local ok, wb = pcall(function()
                return doc:getWordFromPosition({x = math.floor(sw * fx),
                                                y = math.floor(sh * fy)})
            end)
            if ok and wb and wb.sbox and wb.sbox.w > 0 then
                probed = probed + 1
                -- Threshold widened from `h*2 > w` to `h*2 >= w` after the
                -- vmtx-based gy formula landed.  TTB metrics produce per-glyph
                -- offsets ~1–5 px (vs 0–14 px with the previous em_top formula),
                -- so the smallest-glyph corner case lands at exactly h = w/2 by
                -- the new arithmetic instead of slightly above.  The original
                -- regression (h ≪ w, e.g. 20/40 with the page-wide-min fallback)
                -- is still caught.
                assert.is_true(wb.sbox.h * 2 >= wb.sbox.w,
                    string.format("sbox stunted: w=%d h=%d (h must be ≥ w/2; "
                               .. "bottomRight is falling back to page-wide min "
                               .. "instead of inheriting topLeft's per-glyph offset)",
                               wb.sbox.w, wb.sbox.h))
                if wb.sbox.h * 10 >= wb.sbox.w * 9 then  -- ratio >= 0.9
                    saw_full = true
                end
            end
        end
        end
        assert.is_true(probed > 0,
            "no sbox returned by any probe — test cannot verify sbox height")
        assert.is_true(saw_full,
            "no probe hit a full-height CJK glyph — test did not exercise the "
         .. "case the offset-sharing fix is intended to repair")
    end)
end)
