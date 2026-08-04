# frozen_string_literal: true

require "psych"

ROOT = File.expand_path("../config/locales", __dir__)
BREAKOUT_PREFIXES = %w[auth billing controllers discord guilds home settings].freeze
DEFAULT_LOCALE = "en"
# Locales skipped entirely (no breakout writes): `en` is canonical; `de` is restored from git on this branch;
# `es` is maintained outside this script—do not remove `es` from this list without an explicit project decision.
EXCLUDED_FROM_TRANSFER = %w[en de es].freeze

def deep_copy(value)
  Marshal.load(Marshal.dump(value))
end

def transfer_template(template, source)
  case template
  when Hash
    return deep_copy(source.nil? ? {} : source) if template.empty?

    template.each_with_object({}) do |(key, value), result|
      source_value = source.is_a?(Hash) ? source[key] : nil
      result[key] = transfer_template(value, source_value)
    end
  else
    source.nil? ? template : deep_copy(source)
  end
end

# Union locale breakout keys with the English canonical breakout (`en/<prefix>.en.yml`)
# so missing subtrees (e.g. `sidebar.navigation`, `guild_warnings`) still participate
# in `transfer_template` and pull strings from the base `XX.yml`.
def merge_breakout_structure(english_root, locale_breakout_root)
  case english_root
  when Hash
    locale_breakout_root = {} unless locale_breakout_root.is_a?(Hash)
    keys = english_root.keys | locale_breakout_root.keys
    keys.each_with_object({}) do |key, acc|
      en_v = english_root[key]
      loc_v = locale_breakout_root[key]
      if en_v.is_a?(Hash) && (loc_v.nil? || loc_v.is_a?(Hash))
        acc[key] = merge_breakout_structure(en_v, loc_v.is_a?(Hash) ? loc_v : {})
      elsif !loc_v.nil?
        acc[key] = deep_copy(loc_v)
      else
        acc[key] = deep_copy(en_v)
      end
    end
  else
    locale_breakout_root.nil? ? deep_copy(english_root) : deep_copy(locale_breakout_root)
  end
end

def load_yaml(path)
  raw = File.read(path)
  data = Psych.safe_load(raw, aliases: true)
  data.is_a?(Hash) ? data : {}
end

def dump_yaml(path, locale, payload)
  yaml = Psych.dump({ locale => payload }, line_width: -1)
  yaml = yaml.sub(/\A---\n/, "")
  File.write(path, yaml)
end

locale_dirs = Dir.children(ROOT).select do |entry|
  File.directory?(File.join(ROOT, entry))
end.sort

updated = []
skipped = []

locale_dirs.each do |locale|
  if EXCLUDED_FROM_TRANSFER.include?(locale)
    skipped << "#{locale}: excluded from automated transfer"
    next
  end

  base_path = File.join(ROOT, locale, "#{locale}.yml")
  unless File.exist?(base_path)
    skipped << "#{locale}: missing base file #{locale}.yml"
    next
  end

  base_data = load_yaml(base_path)
  source_root = base_data[locale] || {}

  breakout_glob = File.join(ROOT, locale, "*.#{locale}.yml")
  breakout_paths = Dir.glob(breakout_glob).select do |path|
    BREAKOUT_PREFIXES.include?(File.basename(path).split(".").first)
  end.sort

  breakout_paths.each do |path|
    breakout_data = load_yaml(path)
    template_root = breakout_data[locale] || {}

    prefix = File.basename(path).split(".").first
    if BREAKOUT_PREFIXES.include?(prefix)
      en_canon_path = File.join(ROOT, DEFAULT_LOCALE, "#{prefix}.#{DEFAULT_LOCALE}.yml")
      if File.exist?(en_canon_path)
        en_template = load_yaml(en_canon_path)[DEFAULT_LOCALE] || {}
        template_root = merge_breakout_structure(en_template, template_root) if en_template.any?
      end
    end

    transferred = transfer_template(template_root, source_root)
    dump_yaml(path, locale, transferred)
    updated << path
  end
end

puts "Updated #{updated.count} breakout files."
updated.each { |path| puts "  - #{path}" }

if skipped.any?
  puts ""
  puts "Skipped:"
  skipped.each { |message| puts "  - #{message}" }
end
