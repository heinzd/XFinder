# XFinder

XFinder is a native file manager for macOS with a custom SwiftUI interface.

## Current version: 0.4

- Folder navigation with Back, Forward, and Enclosing Folder actions
- Native macOS window toolbar with navigation, file actions, and search
- Sidebar with favorites, AirDrop, iCloud Drive, Trash, and mounted volumes
- Detection of local, USB, and mounted network drives
- Compact multi-column file list with Finder-style multiple selection
- Standard macOS text size with reduced row spacing
- Open files with their default applications
- Create folders, rename items, and move items to Trash
- Optionally show hidden files
- Recursive name search through all subfolders
- Search-result location column
- Standard and persistent custom favorites
- Open the current path in the original Finder
- Complete macOS application icon
- Dedicated Settings dialog (`⌘,`)
- English as the default language, with German available at runtime

## Requirements

- macOS 15 or later
- Xcode 26 or later

## Build and run

1. Clone the repository.
2. Open `XFinder.xcodeproj` in Xcode.
3. Select `My Mac` as the run destination.
4. Run with `⌘R`.

To update an existing clone:

```bash
cd ~/Developer/XFinder
git pull
```

## File-system access

XFinder intentionally does not use the App Sandbox so that it can work like a
file manager and access folders available to the current user. macOS may still
request permission for protected locations.

Use `XFinder > Configure Full Disk Access…` to grant permission once. The
`XFinder > Show XFinder App in Finder` command locates the application launched
from Xcode. Restart XFinder after changing Full Disk Access.

## Deutsch

XFinder ist ein nativer macOS-Dateimanager. Englisch ist die primäre Sprache;
Deutsch kann jederzeit in den Einstellungen ausgewählt werden.
