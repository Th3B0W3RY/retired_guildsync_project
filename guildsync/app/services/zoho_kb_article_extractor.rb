# frozen_string_literal: true

# Extracts only the KB article content from a Zoho Desk portal page HTML,
# stripping portal chrome (header, nav, sidebar, scripts) so we cache and
# display just the article body.
class ZohoKbArticleExtractor
  # Selectors to try for the main article content (Zoho / common help-center patterns).
  ARTICLE_SELECTORS = [
    "article",
    "main",
    "[role='main']",
    ".article-body",
    ".article-content",
    ".articleBody",
    ".kb-article-body",
    ".kb-article-content",
    ".zd-article-content",
    ".hc-article-body",
    "[class*='article-body']",
    "[class*='articleBody']",
    "[class*='ArticleContent']",
    "[data-testid*='article']",
    ".content-area",
    "#content .article",
    ".prose",  # common for article text
  ].freeze

  class << self
    # @param raw_html [String] full HTML from GET portal article URL
    # @return [String, nil] extracted article HTML or nil if nothing useful
    def extract(raw_html)
      return nil if raw_html.blank?

      doc = Nokogiri::HTML(raw_html)
      # Strip scripts and styles so we never keep PortalInfo or other JS/CSS.
      doc.xpath("//script | //style").each(&:remove)

      # Try to find the article container.
      ARTICLE_SELECTORS.each do |selector|
        node = doc.at_css(selector)
        next unless node

        html = node.inner_html.to_s.strip
        next if html.blank?
        next if looks_like_portal_chrome?(html)

        return html if looks_like_article_content?(html)
      end

      # Fallback: look for article content in JSON inside script tags (SPA hydration).
      extracted = extract_from_script_json(raw_html)
      return extracted if extracted.present?

      # Last resort: find a node that contains article-like text (e.g. "Release Notes", "Version").
      find_node_with_article_text(doc)
    end

    private

    def looks_like_portal_chrome?(html)
      return true if html.length < 50
      # Portal nav/chrome often contains these.
      html.include?("PortalInfo") ||
        html.include?("Sign In") && html.include?("Knowledge Base") && html.length < 500
    end

    def looks_like_article_content?(html)
      return false if html.length < 20
      # Likely article if it has headings or paragraphs or list items.
      html.include?("<h") ||
        html.include?("<p>") ||
        html.include?("<li>") ||
        html.include?("Version ") ||
        html.include?("Release Notes")
    end

    def extract_from_script_json(raw_html)
      # Some portals embed article HTML or content in a script tag (e.g. __NEXT_DATA__, or article payload).
      doc = Nokogiri::HTML(raw_html)
      doc.xpath("//script[not(@src)]").each do |script|
        content = script.content.to_s
        next if content.blank? || content.length < 100

        # Look for JSON that might contain article body (e.g. "content": "<div>...", "body": "...")
        %w[content body articleContent html body_html].each do |key|
          # Match key in JSON with string value that looks like HTML.
          pattern = /["']#{key}["']\s*:\s*["'](<[^>]+[\s\S]*?)["']/m
          next unless content.match?(pattern)

          match = content.match(pattern)
          next unless match

          html = match[1].to_s
          html = unescape_json_string(html)
          next if html.blank? || html.length < 20
          next unless looks_like_article_content?(html)

          return html
        end
      end
      nil
    end

    def unescape_json_string(str)
      str.gsub(/\\x([0-9a-fA-F]{2})/) { |_| [Regexp.last_match(1).hex].pack("C") }
         .gsub(/\\"/, '"')
         .gsub(/\\\\/, "\\")
    end

    def find_node_with_article_text(doc)
      candidates = doc.xpath("//*[contains(., 'Release Notes') and (contains(., 'Version') or contains(., 'Updated'))]")
      candidates = candidates.reject { |n| %w[script style].include?(n.name) }
      candidates = candidates.map { |n| [n, n.inner_html.to_s.strip] }
                             .reject { |_, html| html.blank? || html.length < 30 }
                             .reject { |_, html| looks_like_portal_chrome?(html) }
                             .select { |_, html| looks_like_article_content?(html) }
      return nil if candidates.empty?

      # Prefer the smallest container (most specific).
      _, html = candidates.min_by { |_, html| html.length }
      html
    end
  end
end
