// Which release Sparkle (vendor/sparkle, the 2.10 every Cra since 0.1.2 ships) offers a Cra at a given build, from a
// feed. usage: feedcheck <stub.app>   prints FOUND <version> <build> | NONE | ERROR <message>
import AppKit
import Sparkle

final class Driver: NSObject, SPUUserDriver {
    func done(_ s: String) { print(s); fflush(stdout); exit(0) }
    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        reply(SUUpdatePermissionResponse(automaticUpdateChecks: false, sendSystemProfile: false))
    }
    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {}
    func showUpdateFound(with item: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) {
        done("FOUND \(item.displayVersionString) \(item.versionString)\(item.isInformationOnlyUpdate ? " info-only" : "")")
    }
    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}
    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {}
    func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) { done("NONE") }
    func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) { done("ERROR \(error.localizedDescription)") }
    func showDownloadInitiated(cancellation: @escaping () -> Void) {}
    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {}
    func showDownloadDidReceiveData(ofLength length: UInt64) {}
    func showDownloadDidStartExtractingUpdate() {}
    func showExtractionReceivedProgress(_ progress: Double) {}
    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {}
    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void) {}
    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {}
    func showUpdateInFocus() {}
    func dismissUpdateInstallation() {}
}

let bundle = Bundle(path: CommandLine.arguments[1])!
let driver = Driver()
let updater = SPUUpdater(hostBundle: bundle, applicationBundle: bundle, userDriver: driver, delegate: nil)
do { try updater.start() } catch { print("ERROR start \(error)"); exit(1) }
updater.checkForUpdates()
DispatchQueue.main.asyncAfter(deadline: .now() + 20) { print("ERROR timeout"); exit(1) }
NSApplication.shared.run()
