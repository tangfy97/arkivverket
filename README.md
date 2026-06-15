# Arkiv

Arkiv is a native macOS image archive browser for local model folders. It pairs a fast thumbnail grid with a rendered `profile.md` pane, folder navigation, selection workflows, and CorpusVault export actions.

## Repository Layout

- `Arkiv/` contains the Swift package for the macOS app.
- `Arkiv/Resources/` contains the app bundle metadata and icon.
- `branding/` contains source brand/icon assets.
- `docs/` contains implementation notes and migration plans.
- `scripts/build_app.sh` builds `dist/Arkiv.app`.

Generated build output lives under `Arkiv/.build/` and `dist/`; both are ignored.

## Library Shape

Open either a root archive folder containing model directories, or one model folder directly:

```text
documents/arkiv/
  Sofia Jaspers/
    profile.md
    image-001.jpg
    image-002.jpg
```

The scanner treats any folder with `profile.md` or image files as an archive folder.

## Controls

- Open a folder with **Open Archive...**, drag a folder onto the window, or pass a folder as a launch argument.
- Use the sidebar to move between archive folders.
- Click/tap a thumbnail to select it.
- Cmd-click thumbnails to build a multi-selection.
- Drag from a thumbnail to select a range.
- Use **Send to Corpus** to add the selection to an existing CorpusVault profile or create a new profile.
- Use Left/Right or Space to move through images.
- Press Return to enter Viewer mode.
- Press Escape to leave Viewer mode or stop a slideshow.
- Press Home/End to jump to the first/last image.

## Build

```bash
scripts/build_app.sh
open "dist/Arkiv.app"
```

For development, run the Swift package directly:

```bash
swift run --package-path Arkiv Arkiv /path/to/documents/arkiv
```

Viewer mode can be smoke-tested from the app bundle:

```bash
open -n "dist/Arkiv.app" --args --viewer /path/to/documents/arkiv
open -n "dist/Arkiv.app" --args --viewer --viewer-profile /path/to/documents/arkiv
```
