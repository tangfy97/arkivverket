# UI Architecture Plan

Goal: move Arkiv from one manually-laid-out AppKit controller toward native macOS structure without disrupting the browsing workflow.

## Migration Order

1. Stabilize the current shell
   - Keep `MainWindowController` as the coordinator while extracting leaf views.
   - Keep manual layout until the extracted panes have clear APIs.
   - Do not migrate toolbar and split view in the same patch.

2. Extract pane controllers
   - `HomeStateView` is the first extracted surface and should stay independent.
   - Extract `SidebarViewController` next: own `NSOutlineView`, library header, and row configuration.
   - Extract `ThumbnailGridViewController`: own `NSCollectionView`, density layout, selection, and search-result empty state.
   - Extract `ProfileViewController`: own `WKWebView` and markdown loading.
   - Extract `ImageViewerController`: own viewer overlay, preview image, profile toggle, and slideshow controls.

3. Adopt `NSSplitViewController`
   - Build a three-pane split structure: sidebar, content, profile.
   - Use a collapsible sidebar item and a collapsible profile item.
   - Persist divider positions with autosave names.
   - Preserve current defaults: sidebar around 220-270 pt, profile around 300-360 pt.

4. Adopt `NSToolbar`
   - Move open, search, density, slideshow, and profile controls into a unified toolbar.
   - Keep `window.representedURL` and folder title behavior.
   - Use toolbar item validation so disabled states are clear before a library is open.
   - Remove the custom `topBar` after toolbar parity is confirmed.

5. Reduce `MainWindowController`
   - Leave it responsible for application state, routing, and coordination only.
   - Remove data-source/delegate conformances once child controllers own their views.
   - Keep scan/cache logic outside UI controllers.

## Acceptance Criteria

- Opening, dropping, and reopening recent libraries still works.
- Sidebar selection does not rescan unchanged folders.
- Search, density, profile toggle, viewer entry, and slideshow keep their shortcuts and menu entries.
- Split panes are draggable, collapsible, and restored across launches.
- Toolbar controls expose accessibility labels and disabled states.
- `swift build` and `scripts/build_app.sh` pass after each step.

## First Patch Scope

The first phase-4 patch should extract `HomeStateView` and keep the rest of the controller stable. This gives the app a cleaner first-run surface while creating the first reusable UI surface for the later split-view migration.
