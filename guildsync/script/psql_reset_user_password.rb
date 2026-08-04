# frozen_string_literal: true

begin
  require "dotenv"
  env_file = File.expand_path("../.env", __dir__)
  Dotenv.load(env_file) if File.exist?(env_file)
rescue LoadError
  warn "dotenv gem not available; continuing without loading .env"
end

require "pg"

def env_or_default(key, fallback)
  value = ENV[key]
  value.nil? || value.strip.empty? ? fallback : value
end

# Get connection parameters for postgres superuser
host = env_or_default("DATABASE_HOST", "127.0.0.1")
host = "127.0.0.1" if host == "localhost" # Normalize localhost to IPv4
port = env_or_default("DATABASE_PORT", "5432")
super_user = env_or_default("PGSUPERUSER", "postgres")
super_password = env_or_default("PGSUPERPASS", ENV["PGPASSWORD"] || "postgres")

# Get user and password from command line arguments
# Usage: script/reset_user_password.rb <username> <new_password>
if ARGV.length < 2
  warn "Usage: bundle exec ruby script/reset_user_password.rb <username> <new_password>"
  warn ""
  warn "Example:"
  warn "  bundle exec ruby script/reset_user_password.rb guildsync mynewpassword"
  exit 1
end

target_user = ARGV[0]
new_password = ARGV[1]

def ensure_connection(super_user:, super_password:, host:, port:)
  # Try connecting with the provided host
  PG.connect(
    host: host,
    port: port,
    dbname: "postgres",
    user: super_user,
    password: super_password
  )
rescue PG::Error => e
  # If host was "localhost" and connection failed, try IPv4 explicitly
  if host == "localhost"
    warn "Connection to localhost failed (may have resolved to IPv6). Trying 127.0.0.1..."
    begin
      return PG.connect(
        host: "127.0.0.1",
        port: port,
        dbname: "postgres",
        user: super_user,
        password: super_password
      )
    rescue PG::Error => e2
      warn "Unable to connect to PostgreSQL as #{super_user}@127.0.0.1:#{port}"
      warn e2.message
      exit 1
    end
  else
    warn "Unable to connect to PostgreSQL as #{super_user}@#{host}:#{port}"
    warn e.message
    exit 1
  end
end

def role_exists?(conn, role)
  conn.exec_params("SELECT 1 FROM pg_roles WHERE rolname = $1 LIMIT 1", [ role ]).ntuples.positive?
end

def escape(conn, identifier)
  conn.escape_identifier(identifier)
end

puts "Connecting to PostgreSQL as superuser (#{super_user})..."
conn = ensure_connection(
  super_user: super_user,
  super_password: super_password,
  host: host,
  port: port
)

begin
  puts "Checking if user '#{target_user}' exists..."
  unless role_exists?(conn, target_user)
    warn "Error: User '#{target_user}' does not exist."
    exit 1
  end

  puts "Resetting password for user '#{target_user}'..."
  conn.exec("ALTER ROLE #{escape(conn, target_user)} WITH LOGIN PASSWORD #{conn.escape_literal(new_password)};")
  
  puts "✓ Password successfully reset for user '#{target_user}'"
  puts ""
  puts "You can now update your .env file with:"
  puts "  DATABASE_USER=#{target_user}"
  puts "  DATABASE_PASSWORD=#{new_password}"
ensure
  conn&.close
end

