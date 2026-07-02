import Foundation
#if SPARKLE_ENABLED
import Sparkle
#endif

/// Wraps Sparkle for the GitHub-channel build only (`SPARKLE_ENABLED`, set by
/// `OTHER_SWIFT_FLAGS` on the `SafeClip` target in project.yml — the `Sparkle`
/// package is likewise only a dependency of that target). `SafeClip-MAS`
/// shares this file but compiles the stub branch below: Apple's MAS
/// guidelines forbid an app updating itself, and App Review handles that
/// channel's updates instead.
///
/// The app never phones home on its own: `SUEnableAutomaticChecks` starts
/// `false` in Info.plist, and `automaticallyChecksForUpdates` here only
/// flips on when the user explicitly opts in via Settings → Updates (see
/// `UpdatesSettingsView`, which shows a consent alert first — same pattern
/// as `CaretLocator`'s Accessibility opt-in). `SUEnableSystemProfiling` is
/// off, so a check sends nothing but "is there a version newer than mine."
@MainActor
final class UpdateService: NSObject, ObservableObject {
    static let isSupported: Bool = {
        #if SPARKLE_ENABLED
        true
        #else
        false
        #endif
    }()

    #if SPARKLE_ENABLED
    private let controller: SPUStandardUpdaterController
    #endif

    /// Bound directly by the Settings toggle. Setting it writes straight
    /// through to Sparkle's own persisted preference.
    @Published var automaticallyChecksForUpdates: Bool {
        didSet {
            #if SPARKLE_ENABLED
            controller.updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates
            #endif
        }
    }

    override init() {
        #if SPARKLE_ENABLED
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        automaticallyChecksForUpdates = controller.updater.automaticallyChecksForUpdates
        #else
        automaticallyChecksForUpdates = false
        #endif
        super.init()
    }

    var canCheckForUpdates: Bool {
        #if SPARKLE_ENABLED
        controller.updater.canCheckForUpdates
        #else
        false
        #endif
    }

    var lastUpdateCheckDate: Date? {
        #if SPARKLE_ENABLED
        controller.updater.lastUpdateCheckDate
        #else
        nil
        #endif
    }

    /// User-initiated check — shows Sparkle's own progress/result UI.
    func checkForUpdates() {
        #if SPARKLE_ENABLED
        controller.checkForUpdates(nil)
        #endif
    }
}
