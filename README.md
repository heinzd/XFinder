# XFinder

XFinder is a native file manager for macOS with a custom SwiftUI interface.

## Current version: 0.4

- Folder navigation with Back, Forward, and Enclosing Folder actions
- Native macOS window toolbar with navigation, file actions, and search
- “Dock Second Window” toolbar button opens the current folder in an independent
  window and tiles both windows on the current screen. Moving either window keeps
  the pair together; resizing aligns their adjacent edges and heights. Clicking the
  button again focuses the existing partner. Closing either window or entering full
  screen releases the pair. Navigation, selection, search, and menu actions belong
  to the active window. Dragging between different XFinder windows copies files.
- Sidebar with standard, imported Finder, and clearly separated XFinder favorites
- Add selected folders to XFinder favorites from the context menu
- Locations for AirDrop, iCloud Drive, Trash, connected iPhones/media devices,
  external drives, and network volumes
- Internal and virtual system volumes are excluded from the sidebar
- Compact multi-column file list with Finder-style multiple selection
- Sortable Name, Date Modified, Size, Kind, and search-location columns
- Drag files from XFinder to Finder folders or other applications, and copy files
  from Finder into the current XFinder folder or a displayed subfolder
- Copy files between different XFinder windows. Drops within the same XFinder
  window and drops back into the source folder remain blocked, including when
  two windows show the same folder.
- Create a new folder from the current multi-selection and move the selected items
  into it from the context menu
- Native Quick Look preview for one or multiple selected files (`Space`)
- Double-click images for Quick Look and MP3 files for the shared native audio
  player. Selecting another image or MP3 updates the respective open viewer.
- The MP3 player uses a Quick Look-like layout with embedded cover artwork, title,
  artist, album, and native playback/seek/volume controls. Metadata loads without
  blocking playback; files without artwork show a music-note placeholder. Single
  files and playlist tracks use the same player, including automatic track advance
  for playlists.
- The playlist toolbar button opens a read-only table in a separate window, using
  the selected folder, or the current folder when no single folder is selected.
  MP3 files are collected breadth-first: songs from the root first, then songs
  from each immediate subfolder, then the next depth. Each folder stays together
  as an album, with natural filename order inside it.
- Click a playlist row to play it in the same audio player used for single MP3s.
  The playlist toolbar offers previous, play/stop, next, beginning, end, and persistent
  random/in-order playback. The list keeps its album order even in random mode.
  Playback automatically advances at the end of a track and stops after the last.
  Closing the playlist discards it and stops its playback.
- The audio player uses normal window ordering so other windows and applications
  can cover it. Automatic track changes do not raise the player. Stop keeps the
  selected playlist track; Play starts it again from the beginning.
- During playlist playback, the player docks beside the playlist with matching
  window height. Moving or resizing either window keeps the pair aligned; single
  MP3 playback detaches the player. Cover art and metadata update together after
  loading, without an intermediate placeholder or changes to the text-row heights.
- Drag sources explicitly provide file URLs; drop targets request copy operations.
  Unreadable drag data and same-folder copies produce an explanatory message.
- Standard macOS text size with reduced row spacing
- Open files with their default applications; recognized Unix scripts require
  confirmation, while ordinary media files open directly
- Create folders, rename items, and move items to Trash
- Create text, rich-text, Word, Excel, and PowerPoint documents from the context menu
- Create OpenDocument text, spreadsheet, and presentation files when LibreOffice
  or OpenOffice is installed
- Optionally show hidden files
- Recursive name search through all subfolders, including wildcard patterns such
  as `test.*`, `*.txt`, and `report-?.pdf`
- Search-result location column
- Standard and persistent custom favorites
- Open the current path in the original Finder
- Open the current folder in Terminal
- Complete macOS application icon
- Explicit regular-app activation so the icon is visible in the Dock when run from Xcode
- Dedicated Settings dialog (`⌘,`)
- English as the default language, with German available at runtime

## Requirements

- macOS 15 or later
- Xcode 26 or later

## Build and run

1. Clone the repository.
2. Open `XFinder.xcodeproj` in Xcode.
3. Configure your development team in Signing & Capabilities.
4. Select `My Mac` as the run destination.
5. Run with `⌘R`.

Xcode stores the selected development team in `project.pbxproj`. Developers who
maintain that file locally can mark it as `skip-worktree` after the initial setup.
Repository updates that require a project-file change are called out explicitly.

To update an existing clone:

```bash
cd ~/Developer/XFinder
git pull
```

## File-system access

XFinder intentionally does not use the App Sandbox so that it can work like a
file manager and access folders available to the current user. macOS may still
request permission for protected locations.

Importing custom favorites from the original Finder also reads the user's local
Shared File List and may therefore require Full Disk Access.

Connected iPhones and other local media devices are detected through Apple's
Image Capture interface. The device must be unlocked and trusted. Since iOS
devices are not mounted as normal file-system volumes, selecting one opens Image
Capture for the media Apple exposes publicly.

Use `XFinder > Configure Full Disk Access…` to grant permission once. The
`XFinder > Show XFinder App in Finder` command locates the application launched
from Xcode. Restart XFinder after changing Full Disk Access.

## Deutsch

XFinder ist ein nativer macOS-Dateimanager. Englisch ist die primäre Sprache;
Deutsch kann jederzeit in den Einstellungen ausgewählt werden.
