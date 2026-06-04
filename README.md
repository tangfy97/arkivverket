# Lumina Archive

Lumina Archive is a fast native macOS viewer for results generated under `documents/arkiv`.
It keeps the Phoenix Slides idea of quick local image browsing, then adds a rendered
`profile.md` pane for each model folder.

## Layout

- `PhoenixSlidesLegacy/` preserves the original Phoenix Slides source.
- `LuminaArchive/` contains the new Swift native macOS application.
- `scripts/build_app.sh` builds a standalone app bundle into `dist/`.

## Expected Folder Shape

Open either a root archive folder containing model directories, or one model folder directly:

```text
documents/arkiv/
  Sofia Jaspers/
    profile.md
    image-001.jpg
    image-002.jpg
```

The scanner treats any folder with `profile.md` or image files as a model archive.

## Current Controls

- Open a root folder with **Open Folder** or pass it as a launch argument.
- Use the left folder browser to move between model folders.
- Use Left/Right or Space to move through images.
- Press Return to enter fullscreen image viewing.
- Press Escape to leave fullscreen or stop a slideshow.
- Press Home/End to jump to the first/last image.
- Toggle the Profile pane to show or hide the rendered `profile.md`.

For smoke testing the image viewer directly:

```bash
open -n "dist/Lumina Archive.app" --args --viewer /path/to/documents/arkiv
open -n "dist/Lumina Archive.app" --args --viewer --viewer-profile /path/to/documents/arkiv
```

## Build

```bash
scripts/build_app.sh
open "dist/Lumina Archive.app"
```

You can also pass a folder path while developing:

```bash
swift run --package-path LuminaArchive LuminaArchive /path/to/documents/arkiv
```
