const withDojahKyc = require('./plugin/withDojahKyc');

module.exports = function withPlugin(config) {
  return withDojahKyc(config);
};
