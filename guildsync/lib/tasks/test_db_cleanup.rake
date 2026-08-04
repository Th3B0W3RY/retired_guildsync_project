# frozen_string_literal: true

namespace :test_db do
  desc "Kill all connections to the test database (useful when tests are interrupted)"
  task kill_connections: :environment do
    require 'pg'
    
    # Get test database configuration directly (don't rely on current environment)
    # Access the test config from Rails' database configuration
    test_config = Rails.application.config.database_configuration['test']
    
    db_name = test_config['database'] || ENV['TEST_DATABASE_NAME'] || 'guildsync_test'
    db_user = test_config['username'] || test_config['user'] || ENV['TEST_DATABASE_USER'] || 'guildsync'
    db_password = test_config['password'] || ENV['TEST_DATABASE_PASSWORD']
    db_host = test_config['host'] || ENV['TEST_DATABASE_HOST'] || '127.0.0.1'
    db_port = test_config['port'] || ENV['TEST_DATABASE_PORT'] || 5432
    
    # Connect to postgres database (not the test database) to kill connections
    begin
      conn = PG.connect(
        host: db_host,
        port: db_port,
        dbname: 'postgres',
        user: db_user,
        password: db_password
      )
      
      puts "Checking for connections to database '#{db_name}'..."
      
      # Get all connections to the test database
      result = conn.exec_params(
        "SELECT pid, usename, application_name, state, query_start, state_change 
         FROM pg_stat_activity 
         WHERE datname = $1 AND pid != pg_backend_pid()",
        [db_name]
      )
      
      if result.ntuples.zero?
        puts "No other connections found to '#{db_name}'."
      else
        puts "Found #{result.ntuples} connection(s) to '#{db_name}':"
        result.each do |row|
          puts "  PID: #{row['pid']}, User: #{row['usename']}, State: #{row['state']}, App: #{row['application_name']}"
        end
        
        # Allow force flag to skip prompt
        force = ENV['FORCE'] == '1' || ENV['FORCE'] == 'true'
        answer = nil
        
        if force
          puts "\nForce flag set, killing connections..."
        else
          print "\nKill these connections? (y/N): "
          answer = $stdin.gets.chomp.downcase
        end
        
        if force || (answer && answer == 'y')
          result.each do |row|
            pid = row['pid']
            begin
              conn.exec("SELECT pg_terminate_backend(#{pid})")
              puts "  ✓ Terminated connection PID #{pid}"
            rescue => e
              puts "  ✗ Failed to terminate PID #{pid}: #{e.message}"
            end
          end
          puts "\nDone!"
        else
          puts "Cancelled."
        end
      end
      
      conn.close
    rescue PG::Error => e
      puts "Error connecting to PostgreSQL: #{e.message}"
      puts "\nTrying with superuser credentials..."
      
      # Try with superuser
      super_user = ENV['PGSUPERUSER'] || 'postgres'
      super_password = ENV['PGSUPERPASS'] || ENV['PGPASSWORD'] || 'postgres'
      
      begin
        conn = PG.connect(
          host: db_host,
          port: db_port,
          dbname: 'postgres',
          user: super_user,
          password: super_password
        )
        
        result = conn.exec_params(
          "SELECT pid, usename, application_name, state 
           FROM pg_stat_activity 
           WHERE datname = $1 AND pid != pg_backend_pid()",
          [db_name]
        )
        
        if result.ntuples.zero?
          puts "No other connections found to '#{db_name}'."
        else
          force = ENV['FORCE'] == '1' || ENV['FORCE'] == 'true'
          puts "Found #{result.ntuples} connection(s). #{force ? 'Killing all...' : 'Use FORCE=1 to kill automatically'}"
          
          if force
            result.each do |row|
              pid = row['pid']
              begin
                conn.exec("SELECT pg_terminate_backend(#{pid})")
                puts "  ✓ Terminated connection PID #{pid}"
              rescue => e
                puts "  ✗ Failed to terminate PID #{pid}: #{e.message}"
              end
            end
            puts "\nDone!"
          end
        end
        
        conn.close
      rescue => e2
        puts "Error: #{e2.message}"
        puts "\nYou may need to manually kill connections using:"
        puts "  psql -U #{super_user} -d postgres -c \"SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '#{db_name}' AND pid != pg_backend_pid();\""
      end
    end
  end
  
  desc "Show all connections to the test database"
  task show_connections: :environment do
    require 'pg'
    
    # Get test database configuration directly (don't rely on current environment)
    test_config = Rails.application.config.database_configuration['test']
    
    db_name = test_config['database'] || ENV['TEST_DATABASE_NAME'] || 'guildsync_test'
    db_user = test_config['username'] || test_config['user'] || ENV['TEST_DATABASE_USER'] || 'guildsync'
    db_password = test_config['password'] || ENV['TEST_DATABASE_PASSWORD']
    db_host = test_config['host'] || ENV['TEST_DATABASE_HOST'] || '127.0.0.1'
    db_port = test_config['port'] || ENV['TEST_DATABASE_PORT'] || 5432
    
    begin
      conn = PG.connect(
        host: db_host,
        port: db_port,
        dbname: 'postgres',
        user: db_user,
        password: db_password
      )
      
      result = conn.exec_params(
        "SELECT pid, usename, application_name, state, query_start, state_change, query
         FROM pg_stat_activity 
         WHERE datname = $1",
        [db_name]
      )
      
      if result.ntuples.zero?
        puts "No connections found to '#{db_name}'."
      else
        puts "Connections to '#{db_name}':"
        puts "-" * 80
        result.each do |row|
          puts "PID: #{row['pid']}"
          puts "  User: #{row['usename']}"
          puts "  Application: #{row['application_name'] || '(none)'}"
          puts "  State: #{row['state']}"
          puts "  Query Start: #{row['query_start']}"
          puts "  Query: #{row['query']&.truncate(100)}"
          puts "-" * 80
        end
      end
      
      conn.close
    rescue => e
      puts "Error: #{e.message}"
    end
  end
end

