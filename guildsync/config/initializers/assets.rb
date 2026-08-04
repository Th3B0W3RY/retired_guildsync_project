# Configure additional asset paths and precompiled assets for favicons.
#
# This keeps favicon assets in a dedicated folder and ensures they are
# available under /assets/favicon/* in production.

Rails.application.config.assets.paths << Rails.root.join("app", "assets", "images", "favicon")
Rails.application.config.assets.paths << Rails.root.join("app", "assets", "videos")

Rails.application.config.assets.precompile += %w[
  favicon/favicon.ico
  favicon/favicon-16x16.png
  favicon/favicon-32x32.png
  favicon/favicon-48x48.png
  favicon/favicon-64x64.png
  favicon/apple-touch-icon-57x57.png
  favicon/apple-touch-icon-60x60.png
  favicon/apple-touch-icon-72x72.png
  favicon/apple-touch-icon-76x76.png
  favicon/apple-touch-icon-114x114.png
  favicon/apple-touch-icon-120x120.png
  favicon/apple-touch-icon-144x144.png
  favicon/apple-touch-icon-152x152.png
  favicon/apple-touch-icon-167x167.png
  favicon/apple-touch-icon-180x180.png
  favicon/apple-touch-icon-1024x1024.png
  favicon/android-chrome-36x36.png
  favicon/android-chrome-48x48.png
  favicon/android-chrome-72x72.png
  favicon/android-chrome-96x96.png
  favicon/android-chrome-144x144.png
  favicon/android-chrome-192x192.png
  favicon/android-chrome-256x256.png
  favicon/android-chrome-384x384.png
  favicon/android-chrome-512x512.png
  favicon/mstile-70x70.png
  favicon/mstile-150x150.png
  favicon/mstile-310x150.png
  favicon/mstile-310x310.png
  hero-background.mp4
  landing/hero-poster.jpg
]

