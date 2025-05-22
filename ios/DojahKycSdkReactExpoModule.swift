import ExpoModulesCore
import DojahWidget

public class DojahKycSdkReactExpoModule: Module {
  // Each module class must implement the definition function. The definition consists of components
  // that describes the module's functionality and behavior.
  // See https://docs.expo.dev/modules/module-api for more details about available components.
  public func definition() -> ModuleDefinition {
    // Sets the name of the module that JavaScript code will use to refer to the module. Takes a string as an argument.
    // Can be inferred from module's class name, but it's recommended to set it explicitly for clarity.
    // The module will be accessible from `requireNativeModule('DojahKycSdk')` in JavaScript.
    Name("DojahKycSdk")

    // Defines event names that the module can send to JavaScript.
    Events("onChange")

    // Defines a JavaScript function that always returns a Promise and whose native code
    // is by default dispatched on the different thread than the JavaScript runtime runs on.
      AsyncFunction("launch") { (widgetId: String, referenceId: String?, email: String?, extraData: ExtraDataRecord?,promise:Promise) in
          
          guard let rootViewController = UIApplication.shared.keyWindow?.rootViewController else {
              print("no root ctrl")
              return
          }
          
          print("root ctrl: $\(String(describing: rootViewController))")

          let navController = rootViewController as? UINavigationController

          print("nav ctrl: $\(String(describing: navController))")

          if(navController == nil){
              return
          }
          
          DispatchQueue.main.async {
              DojahWidgetSDK.initialize(widgetID: widgetId,referenceID: referenceId,emailAddress: email, navController: navController!)
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

//    func toExtraUserData()-> ExtraUserData {
//        return ExtraUserData(
//            userData = userData?.toUserData(),
//            govData = govData?.toGovData(),
//            govId = govId?.toGovId(),
//            location = location?.toLocation(),
//            businessData = businessData?.toBusinessData(),
//            address = address,
//            metadata = metadata
//        )
//    }

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

//    func toUserData(): UserData {
//        return UserData(
//            firstName = firstName,
//            lastName = lastName,
//            dob = dob,
//            email = email
//        )
//    }
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

//    func toGovData(): GovData {
//        return GovData(
//            bvn = bvn,
//            dl = dl,
//            nin = nin,
//            vnin = vnin
//        )
//    }
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

//    func toGovId(): GovId {
//        return GovId(
//            national = national,
//            passport = passport,
//            dl = dl,
//            voter = voter,
//            nin = nin,
//            others = others
//        )
//    }
}

struct LocationRecord : Record {
    @Field
    var latitude: String? = nil

    @Field
    var longitude: String? = nil

//    func toLocation(): Location {
//        return Location(
//            latitude = latitude,
//            longitude = longitude
//        )
//    }
}

struct BusinessDataRecord : Record {
    @Field
    var cac: String? = nil

//    func toBusinessData(): BusinessData {
//        return BusinessData(
//            cac = cac
//        )
//    }
}

