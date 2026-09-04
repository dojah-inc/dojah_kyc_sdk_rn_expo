const {
  withPlugins,
  withAndroidManifest,
  withAppBuildGradle,
  withMainActivity,
  withProjectBuildGradle,
  withSettingsGradle,
  withGradleProperties,
  withDangerousMod,
  WarningAggregator,
} = require('@expo/config-plugins');

const fs = require('fs');
const path = require('path');

// Keep this in sync with `android/build.gradle` in this package.
const DESUGAR_JDK_LIBS = 'com.android.tools:desugar_jdk_libs:2.0.4';

// Minimum Android tooling required by the Dojah Kotlin SDK
// (`com.github.dojah-inc:sdk-kotlin`). As of `v0.3.4` the SDK and its
// transitive dependencies (`androidx.core:core[-ktx]:1.18.0`,
// `se.warting.signature:*`) compile against Android API 36 and declare that
// consumers must use Android Gradle Plugin 8.9.1+.
//
// Older Expo SDKs default below these values, so the host app build fails at
// `:app:checkDebugAarMetadata` unless they are raised. This plugin bumps them
// automatically during prebuild. Every value here is a minimum: newer hosts
// keep what they already ship (React Native 0.81, for example, uses AGP
// 8.11.0). Keep these in sync with the "Android requirements" section of the
// README.
const REQUIRED_COMPILE_SDK_VERSION = 36;
const REQUIRED_TARGET_SDK_VERSION = 36;
const REQUIRED_BUILD_TOOLS_VERSION = '36.0.0';
const REQUIRED_AGP_VERSION = '8.9.1';
// AGP 8.9.1 requires Gradle 8.11.1+. Expo SDK 54 already ships a newer Gradle,
// but we bump older wrappers (e.g. SDK 53) so the required AGP can run.
const REQUIRED_GRADLE_VERSION = '8.11.1';

// `com.github.dojah-inc:sdk-kotlin` is compiled with Kotlin 2.2.10: its classes
// carry Kotlin metadata version 2.2.0 and it declares `kotlin-stdlib:2.2.10` as
// an api dependency. React Native 0.81 / Expo SDK 54 default to Kotlin 2.1.20,
// whose compiler only reads metadata up to 2.1.0, so
// `:dojah-kyc-sdk-react-expo:compileReleaseKotlin` dies with "Internal compiler
// error" while reading the SDK.
//
// Expo resolves the matching KSP release from this value (its lookup table maps
// 2.2.10 -> 2.2.10-2.0.2), so consumers must not pin `android.kspVersion`
// themselves. Keep this in sync with the version the Kotlin SDK is built with.
const REQUIRED_KOTLIN_VERSION = '2.2.10';

// Gradle properties this plugin manages. Versions of the plugin up to 0.1.21
// appended `android.enableJetifier` on every prebuild instead of replacing it,
// so existing projects can carry duplicates that we clean up.
const MANAGED_GRADLE_PROPERTIES = [
  'android.enableJetifier',
  'android.compileSdkVersion',
  'android.targetSdkVersion',
  'android.buildToolsVersion',
  'android.kotlinVersion',
  'android.suppressUnsupportedCompileSdk',
];

// The Dojah Kotlin SDK (`com.github.dojah-inc:sdk-kotlin`) declares the legacy
// storage permissions with `android:maxSdkVersion="28"`. Other Expo libraries
// (e.g. `expo-image`) declare the same permissions with a higher
// `maxSdkVersion`, which makes the Android manifest merger fail with a
// conflicting-attribute error. Google recommends `maxSdkVersion="32"` when
// supporting pre-Android-13 devices, so we override the value at the app level
// (highest merge priority) and tell the merger to replace conflicting values.
const STORAGE_PERMISSION_MAX_SDK_VERSION = '32';
const STORAGE_PERMISSIONS = [
  'android.permission.READ_EXTERNAL_STORAGE',
  'android.permission.WRITE_EXTERNAL_STORAGE',
];

const withDojahKyc = config => {
  return withPlugins(config, [
    // withAppBuildGradleModification,
    // withSettingsGradleModification,
    withGradlePropertiesModification,
    withDojahAndroidSdkVersions,
    withDojahAndroidGradlePluginVersion,
    withDojahGradleWrapperVersion,
    withAndroidCoreLibraryDesugaring,
    withDojahStoragePermissionMaxSdk,
    withDojahOnUserLeaveHintGuard,
  ]);
};

/**
 * Compare two dotted version strings (e.g. `8.9.1`).
 *
 * @returns negative if `a < b`, `0` if equal, positive if `a > b`.
 */
function compareVersions(a, b) {
  const pa = String(a).split('.').map((n) => parseInt(n, 10) || 0);
  const pb = String(b).split('.').map((n) => parseInt(n, 10) || 0);
  const length = Math.max(pa.length, pb.length);
  for (let i = 0; i < length; i++) {
    const diff = (pa[i] || 0) - (pb[i] || 0);
    if (diff !== 0) {
      return diff;
    }
  }
  return 0;
}

/**
 * Raise the Android SDK build properties consumed by the host app so they meet
 * the Dojah Kotlin SDK's minimums.
 *
 * Expo writes these keys to `android/gradle.properties`, where the
 * `expo-root-project` Gradle plugin reads them into `rootProject.ext.*`. We
 * never *lower* a value the developer has already set higher.
 */
function withDojahAndroidSdkVersions(config) {
  return withGradleProperties(config, (config) => {
    if (!config.modResults) {
      config.modResults = [];
    }

    ensureMinIntGradleProperty(
      config.modResults,
      'android.compileSdkVersion',
      REQUIRED_COMPILE_SDK_VERSION
    );
    ensureMinIntGradleProperty(
      config.modResults,
      'android.targetSdkVersion',
      REQUIRED_TARGET_SDK_VERSION
    );
    ensureMinVersionGradleProperty(
      config.modResults,
      'android.buildToolsVersion',
      REQUIRED_BUILD_TOOLS_VERSION
    );
    ensureMinVersionGradleProperty(
      config.modResults,
      'android.kotlinVersion',
      REQUIRED_KOTLIN_VERSION
    );

    warnOnMismatchedKspVersion(config.modResults);

    // AGP only "supports" a known set of compileSdk levels and otherwise emits
    // a build-failing warning. We require AGP 8.9.1+ (which supports API 36)
    // below, but keep this as a safety net for stricter setups.
    setGradleProperty(
      config.modResults,
      'android.suppressUnsupportedCompileSdk',
      String(REQUIRED_COMPILE_SDK_VERSION)
    );

    return config;
  });
}

/**
 * Warn when the host app pins `android.kspVersion` to a release that does not
 * belong to the Kotlin version we just set.
 *
 * Expo derives KSP from `android.kotlinVersion` automatically, but an explicit
 * `android.kspVersion` wins over that lookup. A stale pin (e.g. the Expo SDK 54
 * default `2.1.20-2.0.1`) then fails the build in a way that looks unrelated to
 * the Kotlin version.
 */
function warnOnMismatchedKspVersion(modResults) {
  const ksp = findGradleProperty(modResults, 'android.kspVersion');
  if (!ksp) {
    return;
  }

  const kotlin = findGradleProperty(modResults, 'android.kotlinVersion');
  const kotlinVersion = kotlin ? kotlin.value : REQUIRED_KOTLIN_VERSION;

  if (!String(ksp.value).startsWith(`${kotlinVersion}-`)) {
    WarningAggregator.addWarningAndroid(
      'withDojahKyc',
      `android.kspVersion is pinned to "${ksp.value}", which does not match ` +
        `Kotlin ${kotlinVersion}. Remove the pin so Expo can resolve the ` +
        'matching KSP release, or update it to a KSP build for that Kotlin ' +
        'version.'
    );
  }
}

function findGradleProperty(modResults, key) {
  return modResults.find(
    (item) => item && item.type === 'property' && item.key === key
  );
}

/**
 * Collapse repeated entries for `key` down to a single one.
 *
 * Gradle honours the last occurrence in a properties file, so that is the one
 * we keep.
 */
function dedupeGradleProperty(modResults, key) {
  const matches = modResults.filter(
    (item) => item && item.type === 'property' && item.key === key
  );

  matches.slice(0, -1).forEach((duplicate) => {
    modResults.splice(modResults.indexOf(duplicate), 1);
  });
}

function setGradleProperty(modResults, key, value) {
  const existing = findGradleProperty(modResults, key);
  if (existing) {
    existing.value = value;
  } else {
    modResults.push({ type: 'property', key, value });
  }
}

function ensureMinIntGradleProperty(modResults, key, minValue) {
  const existing = findGradleProperty(modResults, key);
  if (!existing) {
    modResults.push({ type: 'property', key, value: String(minValue) });
    return;
  }
  const current = parseInt(existing.value, 10);
  if (Number.isNaN(current) || current < minValue) {
    existing.value = String(minValue);
  }
}

function ensureMinVersionGradleProperty(modResults, key, minValue) {
  const existing = findGradleProperty(modResults, key);
  if (!existing) {
    modResults.push({ type: 'property', key, value: minValue });
    return;
  }
  if (compareVersions(existing.value, minValue) < 0) {
    existing.value = minValue;
  }
}

// Markers used to keep the AGP injection idempotent across repeated prebuilds.
const AGP_FLOOR_MARKER = '@dojah-kyc-sdk: Android Gradle Plugin floor';
const AGP_FLOOR_BLOCK_REGEX = new RegExp(
  `\\n// ${AGP_FLOOR_MARKER}[\\s\\S]*?\\n\\}\\n`
);
// Plugin versions up to 0.1.21 wrote a `force(...)` block that pinned AGP
// exactly, downgrading hosts that shipped something newer.
const LEGACY_AGP_FORCE_BLOCK_REGEX =
  /\n\/\/ @dojah-kyc-sdk: pin Android Gradle Plugin[\s\S]*?\n\}\n/;

/**
 * Raise the Android Gradle Plugin version on the host app's root
 * `android/build.gradle` to the minimum the Dojah Kotlin SDK needs.
 *
 * `androidx.core:core[-ktx]:1.18.0` (pulled in transitively by the Dojah Kotlin
 * SDK) hard-requires AGP 8.9.1+; older AGP fails the build at
 * `:app:checkDebugAarMetadata`. Expo SDK 54 cannot raise AGP via
 * `expo-build-properties`, so we add a buildscript constraint here.
 *
 * This is a floor, not a pin. Gradle resolves `require` to the highest version
 * any participant asks for, so a host that already uses something newer (React
 * Native 0.81 ships AGP 8.11.0) keeps its version.
 *
 * Idempotent: re-running prebuild rewrites our block rather than appending a
 * second one, and migrates the pinning block written by earlier versions.
 */
function withDojahAndroidGradlePluginVersion(config) {
  return withProjectBuildGradle(config, (config) => {
    if (config.modResults.language !== 'groovy') {
      WarningAggregator.addWarningAndroid(
        'withDojahKyc',
        'Cannot raise the Android Gradle Plugin version on a non-Groovy ' +
          `root build.gradle. Please ensure AGP ${REQUIRED_AGP_VERSION}+ ` +
          'is used (see Dojah docs).'
      );
      return config;
    }

    let contents = config.modResults.contents;

    contents = contents.replace(LEGACY_AGP_FORCE_BLOCK_REGEX, '');
    contents = contents.replace(AGP_FLOOR_BLOCK_REGEX, '');

    contents += `
// ${AGP_FLOOR_MARKER}
// androidx.core 1.18.0, pulled in transitively by the Dojah Kotlin SDK, requires
// AGP ${REQUIRED_AGP_VERSION}+. This constraint only raises the version: Gradle keeps a
// newer AGP when the host app or React Native asks for one.
buildscript {
    dependencies {
        constraints {
            classpath("com.android.tools.build:gradle") {
                version {
                    require "${REQUIRED_AGP_VERSION}"
                }
            }
        }
    }
}
`;

    config.modResults.contents = contents;
    return config;
  });
}

/**
 * Ensure the Gradle wrapper is new enough to run the forced AGP version.
 *
 * AGP 8.9.1 requires Gradle 8.11.1+. We only raise the wrapper when it is lower,
 * preserving newer wrappers shipped by Expo SDK 54+.
 */
function withDojahGradleWrapperVersion(config) {
  return withDangerousMod(config, [
    'android',
    (config) => {
      const wrapperPath = path.join(
        config.modRequest.platformProjectRoot,
        'gradle',
        'wrapper',
        'gradle-wrapper.properties'
      );

      if (!fs.existsSync(wrapperPath)) {
        WarningAggregator.addWarningAndroid(
          'withDojahKyc',
          'Could not find gradle-wrapper.properties. Please ensure Gradle ' +
            `${REQUIRED_GRADLE_VERSION}+ is used (required by AGP ` +
            `${REQUIRED_AGP_VERSION}).`
        );
        return config;
      }

      let contents = fs.readFileSync(wrapperPath, 'utf8');
      const distRegex =
        /distributionUrl=.*gradle-([\d.]+)-(all|bin)\.zip/;
      const match = contents.match(distRegex);

      if (match && compareVersions(match[1], REQUIRED_GRADLE_VERSION) < 0) {
        contents = contents.replace(
          distRegex,
          'distributionUrl=https\\://services.gradle.org/distributions/' +
            `gradle-${REQUIRED_GRADLE_VERSION}-${match[2]}.zip`
        );
        fs.writeFileSync(wrapperPath, contents);
      }

      return config;
    },
  ]);
}


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

    MANAGED_GRADLE_PROPERTIES.forEach((key) => {
      dedupeGradleProperty(config.modResults, key);
    });

    setGradleProperty(config.modResults, 'android.enableJetifier', 'true');

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

/**
 * Resolve the Android manifest merger conflict between the Dojah Kotlin SDK and
 * other Expo libraries (notably `expo-image`) over the legacy storage
 * permissions.
 *
 * The Dojah SDK ships `READ_EXTERNAL_STORAGE` / `WRITE_EXTERNAL_STORAGE` with
 * `android:maxSdkVersion="28"`, while `expo-image` ships them with a higher
 * `maxSdkVersion`. Without intervention the merger aborts with:
 *
 *   Attribute uses-permission#android.permission.READ_EXTERNAL_STORAGE@maxSdkVersion
 *   value=(28) ... is also present at [expo-image] value=(33).
 *   Suggestion: add 'tools:replace="android:maxSdkVersion"' ...
 *
 * We force `maxSdkVersion="32"` at the app level (the highest-priority manifest)
 * and add `tools:replace` so the app value wins over every library. `32` keeps
 * the permission active on Android 9–12L (instead of cutting it off at 28),
 * which matches Google's guidance for apps still supporting pre-Android-13
 * devices.
 *
 * This modifier is idempotent: it updates the existing entry in place rather
 * than appending duplicates on repeated `expo prebuild` runs.
 */
function withDojahStoragePermissionMaxSdk(config) {
  return withAndroidManifest(config, (config) => {
    const manifest = config.modResults.manifest;

    // Ensure the `tools` namespace exists so `tools:replace` is valid.
    manifest.$ = manifest.$ || {};
    if (!manifest.$['xmlns:tools']) {
      manifest.$['xmlns:tools'] = 'http://schemas.android.com/tools';
    }

    const permissions = manifest['uses-permission'] || [];

    STORAGE_PERMISSIONS.forEach((permissionName) => {
      let entry = permissions.find(
        (item) => item.$ && item.$['android:name'] === permissionName
      );

      if (!entry) {
        entry = { $: { 'android:name': permissionName } };
        permissions.push(entry);
      }

      entry.$['android:maxSdkVersion'] = STORAGE_PERMISSION_MAX_SDK_VERSION;
      entry.$['tools:replace'] = 'android:maxSdkVersion';
    });

    manifest['uses-permission'] = permissions;

    return config;
  });
}


// Marker used to keep the injection idempotent across repeated `expo prebuild` runs.
const ON_USER_LEAVE_HINT_MARKER = '@dojah-kyc-sdk: onUserLeaveHint guard';

const ON_USER_LEAVE_HINT_METHOD_KOTLIN = `
  // ${ON_USER_LEAVE_HINT_MARKER}
  // Works around a React Native 0.79 crash: ReactActivityDelegate.onUserLeaveHint
  // calls Objects.requireNonNull(getReactHost()) on the New Architecture, but
  // getReactHost() can be null while the activity is leaving (e.g. when the Dojah
  // SDK launches its native verification flow over the React activity). Swallowing
  // the NPE keeps the host app from crashing; the leave hint is non-critical.
  override fun onUserLeaveHint() {
    try {
      super.onUserLeaveHint()
    } catch (e: NullPointerException) {
      android.util.Log.w("DojahKyc", "Ignored NPE from onUserLeaveHint (ReactHost not ready)", e)
    }
  }
`;

const ON_USER_LEAVE_HINT_METHOD_JAVA = `
  // ${ON_USER_LEAVE_HINT_MARKER}
  // Works around a React Native 0.79 crash: ReactActivityDelegate.onUserLeaveHint
  // calls Objects.requireNonNull(getReactHost()) on the New Architecture, but
  // getReactHost() can be null while the activity is leaving (e.g. when the Dojah
  // SDK launches its native verification flow over the React activity). Swallowing
  // the NPE keeps the host app from crashing; the leave hint is non-critical.
  @Override
  public void onUserLeaveHint() {
    try {
      super.onUserLeaveHint();
    } catch (NullPointerException e) {
      android.util.Log.w("DojahKyc", "Ignored NPE from onUserLeaveHint (ReactHost not ready)", e);
    }
  }
`;

/**
 * Inject an `onUserLeaveHint` override into the host app's `MainActivity` that
 * guards against a React Native 0.79 NullPointerException.
 *
 * On the New Architecture, `ReactActivityDelegate.onUserLeaveHint` executes
 * `Objects.requireNonNull(getReactHost())`. When the Dojah SDK launches its own
 * native activity over the React activity, Android delivers `onUserLeaveHint`
 * while `getReactHost()` is momentarily null, throwing an NPE that crashes the
 * host app. RN 0.79.1 does not include the upstream null-check fix, so we inject
 * a defensive override here.
 *
 * Idempotent: repeated `expo prebuild` runs detect the marker and skip.
 */
function withDojahOnUserLeaveHintGuard(config) {
  return withMainActivity(config, (config) => {
    let contents = config.modResults.contents;
    const language = config.modResults.language;

    if (contents.includes(ON_USER_LEAVE_HINT_MARKER)) {
      return config;
    }

    if (language === 'kt') {
      // Insert right after the MainActivity class body opens.
      const classBodyRegex = /(class\s+MainActivity\s*:\s*ReactActivity\s*\([^)]*\)\s*\{)/;
      if (!classBodyRegex.test(contents)) {
        WarningAggregator.addWarningAndroid(
          'withDojahKyc',
          'Could not locate the MainActivity class body to inject the ' +
            'onUserLeaveHint guard. If your app crashes on Android with a ' +
            'NullPointerException in ReactActivityDelegate.onUserLeaveHint, add ' +
            'the override manually (see Dojah docs).'
        );
        return config;
      }
      contents = contents.replace(
        classBodyRegex,
        (match) => `${match}\n${ON_USER_LEAVE_HINT_METHOD_KOTLIN}`
      );
    } else if (language === 'java') {
      const classBodyRegex = /(class\s+MainActivity\s+extends\s+ReactActivity\s*\{)/;
      if (!classBodyRegex.test(contents)) {
        WarningAggregator.addWarningAndroid(
          'withDojahKyc',
          'Could not locate the MainActivity class body to inject the ' +
            'onUserLeaveHint guard. If your app crashes on Android with a ' +
            'NullPointerException in ReactActivityDelegate.onUserLeaveHint, add ' +
            'the override manually (see Dojah docs).'
        );
        return config;
      }
      contents = contents.replace(
        classBodyRegex,
        (match) => `${match}\n${ON_USER_LEAVE_HINT_METHOD_JAVA}`
      );
    } else {
      WarningAggregator.addWarningAndroid(
        'withDojahKyc',
        `Unsupported MainActivity language "${language}". Could not inject the ` +
          'onUserLeaveHint guard automatically.'
      );
      return config;
    }

    config.modResults.contents = contents;
    return config;
  });
}

module.exports = withDojahKyc;
