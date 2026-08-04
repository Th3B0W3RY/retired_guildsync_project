#!/usr/bin/env ruby
# frozen_string_literal: true

# Makes the favicon logo appear LARGER in the browser tab by trimming transparent
# edges and resizing so the logo fills the frame (instead of a tiny logo centered).
#
# Run from guildsync app root: bundle exec ruby script/expand_favicon.rb

require "bundler/setup"
require "mini_magick"

FAVICON_DIR = File.expand_path("app/assets/images/favicon", __dir__)

def expand_favicon(source_path, dest_path, size)
  img = MiniMagick::Image.open(source_path)
  img.trim
  img.resize "#{size}x#{size}"
  img.write dest_path
  puts "  #{File.basename(dest_path)} (logo expanded to fill #{size}x#{size})"
end

Dir.chdir(FAVICON_DIR) do
  source_32 = "favicon-32x32.png"
  source_16 = "favicon-16x16.png"
  raise "Missing #{source_32}" unless File.file?(source_32)
  raise "Missing #{source_16}" unless File.file?(source_16)

  puts "Expanding favicons so logo fills the frame..."
  expand_favicon(source_32, File.join(FAVICON_DIR, "favicon-32x32.png"), 32)
  expand_favicon(source_16, File.join(FAVICON_DIR, "favicon-16x16.png"), 16)
  puts "Done. Reload the site (hard refresh) to see the larger tab icon."
end
