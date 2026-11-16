// Every profile's downloads, for the bridge: each change of each download, and pause, resume and cancel by id
// (the CEF bridge's OnDownloadUpdated and controlDownload).
#ifndef CRA_DOWNLOADS_H_
#define CRA_DOWNLOADS_H_

#include <cstdint>

namespace download {
class DownloadItem;
}

namespace cra {

using DownloadUpdated = void (*)(download::DownloadItem* item);

// Once Chrome is up: watches the downloads of every profile loaded now and later, off the record too.
void StartDownloads(DownloadUpdated updated);

enum class DownloadControl { kPause, kResume, kCancel };
// False when no download in progress has that id.
bool ControlDownload(uint32_t id, DownloadControl control);

}  // namespace cra

#endif  // CRA_DOWNLOADS_H_
