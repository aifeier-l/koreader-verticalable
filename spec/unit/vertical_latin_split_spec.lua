--[[--
Vertical text: Latin word column-split detection.

In vertical-rl, Latin words are rendered as rotated blocks.
processParagraphVertical must not split them mid-word across columns.

This spec uses a minimal EPUB (latin_split_test.epub) whose first page
contains "Nachbild" and "Geschehen" (German words) embedded in Japanese
text. These words only appear as complete units in the source; finding a
known fragment ("Nach", "bild", "Gesche", "hen") without the full word is
unambiguous evidence of a mid-word column split.

The test varies font_size (14–28) AND top/bottom margins (20–100px) to
exercise the many configurations that can trigger the overflow.

Run via:
  ./kodev test front -f "Latin word split"
--]]

describe("Vertical text: Latin word no-split #latin_split", function()
    local DocumentRegistry, ReaderUI, Screen, UIManager
    local epub_path = "spec/front/unit/data/fixtures/vertical_text/latin_split_test.epub"

    setup(function()
        require("commonrequire")
        disable_plugins()
        require("document/canvascontext"):init(require("device"))
        DocumentRegistry = require("document/documentregistry")
        ReaderUI         = require("apps/reader/readerui")
        Screen           = require("device").screen
        UIManager        = require("ui/uimanager")
    end)

    -- -----------------------------------------------------------------------
    -- Target words in the test EPUB plus all substrings (length ≥ 3) that
    -- are ONLY valid as fragments (they do not appear independently in text).
    -- If fragment_set[w] = target then finding `w` without finding `target`
    -- means the word was split at a boundary that produced fragment `w`.
    -- -----------------------------------------------------------------------
    local target_words = {"Nachbild", "Geschehen"}
    -- Fragment → full word mapping.  A fragment is any contiguous sub-string
    -- of a target word that would indicate a split at that exact position.
    -- We keep only fragments with 3–6 chars to match what crengine would return
    -- for the partial word in one column.
    local function build_fragment_map()
        local fmap = {}   -- fragment → full-word
        for _, w in ipairs(target_words) do
            for s = 1, #w - 3 do
                for len = 3, math.min(6, #w - s) do
                    local frag = w:sub(s, s + len - 1)
                    -- Only store if this fragment looks like a word-internal piece
                    -- (not the full word itself).
                    if frag ~= w then
                        fmap[frag] = w
                    end
                end
            end
        end
        return fmap
    end
    local fragment_map = build_fragment_map()

    -- Scan the current page; return a set (table keyed by word string) of all
    -- unique word strings found.
    local function scan_word_set(doc)
        local w = Screen:getWidth()
        local h = Screen:getHeight()
        local step_x = math.max(8, math.floor(w / 40))
        local step_y = math.max(5, math.floor(h / 70))
        local seen_pos, word_set = {}, {}
        for x = w - 4, 4, -step_x do
            for y = 4, h - 4, step_y do
                local ok, word = pcall(function()
                    return doc:getWordFromPosition({x=x, y=y})
                end)
                if ok and word and word.word and word.sbox then
                    local key = string.format("%d_%d", word.sbox.x, word.sbox.y)
                    if not seen_pos[key] then
                        seen_pos[key] = true
                        word_set[word.word] = true
                    end
                end
            end
        end
        return word_set
    end

    -- -----------------------------------------------------------------------

    it("no Latin word splits across varied font sizes and margins #latin_split", function()
        local f = io.open(epub_path, "r")
        if not f then pending("latin_split_test.epub not found"); return end
        f:close()

        local readerui = ReaderUI:new{
            dimen = Screen:getSize(),
            document = DocumentRegistry:openDocument(epub_path),
        }
        UIManager:show(readerui)
        local doc = readerui.document

        -- Apply vertical CSS once.
        if readerui.styletweak then
            readerui.styletweak.book_style_tweak =
                "body { writing-mode: vertical-rl !important; }"
            readerui.styletweak.book_style_tweak_enabled = true
            readerui.styletweak:updateCssText(true)
        end
        readerui.rolling:onGotoPage(1)
        fastforward_ui_events()

        local all_splits = {}
        local configs_tested = 0

        local font_sizes  = {14, 16, 18, 20, 22, 24, 26, 28}
        local margin_sets = {
            {top=20,  bottom=20},
            {top=50,  bottom=50},
            {top=80,  bottom=80},
            {top=100, bottom=100},
            {top=40,  bottom=80},
            {top=80,  bottom=40},
        }

        for _, fs in ipairs(font_sizes) do
            for _, m in ipairs(margin_sets) do
                doc:setFontSize(fs)
                doc:setPageMargins(20, m.top, 20, m.bottom)
                readerui.rolling:onGotoPage(1)
                fastforward_ui_events()

                local word_set = scan_word_set(doc)
                configs_tested = configs_tested + 1

                -- For each fragment: if it appears without its full word, it's a split.
                for frag, full_word in pairs(fragment_map) do
                    if word_set[frag] and not word_set[full_word] then
                        local msg = string.format(
                            "fs=%d t=%d b=%d  fragment '%s' found without '%s'",
                            fs, m.top, m.bottom, frag, full_word)
                        table.insert(all_splits, msg)
                        print("[SPLIT] " .. msg)
                    end
                end
            end
        end

        -- Deduplicate (same fragment can be reported for each scan position).
        local seen_msgs = {}
        local unique_splits = {}
        for _, msg in ipairs(all_splits) do
            if not seen_msgs[msg] then
                seen_msgs[msg] = true
                table.insert(unique_splits, msg)
            end
        end

        print(string.format("[latin_split] configs_tested=%d  splits=%d",
            configs_tested, #unique_splits))

        readerui:onClose()
        UIManager:quit()

        assert.equals(0, #unique_splits,
            #unique_splits .. " Latin word split(s) detected:\n  "
            .. table.concat(unique_splits, "\n  "))
    end)
end)
