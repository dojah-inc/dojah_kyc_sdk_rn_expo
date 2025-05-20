package com.dojah.dojah_Kyc_rn_expo

import expo.modules.kotlin.modules.Module
import expo.modules.kotlin.modules.ModuleDefinition
import java.net.URL
import android.app.Activity
import android.content.Intent
import android.util.Log
import com.dojah.kyc_sdk_kotlin.DOJAH_RESULT_KEY
import com.dojah.kyc_sdk_kotlin.domain.ExtraUserData
import com.dojah.kyc_sdk_kotlin.DojahSdk
import com.dojah.kyc_sdk_kotlin.domain.UserData
import com.dojah.kyc_sdk_kotlin.domain.GovData
import com.dojah.kyc_sdk_kotlin.domain.GovId
import com.dojah.kyc_sdk_kotlin.domain.Location
import com.dojah.kyc_sdk_kotlin.domain.BusinessData
import expo.modules.core.interfaces.ActivityEventListener
import expo.modules.kotlin.Promise
import expo.modules.kotlin.exception.CodedException
import expo.modules.kotlin.records.Field
import expo.modules.kotlin.records.Record

const val BACKWARD_CALL_REQUEST_CODE = 1001

class DojahKycSdkReactExpoModule : Module() {
    var mPromise: Promise? = null

    // Each module class must implement the definition function. The definition consists of components
    // that describes the module's functionality and behavior.
    // See https://docs.expo.dev/modules/module-api for more details about available components.
    override fun definition() = ModuleDefinition {
        // Sets the name of the module that JavaScript code will use to refer to the module. Takes a string as an argument.
        // Can be inferred from module's class name, but it's recommended to set it explicitly for clarity.
        // The module will be accessible from `requireNativeModule('DojahKycSdkReactExpo')` in JavaScript.
        Name("DojahKycSdk")

        // Defines event names that the module can send to JavaScript.
        Events("onChange")

        // Defines a JavaScript function that always returns a Promise and whose native code
        // is by default dispatched on the different thread than the JavaScript runtime runs on.
        AsyncFunction("launch") { widgetId: String, referenceId: String?, email: String?, extraData: ExtraDataRecord?, promise: Promise ->
            mPromise = promise
            val reactContext = appContext.reactContext
            val activity = appContext.currentActivity
            if (reactContext == null || activity == null)
                mPromise?.reject(CodedException("Activity does not exist"))
            else {
                try {
                    DojahSdk.with(reactContext)
                        .launchWithBackwardCompatibility(
                            activity,
                            widgetId,
                            referenceId,
                            email,
                            extraData = extraData?.toExtraUserData()?: ExtraUserData(),
                        )
                    Log.d("DojahKycSdk", "data passed -> ${extraData?.toExtraUserData()}")
                } catch (e: Exception) {
                    e.printStackTrace()
                    mPromise?.reject(CodedException("Error launching Dojah SDK"))
                }
            }
        }


        OnActivityResult { _, payload ->
            val requestCode = payload.requestCode
            val resultCode = payload.resultCode
            val data = payload.data
            if (requestCode == BACKWARD_CALL_REQUEST_CODE) {
                if (resultCode == Activity.RESULT_OK) {
                    val result = data?.getStringExtra(DOJAH_RESULT_KEY)
                    mPromise?.resolve(result)
                } else {
                    mPromise?.reject(CodedException("Activity did not return OK"))
                }
                mPromise = null
            }
        }


        // Enables the module to be used as a native view. Definition components that are accepted as part of
        // the view definition: Prop, Events.
        View(DojahKycSdkReactExpoView::class) {
            // Defines a setter for the `url` prop.
            Prop("url") { view: DojahKycSdkReactExpoView, url: URL ->
                view.webView.loadUrl(url.toString())
            }
            // Defines an event that the view can send to JavaScript.
            Events("onLoad")
        }
    }
}

class ExtraDataRecord : Record {
    @Field
    val userData: UserRecord? = null

    @Field
    val govData: GovDataRecord? = null

    @Field
    val govId: GovIdRecord? = null

    @Field
    val location: LocationRecord? = null

    @Field
    val businessData: BusinessDataRecord? = null

    @Field
    val address: String? = null

    @Field
    val metadata: Map<String, Any>? = null

    fun toExtraUserData(): ExtraUserData {
        return ExtraUserData(
            userData = userData?.toUserData(),
            govData = govData?.toGovData(),
            govId = govId?.toGovId(),
            location = location?.toLocation(),
            businessData = businessData?.toBusinessData(),
            address = address,
            metadata = metadata
        )
    }

}


class UserRecord : Record {
    @Field
    val firstName: String? = null

    @Field
    val lastName: String? = null

    @Field
    val dob: String? = null

    @Field
    val email: String? = null

    fun toUserData(): UserData {
        return UserData(
            firstName = firstName,
            lastName = lastName,
            dob = dob,
            email = email
        )
    }
}

class GovDataRecord : Record {
    @Field
    val bvn: String? = null

    @Field
    val dl: String? = null

    @Field
    val nin: String? = null

    @Field
    val vnin: String? = null

    fun toGovData(): GovData {
        return GovData(
            bvn = bvn,
            dl = dl,
            nin = nin,
            vnin = vnin
        )
    }
}

class GovIdRecord : Record {
    @Field
    val national: String? = null

    @Field
    val passport: String? = null

    @Field
    val dl: String? = null

    @Field
    val voter: String? = null

    @Field
    val nin: String? = null

    @Field
    val others: String? = null

    fun toGovId(): GovId {
        return GovId(
            national = national,
            passport = passport,
            dl = dl,
            voter = voter,
            nin = nin,
            others = others
        )
    }
}

class LocationRecord : Record {
    @Field
    val latitude: String? = null

    @Field
    val longitude: String? = null

    fun toLocation(): Location {
        return Location(
            latitude = latitude,
            longitude = longitude
        )
    }
}

class BusinessDataRecord : Record {
    @Field
    val cac: String? = null

    fun toBusinessData(): BusinessData {
        return BusinessData(
            cac = cac
        )
    }
}
