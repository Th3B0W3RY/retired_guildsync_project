# frozen_string_literal: true

namespace :guildsync do
  desc "Build JS (esbuild) and Tailwind CSS into app/assets/builds for rails server -e test and Playwright"
  task :integration_assets do
    root = Pathname.new(__dir__).join("../..").expand_path
    Dir.chdir(root) do
      abort("npm run build failed") unless system("npm run build")
      abort("npm run build:css failed") unless system("npm run build:css")
    end
    puts "guildsync:integration_assets — wrote app/assets/builds/application.js and tailwind.css"
  end
end
