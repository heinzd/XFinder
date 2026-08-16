# XFinder

XFinder is a native file manager for macOS with a custom SwiftUI interface.

## Current version: 0.4

- Folder navigation with Back, Forward, and Enclosing Folder actions
- Native macOS window toolbar with navigation, file actions, and search
- Sidebar with standard, imported Finder, and clearly separated XFinder favorites
- Add selected folders to XFinder favorites from the context menu
- Locations for AirDrop, iCloud Drive, Trash, external drives, and network volumes
- Internal and virtual system volumes are excluded from the sidebar
- Compact multi-column file list with Finder-style multiple selection
- Standard macOS text size with reduced row spacing
- Open files with their default applications
- Create folders, rename items, and move items to Trash
- Create text, rich-text, Word, Excel, and PowerPoint documents from the context menu
- Optionally show hidden files
- Recursive name search through all subfolders
- Search-result location column
- Standard and persistent custom favorites
- Open the current path in the original Finder
- Open the current folder in Terminal
- Complete macOS application icon
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

Use `XFinder > Configure Full Disk Access…` to grant permission once. The
`XFinder > Show XFinder App in Finder` command locates the application launched
from Xcode. Restart XFinder after changing Full Disk Access.

## Deutsch

XFinder ist ein nativer macOS-Dateimanager. Englisch ist die primäre Sprache;
Deutsch kann jederzeit in den Einstellungen ausgewählt werden.
