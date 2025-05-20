const {
  withPlugins,
  withAppBuildGradle,
  withSettingsGradle,
  withGradleProperties,
} = require('@expo/config-plugins');
const path = require('path');

const withDojahKyc = config => {
  return withPlugins(config, [
    // withAppBuildGradleModification,
    // withSettingsGradleModification,
    // withGradlePropertiesModification,
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

    // Add new entries
    config.modResults.push(
      [{
        key: 'org.gradle.jvmargs',
        value:
          '-Xmx4096m -XX:MaxMetaspaceSize=512m -XX:MaxPermSize=1024m -XX:+HeapDumpOnOutOfMemoryError -Dfile.encoding=UTF-8',
      },
      {
        key: 'android.enableJetifier',
        value: 'true',
      }]
    );

    return config;
  });
}



module.exports = withDojahKyc;
