const {
  withPlugins,
  withAppBuildGradle,
  withSettingsGradle,
  withGradleProperties,
  withAppDelegate,
  WarningAggregator,
} = require('@expo/config-plugins');

const path = require('path');

const withDojahKyc = config => {
  return withPlugins(config, [
    // withAppBuildGradleModification,
    // withSettingsGradleModification,
    withGradlePropertiesModification,
    withCustomSwiftAppDelegateRootView,
    withCustomObjcAppDelegateRootView,
  ]);
};


function withAppBuildGradleModification(config) {
  return withAppBuildGradle(config, config => {
    if (!config.modResults.contents.includes("project(':dojah_Kyc_rn_expo')")) {
      config.modResults.contents += `
        dependencies {
            implementation project(':dojah_Kyc_rn_expo')
        }
      `;
    }
    return config;
  });
}

function withSettingsGradleModification(config) {
  return withSettingsGradle(config, config => {
    if (!config.modResults.contents.includes("include ':dojah_Kyc_rn_expo'")) {
      config.modResults.contents += `
        include ':dojah_Kyc_rn_expo'
        project(':dojah_Kyc_rn_expo').projectDir = new File(rootProject.projectDir, '../node_modules/dojah-kyc-sdk-react-expo/android')
      `;
    }
    return config;
  });
}

function withGradlePropertiesModification(config) {
  return withGradleProperties(config, (config) => {

    if (!config.modResults) {
      config.modResults = [];
    }

    [
      {
        type: 'property',
        key: 'android.enableJetifier',
        value: 'true',
      }
    ].map((entry) => {
      config.modResults.push(entry);
    });

    return config;
  });
}


const CUSTOM_CREATE_ROOT_VIEW = `
  override func createRootViewController() -> UIViewController {
    let rootVC = UIViewController()
    let nav = UINavigationController(rootViewController: rootVC)
    return nav
  }

  override func setRootView(_ rootView: UIView, toRootViewController rootViewController: UIViewController) {
    if let nav = rootViewController as? UINavigationController,
       let firstVC = nav.viewControllers.first {
      firstVC.view = rootView
    } else {
      rootViewController.view = rootView
    }
  }
`;

const withCustomSwiftAppDelegateRootView = config => {
  return withAppDelegate(config, config => {
    const contents = config.modResults.contents;

    const classStart = contents.indexOf("class ReactNativeDelegate");
    if (classStart === -1) {
      WarningAggregator.addWarningIOS(
        "withCustomRootView",
        "`ReactNativeDelegate` not found in AppDelegate.swift"
      );
      return config;
    }

    const insertionPoint = contents.indexOf("{", classStart) + 1;

    const newContents =
      contents.slice(0, insertionPoint) +
      "\n" +
      CUSTOM_CREATE_ROOT_VIEW +
      "\n" +
      contents.slice(insertionPoint);

    config.modResults.contents = newContents;

    return config;
  });
};

const NAV_CONTROLLER_SETUP = `
  // Injected by withObjcNavigationRoot config plugin
  RCTBridge *bridge = [[RCTBridge alloc] initWithDelegate:self launchOptions:launchOptions];
  RCTRootView *rootView = [[RCTRootView alloc] initWithBridge:bridge
                                                   moduleName:@"main"
                                            initialProperties:nil];

  UIViewController *rootViewController = [UIViewController new];
  rootViewController.view = rootView;

  UINavigationController *navigationController = [[UINavigationController alloc] initWithRootViewController:rootViewController];

  self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
  self.window.rootViewController = navigationController;
  [self.window makeKeyAndVisible];
`;

const withCustomObjcAppDelegateRootView = config => {
  return withAppDelegate(config, config => {
    let contents = config.modResults.contents;

    // Check it's Obj-C
    if (!contents.includes("@implementation AppDelegate")) {
      WarningAggregator.addWarningIOS(
        "withObjcNavigationRoot",
        "AppDelegate.m does not appear to be an Objective-C file."
      );
      return config;
    }

    // Match the method and locate the `return` statement
    const didFinishPattern = /(-\s*\(BOOL\)application:\(UIApplication \*\)application didFinishLaunchingWithOptions:\(NSDictionary \*\)launchOptions\s*\{)([\s\S]*?)(\s+return\s+\[super application:application didFinishLaunchingWithOptions:launchOptions];[\s\S]*?\})/;

    const match = contents.match(didFinishPattern);

    if (!match) {
      WarningAggregator.addWarningIOS(
        "withObjcNavigationRoot",
        "`application:didFinishLaunchingWithOptions:` method not found in AppDelegate.m"
      );
      return config;
    }

    const [fullMatch, methodStart, methodBody, methodEnd] = match;

    // Inject just before the return
    const updatedBody = `${methodBody.trimEnd()}\n${NAV_CONTROLLER_SETUP}\n`;

    const newMethod = `${methodStart}${updatedBody}${methodEnd}`;
    contents = contents.replace(didFinishPattern, newMethod);

    config.modResults.contents = contents;
    return config;
  });
};


module.exports = withDojahKyc;
