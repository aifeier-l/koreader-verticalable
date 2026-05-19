--[[--
Ruby annotation Y-alignment regression test for 三四郎.epub.

BUG: In vertical-rl mode, `CCRTable::renderCells()` checks
`table_style->writing_mode` to decide whether to use setX(0) for ruby
table cells.  Because crengine stores the CSS *specified* value (not
the *computed* value), inherited writing-mode returns css_wm_inherit
(= 0), not css_wm_vertical_rl.  The vertical branch is never taken, so
cells use `setX(cell->col->x)` which displaces annotation characters
in the inline (screen-Y) direction by one column-width (≈13–26 px).
Visually the annotation bleeds into the character above the ruby group.

FIX: resolve the effective writing-mode by walking up the DOM when the
element's stored value is css_wm_inherit.

DETECTION: `lvrend_reset_ruby_diag()` / `lvrend_get_ruby_diag()` (via
`doc._document:resetRubyDiag()` / `getRubyDiagStats()`) track how many
ruby table cells were processed with the wrong (non-vertical) path.

 • vert_ok   – cells correctly handled via the vertical path
 • vert_miss – cells handled via the horizontal path despite being in a
               vertical document (the bug); each represents one
               misaligned annotation strip
 • col_x_max – the largest col->x applied (= displacement in px)

Run via:
  ./kodev test front -f "Ruby annotation Y alignment"

Requires: 三四郎.epub in the KOReader root directory.
--]]

local lfs = require("libs/libkoreader-lfs")

describe("Vertical text: ruby annotation Y alignment", function()
    local DocumentRegistry, ReaderUI, UIManager, Screen
    local epub_candidates = {
        "spec/front/unit/data/fixtures/vertical_text/sanshiro.epub",
        "三四郎.epub",
    }
    local epub_path
    for _, p in ipairs(epub_candidates) do
        if lfs.attributes(p) then epub_path = p; break end
    end
    local epub_found = epub_path ~= nil

    setup(function()
        require("commonrequire")
        disable_plugins()
        require("document/canvascontext"):init(require("device"))
        DocumentRegistry = require("document/documentregistry")
        ReaderUI = require("apps/reader/readerui")
        Screen = require("device").screen
        UIManager = require("ui/uimanager")
    end)

    local function apply_vertical_css(readerui)
        if readerui.styletweak then
            readerui.styletweak.book_style_tweak =
                "body { writing-mode: vertical-rl !important; }"
            readerui.styletweak.book_style_tweak_enabled = true
            readerui.styletweak:updateCssText(true)
        end
        fastforward_ui_events()
    end

    describe("rendering with vertical-rl #ruby_annot_y", function()
        local readerui, doc

        setup(function()
            if not epub_found then return end
            readerui = ReaderUI:new{
                dimen = Screen:getSize(),
                document = DocumentRegistry:openDocument(epub_path),
            }
        end)

        teardown(function()
            if readerui then readerui:onClose() end
        end)

        before_each(function()
            if not readerui then return end
            UIManager:show(readerui)
            -- Reset diagnostic counters BEFORE triggering the render.
            doc = readerui.document
            doc._document:resetRubyDiag()
            -- Apply vertical-rl CSS: this triggers a full document re-render,
            -- which populates the diagnostic counters for ALL ruby tables.
            apply_vertical_css(readerui)
            doc = readerui.document
        end)

        after_each(function()
            UIManager:quit()
        end)

        it("ruby tables are detected as vertical (no Y displacement bug) #ruby_annot_y", function()
            if not epub_found then
                pending("sanshiro.epub not found in fixtures — skipping")
                return
            end

            -- Navigate a few pages to ensure rendering has been triggered.
            -- (The full document is laid out during the CSS-tweak re-render
            -- above, so page navigation is not strictly required, but it also
            -- exercises the drawing path which may trigger partial re-renders.)
            local pages_to_visit = math.min(5, doc:getPageCount())
            for page = 1, pages_to_visit do
                readerui.rolling:onGotoPage(page)
                fastforward_ui_events()
            end

            local vert_ok, vert_miss, col_x_max = doc._document:getRubyDiagStats()

            -- Always print so we can see the values in test output.
            print(string.format(
                "\n[ruby_annot_y] vert_ok=%d  vert_miss=%d  col_x_max=%d",
                vert_ok, vert_miss, col_x_max))

            -- With the bug (table_style->writing_mode == css_wm_inherit):
            --   vert_ok  == 0   (vertical path never taken)
            --   vert_miss > 0   (cells rendered via horizontal path)
            --   col_x_max > 0   (annotation cells displaced by col_x_max px)
            --
            -- After the fix (effective writing-mode via DOM walk):
            --   vert_ok  > 0
            --   vert_miss == 0
            --   col_x_max == 0

            assert.are.equal(0, vert_miss, string.format(
                "Ruby table cells processed via HORIZONTAL path in vertical document: "..
                "%d miss(es), col_x_max=%d px (annotation displaced by that many px). "..
                "vert_ok=%d. "..
                "Fix: resolve effective writing-mode (DOM walk) in renderCells().",
                vert_miss, col_x_max, vert_ok))

            -- Sanity: at least some ruby tables were found and processed correctly.
            assert.truthy(vert_ok > 0,
                "No ruby tables detected at all (vert_ok=0). "..
                "Verify that 三四郎.epub has ruby annotations and vertical CSS was applied.")
        end)

        it("resetRubyDiag / getRubyDiagStats API is available #ruby_annot_y", function()
            if not epub_found then
                pending("sanshiro.epub not found")
                return
            end

            doc._document:resetRubyDiag()
            local ok, miss, col_x = doc._document:getRubyDiagStats()
            assert.are.equal(0, ok)
            assert.are.equal(0, miss)
            assert.are.equal(0, col_x)
        end)
    end)
end)
