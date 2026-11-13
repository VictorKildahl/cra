// downloads.h says what this is.

#include "cra/downloads.h"

#include <map>
#include <memory>

#include "base/memory/raw_ptr.h"
#include "base/scoped_multi_source_observation.h"
#include "chrome/browser/browser_process.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/profiles/profile_manager.h"
#include "chrome/browser/profiles/profile_manager_observer.h"
#include "chrome/browser/profiles/profile_observer.h"
#include "components/download/public/common/download_item.h"
#include "content/public/browser/download_manager.h"

namespace cra {
namespace {

class Downloads : public ProfileManagerObserver,
                  public ProfileObserver,
                  public content::DownloadManager::Observer,
                  public download::DownloadItem::Observer {
 public:
  void Start(DownloadUpdated updated) {
    updated_ = updated;
    manager_ = g_browser_process->profile_manager();
    manager_->AddObserver(this);
    for (Profile* profile : manager_->GetLoadedProfiles()) {
      Watch(profile);
      for (Profile* off_the_record : profile->GetAllOffTheRecordProfiles()) {
        WatchManager(off_the_record);
      }
    }
  }

  bool Control(uint32_t id, DownloadControl control) {
    for (auto& [manager, profile] : managers_) {
      download::DownloadItem* item = manager->GetDownload(id);
      if (!item || item->GetState() != download::DownloadItem::IN_PROGRESS) {
        continue;
      }
      switch (control) {
        case DownloadControl::kPause:
          item->Pause();
          break;
        case DownloadControl::kResume:
          item->Resume(/*user_resume=*/true);
          break;
        case DownloadControl::kCancel:
          item->Cancel(/*user_cancel=*/true);
          break;
      }
      return true;
    }
    return false;
  }

  // ProfileManagerObserver:
  void OnProfileAdded(Profile* profile) override { Watch(profile); }
  void OnProfileManagerDestroying() override {
    profiles_.RemoveAllObservations();
    // The manager being destroyed: g_browser_process no longer returns it.
    manager_->RemoveObserver(this);
    manager_ = nullptr;
  }

  // ProfileObserver:
  void OnOffTheRecordProfileCreated(Profile* off_the_record) override { WatchManager(off_the_record); }
  void OnProfileWillBeDestroyed(Profile* profile) override {
    if (profiles_.IsObservingSource(profile)) {
      profiles_.RemoveObservation(profile);
    }
  }

  // content::DownloadManager::Observer:
  void OnDownloadCreated(content::DownloadManager* manager, download::DownloadItem* item) override {
    item->AddObserver(this);
    updated_(item);
  }
  void ManagerGoingDown(content::DownloadManager* manager) override {
    manager->RemoveObserver(this);
    managers_.erase(manager);
  }

  // download::DownloadItem::Observer:
  void OnDownloadUpdated(download::DownloadItem* item) override { updated_(item); }
  void OnDownloadDestroyed(download::DownloadItem* item) override { item->RemoveObserver(this); }

 private:
  void Watch(Profile* profile) {
    if (!profiles_.IsObservingSource(profile)) {
      profiles_.AddObservation(profile);
    }
    WatchManager(profile);
  }

  void WatchManager(Profile* profile) {
    content::DownloadManager* manager = profile->GetDownloadManager();
    if (!manager || managers_.count(manager)) {
      return;
    }
    managers_[manager] = profile;
    manager->AddObserver(this);
  }

  DownloadUpdated updated_ = nullptr;
  raw_ptr<ProfileManager> manager_ = nullptr;
  base::ScopedMultiSourceObservation<Profile, ProfileObserver> profiles_{this};
  std::map<content::DownloadManager*, Profile*> managers_;
};

Downloads& TheDownloads() {
  static auto* downloads = new Downloads();
  return *downloads;
}

}  // namespace

void StartDownloads(DownloadUpdated updated) {
  TheDownloads().Start(updated);
}

bool ControlDownload(uint32_t id, DownloadControl control) {
  return TheDownloads().Control(id, control);
}

}  // namespace cra
