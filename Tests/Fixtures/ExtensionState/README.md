A made-up Cra Chromium profile (Default/) for scripts/test-extension-state.sh: which extensions
chrome://extensions has turned off (GitHub #41) and the live extensions.settings Chromium answers
from memory before it writes the files (GitHub #43).

- Preferences: an older Chromium's `state: 0` (off).
- Secure Preferences: two Web Store installs (location 1, one off, one on) and two
  --load-extension copies (location 8, one off, one with no disable reasons).
- live-extensions-settings.json: the same settings as Chromium holds them a moment after
  "Load unpacked" picked Unpacked/ and the --load-extension copy that was on was turned off.
  `${FIXTURE}` stands for this folder.
