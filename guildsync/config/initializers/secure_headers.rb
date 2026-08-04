# frozen_string_literal: true

SecureHeaders::Configuration.default do |config|
  config.x_frame_options = "DENY"
  config.x_content_type_options = "nosniff"
  config.x_xss_protection = "1; mode=block"
  config.x_download_options = "noopen"
  config.x_permitted_cross_domain_policies = "none"
  config.referrer_policy = "strict-origin-when-cross-origin"

        # Content Security Policy
        config.csp = {
          default_src: %w['self'],
          # Allow scripts from self, CDNs (for Stimulus, Tiptap, etc.), and unsafe-inline for development
          script_src: %w['self' https://cdn.jsdelivr.net https://unpkg.com https://challenges.cloudflare.com 'unsafe-inline'],
          script_src_elem: %w['self' https://cdn.jsdelivr.net https://unpkg.com https://challenges.cloudflare.com 'unsafe-inline'],
          script_src_attr: %w['self' 'unsafe-inline'],
          style_src: %w['self' 'unsafe-inline' https://fonts.googleapis.com https://cdnjs.cloudflare.com],
          img_src: %w['self' data: https:],
          font_src: %w['self' data: https://fonts.gstatic.com https://cdnjs.cloudflare.com],
          # Allow connections to CDNs for source maps and other resources
          connect_src: %w['self' https://cdn.jsdelivr.net https://unpkg.com https://challenges.cloudflare.com],
          frame_src: %w['self' https://discord.com https://challenges.cloudflare.com],
          frame_ancestors: %w['none']
        }
end
