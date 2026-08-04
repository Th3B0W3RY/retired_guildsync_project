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

db_name = env_or_default("TEST_DATABASE_NAME", "guildsync_test")
db_user = env_or_default("TEST_DATABASE_USER", "guildsync")
db_password = env_or_default("TEST_DATABASE_PASSWORD", "guildsync")
host = env_or_default("TEST_DATABASE_HOST", "127.0.0.1")
port = env_or_default("TEST_DATABASE_PORT", "5432")
super_user = env_or_default("PGSUPERUSER", "postgres")
super_password = env_or_default("PGSUPERPASS", ENV["PGPASSWORD"] || "postgres")

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

def db_exists?(conn, db_name)
  conn.exec_params("SELECT 1 FROM pg_database WHERE datname = $1 LIMIT 1", [ db_name ]).ntuples.positive?
end

def escape(conn, identifier)
  conn.escape_identifier(identifier)
end

conn = ensure_connection(
  super_user: super_user,
  super_password: super_password,
  host: host,
  port: port
)

begin
  puts "Ensuring PostgreSQL role '#{db_user}' exists..."
  if role_exists?(conn, db_user)
    conn.exec("ALTER ROLE #{escape(conn, db_user)} WITH LOGIN PASSWORD #{conn.escape_literal(db_password)};")
    puts "Role '#{db_user}' already exists. Password updated."
  else
    conn.exec("CREATE ROLE #{escape(conn, db_user)} WITH LOGIN PASSWORD #{conn.escape_literal(db_password)};")
    puts "Created role '#{db_user}'."
  end

  puts "Ensuring database '#{db_name}' exists..."
  if db_exists?(conn, db_name)
    puts "Database '#{db_name}' already exists."
  else
    conn.exec("CREATE DATABASE #{escape(conn, db_name)} WITH OWNER = #{escape(conn, db_user)} ENCODING = 'UTF8';")
    puts "Created database '#{db_name}'."
  end

  puts "Granting privileges..."
  conn.exec("GRANT ALL PRIVILEGES ON DATABASE #{escape(conn, db_name)} TO #{escape(conn, db_user)};")

  puts <<~MSG
    Setup complete.
    Configure your environment variables (e.g. TEST_DATABASE_NAME/USER/PASSWORD) to point tests at '#{db_name}'.
  MSG
ensure
  conn&.close
end

def prepare_test_database(skip:)
  if skip
    puts "Skipping Rails test schema preparation (SKIP_TEST_DB_PREP=1)."
    puts "Run `bundle exec rails db:test:prepare` manually before running specs."
    return
  end

  puts "Running `rails db:test:prepare`..."
  env = { "RAILS_ENV" => "test" }
  success = system(env, "bundle", "exec", "rails", "db:test:prepare")
  if success
    puts "Rails test database prepared."
  else
    warn "Failed to run rails db:test:prepare. Please run it manually."
  end
end

prepare_test_database(skip: ENV["SKIP_TEST_DB_PREP"] == "1")

