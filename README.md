# koreader-tategumi

**KOReader fork with Japanese vertical text (縦書き / tategumi) support.**

This is a personal fork of [KOReader](https://github.com/koreader/koreader) that adds
`writing-mode: vertical-rl` rendering for Japanese novels in EPUB format.
It is regularly synced with upstream KOReader (master / nightly).

> **Third-party plugins:** This fork tracks upstream master, so plugin compatibility
> is equivalent to upstream nightly — not the stable release. If a plugin does not work,
> please verify it also fails with vanilla upstream KOReader nightly before filing an issue here.

![Vertical text rendering of 三四郎 (Natsume Soseki)](doc/screenshots/tategumi.png)

## Downloads

| Platform | File |
|----------|------|
| Kindle (legacy) | `koreader-kindle-vYYYY.MM.zip` |
| Kindle (HF) | `koreader-kindlehf-vYYYY.MM.zip` |
| Kobo | `koreader-kobo-vYYYY.MM.zip` |
| PocketBook | `koreader-pocketbook-vYYYY.MM.zip` |
| Cervantes | `koreader-cervantes-vYYYY.MM.zip` |
| reMarkable | `koreader-remarkable-vYYYY.MM.zip` |
| Android (ARM64, most modern phones) | `koreader-android-arm64-vYYYY.MM.apk` |
| Android (ARM 32-bit) | `koreader-android-vYYYY.MM.apk` |

[Latest release](https://github.com/m-tky/koreader-tategumi/releases/latest)

Installation steps are the same as upstream KOReader:
[Android](https://github.com/koreader/koreader/wiki/Installation-on-Android-devices) •
[Kindle](https://github.com/koreader/koreader/wiki/Installation-on-Kindle-devices) •
[Kobo](https://github.com/koreader/koreader/wiki/Installation-on-Kobo-devices)

In-app OTA update is supported. Go to **Menu → Update → Check for update**.

## Switching from vanilla KOReader

If you already have vanilla KOReader installed, you can switch to this fork without
reinstalling from scratch:

1. Copy `frontend/ui/otamanager.lua` from this repository into
   `<koreader-dir>/frontend/ui/otamanager.lua` on your device.
2. Restart KOReader and go to **Menu → Update → Check for update**.
3. KOReader will download and apply this fork's build automatically.

## Using vertical text

EPUBs that already contain `writing-mode: vertical-rl` in their CSS (e.g. most commercial
Japanese novels) will render in vertical mode automatically.

For EPUBs that do not include this CSS, add the following via
**Typeset (Aa icon) → Style tweaks → Book-specific tweak** (long-press to edit):

```css
body { writing-mode: vertical-rl !important; }
```

## RTL page order (漫画・右開き)

Japanese manga EPUBs and CBZ/CBR files with right-to-left page order are detected
automatically when you open them for the first time:

- **EPUB**: reads `page-progression-direction="rtl"` from the OPF spine
- **CBZ/CBR**: reads `<ReadingDirection>RTL</ReadingDirection>` from `ComicInfo.xml`

When RTL is detected a notification appears, the page-turn direction is reversed,
and the progress bar fills from right (page 1) to left (last page).

You can always override the detected direction via
**Menu → Taps & gestures → Page turns → Switch page-turn direction**.
The override is saved per-book and will not be overwritten on subsequent opens.

## Known limitations

- **Mixed horizontal/vertical layouts are not supported.** A single document renders
  entirely in one writing mode. EPUBs that mix horizontal and vertical sections within
  the same file may not display correctly.

- **EPUBs with stray whitespace between ruby groups** may show a small gap between ruby
  groups and the following character. This is a property of the EPUB source, not a
  rendering bug.

- **Some EPUBs show a double paragraph indent (two characters instead of one).**
  This occurs when the EPUB uses a U+3000 ideographic space character (`　`) for
  indentation while CREngine also applies its default `text-indent: 1.2em`. To fix
  this for a specific book, go to the top menu → Aa → Style tweaks → Paragraph
  first-line indentation → select **0** (no indent).

## Support

If you find this vertical text fork useful, you can support its development:

[![Ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/mtkydev)

For the KOReader project itself, please see [koreader/koreader](https://github.com/koreader/koreader).

## Acknowledgements

This project is a fork of [KOReader](https://github.com/koreader/koreader),
an open-source e-book reader developed by volunteers around the world.
The vertical text (tategumi) implementation is built on top of their work.

## Contributors

[![Last commit](https://img.shields.io/github/last-commit/m-tky/koreader-tategumi?color=orange)](https://github.com/m-tky/koreader-tategumi/commits/master)
[![License](https://img.shields.io/github/license/koreader/koreader)](https://github.com/koreader/koreader/blob/master/COPYING)

---

[![KOReader](https://raw.githubusercontent.com/koreader/koreader.github.io/master/koreader-logo.png)](https://koreader.rocks)

#### KOReader is a document viewer primarily aimed at e-ink readers.

[![AGPL Licence][badge-license]](COPYING)
[![Latest release][badge-release]][link-gh-releases]
[![Gitter][badge-gitter]][link-gitter]
[![Mobileread][badge-mobileread]][link-forum]
[![Build Status][badge-circleci]][link-circleci]
[![Coverage Status][badge-coverage]][link-coverage]
[![Weblate Status][badge-weblate]][link-weblate]

[Download](https://github.com/koreader/koreader/releases) •
[User guide](http://koreader.rocks/user_guide/) •
[Wiki](https://github.com/koreader/koreader/wiki) •
[Developer docs](http://koreader.rocks/doc/)

## Main features

* **portable**: runs on embedded devices (Cervantes, Kindle, Kobo, PocketBook, reMarkable), Android and Linux computers. Developers can run a KOReader emulator in Linux and MacOS.

* **multi-format documents**: supports fixed page formats (PDF, DjVu, CBT, CBZ) and reflowable e-book formats (EPUB, FB2, Mobi, DOC, RTF, HTML, CHM, TXT). Scanned PDF/DjVu documents can also be reflowed with the built-in K2pdfopt library. [ZIP files][link-wiki-zip] are also supported for some formats.

* **full-featured reading**: multi-lingual user interface with a highly customizable reader view and many typesetting options. You can set arbitrary page margins, override line spacing and choose external fonts and styles. It has multi-lingual hyphenation dictionaries bundled into the application.

* **integrated** with *calibre* (search metadata, receive ebooks wirelessly, browse library via OPDS), *Wallabag*, *Wikipedia*, *Google Translate* and other content providers.

* **optimized for e-ink devices**: custom UI without animation, with paginated menus, adjustable text contrast, and easy zoom to fit content or page in paged media.

* **extensible**: via plugins

* **fast**: on some older devices, it has been measured to have less than half the page-turn delay as the built in reading software.

* **and much more**: look up words with StarDict dictionaries / Wikipedia, add your own online OPDS catalogs and RSS feeds, over-the-air software updates, an FTP client, an SSH server, …

Please check the [user guide](http://koreader.rocks/user_guide/) and the [wiki][link-wiki] to discover more features and to help us document them.

## Screenshots

<a href="https://github.com/koreader/koreader-artwork/raw/master/koreader-menu.png"><img src="https://github.com/koreader/koreader-artwork/raw/master/koreader-menu-thumbnail.png" alt="" width="200px"></a>
<a href="https://github.com/koreader/koreader-artwork/raw/master/koreader-footnotes.png"><img src="https://github.com/koreader/koreader-artwork/raw/master/koreader-footnotes-thumbnail.png" alt="" width="200px"></a>
<a href="https://github.com/koreader/koreader-artwork/raw/master/koreader-dictionary.png"><img src="https://github.com/koreader/koreader-artwork/raw/master/koreader-dictionary-thumbnail.png" alt="" width="200px"></a>

## Installation

Please follow the model specific steps for your device:

[Android](https://github.com/koreader/koreader/wiki/Installation-on-Android-devices) •
[Cervantes](https://github.com/koreader/koreader/wiki/Installation-on-BQ-devices) •
[Kindle](https://github.com/koreader/koreader/wiki/Installation-on-Kindle-devices) •
[Kobo](https://github.com/koreader/koreader/wiki/Installation-on-Kobo-devices) •
[Pocketbook](https://github.com/koreader/koreader/wiki/Installation-on-PocketBook-devices) •
[reMarkable](https://github.com/koreader/koreader/wiki/Installation-on-Remarkable)


## Development

[Setting up a build environment](doc/Building.md) •
[Collaborating with Git](doc/Collaborating_with_Git.md) •
[Building targets](doc/Building_targets.md) •
[Porting](doc/Porting.md) •
[Developer docs](http://koreader.rocks/doc/)

[link-forum]:http://www.mobileread.com/forums/forumdisplay.php?f=276
[link-wiki]:https://github.com/koreader/koreader/wiki
