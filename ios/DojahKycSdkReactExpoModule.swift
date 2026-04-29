import ExpoModulesCore
import DojahWidget
import UIKit
import os.log

// Custom NavigationController that prevents duplicate presentations at root level only
// Allows SDK to present view controllers (camera, verification screens) within the navigation flow
class SafeDojahNavigationController: UINavigationController {
    private var isPresentingRoot = false
    private var isCurrentlyPresenting = false
    
    override func present(_ viewControllerToPresent: UIViewController, animated: Bool, completion: (() -> Void)? = nil) {
        // Safety check: Prevent duplicate presentations that could cause crashes
        // But allow SDK to present view controllers within the navigation flow
        
        // If we're already presenting something, check if it's a duplicate
        if isCurrentlyPresenting {
            // Check if this is the same view controller type being presented again
            if let currentPresented = presentedViewController,
               type(of: currentPresented) == type(of: viewControllerToPresent) {
                print("⚠️ Duplicate presentation detected (same type), preventing crash: \(String(describing: type(of: viewControllerToPresent)))")
                completion?()
                return
            }
            // If it's a different type, allow it (SDK might be presenting camera/verification screen)
            // But log it for debugging
            print("⚠️ Presenting new VC while another is presented: \(String(describing: type(of: viewControllerToPresent)))")
        }
        
        // Mark as presenting
        isCurrentlyPresenting = true
        
        // Call super to actually present
        super.present(viewControllerToPresent, animated: animated) { [weak self] in
            self?.isCurrentlyPresenting = false
            completion?()
        }
    }
    
    override func dismiss(animated: Bool, completion: (() -> Void)? = nil) {
        isPresentingRoot = false
        isCurrentlyPresenting = false
        super.dismiss(animated: animated) { [weak self] in
            self?.isCurrentlyPresenting = false
            completion?()
        }
    }
    
    // Mark when root is being presented
    func markRootPresenting() {
        isPresentingRoot = true
    }
}

class DojahNavigationControllerDelegate: NSObject, UINavigationControllerDelegate {
    var onDidShow: (UIViewController) -> Void = { _ in }
    
    func navigationController(_ navigationController: UINavigationController,
                              didShow viewController: UIViewController,
                              animated: Bool) {
        print("📱 Did show: \(viewController)")
        onDidShow(viewController)
    }
    
    func setOnDidShow(_ onDidShow: @escaping (UIViewController) -> Void) {
        self.onDidShow = onDidShow
    }
}

class DojahPresentationControllerDelegate: NSObject, UIAdaptivePresentationControllerDelegate {
    var onDidDismiss: () -> Void = { }
    
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        print("🛑 Modal was dismissed manually")
        onDidDismiss()
    }
    
    func setOnDidDismiss(_ onDidDismiss: @escaping () -> Void) {
        self.onDidDismiss = onDidDismiss
    }
}

public class DojahKycSdkReactExpoModule: Module {
    
    var mPromise: Promise? = nil
    let navDelegate = DojahNavigationControllerDelegate()
    let presentationDelegate = DojahPresentationControllerDelegate()
    
    // Track Dojah state
    private var isDojahActive = false
    private var dojahNavController: SafeDojahNavigationController?
    private var prevController: UIViewController? // Track previous controller for DJDisclaimer handling
    private var hasSeenSDKInit = false // Track if we've seen SDKInitViewController before
    private var navigationCheckTimer: Timer? // Timer to check navigation stack changes
    private var formScreenStartTime: Date? // Track when we entered form screen
    private var formScreenStuckTimer: Timer? // Timer to detect stuck form screen
    private var preDojahGestureRecognizerIds = Set<ObjectIdentifier>()
    
    // Debug mode flag - set to false to disable debug logs
    private let debugMode = false
    
    // Helper to log to both console and React Native (only if debug mode is enabled)
    private func debugLog(_ message: String) {
        guard debugMode else { return }
        print(message)
        os_log("%{public}@", log: OSLog.default, type: .debug, message)
        // Send to React Native via event
        sendEvent("onDebugLog", [
            "message": message,
            "timestamp": Date().timeIntervalSince1970
        ])
    }
    
    required public init(appContext: AppContext) {
        super.init(appContext: appContext)
        
        // Set up presentation delegate callback
        presentationDelegate.setOnDidDismiss { [weak self] in
            guard let self = self else { return }
            print("🛑 Modal was dismissed manually")
            // User dismissed the sheet — do not trust getVerificationResultStatus() (can be stale, e.g. "approved")
            self.resolveSdkResult(statusOverride: "closed")
            self.dojahNavController = nil
        }
    }
    
    /// - Parameter statusOverride: When set (e.g. user closed the flow), use this instead of `getVerificationResultStatus()`,
    ///   which can retain a previous session value such as "approved" after the user dismisses.
    private func resolveSdkResult(statusOverride: String? = nil) {
        let status: String
        if let override = statusOverride {
            status = override
        } else {
            let vStatus = DojahWidgetSDK.getVerificationResultStatus()
            status = vStatus.isEmpty ? "closed" : vStatus
        }
        
        print("📊 Resolving SDK result: \(status)")
        
        let promise = self.mPromise
        self.mPromise = nil
        
        // Clear state
        self.prevController = nil
        
        // Dismiss the navigation controller before resolving JS. If JS routes
        // while the full-screen Dojah controller is still being removed, iOS can
        // leave a native view in the touch path and React pressables stop
        // receiving taps until the app is killed.
        self.dismissDojahController { [weak self] in
            self?.isDojahActive = false
            promise?.resolve(status)
        }
    }
    
    private func getTopViewController() -> UIViewController? {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else {
            return nil
        }
        
        var topViewController = rootViewController
        while let presentedViewController = topViewController.presentedViewController {
            topViewController = presentedViewController
        }
        
        return topViewController
    }
    
    private func dismissDojahController(completion: (() -> Void)? = nil) {
        DispatchQueue.main.async { [weak self] in
            // Stop all timers
            self?.navigationCheckTimer?.invalidate()
            self?.navigationCheckTimer = nil
            self?.formScreenStuckTimer?.invalidate()
            self?.formScreenStuckTimer = nil
            
            guard let self = self else {
                completion?()
                return
            }
            
            guard let navController = self.dojahNavController else {
                self.finishDojahDismissal(nil, completion: completion)
                return
            }
            
            guard navController.presentingViewController != nil ||
                    navController.presentedViewController != nil else {
                self.finishDojahDismissal(navController, completion: completion)
                return
            }
            
            navController.dismiss(animated: true) { [weak self] in
                self?.finishDojahDismissal(navController, completion: completion)
            }
        }
    }

    private func finishDojahDismissal(_ navController: SafeDojahNavigationController?, completion: (() -> Void)? = nil) {
        navController?.view.removeFromSuperview()
        navController?.removeFromParent()
        self.dojahNavController = nil
        self.removeGestureRecognizersAddedByDojah()
        self.removeReactSurfaceProxyGestureRecognizers(context: "finishDojahDismissal")
        self.neutralizeTouchCancellingNavigationRecognizers()
        self.resetAllGestureRecognizers()
        self.resetReactSurfaceTouchHandlersRepeatedly(context: "finishDojahDismissal")
        self.restoreAppInteractions()
        completion?()
    }

    private func snapshotGestureRecognizersBeforeDojah() {
        self.preDojahGestureRecognizerIds = self.collectGestureRecognizerIds()
        print("🧭 Dojah gesture snapshot count: \(self.preDojahGestureRecognizerIds.count)")
    }

    private func collectGestureRecognizerIds() -> Set<ObjectIdentifier> {
        var ids = Set<ObjectIdentifier>()

        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }

            for window in windowScene.windows {
                self.collectGestureRecognizerIds(from: window, into: &ids)
            }
        }

        return ids
    }

    private func collectGestureRecognizerIds(from view: UIView, into ids: inout Set<ObjectIdentifier>) {
        for recognizer in view.gestureRecognizers ?? [] {
            ids.insert(ObjectIdentifier(recognizer))
        }

        for subview in view.subviews {
            self.collectGestureRecognizerIds(from: subview, into: &ids)
        }
    }

    private func removeGestureRecognizersAddedByDojah() {
        guard !self.preDojahGestureRecognizerIds.isEmpty else { return }

        var removedCount = 0

        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }

            for window in windowScene.windows {
                removedCount += self.removeGestureRecognizersAddedByDojah(from: window)
            }
        }

        print("🧹 Removed \(removedCount) gesture recognizers added during Dojah")
        self.preDojahGestureRecognizerIds.removeAll()
    }

    private func removeGestureRecognizersAddedByDojah(from view: UIView) -> Int {
        var removedCount = 0

        for recognizer in view.gestureRecognizers ?? [] {
            if !self.preDojahGestureRecognizerIds.contains(ObjectIdentifier(recognizer)) {
                view.removeGestureRecognizer(recognizer)
                removedCount += 1
            }
        }

        for subview in view.subviews {
            removedCount += self.removeGestureRecognizersAddedByDojah(from: subview)
        }

        return removedCount
    }

    private func restoreAppInteractions() {
        DispatchQueue.main.async {
            let application = UIApplication.shared
            var safetyCount = 0

            while application.isIgnoringInteractionEvents && safetyCount < 8 {
                application.endIgnoringInteractionEvents()
                safetyCount += 1
            }

            for scene in application.connectedScenes {
                guard let windowScene = scene as? UIWindowScene else { continue }

                for window in windowScene.windows {
                    window.isUserInteractionEnabled = true
                    window.rootViewController?.view.isUserInteractionEnabled = true
                }
            }
        }
    }

    private func shouldNeutralizeNavigationRecognizer(_ recognizer: UIGestureRecognizer) -> Bool {
        let recognizerName = String(describing: type(of: recognizer))
        return recognizerName == "RNSScreenEdgeGestureRecognizer" ||
            recognizerName == "RNSPanGestureRecognizer" ||
            recognizerName == "_UIParallaxTransitionPanGestureRecognizer"
    }

    private func shouldResetReactSurfaceTouchRecognizer(_ recognizer: UIGestureRecognizer) -> Bool {
        return String(describing: type(of: recognizer)) == "RCTSurfaceTouchHandler"
    }

    private func removeReactSurfaceProxyGestureRecognizers(context: String) {
        DispatchQueue.main.async {
            var removedCount = 0

            for scene in UIApplication.shared.connectedScenes {
                guard let windowScene = scene as? UIWindowScene else { continue }

                for window in windowScene.windows {
                    removedCount += self.removeReactSurfaceProxyGestureRecognizers(from: window)
                }
            }

            print("🧹 Removed \(removedCount) React surface proxy recognizers after Dojah (\(context))")
        }
    }

    private func removeReactSurfaceProxyGestureRecognizers(from view: UIView) -> Int {
        var removedCount = 0
        let viewName = String(describing: type(of: view))

        if viewName == "RCTSurfaceHostingProxyRootView" {
            for recognizer in view.gestureRecognizers ?? [] {
                view.removeGestureRecognizer(recognizer)
                removedCount += 1
            }
        }

        for subview in view.subviews {
            removedCount += self.removeReactSurfaceProxyGestureRecognizers(from: subview)
        }

        return removedCount
    }

    private func neutralizeTouchCancellingNavigationRecognizers() {
        DispatchQueue.main.async {
            var neutralizedCount = 0

            for scene in UIApplication.shared.connectedScenes {
                guard let windowScene = scene as? UIWindowScene else { continue }

                for window in windowScene.windows {
                    neutralizedCount += self.neutralizeTouchCancellingNavigationRecognizers(from: window)
                }
            }

            print("🧭 Neutralized \(neutralizedCount) touch-cancelling navigation recognizers after Dojah")
        }
    }

    private func neutralizeTouchCancellingNavigationRecognizers(from view: UIView) -> Int {
        var neutralizedCount = 0

        for recognizer in view.gestureRecognizers ?? [] {
            if self.shouldNeutralizeNavigationRecognizer(recognizer) {
                recognizer.cancelsTouchesInView = false
                recognizer.delaysTouchesBegan = false
                recognizer.delaysTouchesEnded = false
                recognizer.requiresExclusiveTouchType = false
                recognizer.isEnabled = false
                neutralizedCount += 1
            }
        }

        for subview in view.subviews {
            neutralizedCount += self.neutralizeTouchCancellingNavigationRecognizers(from: subview)
        }

        return neutralizedCount
    }

    private func resetAllGestureRecognizers() {
        DispatchQueue.main.async {
            var resetCount = 0

            for scene in UIApplication.shared.connectedScenes {
                guard let windowScene = scene as? UIWindowScene else { continue }

                for window in windowScene.windows {
                    resetCount += self.resetGestureRecognizers(from: window)
                }
            }

            print("🔁 Reset \(resetCount) gesture recognizers after Dojah")
        }
    }

    private func resetGestureRecognizers(from view: UIView) -> Int {
        var resetCount = 0

        for recognizer in view.gestureRecognizers ?? [] {
            if self.shouldNeutralizeNavigationRecognizer(recognizer) {
                recognizer.isEnabled = false
            } else {
                recognizer.isEnabled = false
                recognizer.isEnabled = true
            }
            resetCount += 1
        }

        for subview in view.subviews {
            resetCount += self.resetGestureRecognizers(from: subview)
        }

        return resetCount
    }

    private func resetReactSurfaceTouchHandlersRepeatedly(context: String) {
        self.removeReactSurfaceProxyGestureRecognizers(context: "\(context).now")
        self.reattachAllReactSurfaceViews(context: "\(context).now")
        self.resetReactSurfaceTouchHandlers(context: "\(context).now")

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.removeReactSurfaceProxyGestureRecognizers(context: "\(context).50ms")
            self?.reattachAllReactSurfaceViews(context: "\(context).50ms")
            self?.resetReactSurfaceTouchHandlers(context: "\(context).50ms")
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.removeReactSurfaceProxyGestureRecognizers(context: "\(context).250ms")
            self?.reattachAllReactSurfaceViews(context: "\(context).250ms")
            self?.resetReactSurfaceTouchHandlers(context: "\(context).250ms")
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.removeReactSurfaceProxyGestureRecognizers(context: "\(context).500ms")
            self?.reattachAllReactSurfaceViews(context: "\(context).500ms")
            self?.resetReactSurfaceTouchHandlers(context: "\(context).500ms")
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.removeReactSurfaceProxyGestureRecognizers(context: "\(context).1000ms")
            self?.reattachAllReactSurfaceViews(context: "\(context).1000ms")
            self?.resetReactSurfaceTouchHandlers(context: "\(context).1000ms")
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.removeReactSurfaceProxyGestureRecognizers(context: "\(context).2000ms")
            self?.reattachAllReactSurfaceViews(context: "\(context).2000ms")
            self?.resetReactSurfaceTouchHandlers(context: "\(context).2000ms")
        }
    }

    private func resetReactSurfaceTouchHandlers(context: String) {
        DispatchQueue.main.async {
            var resetCount = 0

            for scene in UIApplication.shared.connectedScenes {
                guard let windowScene = scene as? UIWindowScene else { continue }

                for window in windowScene.windows {
                    resetCount += self.resetReactSurfaceTouchHandlers(from: window)
                }
            }

            print("🧼 Reset \(resetCount) React surface touch handlers after Dojah (\(context))")
        }
    }

    private func resetReactSurfaceTouchHandlers(from view: UIView) -> Int {
        var resetCount = 0
        let viewName = String(describing: type(of: view))

        for recognizer in view.gestureRecognizers ?? [] {
            if self.shouldResetReactSurfaceTouchRecognizer(recognizer) {
                self.forceResetReactSurfaceTouchRecognizer(recognizer, on: view)
                resetCount += 1
            } else if viewName == "RCTSurfaceHostingProxyRootView" {
                view.removeGestureRecognizer(recognizer)
                resetCount += 1
            }
        }

        for subview in view.subviews {
            resetCount += self.resetReactSurfaceTouchHandlers(from: subview)
        }

        return resetCount
    }

    private func forceResetReactSurfaceTouchRecognizer(_ recognizer: UIGestureRecognizer, on view: UIView) {
        let shouldReattachSurfaceView = recognizer.state == .failed || recognizer.state == .cancelled

        recognizer.cancelsTouchesInView = false
        recognizer.delaysTouchesBegan = false
        recognizer.delaysTouchesEnded = false
        recognizer.requiresExclusiveTouchType = false

        recognizer.isEnabled = false
        recognizer.reset()
        view.removeGestureRecognizer(recognizer)
        view.addGestureRecognizer(recognizer)
        recognizer.reset()
        recognizer.isEnabled = true

        DispatchQueue.main.async {
            recognizer.reset()
            recognizer.isEnabled = false
            recognizer.isEnabled = true
        }

        self.scheduleReactSurfaceViewReattach(view, reason: shouldReattachSurfaceView ? "stuck" : "reset")
    }

    private func reattachAllReactSurfaceViews(context: String) {
        DispatchQueue.main.async {
            var reattachedCount = 0

            for scene in UIApplication.shared.connectedScenes {
                guard let windowScene = scene as? UIWindowScene else { continue }

                for window in windowScene.windows {
                    reattachedCount += self.reattachReactSurfaceViews(from: window, reason: context)
                }
            }

            print("🧼 Reattached \(reattachedCount) React surface views after Dojah (\(context))")
        }
    }

    private func reattachReactSurfaceViews(from view: UIView, reason: String) -> Int {
        var reattachedCount = 0

        if String(describing: type(of: view)) == "RCTSurfaceView" {
            self.reattachReactSurfaceView(view, reason: reason)
            reattachedCount += 1
        }

        for subview in view.subviews {
            reattachedCount += self.reattachReactSurfaceViews(from: subview, reason: reason)
        }

        return reattachedCount
    }

    private func scheduleReactSurfaceViewReattach(_ view: UIView, reason: String) {
        DispatchQueue.main.async { [weak view] in
            guard let view = view else { return }
            self.reattachReactSurfaceView(view, reason: "\(reason).now")
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak view] in
            guard let view = view else { return }
            self.reattachReactSurfaceView(view, reason: "\(reason).100ms")
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak view] in
            guard let view = view else { return }
            self.reattachReactSurfaceView(view, reason: "\(reason).250ms")
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak view] in
            guard let view = view else { return }
            self.reattachReactSurfaceView(view, reason: "\(reason).500ms")
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak view] in
            guard let view = view else { return }
            self.reattachReactSurfaceView(view, reason: "\(reason).1000ms")
        }
    }

    private func reattachReactSurfaceView(_ view: UIView, reason: String) {
        guard String(describing: type(of: view)) == "RCTSurfaceView",
              let superview = view.superview else {
            return
        }

        let currentIndex = superview.subviews.firstIndex(of: view) ?? superview.subviews.count
        view.removeFromSuperview()
        superview.insertSubview(view, at: min(currentIndex, superview.subviews.count))
        view.isUserInteractionEnabled = true
        superview.isUserInteractionEnabled = true
        view.setNeedsLayout()
        superview.setNeedsLayout()
        self.restoreReactSurfaceAncestorInteractions(from: superview)
        print("🧼 Reattached React surface view after touch handler reset (\(reason))")
    }

    private func restoreReactSurfaceAncestorInteractions(from view: UIView) {
        var current: UIView? = view

        while let candidate = current {
            let viewName = String(describing: type(of: candidate))
            if viewName == "RCTSurfaceView" ||
                viewName == "RCTRootComponentView" ||
                viewName == "RCTSurfaceHostingProxyRootView" ||
                viewName == "RCTViewComponentView" ||
                viewName == "RNCSafeAreaProviderComponentView" {
                candidate.isUserInteractionEnabled = true
                candidate.setNeedsLayout()
            }
            current = candidate.superview
        }
    }

    public func definition() -> ModuleDefinition {
        Name("DojahKycSdk")
        Events("onChange", "onDebugLog")

        AsyncFunction("launch") { (widgetId: String, referenceId: String?, email: String?, extraData: ExtraDataRecord?, promise: Promise) in
            self.mPromise = promise
            
            guard let rootVC = self.getTopViewController() else {
                promise.reject("002", "Failed to get top view controller")
                return
            }
            
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                
                // Reset state for new launch
                self.prevController = nil
                self.isDojahActive = false
                self.hasSeenSDKInit = false
                self.snapshotGestureRecognizersBeforeDojah()
                
                // Create safe navigation controller for Dojah (prevents duplicate presentations)
                let dojahNavController = SafeDojahNavigationController()
                dojahNavController.modalPresentationStyle = .fullScreen
                self.dojahNavController = dojahNavController
                
                // Mark that we're presenting the root navigation controller
                dojahNavController.markRootPresenting()
                
                // Set delegate BEFORE presenting (important!)
                dojahNavController.delegate = self.navDelegate
                
                // Detect modal dismissal (for cancel)
                dojahNavController.presentationController?.delegate = self.presentationDelegate
                
                // DEBUG: Add observer to watch navigation stack changes
                var previousViewControllers: [UIViewController] = []
                let checkNavigationStack: () -> Void = { [weak self] in
                    guard let self = self, let navController = self.dojahNavController else { return }
                    let currentVCs = navController.viewControllers
                    
                    // Initialize previousViewControllers on first check
                    if previousViewControllers.isEmpty && !currentVCs.isEmpty {
                        previousViewControllers = currentVCs
                        let message = "🔍 Initial navigation stack captured: \(currentVCs.count) VCs"
                        self.debugLog(message)
                        currentVCs.forEach { vc in
                            self.debugLog("   📱 VC: \(String(describing: vc))")
                        }
                        return
                    }
                    
                    // Check if stack changed
                    if currentVCs.count != previousViewControllers.count {
                        self.debugLog("🔍 ⚠️ NAVIGATION STACK COUNT CHANGED: \(previousViewControllers.count) -> \(currentVCs.count)")
                        self.debugLog("   Previous VCs:")
                        previousViewControllers.forEach { vc in
                            self.debugLog("     - \(String(describing: vc))")
                        }
                        self.debugLog("   Current VCs:")
                        currentVCs.forEach { vc in
                            self.debugLog("     - \(String(describing: vc))")
                        }
                        previousViewControllers = currentVCs
                    } else if currentVCs.count > 0 {
                        // Check if top VC changed (same count but different VC)
                        let currentTop = currentVCs.last!
                        let previousTop = previousViewControllers.last
                        if previousTop != nil && currentTop !== previousTop! {
                            self.debugLog("🔍 ⚠️ TOP VC CHANGED (delegate NOT called!):")
                            self.debugLog("     Previous: \(String(describing: previousTop!))")
                            self.debugLog("     Current: \(String(describing: currentTop))")
                            previousViewControllers = currentVCs
                        }
                    }
                }
                
                // Check navigation stack every 0.5 seconds (only if debug mode is enabled)
                if self.debugMode {
                    self.navigationCheckTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                        checkNavigationStack()
                    }
                }
                
                // Track Dojah flow - simplified like original but with Flutter closing logic
                self.navDelegate.setOnDidShow { [weak self] vc in
                    guard let self = self else { return }
                    
                    // Use String(describing: vc) like the original code
                    let vcName = String(describing: vc)
                    self.debugLog("🔄 onDidShow: \(vcName)")
                    
                    // Track when we're on the form screen (GovernmentDataViewController)
                    if vcName.contains("GovernmentDataViewController") {
                        self.formScreenStartTime = Date()
                        self.debugLog("📝 On form screen (GovernmentDataViewController) - waiting for submission...")
                        
                        // Set up timer to detect if form screen is stuck (no navigation after 10 seconds)
                        self.formScreenStuckTimer?.invalidate()
                        self.formScreenStuckTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: false) { [weak self] _ in
                            guard let self = self else { return }
                            // Check if we're still on the form screen
                            if let navController = self.dojahNavController,
                               let topVC = navController.viewControllers.last,
                               String(describing: topVC).contains("GovernmentDataViewController") {
                                self.debugLog("⚠️ ⚠️ ⚠️ FORM SCREEN STUCK - No navigation after 10 seconds! Possible submission failure.")
                                self.debugLog("   This usually means the form submission failed silently.")
                            }
                        }
                    } else {
                        // We navigated away from form screen - clear timer
                        if self.formScreenStartTime != nil {
                            let timeOnForm = Date().timeIntervalSince(self.formScreenStartTime!)
                            self.debugLog("⏱️ Time spent on form screen: \(String(format: "%.1f", timeOnForm)) seconds")
                            self.formScreenStartTime = nil
                        }
                        self.formScreenStuckTimer?.invalidate()
                        self.formScreenStuckTimer = nil
                    }
                    
                    // Match original + Flutter logic:
                    // 1. If not DojahWidget, resolve (but only if we were in Dojah)
                    if !vcName.contains("DojahWidget") {
                        if self.isDojahActive {
                            self.debugLog("🚪 Not DojahWidget - resolving")
                            self.resolveSdkResult()
                        }
                        return
                    }
                    
                    // Mark as active when we see Dojah screens
                    self.isDojahActive = true
                    
                    // 2. If DJDisclaimer with prevController, pop to root (like original)
                    if vcName.contains("DojahWidget.DJDisclaimer") && self.prevController != nil {
                        print("📱 DJDisclaimer with prevController - popping to root")
                        self.dojahNavController?.popToRootViewController(animated: false)
                        return
                    }
                    
                    // 3. If not SDKInitViewController, track as prevController (like original)
                    if !vcName.contains("DojahWidget.SDKInitViewController") {
                        self.prevController = vc
                        print("✅ Tracking prevController: \(vcName)")
                    } else {
                        // 4. SDKInitViewController - resolve (matches Flutter's "else" case)
                        // Resolve if we've seen it before OR if we've progressed
                        if self.hasSeenSDKInit || self.prevController != nil {
                            self.debugLog("📱 SDKInitViewController - resolving (user exit / close; avoid stale verification status)")
                            // Second pass at SDK init or return after progress — usually dismiss/close, not a completed check
                            self.resolveSdkResult(statusOverride: "closed")
                        } else {
                            // First time seeing SDKInitViewController - allow to continue
                            self.debugLog("📱 SDKInitViewController on initial launch - allowing to continue")
                            self.hasSeenSDKInit = true
                        }
                    }
                    
                    // Log successful navigation from form screen
                    if vcName.contains("FeedbackViewController") {
                        self.debugLog("✅ Successfully navigated from form to feedback screen!")
                    }
                }
                
                // Present modally and wait for completion to ensure view hierarchy is ready
                rootVC.present(dojahNavController, animated: true) {
                    // Add a small delay to ensure view hierarchy is fully laid out
                    // This helps with camera session initialization timing
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        // Initialize SDK after presentation completes and view is laid out
                        // This ensures the view hierarchy is fully set up before camera access
                        DojahWidgetSDK.initialize(
                            widgetID: widgetId,
                            referenceID: referenceId,
                            emailAddress: email,
                            extraUserData: extraData?.toExtraUserData(),
                            source: "ios_react_native_expo",
                            navController: dojahNavController
                        )
                        self.debugLog("🎯 Dojah SDK initialized")
                        
                        // DEBUG: Log initial navigation state
                        self.debugLog("🔍 Initial navigation stack count: \(dojahNavController.viewControllers.count)")
                        dojahNavController.viewControllers.forEach { vc in
                            self.debugLog("   📱 Initial VC: \(String(describing: vc))")
                        }
                    }
                }
            }
        }

        AsyncFunction("restoreInteractions") { [weak self] (promise: Promise) in
            self?.restoreAppInteractions()
            self?.neutralizeTouchCancellingNavigationRecognizers()
            self?.resetReactSurfaceTouchHandlersRepeatedly(context: "restoreInteractions")
            promise.resolve("restored")
        }

        AsyncFunction("close") { [weak self] (promise: Promise) in
            print("🛑 Manual close requested")
            
            guard let self = self else {
                promise.resolve("no_instance")
                return
            }
            
            let launchPromise = self.mPromise
            self.mPromise = nil
            self.prevController = nil
            
            self.dismissDojahController { [weak self] in
                self?.isDojahActive = false
                self?.resetReactSurfaceTouchHandlersRepeatedly(context: "close")
                launchPromise?.resolve("closed")
                promise.resolve("closed")
            }
        }

        View(DojahKycSdkReactExpoView.self) {
            Prop("url") { (view: DojahKycSdkReactExpoView, url: URL) in
                if view.webView.url != url {
                    view.webView.load(URLRequest(url: url))
                }
            }
            Events("onLoad")
        }
    }
}


// ============= KEEP ALL THESE STRUCTS =============

struct ExtraDataRecord : Record {
    @Field
    var userData: UserRecord? = nil

    @Field
    var govData: GovDataRecord? = nil

    @Field
    var govId: GovIdRecord? = nil

    @Field
    var location: LocationRecord? = nil

    @Field
    var businessData: BusinessDataRecord? = nil

    @Field
    var address: String? = nil

    @Field
    var metadata: [String:Any]? = nil

    func toExtraUserData()-> ExtraUserData {
        return ExtraUserData(
            userData: userData?.toUserData(),
            govData: govData?.toGovData(),
            govId: govId?.toGovId(),
            location: location?.toLocation(),
            businessData: businessData?.toBusinessData(),
            address: address,
            metadata: metadata
        )
    }
}

struct UserRecord : Record {
    @Field
    var firstName: String? = nil

    @Field
    var lastName: String? = nil

    @Field
    var dob: String? = nil

    @Field
    var email: String? = nil

    func toUserData()-> UserBioData {
        return UserBioData(
            firstName: firstName,
            lastName: lastName,
            dob: dob,
            email: email
        )
    }
}

struct GovDataRecord : Record {
    
    @Field
    var bvn: String? = nil

    @Field
    var dl: String? = nil

    @Field
    var nin: String? = nil

    @Field
    var vnin: String? = nil

    func toGovData()-> ExtraGovData {
        return ExtraGovData(
            bvn: bvn,
            dl: dl,
            nin: nin,
            vnin: vnin
        )
    }
}

struct GovIdRecord : Record {
    @Field
    var national: String? = nil

    @Field
    var passport: String? = nil

    @Field
    var dl: String? = nil

    @Field
    var voter: String? = nil

    @Field
    var nin: String? = nil

    @Field
    var others: String? = nil

    func toGovId()-> ExtraGovIdData {
        return ExtraGovIdData(
            national:  national,
            passport: passport,
            dl: dl,
            voter: voter,
            nin: nin,
            others: others
        )
    }
}

struct LocationRecord : Record {
    @Field
    var latitude: String? = nil

    @Field
    var longitude: String? = nil

    func toLocation()-> ExtraLocationData {
        return ExtraLocationData(
            longitude: longitude,
            latitude: latitude
        )
    }
}

struct BusinessDataRecord : Record {
    @Field
    var cac: String? = nil

    func toBusinessData()-> ExtraBusinessData {
        return ExtraBusinessData(
            cac: cac
        )
    }
}