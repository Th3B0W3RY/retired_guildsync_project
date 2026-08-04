# Pin npm packages by running ./bin/importmap

pin "application", preload: true

pin "@hotwired/stimulus", to: "https://cdn.jsdelivr.net/npm/@hotwired/stimulus@3.2.2/dist/stimulus.js", preload: true

# Tiptap packages - using local vendor files (no CDN)
pin "@tiptap/core", to: "vendor/tiptap-core.js"
pin "@tiptap/starter-kit", to: "vendor/tiptap-starter-kit.js"
pin "@tiptap/extension-link", to: "vendor/tiptap-extension-link.js"

# Our controllers entry file
pin "controllers", to: "controllers/index.js"

# Map everything under app/javascript/controllers/*
pin_all_from "app/javascript/controllers", under: "controllers"
