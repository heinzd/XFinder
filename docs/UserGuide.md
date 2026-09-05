# XFinder – User Guide

This guide describes XFinder 0.4. Help follows the language selected in XFinder Settings, including when the help window is already open. Open it offline through Help > XFinder Help or the question-mark toolbar button. The contents appear on the left; the search field searches both headings and chapter text.

## Getting started and navigation

XFinder displays favorites and locations on the left and the current folder's files on the right. Double-click a folder to open it. The path bar shows the current location; click a folder component to navigate up the hierarchy.

The toolbar arrows go back, forward, and to the enclosing folder. Reload refreshes the view. The Finder and Terminal buttons open the current folder in the respective application.

Open Settings using the gear button or ⌘,. You can switch between English and German; the choice is saved. View > Show hidden files also displays files that are normally hidden.

## Selection and table sorting

Click an item to select it. Command-click adds or removes individual items. Shift-click selects a contiguous range. The status bar shows the number of selected items.

Click a column heading to sort by Name, Date Modified, Size, or Kind. Click again to reverse the direction. Search results can also be sorted by Location. Dates use leading zeros, for example 06.08.2026, 09:05.

Open the context menu with a right-click or Control-click. Selection actions apply to the items selected for that menu.

## Working with files and folders

New Folder creates a folder in the current directory. Rename… changes the name of a single selected item. Move to Trash moves the selected items to the macOS Trash.

To group several items, select the files and folders, open the context menu, and choose New Folder with Selection. XFinder creates a folder, moves the selection into it, and opens the rename dialog for that folder. This moves the items rather than copying them. Missing items are checked first; duplicate and nested selection paths are handled so they are not moved twice.

New File in the context menu offers text, rich text, and Office documents for Word, Excel, and PowerPoint. An additional LibreOffice/OpenOffice menu provides ODT, ODS, and ODP when at least one of these applications is installed. Otherwise, that submenu is hidden.

## Drag and drop and copy rules

Drag a file from the table to a Finder folder or to another application, such as Preview. The receiving application decides how to handle it. Dragging files from Finder onto the XFinder table copies them into the current folder. Dropping onto a displayed subfolder copies them into that subfolder.

Files dragged between two different XFinder windows are also copied. The originals remain in place. Open different folders in the two windows for this operation.

Drops within the same XFinder window are blocked. Dropping back into the source folder is also rejected, even when the source and destination are displayed in different windows or applications. This prevents an unnecessary renamed copy in the same folder.

If a different file already has the same name at the destination, XFinder chooses an available name such as “File copy” or “File copy 2”. Existing destination files are not overwritten. Problems accepting files are reported in an error message.

## Two docked file windows

Dock Second Window in the toolbar opens the current folder in a second window and arranges both windows side by side. Navigation, search, and selection are independent in each window; menu commands apply to the active file window.

Moving either window moves the pair together. Resizing aligns their heights and adjacent edges. Clicking the button again activates the existing partner. Closing either window or entering full screen releases the pair.

To copy files, navigate to the source folder on one side and the destination on the other, then drag the files across. The rules in “Drag and drop and copy rules” also apply to this window pair.

## Searching for files

The Search field searches file names in the current folder and recursively in its subfolders. It searches names, not the contents of documents.

Without wildcards, part of a name is enough. Use * for any number of characters and ? for exactly one character. Examples: *.pdf for PDF files, test.* for files named test with any extension, and report-?.pdf for names such as report-1.pdf.

The additional Location column shows the folder containing each result. Clear the search text to return to the normal folder view. Large directory trees can take time; an activity indicator is shown while searching.

## Images, PDFs, and Quick Look

Select one or more files in the file table and press Space or click the eye button for Quick Look. The action is also available in the context menu. With several files selected, you can navigate through them in the preview window.

Double-clicking an image opens the image viewer. While it is open, clicking another image updates the preview, including from the other file window. Use the preview action for PDFs and other formats supported by macOS as well.

Other files open in their default applications. Recognized scripts require confirmation first: XFinder checks known script extensions and the #! shebang at the start of a file. The Unix executable bit alone does not trigger a prompt; an ordinary MP3 file needs no such confirmation.

## Playing a single MP3

Double-click an MP3 file to open the audio player and start playback. While the single-file player is open, clicking another MP3 switches to that track. Single files and the playlist use the same player.

The player displays embedded artwork, title, artist, and album. A music symbol appears when artwork is missing; the file name is used when there is no title. Titles can occupy up to three lines. When changing tracks, the previous presentation remains until the new metadata can be displayed together.

The player window can be moved and resized. It uses normal window ordering, so other applications can cover it. Native playback controls offer play/pause and additional controls depending on the available width.

Known limitation: At narrow window widths, the native controls hide the timeline. Widen the player to seek within a track. A separate, permanently visible timeline is not included in this version.

## Creating a playlist from a folder

Select one or more folders and click the playlist toolbar button with the music-list symbol. XFinder collects MP3 files only from those folders and their subfolders. If no folder is selected, the current folder is used instead. A selected parent folder already includes selected folders below it, so tracks are not duplicated.

The playlist opens in its own window. Its read-only table is on the left and the complete player with artwork, metadata, playback controls, and timeline is integrated on the right. Embedded cover artwork is also loaded asynchronously into the Name column; tracks without artwork show a music-note placeholder. Clicking a track starts it; opening the list alone does not start playback. Playing an MP3 from the regular file view continues to use a separate player window.

Folders form album groups. Files are collected breadth-first: tracks directly in the root folder first, then tracks in its immediate subfolders, then the next level. Tracks within each folder use natural file-name order, such as Track 2 before Track 10. Album / Folder shows the folder path, not the MP3 album metadata field.

Hidden files follow the file view's setting. Directory symlinks and packages are not traversed. Unreadable subfolders are skipped, so missing access permissions can result in an incomplete playlist.

## Controlling the playlist

The toolbar offers these actions from left to right:

- Beginning: Plays the first track in the visible list.
- Previous: Plays the preceding track in the current playback order.
- Play/Stop: Stops playback or starts the selected track. After Stop, Play restarts the track from the beginning. With no selection, playback starts at the first track in the playback order.
- Next: Plays the next track in the current playback order.
- End: Plays the last track in the visible list.
- Random/In Order: Switches between random and sequential playback. This setting persists after restarting the app.
- Endless: Repeats the playlist after the last track. This setting also persists after restarting the app.

The visible list keeps its album groups even in random mode. Switching modes retains the current track. Beginning and End still refer to the visible list; Previous and Next follow the playback order.

At the end of a file, the next track starts automatically and the corresponding table row is scrolled into view, including in random mode. The playlist controls also reveal the affected row, which is especially useful for Previous and Next during random playback. Clicking a row directly does not reposition the table. Playback ends after the last track unless Endless is enabled; in Endless mode it continues at the beginning of the current playback order. Closing the playlist discards the temporary list and stops its playback. Clicking the playlist button again rebuilds the list from the chosen folder.

## Favorites, locations, and permissions

The sidebar distinguishes standard favorites, imported Finder favorites, and custom XFinder favorites. Add selected folders permanently using Add to Favorites in the context menu.

Locations include iCloud Drive, Trash, AirDrop, external drives, and a Finder-style Network node. XFinder discovers SMB and AFP file servers on the local network even before a share is mounted. Expand Network to see available servers and other Macs. Mounted shares are grouped below their server. Selecting an unmounted server opens the macOS connection dialog. Internal and virtual system volumes are excluded. Allow local-network access when macOS asks; otherwise discovery remains empty.

Connected iPhones are detected through Apple's media-device interface. Unlock the device and confirm that it trusts this Mac. Clicking it opens Image Capture; the iPhone is not mounted as a freely accessible file system.

macOS may restrict access to protected folders. XFinder > Configure Full Disk Access… opens System Settings. Show XFinder App in Finder helps locate the application actually running, including when launched from Xcode. Restart XFinder after changing access permissions. Importing Finder favorites may also require this access.

## Keyboard shortcuts and troubleshooting

- ⌘⇧N: New folder.
- Space: Preview the selection while the file table has keyboard focus.
- ⌘⌫: Move the selection to Trash.
- ⌘⇧.: Show or hide hidden files.
- ⌘R: Reload the folder view.
- ⌘[: Go back.
- ⌘]: Go forward.
- ⌘↑: Open the enclosing folder.
- ⌘⇧H: Open the home folder.
- ⌘,: Open Settings.

Command-key shortcuts apply to the active XFinder file window. Click that window first; help, playlist, player, and dialog windows do not target a file window in the background. Space previews files only when the file table has keyboard focus and remains a space during text entry. Use ⌘⌫ to move files to Trash; plain Delete does not delete files. Menu items display the Command-key shortcuts.

If a drop is rejected, first check whether source and destination are the same folder or the drag began in the same XFinder window. For an empty playlist, check the folder selection, MP3 extensions, and access permissions. If the MP3 timeline is missing, widen the player.

Update an existing Git checkout with git pull. Then open XFinder.xcodeproj and run the app in Xcode with ⌘R. Requirements: macOS 15 or later and Xcode 26 or later. Xcode's ⌘R Run command is separate from the Reload command with the same shortcut inside the running app.
