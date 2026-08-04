# frozen_string_literal: true

begin
  require "dotenv"
  env_file = File.expand_path("../.env", __dir__)
  Dotenv.load(env_file) if File.exist?(env_file)
rescue LoadError
  warn "dotenv gem not available; continuing without loading .env"
end

def env_or_default(key, fallback)
  value = ENV[key]
  value.nil? || value.strip.empty? ? fallback : value
end

# Get connection parameters
host = env_or_default("DATABASE_HOST", "127.0.0.1")
host = "127.0.0.1" if host == "localhost" # Normalize localhost to IPv4
port = env_or_default("DATABASE_PORT", "5432")

# Allow database name, username, and password to be passed as arguments
# Usage: script/psql_superuser.rb [database] [username] [password]
db_name = ARGV[0] || "postgres"
super_user = ARGV[1] || env_or_default("PGSUPERUSER", "postgres")
super_password = ARGV[2] || env_or_default("PGSUPERPASS", ENV["PGPASSWORD"] || "postgres")

# Show connection info
puts "Connecting to PostgreSQL as superuser..."
puts "  Host: #{host}"
puts "  Port: #{port}"
puts "  User: #{super_user}"
puts "  Database: #{db_name}"
puts ""
puts "Type '\\q' to quit, '\\?' for help, or '\\l' to list databases."
puts "=" * 60
puts ""

# Check if psql is available (allow override via PGPATH env var)
psql_path = ENV["PGPATH"]

if psql_path.nil? || psql_path.empty?
  if Gem.win_platform?
    # Windows: try 'where' command
    result = `where psql 2>nul`.strip
    psql_path = result.split("\n").first unless result.empty?
  else
    # Unix-like: try 'which' command
    psql_path = `which psql 2>/dev/null`.strip
  end
end

if psql_path.nil? || psql_path.empty?
  warn "psql command not found. Please ensure PostgreSQL client tools are installed and on your PATH."
  warn "You can also set PGPATH environment variable to point to the psql executable."
  exit 1
end

# Set password environment variable for psql
ENV["PGPASSWORD"] = super_password

# Build psql command
cmd = [
  psql_path,
  "--host=#{host}",
  "--port=#{port}",
  "--username=#{super_user}",
  "--dbname=#{db_name}"
]

# Execute psql interactively
exec(*cmd)

