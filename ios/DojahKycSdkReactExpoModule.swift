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
            //return result from DojahWidget once verification
            //is done,failed or cancel
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
            
            // Get the navigation controller when needed, not during initialization
            if self.navCtrl == nil {
                DispatchQueue.main.async {
                    if let window = UIApplication.shared.windows.first(where: { $0.isKeyWindow }) {
                        if let rootNav = window.rootViewController as? UINavigationController {
                            self.navCtrl = rootNav
                        } else if let rootVC = window.rootViewController {
                            // If rootViewController isn't a nav controller, create one
                            let navController = UINavigationController(rootViewController: rootVC)
                            window.rootViewController = navController
                            self.navCtrl = navController
                        }
                    }
                    
                    guard let navController = self.navCtrl else {
                        self.mPromise?.reject("002", "failed to initialize, can't find navController")
                        return
                    }
                    
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
            } else {
                // If navCtrl already exists
                DispatchQueue.main.async {
                    guard let navController = self.navCtrl else {
                        self.mPromise?.reject("002", "failed to initialize, can't find navController")
                        return
                    }
                    
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

