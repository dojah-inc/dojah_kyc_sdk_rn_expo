# Dojah KYC SDK (React Native Expo)

## Installation

```sh
npm install dojah-kyc-sdk-react-expo
```


## Android Setup

### Requirements
* Minimum Android SDK version - 21
* Supported targetSdkVersion - 35


Enable jetifier in grade.properties:
```
android.enableJetifier=true
```

### Permissions

For Android you don't need to declare permissions, its already included in the Package.

## IOS Setup

### Requirements

* Minimum iOS version - 14

### Add the following POD dependencies in your Podfile app under your App target

```
  pod 'Realm', '~> 10.52.2', :modular_headers => true
  pod 'DojahWidget', :git => 'https://github.com/dojah-inc/sdk-swift.git', :branch => 'pod-package'
```

example

```
target 'Example' do
  ...
  pod 'Realm', '~> 10.52.2', :modular_headers => true
  pod 'DojahWidget', :git => 'https://github.com/dojah-inc/sdk-swift.git', :branch => 'pod-package'
  ...
end
```

and run pod install in your ios folder:

```sh
cd ios
pod install
```

### Permissions

For IOS, Add the following keys to your Info.plist file:

NSCameraUsageDescription - describe why your app needs access to the camera. This is called
Privacy - Camera Usage Description in the visual editor.

NSMicrophoneUsageDescription - describe why your app needs access to the microphone, if you intend
to record videos. This is called Privacy - Microphone Usage Description in the visual editor.

NSLocationWhenInUseUsageDescription - describe why your app needs access to the location, if you
intend to verify address/location. This is called Privacy - Location Usage Description in the visual
editor.

## Usage

To start KYC, import Dojah in your React Native code, and launch Dojah Screen

```js
import DojahKycSdk from 'dojah-kyc-sdk-react-expo';


/** 
 * The following parameters are available 
 * for launching the flow.
*/

/**
* This is your widget ID, a unique identifier for your Dojah flow. You can find it in your Dojah Dashboard after creating and publishing a flow. Replace `'your-widget-id'` with the actual widget ID from your dashboard.
*/
const widgetId = 'your-widget-id';

/**
 * Reference ID: This is an optional parameter that allows you to initialize the SDK for an ongoing verification process.
 */
const referenceId = 'your-reference-id';

/**
 * Email: This is an optional parameter that allows you to initialize the SDK with the user's email address.
 */
const email = 'your-email@example.com';

/**
 * User Data: This object contains personal information about the user, such as their first name, last name, date of birth, and email.
 */
    const userData = {
      firstName: 'John',
      lastName: 'Doe',
      dob: '1990-01-01',
      email: email
    };

/**
 * Government Data: This object contains government-issued identifiers such as BVN, driver's license, NIN, and voter ID.
 */
    const govData = {
      bvn: 'your-bvn',
      dl: 'your-dl',
      nin: 'your-nin',
      vnin: 'your-vnin'
    };

/**
 * Government ID: This object contains various types of government-issued IDs, such as national ID, passport, driver's license, voter ID, and others.
 */
    const govId = {
      national: 'your-national-id',
      passport: 'your-passport-id',
      dl: 'your-dl-id',
      voter: 'your-voter-id',
      nin: 'your-nin-id',
      others: 'your-others-id'
    };

/**
 * Location: This object contains the latitude and longitude of the user's location, which can be used for address verification.
 */
    const location = {
      latitude: 'your-latitude',
      longitude: 'your-longitude'
    };

/**
 * Business Data: This object contains business-related information, such as the CAC (Corporate Affairs Commission) registration number.
 */
    const businessData = {
      cac: 'your-cac'
    };

/**
 * Address: This is the user's address, which can be used for address verification.
 */
    const address = 'your-address';

/**
 * Metadata: This object contains additional key-value pairs that can be used to pass custom data to the SDK.
 */
    const metadata = {
      key1: 'value1',
      key2: 'value2'
    };

/** 
 * to launch the flow only [widgetId] is mandatory  
 * @returns - the Promise of the result, promise
 * will return a status that you can use to track 
 * the immidiate progress. 
 * @throws - an error if the Dojah KYC flow fails
*/

  const status = await DojahKycSdk.launch(widgetId, referenceId, email, {
    userData: userData,
    govData: govData,
    govId: govId,
    location: location,
    businessData: businessData,
    address: address,
    metadata: metadata
  });
  switch(status){
    case 'approved':
      //kyc approved
      console.log('KYC Approved');
      break;
    case 'pending':
      //kyc pending
      console.log('KYC Pending');
      break;
    case 'failed':
      //kyc failed
      console.log('KYC Failed');
      break;
    case 'closed':
      //user has cancelled the KYC
      console.log('KYC Closed');
  }
```

## How to Get a Widget ID
To use the SDK, you need a WidgetID, which is a required parameter for initializing the SDK. You can obtain this by creating a flow on the Dojah platform. Follow these steps to configure and get your Widget ID:

```txt
1. Log in to your Dojah Dashboard: If you don’t have an account, sign up on the Dojah platform.

2. Navigate to the EasyOnboard Feature: Once logged in, find the EasyOnboard section on your dashboard.

3. Create a Flow:

    - Click on the 'Create a Flow' button.
    - Name Your Flow: Choose a meaningful name for your flow, which will help you identify it later.

4. Add an Application:

    - Either create a new application or add an existing one.
    - Customise your widget with your brand logo and color by selecting an application.

5. Configure the Flow:

    - Select a Country: Choose the country or countries relevant to your verification process.
    - Select a Preview Process: Decide between automatic or manual verification.
    - Notification Type: Choose how you’d like to receive notifications for updates (email, SMS, etc.).
    - Add Verification Pages: Customize the verification steps in your flow (e.g., ID verification, address verification, etc.).

6. Publish Your Widget: After configuring your flow, publish the widget. Once published, your flow is live.

7. Copy Your Widget ID: After publishing, the platform will generate a Widget ID. Copy this Widget ID as you will need it to initialize the SDK as stated above.
```

