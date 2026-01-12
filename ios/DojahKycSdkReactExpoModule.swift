import ExpoModulesCore
import DojahWidget
import UIKit

// Custom NavigationController that prevents duplicate presentations
class SafeDojahNavigationController: UINavigationController {
    private var isPresenting = false
    
    override func present(_ viewControllerToPresent: UIViewController, animated: Bool, completion: (() -> Void)? = nil) {
        // Check if we're already presenting something
        if isPresenting {
            print("⚠️ Already presenting, preventing duplicate: \(String(describing: type(of: viewControllerToPresent)))")
            completion?()
            return
        }
        
        // Check if this view controller is already in the navigation stack
        if viewControllers.contains(where: { 
            type(of: $0) == type(of: viewControllerToPresent)
        }) {
            print("⚠️ ViewController already in navigation stack: \(String(describing: type(of: viewControllerToPresent)))")
            completion?()
            return
        }
        
        // Check if we're already presenting something
        if presentedViewController != nil {
            print("⚠️ NavigationController already has a presentedViewController")
            completion?()
            return
        }
        
        // Mark as presenting
        isPresenting = true
        
        // Call super to actually present
        super.present(viewControllerToPresent, animated: animated) { [weak self] in
            self?.isPresenting = false
            completion?()
        }
    }
    
    override func dismiss(animated: Bool, completion: (() -> Void)? = nil) {
        isPresenting = false
        super.dismiss(animated: animated, completion: completion)
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
            self?.dojahNavController?.dismiss(animated: true) {
                self?.dojahNavController = nil
            }
        }
    }

    public func definition() -> ModuleDefinition {
        Name("DojahKycSdk")
        Events("onChange")

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
                
                // Set delegate BEFORE presenting (important!)
                dojahNavController.delegate = self.navDelegate
                
                // Detect modal dismissal (for cancel)
                dojahNavController.presentationController?.delegate = self.presentationDelegate
                
                // Track Dojah flow - simplified like original but with Flutter closing logic
                self.navDelegate.setOnDidShow { [weak self] vc in
                    guard let self = self else { return }
                    
                    // Use String(describing: vc) like the original code
                    let vcName = String(describing: vc)
                    print("🔄 onDidShow: \(vcName)")
                    
                    // Match original + Flutter logic:
                    // 1. If not DojahWidget, resolve (but only if we were in Dojah)
                    if !vcName.contains("DojahWidget") {
                        if self.isDojahActive {
                            print("🚪 Not DojahWidget - resolving")
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
                            print("📱 SDKInitViewController - resolving")
                            self.resolveSdkResult()
                        } else {
                            // First time seeing SDKInitViewController - allow to continue
                            print("📱 SDKInitViewController on initial launch - allowing to continue")
                            self.hasSeenSDKInit = true
                        }
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
                        print("🎯 Dojah SDK initialized")
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