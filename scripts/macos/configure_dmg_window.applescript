on run arguments
    set mountPath to item 1 of arguments
    set targetFolder to POSIX file mountPath as alias
    set backgroundImage to POSIX file (mountPath & "/.background/background.png") as alias
    tell application "Finder"
        open targetFolder
        set targetWindow to container window of targetFolder
        set current view of targetWindow to icon view
        tell targetWindow
            set toolbar visible to false
            set sidebar width to 0
            set statusbar visible to false
            set pathbar visible to false
            set bounds to {100, 100, 760, 520}
        end tell
        set viewOptions to icon view options of targetWindow
        tell viewOptions
            set arrangement to not arranged
            set icon size to 96
            set text size to 12
            set background picture to backgroundImage
        end tell
        set position of item "SIDEY.app" of targetFolder to {165, 205}
        set position of item "Applications" of targetFolder to {495, 205}
        update targetFolder without registering applications
        delay 1
        close targetWindow
    end tell
end run
