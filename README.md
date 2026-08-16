# XFinder

XFinder is a native file manager for macOS with a custom SwiftUI interface.

## Current version: 0.4

- Folder navigation with Back, Forward, and Enclosing Folder actions
- Native macOS window toolbar with navigation, file actions, and search
- Sidebar with standard and clearly separated custom favorites
- Locations for AirDrop, iCloud Drive, Trash, USB drives, and network volumes
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
2. Copy `Config/Local.xcconfig.example` to `Config/Local.xcconfig`.
3. Replace `YOUR_TEAM_ID` in the local file with your Apple Developer Team ID.
4. Open `XFinder.xcodeproj` in Xcode.
5. Select `My Mac` as the run destination.
6. Run with `⌘R`.

`Config/Local.xcconfig` is ignored by Git. Personal signing-team changes therefore
stay on the development Mac and are never committed to the repository. Keep the
shared `project.pbxproj` under version control because it defines the targets,
source files, and common build settings.

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
