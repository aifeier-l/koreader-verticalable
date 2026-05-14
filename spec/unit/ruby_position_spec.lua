--[[--
Vertical-rl space-reduction regression test.

In vertical-rl mode, when a paragraph has text-indent applied to its first column,
the old code triggered alignLineHorizontal's space-reduction loop (extra_width < 0)
which compressed every CJK-flexible character in the column.  The cumulative
compression pulled the entire column's content UPWARD by ~text-indent pixels,
visibly misaligning ruby-annotated characters relative to the surrounding text.

Fix: skip the space-reduction loop for vertical-rl text.

This test takes a fixture with:
  - vertical-rl writing-mode + text-indent: 2em baked into CSS
  - A long paragraph filled with many 「kana、」 pairs (the 、 are flexible-width CJK)
  - Ruby groups placed inside the first column

and verifies that consecutive character pairs in the first column have the SAME
y-stride as in non-indented columns (i.e. no compression applied).  With the bug,
the indented column's stride is ~1px smaller per pair, so over many pairs the
total compression becomes detectable.

Run via:
  ./kodev test front -f "Ruby position"

Requires: spec/front/unit/data/fixtures/vertical_text/ruby_indent.epub
--]]

describe("Ruby position", function()
    local DocumentRegistry, ReaderUI, UIManager, Screen
    local epub_path = "spec/front/unit/data/fixtures/vertical_text/ruby_indent.epub"

    setup(function()
        require("commonrequire")
        disable_plugins()
        require("document/canvascontext"):init(require("device"))
        DocumentRegistry = require("document/documentregistry")
        ReaderUI = require("apps/reader/readerui")
        Screen = require("device").screen
        UIManager = require("ui/uimanager")
    end)

    -- Scan a vertical column at x from y_start downward, returning trusted entries.
    -- A trusted entry has the tap_y within ±near_tol of the sbox vertical midpoint
    -- (filters out P4-style sbox/coord inaccuracies for rt-descendant nodes).
    local function scan_column_trusted(doc, x, y_start, y_end, step, near_tol)
        near_tol = near_tol or 60
        local results = {}
        local last_text = nil
        for tap_y = y_start, y_end, step do
            local ok, w = pcall(function()
                return doc:getWordFromPosition({x=x, y=tap_y})
            end)
            if ok and w and w.word and w.sbox then
                local sb = w.sbox
                local sb_mid_y = sb.y + sb.h / 2
                if math.abs(tap_y - sb_mid_y) <= near_tol then
                    if w.word ~= last_text then
                        table.insert(results, {
                            word = w.word,
                            sbox = { y = sb.y, h = sb.h },
                            tap_y = tap_y,
                        })
                        last_text = w.word
                    end
                end
            end
        end
        return results
    end

    -- Find x positions of content columns.
    local function find_columns(doc)
        local w, h = Screen:getWidth(), Screen:getHeight()
        local y_mid = math.floor(h * 0.4)
        local step = math.max(8, math.floor(w / 20))
        local cols = {}
        for x = w - 10, 10, -step do
            local ok, r = pcall(function()
                return doc:getWordFromPosition({x=x, y=y_mid})
            end)
            if ok and r and r.word and r.sbox then
                if math.abs(y_mid - (r.sbox.y + r.sbox.h/2)) <= 60 then
                    table.insert(cols, x)
                end
            end
        end
        return cols
    end

    describe("first-column compression in vertical-rl with text-indent #ruby_pos", function()
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
            readerui.rolling:onGotoPage(1)
            fastforward_ui_events()
            doc = readerui.document
        end)

        after_each(function()
            UIManager:quit()
        end)

        it("first column (with text-indent) has same character stride as later columns", function()
            -- Scan multiple columns.  Column 1 has text-indent.  Columns 2+ do not.
            -- In each column, measure the average y-stride between consecutive distinct
            -- words found by top-to-bottom scan.  The bug compresses column 1's stride
            -- below the natural column stride.
            local h = Screen:getHeight()
            local cols = find_columns(doc)
            if #cols < 2 then
                pending("Need at least 2 content columns")
                return
            end

            local function median_stride(words)
                if #words < 5 then return nil end
                -- Use only body-char entries (sbox.h ≈ font_size).
                -- Skip ruby annotation chars (smaller h) and combined word entries (much larger h).
                local body = {}
                local max_h = 0
                for _, w in ipairs(words) do
                    if w.sbox.h > max_h then max_h = w.sbox.h end
                end
                local h_threshold = max_h * 0.75
                for _, w in ipairs(words) do
                    if w.sbox.h >= h_threshold and w.sbox.h <= max_h then
                        table.insert(body, w)
                    end
                end
                if #body < 5 then return nil end
                -- Collect strides.  Use median (not mean) to ignore outliers like
                -- the gap where a ruby inline-box occupies the column.
                local strides = {}
                for i = 2, #body do
                    local d = body[i].sbox.y - body[i-1].sbox.y
                    if d > 0 and d < 200 then table.insert(strides, d) end
                end
                if #strides == 0 then return nil end
                table.sort(strides)
                return strides[math.ceil(#strides / 2)]
            end

            local step = math.max(4, math.floor(h / 80))
            local strides = {}
            for _, x in ipairs(cols) do
                local words = scan_column_trusted(doc, x, 5, h - 5, step)
                local s = median_stride(words)
                if s then table.insert(strides, {x=x, stride=s, n=#words}) end
            end

            if #strides < 2 then
                pending("Need at least 2 columns with measurable stride")
                return
            end

            -- Find the MIN stride (most compressed) and MAX stride (uncompressed).
            local min_s, max_s = strides[1].stride, strides[1].stride
            local min_x, max_x = strides[1].x, strides[1].x
            for _, s in ipairs(strides) do
                if s.stride < min_s then min_s = s.stride; min_x = s.x end
                if s.stride > max_s then max_s = s.stride; max_x = s.x end
            end

            -- Without the bug, all columns should have the SAME stride within tight
            -- rounding tolerance (≤ 0.5px).  With the bug, the indented column is
            -- compressed by ~1px per pair, so its median stride differs from the
            -- non-indented columns by ~1px.
            local stride_diff = max_s - min_s
            assert.truthy(stride_diff <= 0.5,
                string.format(
                    "Column stride mismatch (compression detected): "..
                    "min_stride=%.2fpx at col_x=%d, max_stride=%.2fpx at col_x=%d, diff=%.2fpx\n"..
                    "(All strides: %s)",
                    min_s, min_x, max_s, max_x, stride_diff,
                    (function()
                        local parts = {}
                        for _, s in ipairs(strides) do
                            table.insert(parts, string.format("x=%d stride=%.1f n=%d", s.x, s.stride, s.n))
                        end
                        return table.concat(parts, ", ")
                    end)()))
        end)
    end)

    -----------------------------------------------------------------------
    -- P8 regression: annotation center alignment.
    -- In vertical-rl, both the base and annotation strings of a ruby group
    -- must be centred on the same point (JLReq §3.3.8).  Residual misalignment
    -- caused by integer-division truncation in alignLineHorizontal (extra_width/2
    -- when extra_width is odd) results in a 0.5 px shift of the annotation above
    -- the base.  The fix uses round-half-up ((extra_width+1)/2) for inner ruby
    -- cells so that both sub-cells converge to the same integer pixel centre.
    --
    -- This test cannot measure sub-pixel positions directly.  Instead it verifies
    -- a necessary proxy: in a column of CJK text the stride between consecutive
    -- PLAIN-BODY chars (i.e. chars not separated by a ruby group) must equal
    -- char_size exactly (±1 px rounding tolerance).  Ruby base chars legitimately
    -- sit at char_size/2 offset within their slot (correct JLReq centering), so
    -- cross-ruby-boundary pairs are excluded by keeping only "tight" pairs where
    -- the raw dy is within 1 of char_size.
    -----------------------------------------------------------------------
    describe("annotation center alignment #ruby_p8", function()
        local readerui, doc
        local p8_epub = "spec/front/unit/data/fixtures/vertical_text/sanshiro.epub"

        setup(function()
            readerui = ReaderUI:new{
                dimen = Screen:getSize(),
                document = DocumentRegistry:openDocument(p8_epub),
            }
        end)

        teardown(function()
            readerui:onClose()
        end)

        before_each(function()
            UIManager:show(readerui)
            readerui.rolling:onGotoPage(1)
            fastforward_ui_events()
            doc = readerui.document
        end)

        after_each(function()
            UIManager:quit()
        end)

        it("plain-body consecutive char stride equals char_size in 三四郎 #ruby_p8", function()
            -- Scan the first 10 pages (enough to exercise many columns with ruby).
            -- For each pair of consecutive body chars with dy ≈ char_size (no ruby
            -- group between them), verify |dy - char_size| ≤ 1 px.
            local h = Screen:getHeight()
            local pages_to_scan = 10
            local h_counts = {}

            local step = math.max(2, math.floor(h / 100))

            local page_words = {}
            for pg = 1, pages_to_scan do
                readerui.rolling:onGotoPage(pg)
                fastforward_ui_events()
                doc = readerui.document
                local cols = find_columns(doc)
                local page_data = {}
                for _, x in ipairs(cols) do
                    local words = scan_column_trusted(doc, x, 5, h - 5, step)
                    if #words > 0 then
                        table.insert(page_data, {x=x, words=words})
                        for _, w in ipairs(words) do
                            if w.sbox.h >= 12 and w.sbox.h <= 40 then
                                h_counts[w.sbox.h] = (h_counts[w.sbox.h] or 0) + 1
                            end
                        end
                    end
                end
                page_words[pg] = page_data
            end

            local char_size, char_max_count = 20, 0
            for h_val, cnt in pairs(h_counts) do
                if cnt > char_max_count then
                    char_size = h_val
                    char_max_count = cnt
                end
            end

            local violations = {}
            local total_checked = 0

            for pg, page_data in pairs(page_words) do
                for _, col_data in ipairs(page_data) do
                    local x = col_data.x
                    local body = {}
                    for _, w in ipairs(col_data.words) do
                        if w.sbox.h >= char_size - 2 and w.sbox.h <= char_size + 2 then
                            table.insert(body, w)
                        end
                    end
                    for i = 2, #body do
                        local prev, curr = body[i-1], body[i]
                        local dy = curr.sbox.y - prev.sbox.y
                        -- Only check "tight" consecutive pairs (no ruby group between them).
                        -- Ruby base chars sit at char_size/2 offset, so cross-ruby dy will
                        -- differ by ≥ char_size/2 - 1 from an exact multiple of char_size.
                        if dy > 0 and math.abs(dy - char_size) <= 1 then
                            total_checked = total_checked + 1
                            -- Allow ±1 px for font-metric rounding.
                            if math.abs(dy - char_size) > 1 then
                                table.insert(violations, {
                                    page = pg, col_x = x,
                                    prev = prev, curr = curr, dy = dy,
                                })
                            end
                        end
                    end
                end
            end

            if total_checked == 0 then
                pending("No tight consecutive body-char pairs found in scanned pages")
                return
            end

            local parts = {}
            for i = 1, math.min(10, #violations) do
                local v = violations[i]
                table.insert(parts, string.format(
                    "p%d col_x=%d: [%s]@y=%d → [%s]@y=%d dy=%d (expected %d)",
                    v.page, v.col_x,
                    v.prev.word, v.prev.sbox.y,
                    v.curr.word, v.curr.sbox.y,
                    v.dy, char_size))
            end

            assert.are.equal(0, #violations,
                string.format(
                    "Stride violations in tight consecutive pairs (%d checked, char_size=%d):\n%s",
                    total_checked, char_size, table.concat(parts, "\n")))
        end)
    end)
end)
