import ExpoModulesCore
import DojahWidget

class DojahNavigationControllerDelegate: NSObject, UINavigationControllerDelegate {
    var onDidShow: (UIViewController) -> Void = { _ in }
    func navigationController(_ navigationController: UINavigationController,
                              didShow viewController: UIViewController,
                              animated: Bool) {
        print("Did show: \(viewController)")
        onDidShow(viewController)
    }

    func navigationController(_ navigationController: UINavigationController,
                              willShow viewController: UIViewController,
                              animated: Bool) {
        print("Will show: \(viewController)")
    }
    
    func setOnDidShow(_ onDidShow: @escaping (UIViewController) -> Void) {
        self.onDidShow = onDidShow
    }
}

public class DojahKycSdkReactExpoModule: Module {
    
    var mPromise: Promise?
    let navDelegate = DojahNavigationControllerDelegate()
    var navCtrl: UINavigationController?
    var prevController: UIViewController?

    required public init(appContext: AppContext) {
        super.init(appContext: appContext)
        navDelegate.setOnDidShow { vc in
            print("onDidShow: \(vc)")
            if !String(describing: vc).contains("DojahWidget") {
                let vStatus = DojahWidgetSDK.getVerificationResultStatus()
                let status = vStatus.isEmpty ? "closed" : vStatus
                self.mPromise?.resolve(status)
                self.prevController = nil
            } else if String(describing: vc).contains("DojahWidget.DJDisclaimer")
                     && self.prevController != nil {
                self.navCtrl?.popToRootViewController(animated: false)
            } else if !String(describing: vc).contains("DojahWidget.SDKInitViewController") {
                self.prevController = vc
            }
        }
    }

    public func definition() -> ModuleDefinition {
        Name("DojahKycSdk")
        Events("onChange")

        AsyncFunction("launch") { (widgetId: String, referenceId: String?, email: String?, extraData: ExtraDataRecord?, promise: Promise) in
            self.mPromise = promise
            
            DispatchQueue.main.async {
                // Get the current key window
                guard let window = UIApplication.shared.windows.first(where: { $0.isKeyWindow }) else {
                    self.mPromise?.reject("002", "No key window found")
                    return
                }
                
                // If we already have a navigation controller, use it
                if let existingNav = self.navCtrl {
                    self.initializeDojahSDK(with: existingNav, widgetId: widgetId, referenceId: referenceId, email: email, extraData: extraData)
                    return
                }
                
                // If root is already a navigation controller
                if let rootNav = window.rootViewController as? UINavigationController {
                    self.navCtrl = rootNav
                    self.initializeDojahSDK(with: rootNav, widgetId: widgetId, referenceId: referenceId, email: email, extraData: extraData)
                    return
                }
                
                // If root is not a navigation controller, create a new one
                if let rootVC = window.rootViewController {
                    // Create a new navigation controller with the root VC
                    let navController = UINavigationController()
                    navController.viewControllers = [rootVC]
                    window.rootViewController = navController
                    self.navCtrl = navController
                    self.initializeDojahSDK(with: navController, widgetId: widgetId, referenceId: referenceId, email: email, extraData: extraData)
                    return
                }
                
                // If we still don't have a navigation controller
                self.mPromise?.reject("002", "Failed to setup navigation controller")
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
    
    private func initializeDojahSDK(with navController: UINavigationController, 
                                  widgetId: String, 
                                  referenceId: String?, 
                                  email: String?, 
                                  extraData: ExtraDataRecord?) {
        navController.delegate = self.navDelegate
        do {
            DojahWidgetSDK.initialize(
                widgetID: widgetId,
                referenceID: referenceId,
                emailAddress: email,
                extraUserData: extraData?.toExtraUserData(),
                navController: navController
            )
        } catch {
            self.mPromise?.reject("001", "failed to initialize")
        }
    }
}


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

