Files Cra on CEF 156 left in its data folder, for scenarios that open them on the engine (`profile`
in a scenario copies this folder into the data folder before launch).

- `Chromium/Default/Cookies`: written by `Migration/cef-write` on an unsigned CEF build (mock
  keychain), one cookie `cra_migration=kept` on 127.0.0.1, encrypted as a "v10" value. Its expiry
  was moved to 2100 by hand so the fixture doesn't age out.
