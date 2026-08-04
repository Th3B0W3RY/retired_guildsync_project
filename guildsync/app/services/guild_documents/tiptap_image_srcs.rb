# frozen_string_literal: true

module GuildDocuments
  # Collects image `src` URLs from TipTap JSON document content (see editor_controller.js).
  module TiptapImageSrcs
    module_function

    def from_node(node)
      out = []
      walk(node) { |src| out << src }
      out.compact.uniq
    end

    def walk(node, &block)
      case node
      when Hash
        if node["type"] == "image" || node[:type] == "image"
          attrs = node["attrs"] || node[:attrs] || {}
          src = attrs["src"] || attrs[:src]
          block.call(src) if src.present?
        end
        node.each_value { |v| walk(v, &block) }
      when Array
        node.each { |v| walk(v, &block) }
      end
    end
  end
end
