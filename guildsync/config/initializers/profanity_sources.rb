# frozen_string_literal: true

# Sources for dynamic profanity list. Fetched every 6 hours by ProfanityListUpdateJob.
# Use :plain for one word per line, :json for JSON with optional json_path (e.g. "words").
PROFANITY_SOURCES = [
  {
    name: "LDNOOBW",
    url: "https://raw.githubusercontent.com/LDNOOBW/List-of-Dirty-Naughty-Obscene-and-Otherwise-Bad-Words/master/en",
    format: :plain,
    enabled: true
  },
  {
    name: "Google Profanity Words",
    url: "https://raw.githubusercontent.com/coffee-and-fun/google-profanity-words/main/data/en.txt",
    format: :plain,
    enabled: true
  },
  {
    name: "Bad Word List",
    url: "https://raw.githubusercontent.com/zacanger/profane-words/master/words.json",
    format: :json,
    json_path: "words",
    enabled: true
  },
  {
    name: "Local Backup",
    url: nil,
    file: "config/profanity_backup.txt",
    format: :plain,
    enabled: true
  }
].freeze
