#!/usr/bin/env ruby
# frozen_string_literal: true

# Generates missing favicon assets using MiniMagick (from image_processing gem):
# - android-chrome-48x48.png, 72x72.png, 144x144.png (from 512x512 source)
# - favicon.ico (multi-size from 16, 32, 48 PNGs)
#
# Run from app root: bundle exec ruby script/generate_favicons.rb

require "bundler/setup"
require "mini_magick"

FAVICON_DIR = File.expand_path("../app/assets/images/favicon", __dir__)

def source_path(name)
  path = File.join(FAVICON_DIR, name)
  raise "Source missing: #{path}" unless File.file?(path)
  path
end

def dest_path(name)
  File.join(FAVICON_DIR, name)
end

Dir.chdir(FAVICON_DIR) do
  # Android Chrome sizes missing from ZIP: 48, 72, 144 (generate from 512)
  source_512 = source_path("android-chrome-512x512.png")
  [ [48, "android-chrome-48x48.png"],
    [72, "android-chrome-72x72.png"],
    [144, "android-chrome-144x144.png"],
  ].each do |size, filename|
    next if File.file?(filename)
    puts "Generating #{filename}..."
    img = MiniMagick::Image.open(source_512)
    img.resize "#{size}x#{size}"
    img.write dest_path(filename)
  end

  # favicon.ico (multi-size from existing PNGs)
  ico_name = "favicon.ico"
  png_names = %w[favicon-16x16.png favicon-32x32.png favicon-48x48.png]
  ico_path = dest_path(ico_name)
  png_paths = png_names.map { |f| source_path(f) }
  skip_ico = File.file?(ico_path) && png_paths.all? { |p| File.mtime(p) <= File.mtime(ico_path) }
  unless skip_ico
    puts "Generating favicon.ico..."
    MiniMagick::Tool::Convert.new do |c|
      png_names.each { |n| c << n }
      c << ico_name
    end
  end
end

puts "Done."
