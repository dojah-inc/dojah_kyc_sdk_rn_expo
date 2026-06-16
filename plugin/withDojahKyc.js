const {
  withPlugins,
  withAndroidManifest,
  withAppBuildGradle,
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
// Expo SDK 54 defaults to `compileSdk 35` and AGP `8.8.2`, so the host app
// build fails at `:app:checkDebugAarMetadata` unless these are raised. This
// plugin bumps them automatically during prebuild. Keep these in sync with the
// "Android requirements" section of the README.
const REQUIRED_COMPILE_SDK_VERSION = 36;
const REQUIRED_TARGET_SDK_VERSION = 36;
const REQUIRED_BUILD_TOOLS_VERSION = '36.0.0';
const REQUIRED_AGP_VERSION = '8.9.1';
// AGP 8.9.1 requires Gradle 8.11.1+. Expo SDK 54 already ships a newer Gradle,
// but we bump older wrappers (e.g. SDK 53) so the forced AGP can run.
const REQUIRED_GRADLE_VERSION = '8.11.1';

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

    // AGP only "supports" a known set of compileSdk levels and otherwise emits
    // a build-failing warning. We force AGP 8.9.1 (which supports API 36)
    // below, but keep this as a safety net for stricter setups.
    setGradleProperty(
      config.modResults,
      'android.suppressUnsupportedCompileSdk',
      String(REQUIRED_COMPILE_SDK_VERSION)
    );

    return config;
  });
}

function findGradleProperty(modResults, key) {
  return modResults.find(
    (item) => item && item.type === 'property' && item.key === key
  );
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

/**
 * Force the Android Gradle Plugin version on the host app's root
 * `android/build.gradle`.
 *
 * `androidx.core:core[-ktx]:1.18.0` (pulled in transitively by the Dojah Kotlin
 * SDK) hard-requires AGP 8.9.1+; older AGP fails the build at
 * `:app:checkDebugAarMetadata`. Expo SDK 54 cannot raise AGP via
 * `expo-build-properties`, so we pin it with a buildscript resolution strategy
 * (the highest-priority override, beating version-catalog constraints).
 *
 * Idempotent: re-running prebuild updates the forced version in place instead of
 * appending duplicate blocks.
 */
function withDojahAndroidGradlePluginVersion(config) {
  return withProjectBuildGradle(config, (config) => {
    if (config.modResults.language !== 'groovy') {
      WarningAggregator.addWarningAndroid(
        'withDojahKyc',
        'Cannot force the Android Gradle Plugin version on a non-Groovy ' +
          `root build.gradle. Please ensure AGP ${REQUIRED_AGP_VERSION}+ ` +
          'is used (see Dojah docs).'
      );
      return config;
    }

    let contents = config.modResults.contents;
    const forceLineRegex =
      /force\(["']com\.android\.tools\.build:gradle:[^"')]+["']\)/;

    if (forceLineRegex.test(contents)) {
      contents = contents.replace(
        forceLineRegex,
        `force("com.android.tools.build:gradle:${REQUIRED_AGP_VERSION}")`
      );
    } else {
      contents += `
// @dojah-kyc-sdk: pin Android Gradle Plugin to a version compatible with the
// Dojah Kotlin SDK (androidx.core 1.18.0 requires AGP ${REQUIRED_AGP_VERSION}+).
buildscript {
    configurations.classpath {
        resolutionStrategy {
            force("com.android.tools.build:gradle:${REQUIRED_AGP_VERSION}")
        }
    }
}
`;
    }

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


module.exports = withDojahKyc;
