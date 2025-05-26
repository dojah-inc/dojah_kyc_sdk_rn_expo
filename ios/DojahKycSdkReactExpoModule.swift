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
    
    var mPromise:Promise? = nil
    
    let navDelegate = DojahNavigationControllerDelegate()
 
    let navCtrl = UIApplication.shared.keyWindow?.rootViewController as? UINavigationController
    
    var prevController:UIViewController? = nil

    required public init(appContext: AppContext) {
        super.init(appContext: appContext)
        navDelegate.setOnDidShow { vc in
            print("onDidShow: \(vc)")
            //return result from DojahWidget once verification
            //is done,failed or cancel
            if(!String(describing:vc).contains("DojahWidget")){
                let vStatus = DojahWidgetSDK.getVerificationResultStatus()
                let status = if(vStatus.isEmpty){  "closed"} else {vStatus}
                self.mPromise?.resolve(status)
                self.prevController = nil
            }else if(String(describing:vc).contains("DojahWidget.DJDisclaimer")
                     && self.prevController != nil){
                self.navCtrl?.popToRootViewController(animated: false)
            }else if(!String(describing:vc).contains("DojahWidget.SDKInitViewController")){
                self.prevController = vc
            }
        }
        
        if navCtrl != nil {
            navCtrl!.delegate = navDelegate
        }
    }

  public func definition() -> ModuleDefinition {

    Name("DojahKycSdk")

    Events("onChange")

    AsyncFunction("launch") { (widgetId: String, referenceId: String?, email: String?, extraData: ExtraDataRecord?,promise:Promise) in
          mPromise = promise

          let navController = navCtrl

          print("nav ctrl: $\(String(describing: navController))")
        
    
          if(navController == nil){
              self.mPromise?.reject("002","failed to initialize, can't find navController")
              return
          }
        
        DispatchQueue.main.async {
            do{
                DojahWidgetSDK.initialize(
                    widgetID: widgetId,
                    referenceID: referenceId,
                    emailAddress: email,
                    extraUserData: extraData?.toExtraUserData(),
                    navController: navController!)
            }catch{
                self.mPromise?.reject("001","failed to initialize")
            }
        }
    }

    // Enables the module to be used as a native view. Definition components that are accepted as part of the
    // view definition: Prop, Events.
    View(DojahKycSdkReactExpoView.self) {
      // Defines a setter for the `url` prop.
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

