--[[--
Vertical-rl bleed detection test.

Renders up to 100 pages of a ruby-annotated vertical-rl EPUB and asserts
that no character overlaps the one above it ("上にめり込む").

Detection is done in C++ Draw() via ltext_vert_bleed_count / ltext_vert_bleed_max_px
(lvtextfm_layout_h.cpp), exposed to Lua as:
  doc._document:resetVertBleedCounters()
  doc._document:getVertBleedStats() → count, max_px

Run via:
  ./kodev test front -f "Vertical bleed"

Requires: 三四郎.epub in the KOReader root directory.
To produce detailed per-event output, also grep for [VERT-BLEED] in stdout:
  ./kodev test front -f "Vertical bleed" 2>&1 | grep VERT-BLEED
--]]

local lfs = require("libs/libkoreader-lfs")

describe("Vertical bleed", function()
    local DocumentRegistry, ReaderUI, UIManager, Screen
    -- Try both root-relative and absolute paths
    local epub_candidates = {
        "三四郎.epub",
        "/home/user/Code/koreader/三四郎.epub",
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

    describe("rendering pages #vertical_bleed", function()
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
            apply_vertical_css(readerui)
            doc = readerui.document
        end)

        after_each(function()
            UIManager:quit()
        end)

        it("has no upward character bleed across first 100 pages", function()
            if not epub_found then
                pending("三四郎.epub not found in KOReader root — skipping")
                return
            end

            doc._document:resetVertBleedCounters()

            local total_pages = doc:getPageCount()
            local pages_to_render = math.min(100, total_pages)

            local w, h = Screen:getWidth(), Screen:getHeight()
            -- Sample x positions spread across columns (RTL, so right → left)
            local sample_xs = {
                math.floor(w * 0.85),
                math.floor(w * 0.55),
                math.floor(w * 0.25),
            }
            local sample_y = math.floor(h * 0.5)

            for page = 1, pages_to_render do
                readerui.rolling:onGotoPage(page)
                fastforward_ui_events()

                -- Tap a few positions to ensure the page is rendered.
                -- getWordFromPosition triggers Draw() internally when the
                -- page needs (re)drawing, which runs the bleed detector.
                for _, x in ipairs(sample_xs) do
                    pcall(function()
                        doc:getWordFromPosition({ x = x, y = sample_y })
                    end)
                end
            end

            local count, max_px = doc._document:getVertBleedStats()

            if count > 0 then
                -- Print detail for debugging even before the assertion fails
                print(string.format(
                    "\n[VERT-BLEED] %d overlap event(s) over %d pages, "
                    .. "max bleed = %d px  (grep [VERT-BLEED] in stdout for per-event detail)",
                    count, pages_to_render, max_px))
            end

            assert.equals(0, count, string.format(
                "%d vertical bleed event(s) detected over %d pages "
                .. "(worst case: %d px overlap). "
                .. "Run with: ./kodev test front -f 'Vertical bleed' 2>&1 | grep VERT-BLEED",
                count, pages_to_render, max_px))
        end)

        it("has resetVertBleedCounters / getVertBleedStats API", function()
            if not epub_found then
                pending("三四郎.epub not found")
                return
            end

            doc._document:resetVertBleedCounters()
            local count, max_px = doc._document:getVertBleedStats()
            assert.equals(0, count)
            assert.equals(0, max_px)
        end)
    end)
end)
