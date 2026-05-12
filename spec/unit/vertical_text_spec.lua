--[[--
Vertical text spec: coordinate conversion and selection in vertical-rl mode.

Tests:
  1. getWordFromPosition: word found, sbox positive, sbox covers tap
  2. getTextFromPositions: all sboxes positive width, span multiple columns
  3. Wide selection spanning page-splitter boundary: positive sboxes
  4. Horizontal-mode regression: unchanged behavior

Run via:
  ./kodev test front -f "Vertical text"

Requires: spec/unit/data/fixtures/vertical_text/simple_ja_noruby.epub
--]]

describe("Vertical text", function()
    local DocumentRegistry, ReaderUI, UIManager, Screen, Geom
    local epub_path = "spec/front/unit/data/fixtures/vertical_text/simple_ja_noruby.epub"

    setup(function()
        require("commonrequire")
        disable_plugins()
        require("document/canvascontext"):init(require("device"))
        DocumentRegistry = require("document/documentregistry")
        Geom = require("ui/geometry")
        ReaderUI = require("apps/reader/readerui")
        Screen = require("device").screen
        UIManager = require("ui/uimanager")
    end)

    local function apply_vertical_css(readerui)
        if readerui.styletweak then
            readerui.styletweak.book_style_tweak = "body { writing-mode: vertical-rl !important; }"
            readerui.styletweak.book_style_tweak_enabled = true
            readerui.styletweak:updateCssText(true)
        end
        fastforward_ui_events()
    end

    -- Scan right-to-left and return {x} positions that have content at given y.
    -- Returns at least 2 positions, or nil if content is too sparse.
    local function find_content_columns(doc, y, min_count)
        min_count = min_count or 2
        local w = Screen:getWidth()
        local step = math.max(10, math.floor(w / 24))
        local xs = {}
        for x = w - 10, 10, -step do
            local ok, word = pcall(function()
                return doc:getWordFromPosition({x=x, y=y})
            end)
            if ok and word and word.word and #word.word > 0 then
                table.insert(xs, x)
            end
        end
        if #xs < min_count then return nil end
        return xs
    end

    -- Find a single position with content. Returns (x, word, sbox) or nil.
    local function find_any_content(doc)
        local w, h = Screen:getWidth(), Screen:getHeight()
        -- Try multiple y positions across the page.
        for _, y_frac in ipairs({0.3, 0.5, 0.2, 0.7}) do
            local y = math.floor(h * y_frac)
            local xs = find_content_columns(doc, y, 1)
            if xs and #xs >= 1 then
                local x = xs[1]
                local ok, word = pcall(function()
                    return doc:getWordFromPosition({x=x, y=y})
                end)
                if ok and word and word.word and word.sbox then
                    return x, y, word, word.sbox
                end
            end
        end
        return nil
    end

    -----------------------------------------------------------------------
    -- 1. Coordinate conversion tests
    -----------------------------------------------------------------------

    describe("Coordinate conversion #coords", function()
        local readerui, doc

        setup(function()
            readerui = ReaderUI:new{
                dimen = Screen:getSize(),
                document = DocumentRegistry:openDocument(epub_path),
            }
        end)

        teardown(function()
            readerui:onClose()
        end)

        before_each(function()
            UIManager:show(readerui)
            apply_vertical_css(readerui)
            readerui.rolling:onGotoPage(1)
            fastforward_ui_events()
            doc = readerui.document
        end)

        after_each(function()
            UIManager:quit()
        end)

        it("should find a word somewhere on the vertical-rl page", function()
            -- Dynamic content detection: scan multiple positions.
            local x, y, word = find_any_content(doc)
            assert.truthy(word,
                "No word found anywhere on page in vertical-rl mode")
            assert.truthy(#word.word > 0, "Word has empty text")
        end)

        it("should return sbox with positive width and height", function()
            local x, y, word, sb = find_any_content(doc)
            assert.truthy(sb, "No word/sbox found on page")
            assert.truthy(sb.w > 0,
                string.format("sbox.w=%d not positive at (%d,%d)", sb.w, x, y))
            assert.truthy(sb.h > 0,
                string.format("sbox.h=%d not positive at (%d,%d)", sb.h, x, y))
        end)

        it("sbox should approximately cover the tap position (round-trip)", function()
            -- The core invariant: tap → word → sbox should contain ~the tap point.
            -- In vertical-rl, docToWindowPoint may be off by ~left_margin (≈9px).
            local tol = 60  -- generous tolerance for margin offsets
            local x, y, word, sb = find_any_content(doc)
            assert.truthy(sb, "No word/sbox found on page")
            assert.truthy(
                sb.x - tol <= x and x <= sb.x + sb.w + tol,
                string.format("tap_x=%d not near sbox x=[%d..%d] ±%d word=%q",
                    x, sb.x, sb.x+sb.w, tol, word.word))
            assert.truthy(
                sb.y - tol <= y and y <= sb.y + sb.h + tol,
                string.format("tap_y=%d not near sbox y=[%d..%d] ±%d word=%q",
                    y, sb.y, sb.y+sb.h, tol, word.word))
        end)

        it("should find different words in adjacent columns", function()
            local h = Screen:getHeight()
            local y = math.floor(h * 0.3)
            -- Find at least 2 content columns.
            local xs = find_content_columns(doc, y, 2)
            if not xs then
                pending("Not enough content columns to test adjacent-column independence")
                return
            end
            local right_x = xs[1]
            local left_x  = xs[2]   -- second rightmost content column
            local ok1, w1 = pcall(function() return doc:getWordFromPosition({x=right_x, y=y}) end)
            local ok2, w2 = pcall(function() return doc:getWordFromPosition({x=left_x,  y=y}) end)
            assert.truthy(ok1 and w1 and w1.word, "No word at right column")
            assert.truthy(ok2 and w2 and w2.word, "No word at left column")
            -- The two columns should contain different words.
            assert.falsy(w1.word == w2.word,
                string.format("Same word %q in columns at x=%d and x=%d — column coordinate may be wrong",
                    w1.word, right_x, left_x))
        end)
    end)

    -----------------------------------------------------------------------
    -- 2. Selection sbox tests
    -----------------------------------------------------------------------

    describe("Text selection #selection", function()
        local readerui, doc

        setup(function()
            readerui = ReaderUI:new{
                dimen = Screen:getSize(),
                document = DocumentRegistry:openDocument(epub_path),
            }
        end)

        teardown(function()
            readerui:onClose()
        end)

        before_each(function()
            UIManager:show(readerui)
            apply_vertical_css(readerui)
            readerui.rolling:onGotoPage(1)
            fastforward_ui_events()
            doc = readerui.document
        end)

        after_each(function()
            UIManager:quit()
        end)

        it("single-position selection returns positive-width sboxes", function()
            local x, y = find_any_content(doc)
            assert.truthy(x, "No content found for test")
            local ok, result = pcall(function()
                return doc:getTextFromPositions({x=x, y=y}, {x=x, y=y})
            end)
            assert.truthy(ok, "getTextFromPositions error")
            local sboxes = result and result.sboxes or {}
            assert.truthy(#sboxes > 0, "No sboxes for single-position selection")
            for i, sb in ipairs(sboxes) do
                assert.truthy(sb.w > 0,
                    string.format("sbox[%d].w=%d not positive", i, sb.w))
            end
        end)

        it("multi-column selection returns all positive-width sboxes", function()
            local h = Screen:getHeight()
            local y = math.floor(h * 0.3)
            local xs = find_content_columns(doc, y, 2)
            if not xs then
                pending("Not enough content columns")
                return
            end
            local right_x, left_x = xs[1], xs[math.min(3, #xs)]
            local ok, result = pcall(function()
                return doc:getTextFromPositions({x=right_x, y=y}, {x=left_x, y=y})
            end)
            assert.truthy(ok, "getTextFromPositions error")
            local sboxes = result and result.sboxes or {}
            assert.truthy(#sboxes > 0, "No sboxes for multi-column selection")
            local neg = 0
            for _, sb in ipairs(sboxes) do
                if sb.w <= 0 then neg = neg + 1 end
            end
            assert.equals(0, neg,
                string.format("%d/%d sboxes have non-positive width", neg, #sboxes))
        end)

        it("wide selection sboxes should span multiple columns", function()
            local h = Screen:getHeight()
            local y = math.floor(h * 0.3)
            local xs = find_content_columns(doc, y, 2)
            if not xs then
                pending("Not enough content columns")
                return
            end
            -- Use at least 2 columns apart.
            local right_x = xs[1]
            local left_x  = xs[math.min(#xs, math.max(2, math.floor(#xs * 0.6)))]
            local ok, result = pcall(function()
                return doc:getTextFromPositions({x=right_x, y=y}, {x=left_x, y=y})
            end)
            assert.truthy(ok and result, "No selection result")
            local sboxes = result.sboxes or {}
            if #sboxes == 0 then return end  -- no content → skip
            local min_x, max_x = math.huge, -math.huge
            for _, sb in ipairs(sboxes) do
                if sb.x < min_x then min_x = sb.x end
                if sb.x + sb.w > max_x then max_x = sb.x + sb.w end
            end
            assert.truthy(max_x - min_x >= 30,
                string.format("sboxes span only %dpx — expected ≥30px for 2+ columns", max_x - min_x))
        end)

        it("wide selection sboxes should all have positive width (cross page-splitter boundary)", function()
            -- Scan the widest possible content range.
            local h = Screen:getHeight()
            local y = math.floor(h * 0.4)
            local xs = find_content_columns(doc, y, 2)
            if not xs then
                pending("Not enough content columns")
                return
            end
            local right_x = xs[1]
            local left_x  = xs[#xs]   -- widest available range
            local ok, result = pcall(function()
                return doc:getTextFromPositions({x=right_x, y=y}, {x=left_x, y=y})
            end)
            assert.truthy(ok, "getTextFromPositions error: " .. tostring(result))
            local sboxes = result and result.sboxes or {}
            assert.truthy(#sboxes > 0,
                string.format("No sboxes for wide selection x=[%d..%d]", left_x, right_x))
            -- Core check: all sboxes must have positive width.
            local neg = 0
            for _, sb in ipairs(sboxes) do
                if sb.w <= 0 then neg = neg + 1 end
            end
            assert.equals(0, neg,
                string.format("%d/%d sboxes have non-positive width in wide selection", neg, #sboxes))
        end)

        it("vertical selection within one column covers significant height", function()
            local w = Screen:getWidth()
            local h = Screen:getHeight()
            local top_y = math.floor(h * 0.1)
            local bot_y = math.floor(h * 0.85)
            -- Find a column that has content at both top and bottom.
            local xs_top = find_content_columns(doc, top_y, 1)
            if not xs_top then
                pending("No content at top of page for vertical selection test")
                return
            end
            local x = xs_top[1]
            local ok, result = pcall(function()
                return doc:getTextFromPositions({x=x, y=top_y}, {x=x, y=bot_y})
            end)
            assert.truthy(ok, "getTextFromPositions error")
            local sboxes = result and result.sboxes or {}
            assert.truthy(#sboxes > 0, "No sboxes for vertical column selection")
            for i, sb in ipairs(sboxes) do
                assert.truthy(sb.w > 0,
                    string.format("vertical sbox[%d].w=%d not positive", i, sb.w))
            end
            local total_h = 0
            for _, sb in ipairs(sboxes) do total_h = total_h + sb.h end
            assert.truthy(total_h >= h * 0.25,
                string.format("Vertical selection covers only %dpx (need ≥%dpx = 25%% of %dpx)",
                    total_h, math.floor(h * 0.25), h))
        end)
    end)

    -----------------------------------------------------------------------
    -- 3. Horizontal mode regression
    -----------------------------------------------------------------------

    describe("Horizontal mode regression #regression", function()
        local readerui, doc

        setup(function()
            readerui = ReaderUI:new{
                dimen = Screen:getSize(),
                document = DocumentRegistry:openDocument(epub_path),
            }
        end)

        teardown(function()
            readerui:onClose()
        end)

        before_each(function()
            UIManager:show(readerui)
            -- No vertical CSS — keep default horizontal-tb.
            readerui.rolling:onGotoPage(1)
            fastforward_ui_events()
            doc = readerui.document
        end)

        after_each(function()
            UIManager:quit()
        end)

        it("should find a word in horizontal mode", function()
            local w, h = Screen:getWidth(), Screen:getHeight()
            local ok, word = pcall(function()
                return doc:getWordFromPosition({x=math.floor(w/2), y=math.floor(h/2)})
            end)
            assert.truthy(ok, "getWordFromPosition error in horizontal mode")
            assert.truthy(word and word.word and #word.word > 0,
                "No word at center of page in horizontal mode")
        end)

        it("horizontal selection should return positive-width sboxes", function()
            local w, h = Screen:getWidth(), Screen:getHeight()
            local y = math.floor(h / 2)
            local ok, result = pcall(function()
                return doc:getTextFromPositions(
                    {x=math.floor(w*0.2), y=y},
                    {x=math.floor(w*0.8), y=y})
            end)
            assert.truthy(ok, "getTextFromPositions error in horizontal mode")
            local sboxes = result and result.sboxes or {}
            assert.truthy(#sboxes > 0, "No sboxes in horizontal mode")
            for i, sb in ipairs(sboxes) do
                assert.truthy(sb.w > 0,
                    string.format("Horizontal sbox[%d].w=%d not positive", i, sb.w))
            end
        end)
    end)

    -----------------------------------------------------------------------
    -- 4. Ruby annotation sbox tests
    -----------------------------------------------------------------------

    describe("Ruby annotation sboxes #ruby", function()
        local readerui, doc
        local epub_path_ruby = "spec/front/unit/data/fixtures/vertical_text/simple_ja_ruby.epub"

        setup(function()
            readerui = ReaderUI:new{
                dimen = Screen:getSize(),
                document = DocumentRegistry:openDocument(epub_path_ruby),
            }
        end)

        teardown(function()
            readerui:onClose()
        end)

        before_each(function()
            UIManager:show(readerui)
            apply_vertical_css(readerui)
            readerui.rolling:onGotoPage(1)
            fastforward_ui_events()
            doc = readerui.document
        end)

        after_each(function()
            UIManager:quit()
        end)

        it("getWordFromPosition never returns off-screen sbox.y near ruby", function()
            local h = Screen:getHeight()
            local tol = 50  -- matches docToWindowPoint 50px page-edge tolerance
            local checked = 0
            for _, yf in ipairs({0.2, 0.3, 0.5, 0.7}) do
                local y = math.floor(h * yf)
                local xs = find_content_columns(doc, y, 1)
                if xs then
                    for _, x in ipairs(xs) do
                        local ok, word = pcall(function()
                            return doc:getWordFromPosition({x=x, y=y})
                        end)
                        if ok and word and word.sbox then
                            local sb = word.sbox
                            -- Uncomment for Phase 2 root-cause diagnostics:
                            -- print(string.format("ruby tap (%d,%d) -> sbox x=%d y=%d w=%d h=%d word=%q",
                            --     x, y, sb.x, sb.y, sb.w, sb.h, word.word or ""))
                            assert.truthy(sb.y >= -tol,
                                string.format("sbox.y=%d < %d (tap %d,%d word=%q)",
                                    sb.y, -tol, x, y, word.word or ""))
                            assert.truthy(sb.y + sb.h <= h + tol,
                                string.format("sbox.y+h=%d > %d (tap %d,%d word=%q)",
                                    sb.y + sb.h, h + tol, x, y, word.word or ""))
                            checked = checked + 1
                        end
                    end
                end
            end
            assert.truthy(checked > 0, "Ruby fixture: no sboxes encountered to validate")
        end)

        it("getTextFromPositions ruby range returns only on-screen sboxes", function()
            local h = Screen:getHeight()
            local tol = 50
            local y = math.floor(h * 0.3)
            local xs = find_content_columns(doc, y, 2)
            if not xs then
                pending("Not enough ruby content columns to test")
                return
            end
            local right_x = xs[1]
            local left_x  = xs[#xs]
            local ok, result = pcall(function()
                return doc:getTextFromPositions({x=right_x, y=y}, {x=left_x, y=y})
            end)
            assert.truthy(ok, "getTextFromPositions errored on ruby range")
            local sboxes = (result and result.sboxes) or {}
            for i, sb in ipairs(sboxes) do
                assert.truthy(sb.y >= -tol,
                    string.format("sbox[%d].y=%d off-screen top (screen_h=%d)", i, sb.y, h))
                assert.truthy(sb.y + sb.h <= h + tol,
                    string.format("sbox[%d].y+h=%d > %d off-screen bottom", i, sb.y + sb.h, h + tol))
            end
        end)
    end)
end)
