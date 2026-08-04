const path = require("path")

module.exports = {
  entryPoints: ["app/javascript/application.js"],
  bundle: true,
  outdir: "app/assets/builds",
  absWorkingDir: path.join(process.cwd()),
  publicPath: "assets",
  watch: process.argv.includes("--watch"),
  plugins: [],
  loader: {
    ".js": "jsx",
    ".png": "file",
    ".jpg": "file",
    ".svg": "file"
  },
  target: "es2017",
  format: "esm",
  sourcemap: true
}

