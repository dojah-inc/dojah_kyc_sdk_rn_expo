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
            self.resolveSdkResult()
            self.dojahNavController = nil
        }
    }
    
    private func resolveSdkResult() {
        let vStatus = DojahWidgetSDK.getVerificationResultStatus()
        let status = vStatus.isEmpty ? "closed" : vStatus
        
        print("📊 Resolving SDK result: \(status)")
        
        // Resolve promise first
        self.mPromise?.resolve(status)
        self.mPromise = nil
        
        // Clear state
        self.prevController = nil
        
        // Dismiss the navigation controller
        self.dismissDojahController()
        
        // Reset flag
        self.isDojahActive = false
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
    
    private func dismissDojahController() {
        DispatchQueue.main.async { [weak self] in
            // Stop all timers
            self?.navigationCheckTimer?.invalidate()
            self?.navigationCheckTimer = nil
            self?.formScreenStuckTimer?.invalidate()
            self?.formScreenStuckTimer = nil
            
            self?.dojahNavController?.dismiss(animated: true) {
                self?.dojahNavController = nil
            }
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
                            self.debugLog("📱 SDKInitViewController - resolving (flow completed)")
                            self.resolveSdkResult()
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

        AsyncFunction("close") { [weak self] (promise: Promise) in
            print("🛑 Manual close requested")
            
            guard let self = self else {
                promise.resolve("no_instance")
                return
            }
            
            let vStatus = DojahWidgetSDK.getVerificationResultStatus()
            let status = vStatus.isEmpty ? "cancelled" : vStatus
            
            self.mPromise?.resolve(status)
            self.mPromise = nil
            self.prevController = nil
            
            self.dismissDojahController()
            self.isDojahActive = false
            
            promise.resolve("closed")
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