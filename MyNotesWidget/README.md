# MyNotesWidget — Home Screen Widget (roadmap item 12)

Small widget: your most recent page (title + first two lines).
Medium widget: your most recent pages, up to 4 (title + first line each).
Tapping a page opens it in the app. The widget follows the system
light/dark appearance automatically.

## How it works

- The app mirrors a lightweight summary of the pages (id, title,
  first two lines of text, block count, creation date — no images,
  no full content) into the App Group shared container
  (`group.morrowchristian.MyNotes`, key `widgetPages`) whenever
  pages change. The local "pages" key in the app stays the source
  of truth; if the App Group is not configured yet, the mirror is
  a no-op and the app works exactly as before.
- The widget reads only that shared summary — it never touches the
  app's data or iCloud directly.
- The widget timeline refreshes every 15 minutes, and the app asks
  WidgetKit to reload the timeline whenever the summary changes,
  so edits show up promptly.
- "Most recent" means newest by creation date — pages have no
  updated-at date yet, so an edited old page does not jump to the
  top. (A future `updatedAt` on Page would fix that.)

## Xcode setup (do this once)

1. **Add the Widget Extension target.** In Xcode: File > New >
   Target... > Widget Extension. Name it `MyNotesWidget` and
   **uncheck "Include Configuration App Intent"** (this widget has
   no settings — it uses a static configuration). Xcode creates a
   `MyNotesWidget` folder with template files.
2. **Replace the template files.** Delete the files Xcode just
   created inside the new `MyNotesWidget` folder, then add the
   files from this folder (`MyNotesWidget.swift`,
   `WidgetData.swift`, `Provider.swift`, `WidgetViews.swift`) to
   the `MyNotesWidget` target only (File > Add Files to "MyNotes…",
   tick the `MyNotesWidget` target, untick the app target). Do NOT
   add them to the app target — the app target already builds
   cleanly without them, and the widget's `@main` entry point must
   not be in the app target.
3. **Enable the App Group on both targets.** Select the project >
   the `MyNotes` app target > Signing & Capabilities > + Capability
   > App Groups, then add `group.morrowchristian.MyNotes`. Repeat
   for the `MyNotesWidget` target — the same group id on both.
   (Both targets must use the same Apple ID / team, or the group
   will not be shared.)
4. **Register the deep-link URL scheme on the app target.**
   Select the `MyNotes` app target > Info tab > URL Types > +.
   Set Identifier to `morrowchristian.MyNotes` and URL Schemes to
   `mynotes`. This is what lets a widget tap open a specific page
   (`mynotes://page/<id>`). Until this is done, tapping a widget
   just opens the app.
5. **Build the app** (Cmd+R). It must build cleanly — the only
   app changes are the shared-container mirror in DataModel.swift
   and the `.onOpenURL` handler in MainView.swift.
6. **Run the widget scheme** (choose the `MyNotesWidget` scheme,
   pick a simulator, Cmd+R) — or build the app, then long-press
   the Home Screen > + > MyNotes to add the widget. Create or edit
   a page in the app and the widget should update within a moment
   (the app reloads the timeline on change) or within 15 minutes
   at most.

## If the widget shows the placeholder

- "Welcome to MyNotes / Create your first page…" means the widget
  has not read a summary yet: check the App Group id matches
  exactly on both targets, run the app once (it writes the summary
  when pages save), and make sure the widget target's files are the
  ones in this folder.
- Tapping a widget that only opens the app (no page) means the URL
  scheme in step 4 is missing.
