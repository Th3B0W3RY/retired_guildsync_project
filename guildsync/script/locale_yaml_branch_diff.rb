# frozen_string_literal: true

# Compare merged locale YAML between two git branches (default: development vs
# i18n/GUI-135-break-up-translation-files). Checks out each branch in turn,
# loads every *.yml under config/locales (Rails root), deep-merges by top-level
# locale key (e.g. es, en), then prints (1) key path diffs, (2) value diffs.
#
# Run from anywhere if you pass the Rails app root (directory that contains
# config/locales), or set GUILDSYNC_RAILS_ROOT. Git is always invoked with -C
# so the script does not depend on your cwd being inside the repo.
#
# Usage:
#   ruby /path/to/locale_yaml_branch_diff.rb --rails-root /path/to/guildsync
#   ruby .../locale_yaml_branch_diff.rb --rails-root /path/to/GuildSync   # monorepo root; script uses guildsync/
#   GUILDSYNC_RAILS_ROOT=/path/to/guildsync ruby .../locale_yaml_branch_diff.rb
#
# From inside the repo you can omit --rails-root; discovery uses git rev-parse
# from the current working directory.
#
# Requires a clean git working tree so checkouts are safe.

require "psych"
require "set"

DEFAULT_BASE = "development"
DEFAULT_COMPARE = "i18n/GUI-135-break-up-translation-files"

def parse_args(argv)
  base = DEFAULT_BASE
  compare = DEFAULT_COMPARE
  rails_root = nil
  i = 0
  while i < argv.length
    case argv[i]
    when "--base"
      base = argv[i + 1] || abort("Missing value for --base")
      i += 2
    when "--compare"
      compare = argv[i + 1] || abort("Missing value for --compare")
      i += 2
    when "--root", "--rails-root"
      rails_root = argv[i + 1] || abort("Missing value for #{argv[i]}")
      i += 2
    when "-h", "--help"
      puts <<~HELP
        Usage: ruby locale_yaml_branch_diff.rb [options]

        Options:
          --rails-root PATH   Rails app root (directory containing config/locales).
                              Also accepted: --root PATH
                              If PATH is the monorepo root and contains guildsync/config/locales,
                              that subdirectory is used automatically.
          --base REF            First branch to checkout and snapshot (default: #{DEFAULT_BASE})
          --compare REF         Second branch (default: #{DEFAULT_COMPARE})
          -h, --help             This message

        Environment:
          GUILDSYNC_RAILS_ROOT   Same as --rails-root if the flag is omitted
          RAILS_ROOT             Used only when GUILDSYNC_RAILS_ROOT is unset

        If no Rails root is given, the script runs `git rev-parse --show-toplevel`
        from the process cwd and then looks for ./config/locales or ./guildsync/config/locales.

        Requires a clean git working tree. Restores your previous branch when done.
      HELP
      exit 0
    else
      abort "Unknown argument: #{argv[i]} (try --help)"
    end
  end
  [base, compare, rails_root]
end

def resolve_rails_root_from_path(path)
  p = File.expand_path(path)
  if File.directory?(File.join(p, "config", "locales"))
    return p
  end
  if File.directory?(File.join(p, "guildsync", "config", "locales"))
    return File.join(p, "guildsync")
  end

  abort <<~MSG.strip
    Could not find locale files under:
      #{p}/config/locales
      #{p}/guildsync/config/locales
    Pass --rails-root to your Rails app root (the directory that contains config/locales),
    or the monorepo root that contains guildsync/.
  MSG
end

def discover_rails_root_from_cwd_git
  top = IO.popen(["git", "rev-parse", "--show-toplevel"], err: File::NULL, &:read).to_s.strip
  return nil if top.empty?

  if File.directory?(File.join(top, "config", "locales"))
    return top
  end
  if File.directory?(File.join(top, "guildsync", "config", "locales"))
    return File.join(top, "guildsync")
  end

  nil
end

def resolve_rails_root(cli_path)
  explicit = cli_path || ENV["GUILDSYNC_RAILS_ROOT"] || ENV["RAILS_ROOT"]
  return resolve_rails_root_from_path(explicit) if explicit

  from_git = discover_rails_root_from_cwd_git
  return from_git if from_git

  abort <<~MSG.strip
    Could not determine Rails root. Either:
      --rails-root /path/to/guildsync
    or set GUILDSYNC_RAILS_ROOT, or run from inside the Git repo so
    `git rev-parse --show-toplevel` finds a tree with config/locales or guildsync/config/locales.
  MSG
end

def git_root_for_rails_app(rails_root)
  out = IO.popen(["git", "-C", rails_root, "rev-parse", "--show-toplevel"], err: File::NULL, &:read)
  root = out.to_s.strip
  abort("Not a git repository (git rev-parse failed for -C #{rails_root}).") if root.empty?

  root
end

def git_capture(git_root, *args)
  IO.popen(["git", "-C", git_root, *args], err: [:child, :out], &:read).strip
end

def git_system(git_root, *args)
  system("git", "-C", git_root, *args, out: File::NULL, err: File::NULL)
end

def ref_exists?(git_root, ref)
  git_system(git_root, "rev-parse", "-q", "--verify", ref)
end

def ensure_clean_tree!(git_root)
  dirty = git_capture(git_root, "status", "--porcelain")
  return if dirty.empty?

  warn "Working tree is not clean; refusing to checkout branches."
  warn dirty
  exit 1
end

def checkout!(git_root, ref)
  ok = system("git", "-C", git_root, "checkout", "-q", ref)
  abort("git checkout #{ref} failed") unless ok
end

def current_branch(git_root)
  b = git_capture(git_root, "branch", "--show-current")
  b.empty? ? nil : b
end

def deep_merge(a, b)
  return deep_copy(b) unless a.is_a?(Hash) && b.is_a?(Hash)

  a.merge(b) do |_, old_val, new_val|
    if old_val.is_a?(Hash) && new_val.is_a?(Hash)
      deep_merge(old_val, new_val)
    else
      new_val
    end
  end
end

def deep_copy(obj)
  Marshal.load(Marshal.dump(obj))
end

def load_all_locale_yamls(locales_glob)
  merged_by_locale = Hash.new { |h, k| h[k] = {} }
  Dir.glob(locales_glob).sort.each do |path|
    raw = File.read(path)
    data = Psych.safe_load(raw, permitted_classes: [Symbol], aliases: true)
    next unless data.is_a?(Hash)

    data.each do |locale_key, tree|
      next unless tree.is_a?(Hash)

      lk = locale_key.to_s
      merged_by_locale[lk] = deep_merge(merged_by_locale[lk], tree)
    end
  end
  merged_by_locale
end

def flatten_leaves(obj, prefix = "")
  out = {}
  case obj
  when Hash
    if obj.empty?
      out[prefix] = {}
      return out
    end
    obj.each do |k, v|
      p = prefix.empty? ? k.to_s : "#{prefix}.#{k}"
      if v.is_a?(Hash) && !v.empty?
        out.merge!(flatten_leaves(v, p))
      else
        out[p] = v
      end
    end
  else
    out[prefix] = obj
  end
  out
end

def all_key_paths(obj, prefix = "")
  paths = []
  return paths unless obj.is_a?(Hash)

  obj.each do |k, v|
    p = prefix.empty? ? k.to_s : "#{prefix}.#{k}"
    paths << p
    paths.concat(all_key_paths(v, p)) if v.is_a?(Hash) && !v.empty?
  end
  paths
end

def stable_value_repr(v)
  case v
  when Hash, Array
    Psych.dump(v).strip
  else
    v.inspect
  end
end

def diff_locales(base_label, compare_label, base_trees, compare_trees)
  locales = (base_trees.keys | compare_trees.keys).sort
  found_diff = false

  locales.each do |locale|
    a = base_trees[locale] || {}
    b = compare_trees[locale] || {}

    paths_a = all_key_paths(a).to_set
    paths_b = all_key_paths(b).to_set
    only_a = paths_a - paths_b
    only_b = paths_b - paths_a

    leaves_a = flatten_leaves(a)
    leaves_b = flatten_leaves(b)
    keys_only_a = leaves_a.keys - leaves_b.keys
    keys_only_b = leaves_b.keys - leaves_a.keys
    value_changes = (leaves_a.keys & leaves_b.keys).reject { |k| leaves_a[k] == leaves_b[k] }

    next if only_a.empty? && only_b.empty? && keys_only_a.empty? && keys_only_b.empty? && value_changes.empty?
    found_diff = true

    puts "=" * 72
    puts "Locale: #{locale}"
    puts "  BASE = #{base_label}  |  COMPARE = #{compare_label}"
    puts "=" * 72

    unless only_a.empty? && only_b.empty?
      puts "\n## Structural key paths (nested hash keys; intermediate + leaf namespaces)"
      puts "\n  Only on BASE (#{base_label}) (#{only_a.size}):"
      only_a.sort.each { |p| puts "    - #{p}" }
      puts "\n  Only on COMPARE (#{compare_label}) (#{only_b.size}):"
      only_b.sort.each { |p| puts "    + #{p}" }
    end

    unless keys_only_a.empty? && keys_only_b.empty?
      puts "\n## Leaf translation keys (dot paths to scalar / empty-hash / array leaves)"
      puts "\n  Only on BASE (#{base_label}) (#{keys_only_a.size}):"
      keys_only_a.sort.each { |k| puts "    - #{k}" }
      puts "\n  Only on COMPARE (#{compare_label}) (#{keys_only_b.size}):"
      keys_only_b.sort.each { |k| puts "    + #{k}" }
    end

    unless value_changes.empty?
      puts "\n## Same leaf key, different value (#{value_changes.size})"
      value_changes.sort.each do |k|
        puts "\n  #{k}"
        puts "    #{base_label}:    #{stable_value_repr(leaves_a[k])}"
        puts "    #{compare_label}: #{stable_value_repr(leaves_b[k])}"
      end
    end

    puts ""
  end

  found_diff
end

base_ref, compare_ref, cli_rails_root = parse_args(ARGV)
rails_root = resolve_rails_root(cli_rails_root)
git_root = git_root_for_rails_app(rails_root)
locales_dir = File.join(rails_root, "config", "locales")
abort "Missing locales directory: #{locales_dir}" unless File.directory?(locales_dir)

locales_glob = File.join(locales_dir, "**", "*.yml")

puts "Rails root:  #{rails_root}"
puts "Git root:    #{git_root}"
puts "Locale glob: #{locales_glob}"
puts ""

ensure_clean_tree!(git_root)
abort("Unknown git ref: #{base_ref}") unless ref_exists?(git_root, base_ref)
abort("Unknown git ref: #{compare_ref}") unless ref_exists?(git_root, compare_ref)

was = current_branch(git_root)
was ||= git_capture(git_root, "rev-parse", "HEAD")

puts "Collecting merged locale YAML from BASE ref:    #{base_ref}"
checkout!(git_root, base_ref)
base_trees = load_all_locale_yamls(locales_glob)

puts "Collecting merged locale YAML from COMPARE ref: #{compare_ref}"
checkout!(git_root, compare_ref)
compare_trees = load_all_locale_yamls(locales_glob)

puts "Restoring previous HEAD: #{was}"
checkout!(git_root, was)

puts "\n"
found_diff = diff_locales(base_ref, compare_ref, base_trees, compare_trees)
unless found_diff
  puts "No merged locale YAML differences found between #{base_ref} and #{compare_ref}."
end
puts "Done."
