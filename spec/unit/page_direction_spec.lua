describe("Page direction metadata detector", function()
    local PageDirection

    setup(function()
        require("commonrequire")
        PageDirection = require("util/page_direction")
    end)

    describe("ComicInfo.xml", function()
        it("finds and parses ComicInfo.xml inside a CBZ archive", function()
            local Archiver = require("ffi/archiver")
            local cbz_path = os.tmpname() .. ".cbz"
            finally(function() os.remove(cbz_path) end)

            local writer = Archiver.Writer:new()
            assert.is_true(writer:open(cbz_path, "zip"))
            assert.is_true(writer:addFileFromMemory("metadata/ComicInfo.xml", [[
                <ComicInfo><Manga>YesAndRightToLeft</Manga></ComicInfo>
            ]]))
            assert.is_true(writer:addFileFromMemory("001.jpg", "not-an-image"))
            writer:close()

            assert.equals("rtl", PageDirection.getDirection({ file = cbz_path }))
        end)

        it("detects the standard right-to-left Manga enum", function()
            assert.equals("rtl", PageDirection.parseComicInfo([[
                <?xml version="1.0"?>
                <ComicInfo xmlns="http://example.invalid/comicinfo">
                    <Manga>YesAndRightToLeft</Manga>
                </ComicInfo>
            ]]))
        end)

        it("accepts namespaced elements, attributes, comments and a BOM", function()
            assert.equals("rtl", PageDirection.parseComicInfo("\239\187\191" .. [[
                <ci:ComicInfo xmlns:ci="urn:comicinfo">
                    <!-- <ci:Manga>No</ci:Manga> -->
                    <ci:Manga source="tagger"> YesAndRightToLeft </ci:Manga>
                </ci:ComicInfo>
            ]]))
        end)

        it("does not infer direction from the other standard Manga values", function()
            for _, value in ipairs({ "Unknown", "No", "Yes" }) do
                assert.is_nil(PageDirection.parseComicInfo(
                    "<ComicInfo><Manga>" .. value .. "</Manga></ComicInfo>"))
            end
        end)

        it("accepts legacy and descriptive ReadingDirection values", function()
            for _, value in ipairs({ "RTL", "rtl", "RightToLeft", "right-to-left", "right_to_left" }) do
                assert.equals("rtl", PageDirection.parseComicInfo(
                    "<ComicInfo><ReadingDirection>" .. value
                    .. "</ReadingDirection></ComicInfo>"))
            end
            for _, value in ipairs({ "LTR", "LeftToRight", "left-to-right" }) do
                assert.equals("ltr", PageDirection.parseComicInfo(
                    "<ComicInfo><ReadingDirection>" .. value
                    .. "</ReadingDirection></ComicInfo>"))
            end
        end)

        it("prefers the standard RTL Manga value over a conflicting extension", function()
            assert.equals("rtl", PageDirection.parseComicInfo([[
                <ComicInfo>
                    <Manga>YesAndRightToLeft</Manga>
                    <ReadingDirection>LTR</ReadingDirection>
                </ComicInfo>
            ]]))
        end)

        it("returns unknown for missing, malformed and unsupported values", function()
            assert.is_nil(PageDirection.parseComicInfo(nil))
            assert.is_nil(PageDirection.parseComicInfo("<ComicInfo/>"))
            assert.is_nil(PageDirection.parseComicInfo(
                "<ComicInfo><MangaFoo>YesAndRightToLeft</MangaFoo></ComicInfo>"))
            assert.is_nil(PageDirection.parseComicInfo(
                "<ComicInfo><ReadingDirection>sideways</ReadingDirection></ComicInfo>"))
        end)
    end)
end)
