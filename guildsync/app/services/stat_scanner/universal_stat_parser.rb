# frozen_string_literal: true

module StatScanner
  # Game-agnostic extraction of label/value pairs from raw OCR text.
  # Produces a flat Hash suitable for JSON storage on GearSnapshot#data.
  class UniversalStatParser
    MAX_LINE_CHARS = 600
    MAX_LABEL_CHARS = 220

    # Stat labels and text values are short noun phrases ("Faction", "Haranya Alliance"). Chat and
    # system messages split on a colon yield long sentence-shaped labels/values. These bounds drop
    # that prose without touching real text stats; tuned generously so multi-word titles survive.
    MAX_STAT_LABEL_WORDS = 6
    MAX_STAT_VALUE_WORDS = 6

    # Core stat value shapes (also used for whole-line value detection in multi-line OCR).
    # Includes m/s with optional trailing (127.1%), longer parens e.g. (1150 + 4640), %, fractions.
    STAT_VALUE_CORE = %r{
      (?:
        [-+]?\d[\d,]*(?:\.\d+)?\s*m\/s(?:\s*\([^)]{1,80}\))?
        |
        [-+]?\d[\d,]*(?:\.\d+)?\s*\([^)]{1,80}\)
        |
        [-+]?\d[\d,]*(?:\.\d+)?%
        |
        \d+\/\d+
        |
        [-+]?\d[\d,]*(?:\.\d+)?
      )
    }x.freeze

    # Entire line is only a numeric/stat value (partner line is the label above).
    STANDALONE_VALUE_LINE = /\A#{STAT_VALUE_CORE.source}\s*\z/x.freeze

    # When OCR pairs a real stat name with chat/UI prose (e.g. "Melee Skill Damage" + "Joeven Stars"),
    # drop the pair: these labels almost always have numeric, %, m/s, or slash stats in-game.
    LABEL_EXPECTS_NUMERIC_VALUE = %r{
      \b(?:Melee|Ranged|Magic|Physical|Shield|Backstab|PvE|PvP)\b.{0,120}?(?:Attack|Damage|Accuracy|Rate|Defense|Penetration|Power|Speed|Time|Healing)\b
      |
      \b(?:Physical|Magic)\s+Defense\b
      |
      \bHealing\s+Power\b
      |
      \b(?:Magic\s+)?Defense\s+Penetration\b
      |
      \b(?:Move|Attack)\s+Speed\b
      |
      \bCast\s+Time\b
      |
      \bEquipment\s+Points\b
      |
      \bHonor\s+Points\b
      |
      \bVocation\s+Badges\b
      |
      \bCrime\s+points\b
      |
      \bInfamy\s+points\b
      |
      \bLeadership\b
      |
      \bPrevious\s+Leadership\b
      |
      \A(?:Strength|Spirit|Intelligence|Stamina|Agility)\z
      |
      \AFocus\z
      |
      \bLabor\b
    }ix.freeze

    class << self
      def parse(raw_text)
        return {} unless raw_text.is_a?(String) && raw_text.present?

        out = {}
        seen = Hash.new(0)
        lines = normalize_lines(raw_text)
        i = 0

        while i < lines.size
          line = lines[i]
          consumed = 1
          pairs = pairs_for_line_at(lines, i)

          if pairs.empty? && multiline_label_candidate?(line) && (i + 1) < lines.size
            nxt = lines[i + 1]
            if nxt.match?(STANDALONE_VALUE_LINE)
              pairs = [[line, nxt]]
              consumed = 2
            end
          end

          pairs.each do |label, value|
            label = sanitize_label(label)
            value = value.to_s.strip
            next if label.empty? || value.empty?
            next unless plausible_stat_label?(label)
            next if action_bar_or_keybind_label?(label)
            next if coordinate_fragment?(value)
            next if junk_pair?(label, value)
            next if chat_or_sentence_pair?(label, value)
            next unless value_satisfies_numeric_label_expectation?(label, value)

            key = uniquify_key(label, seen)
            out[key] = value
          end

          i += consumed
        end

        out
      end

      private

      def normalize_lines(raw_text)
        raw_text.each_line.filter_map do |line|
          line = line.to_s.gsub("\u00a0", " ").strip
          next if line.empty?
          next if line.length > MAX_LINE_CHARS
          next if noise_line?(line)

          line
        end
      end

      def pairs_for_line_at(lines, i)
        line = lines[i]
        return [] if line.blank?

        colon_pair = extract_colon_pair(line)
        return [colon_pair] if colon_pair

        tab_pair = extract_tab_pair(line)
        return [tab_pair] if tab_pair

        wide_pair = extract_wide_space_pair(line)
        return [wide_pair] if wide_pair

        dash_pair = extract_dash_pair(line)
        return [dash_pair] if dash_pair

        scan_trailing_value_pairs(line)
      end

      # Repeated label+value on one line (OCR merged rows). Value must be followed by
      # another label (space + letter) or end of string — not \z on each chunk alone.
      def scan_trailing_value_pairs(line)
        pairs = []
        remainder = line
        pair_head = /\A(.+?)\s+(#{STAT_VALUE_CORE.source})(?=\s+[\p{L}]|\z)/xu
        loop do
          m = remainder.match(pair_head)
          break unless m

          pairs << [m[1].strip, m[2].strip]
          remainder = remainder[m.end(0)..].to_s.strip
          break if remainder.empty?
        end
        pairs
      end

      def multiline_label_candidate?(line)
        return false if line.blank?
        return false unless line.match?(/[\p{L}]/u)
        return false if map_coordinate_line?(line)
        return false if line.match?(STANDALONE_VALUE_LINE)
        return false if line.include?(":")

        true
      end

      # Short lowercase words + bare 4+ digit values are often chat/OCR fragments (e.g. "rever" + 7361).
      SHORT_LABEL_PLAIN_INT_ALLOWLIST = %w[
        labor mana focus guild stamina level power honor strength agility vitality intellect spirit
      ].freeze

      # Drop obvious OCR junk (tiny labels + single-digit "values" from UI chrome).
      def junk_pair?(label, value)
        return true if value.match?(/\A\d\z/)

        s = label.to_s.strip
        val_s = value.to_s.strip
        if s.match?(/\A[a-z]{3,5}\z/) && val_s.match?(/\A\d{4,}\z/) && !SHORT_LABEL_PLAIN_INT_ALLOWLIST.include?(s)
          return true
        end

        false
      end

      # Generalized chat / system-message rejection (game-agnostic, position-independent).
      # Now that OCR keeps text from anywhere on screen, non-bracketed chat and system lines can
      # split on a colon into label/value pairs. Real stats are short label + short/numeric value;
      # chat and system broadcasts are long sentences. Drop those without nuking text stats.
      def chat_or_sentence_pair?(label, value)
        l = label.to_s.strip
        v = value.to_s.strip

        # Sentence-shaped label (e.g. "The Aegis Island region has fallen into a state of Danger Zone").
        return true if word_count(l) > MAX_STAT_LABEL_WORDS

        # Prose value with no number is chat, not a stat. Short word-only values (faction, class,
        # title) are kept because they fall under the word cap.
        return true if !v.match?(/\d/) && word_count(v) > MAX_STAT_VALUE_WORDS

        # Stats never end in a question or exclamation mark; chat frequently does.
        return true if v.match?(/[!?]\s*\z/)

        false
      end

      def word_count(str)
        str.to_s.split(/\s+/).reject(&:empty?).size
      end

      def value_satisfies_numeric_label_expectation?(label, value)
        return true unless label.to_s.match?(LABEL_EXPECTS_NUMERIC_VALUE)

        v = value.to_s.strip
        return false if v.empty?

        return true if v.match?(STAT_VALUE_CORE)
        return true if v.match?(/\d/)

        false
      end

      # Skill bar / keyboard hints OCR'd as text — never character stats.
      # Covers: (W)Dn, (Chans), Shift/Ctrl/Alt chords, F-keys, single-letter slots, mouse/numpad, etc.
      def action_bar_or_keybind_label?(label)
        s = label.to_s.strip
        return false if s.blank?

        # (W)Dn, (Q)Ab — one letter in parens then a short hotkey token (common MMO action bars).
        return true if s.match?(/\([A-Za-z]\)[A-Za-z0-9]{1,8}\s*\z/)

        # Whole label is only a short parenthetical name with no digits (not "(4.9%)" style stat fragments).
        if s.match?(/\A\([^)]{1,18}\)\s*:?\s*\z/) && !s.match?(/\d/)
          return true
        end

        # Modifier + key (Shift 1, Alt F4) — space between modifier and key.
        return true if s.match?(/\A(?:Shift|Ctrl|Control|Alt|Cmd|Command|Meta|Option)\s+[\dA-Z]{1,4}\z/i)
        # Modifier+key without space (Ctrl+Q, Alt+1).
        return true if s.match?(/\A(?:Shift|Ctrl|Control|Alt|Cmd|Command|Meta|Option)\s*\+\s*[A-Z0-9]{1,4}\z/i)

        # Bare function-key slot read as a "stat name".
        return true if s.match?(/\AF\d{1,2}\z/i)

        # Single ASCII letter — almost always a key slot (WASD etc.), never a full stat name.
        return true if s.match?(/\A[A-Z]\z/i)

        # Whole label is a known keyboard / UI key word (OCR'd from hotkey row).
        return true if s.match?(/\A(?:Tab|Esc|Escape|Caps|Space|Enter|Return|Ins|Insert|Del|Delete|Home|End|Backspace|Bksp|Pause|Break|Scroll|Lock|Menu|Apps|Win|Windows)\d{0,2}\z/i)
        return true if s.match?(/\A(?:PgUp|PgDn|PageUp|PageDown|ArrowUp|ArrowDown|ArrowLeft|ArrowRight)\d{0,2}\z/i)

        # Mouse / extra mouse buttons on action bars.
        return true if s.match?(/\A(?:M|MB|Mouse|Middle)\s*\d{1,2}\z/i)

        # Numpad digits as labels.
        return true if s.match?(/\A(?:Num|Numpad)[-\s.]?\d{1,2}\z/i)

        # Short letter + letter chord: Q + E, A + S (not "Melee Attack" — has space and length).
        return true if s.match?(/\A[A-Z]\s*\+\s*[A-Z0-9]{1,3}\z/i)

        # Digit-key row read as label with optional suffix: "1", "12" already fail letter check;
        # allow "Key 5", "K 3" style OCR.
        return true if s.match?(/\A(?:Key|Hotkey|Bind)\s*[-:]?\s*\d{1,2}\z/i)

        false
      end

      def noise_line?(line)
        return true if line.match?(%r{\Ahttps?://}i)
        return true if line.match?(/\A[^\p{L}\p{N}]{1,}\z/) # punctuation-only
        return true if map_coordinate_line?(line)

        false
      end

      # Minimap / world position strings (e.g. W4°35' 31" S19°2') — not character stats.
      # Use compass letter + digit + minute/degree marks only (avoid /i on [NSWE] — would match "e" in "Melee").
      def map_coordinate_line?(line)
        return true if line.match?(/\b[NSWE]\s*\d{1,3}[°˚]?\s*\d{0,3}['′ˊ]/)
        return true if line.match?(/\b[NSWE]\d{1,3}['′ˊ]/) && line.match?(/["″〃]/)
        return true if line.match?(/\b[NSWE]\d{1,2}['′ˊ].{0,35}\b[NSWE]\d/)
        false
      end

      def coordinate_fragment?(s)
        t = s.to_s.strip
        return true if t.match?(/\A\d{1,3}["″〃]\s*\z/) # lone seconds fragment from coords
        false
      end

      def plausible_stat_label?(label)
        return false unless label.match?(/[\p{L}]/u) # need at least one letter (name, not pure noise)
        return false if map_coordinate_line?(label)

        true
      end

      def extract_colon_pair(line)
        return nil unless line.include?(":")

        left, right = line.split(":", 2)
        l = left.to_s.strip
        r = right.to_s.strip
        return nil if l.blank? || r.blank?

        [l, r]
      end

      def extract_tab_pair(line)
        return nil unless line.include?("\t")

        a, b = line.split("\t", 2).map { |s| s.to_s.strip }
        return nil if a.blank? || b.blank?

        [a, b]
      end

      def extract_wide_space_pair(line)
        m = line.match(/\A(.+?)\s{2,}(.+)\z/)
        return nil unless m

        [m[1].strip, m[2].strip]
      end

      def extract_dash_pair(line)
        m = line.match(/\A(.{1,#{MAX_LABEL_CHARS}}?)\s+[-–—]\s+(.+)\z/)
        return nil unless m

        [m[1].strip, m[2].strip]
      end

      def sanitize_label(label)
        s = label.to_s.strip
        s = s[0, MAX_LABEL_CHARS] if s.length > MAX_LABEL_CHARS
        s
      end

      def uniquify_key(label, seen)
        fp = fingerprint(label)
        seen[fp] += 1
        n = seen[fp]
        n == 1 ? label : "#{label} (#{n})"
      end

      def fingerprint(label)
        base = label.downcase.gsub(/[^\p{L}\p{N}]+/u, " ").squeeze(" ").strip
        base.presence || label.downcase.strip
      end
    end
  end
end
