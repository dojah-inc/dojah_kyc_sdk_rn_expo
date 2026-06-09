const {
  withPlugins,
  withAppBuildGradle,
  withSettingsGradle,
  withGradleProperties,
  withAppDelegate,
  WarningAggregator,
} = require('@expo/config-plugins');

const path = require('path');

// Keep this in sync with `android/build.gradle` in this package.
const DESUGAR_JDK_LIBS = 'com.android.tools:desugar_jdk_libs:2.0.4';

const withDojahKyc = config => {
  return withPlugins(config, [
    // withAppBuildGradleModification,
    // withSettingsGradleModification,
    withGradlePropertiesModification,
    withAndroidCoreLibraryDesugaring,
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

/**
 * Enable Android core library desugaring on the host app's `android/app/build.gradle`.
 *
 * The Dojah Kotlin SDK (`com.github.dojah-inc:sdk-kotlin`) uses Java 8+ APIs that
 * are not available on older Android API levels. Without core library desugaring
 * enabled on the consuming `:app` module, AGP fails with:
 *
 *   Dependency 'com.github.dojah-inc:sdk-kotlin:...' requires core library
 *   desugaring to be enabled for :app.
 *
 * This modifier is idempotent: running `expo prebuild` multiple times will not
 * duplicate the inserted lines.
 */
function withAndroidCoreLibraryDesugaring(config) {
  return withAppBuildGradle(config, (config) => {
    if (config.modResults.language !== 'groovy') {
      WarningAggregator.addWarningAndroid(
        'withDojahKyc',
        'Cannot enable core library desugaring on non-Groovy app/build.gradle. ' +
          'Please enable it manually (see Dojah docs).'
      );
      return config;
    }

    let contents = config.modResults.contents;

    contents = ensureCompileOptionsWithDesugaring(contents);
    contents = ensureCoreLibraryDesugaringDependency(contents);

    config.modResults.contents = contents;
    return config;
  });
}

function ensureCompileOptionsWithDesugaring(contents) {
  if (/coreLibraryDesugaringEnabled\s+true/.test(contents)) {
    return contents;
  }

  // Try to extend an existing `compileOptions { ... }` block inside `android { ... }`.
  const compileOptionsRegex = /compileOptions\s*\{([\s\S]*?)\}/;
  const match = contents.match(compileOptionsRegex);
  if (match) {
    const inner = match[1];
    const additions = [];
    if (!/coreLibraryDesugaringEnabled/.test(inner)) {
      additions.push('        coreLibraryDesugaringEnabled true');
    }
    if (!/sourceCompatibility/.test(inner)) {
      additions.push('        sourceCompatibility JavaVersion.VERSION_1_8');
    }
    if (!/targetCompatibility/.test(inner)) {
      additions.push('        targetCompatibility JavaVersion.VERSION_1_8');
    }
    if (additions.length === 0) {
      return contents;
    }
    const updated = `compileOptions {${inner.trimEnd()}\n${additions.join('\n')}\n    }`;
    return contents.replace(compileOptionsRegex, updated);
  }

  // Otherwise inject a new compileOptions block right after `android {`.
  const androidBlockRegex = /android\s*\{/;
  if (!androidBlockRegex.test(contents)) {
    WarningAggregator.addWarningAndroid(
      'withDojahKyc',
      "Could not find `android { ... }` block in app/build.gradle. " +
        'Please enable core library desugaring manually.'
    );
    return contents;
  }

  const compileOptionsBlock =
    '\n    compileOptions {\n' +
    '        coreLibraryDesugaringEnabled true\n' +
    '        sourceCompatibility JavaVersion.VERSION_1_8\n' +
    '        targetCompatibility JavaVersion.VERSION_1_8\n' +
    '    }\n';

  return contents.replace(androidBlockRegex, (match) => `${match}${compileOptionsBlock}`);
}

function ensureCoreLibraryDesugaringDependency(contents) {
  if (/coreLibraryDesugaring\s+["']com\.android\.tools:desugar_jdk_libs/.test(contents)) {
    return contents;
  }

  const depLine = `    coreLibraryDesugaring '${DESUGAR_JDK_LIBS}'`;

  // Inject into the first top-level `dependencies { ... }` block.
  const dependenciesRegex = /(^|\n)dependencies\s*\{/;
  if (dependenciesRegex.test(contents)) {
    return contents.replace(dependenciesRegex, (match) => `${match}\n${depLine}`);
  }

  return `${contents}\n\ndependencies {\n${depLine}\n}\n`;
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
