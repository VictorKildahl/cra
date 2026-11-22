import AppKit

// The connected displays that draw at 2x or more, one name per line (NSScreen.localizedName, what
// CRA_TEST_SCREEN matches): where `scripts/scenario.sh snapshots` can compare against Tests/Snapshots,
// whose references are 2x.
for screen in NSScreen.screens where screen.backingScaleFactor >= 2 {
    print(screen.localizedName)
}
