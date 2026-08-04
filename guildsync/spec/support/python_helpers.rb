# frozen_string_literal: true

# Helper methods for Python-related tests
# Provides utilities to check Python availability and required packages
module PythonHelpers
  # Cache for Python executable availability checks
  # Key: python command string
  # Value: Boolean indicating if executable is available
  @executable_cache = {}

  # Cache for Python package availability checks
  # Key: "#{python_cmd}::#{imports.join('|')}"
  # Value: Boolean indicating if packages are available
  @package_cache = {}

  class << self
    attr_accessor :executable_cache, :package_cache
  end

  # Check if Python executable is available
  # Results are cached to avoid repeated checks
  # @param python_cmd [String] Python command to check (defaults to GUILDSYNC_PYTHON_CMD or 'python3')
  # @return [Boolean] true if Python is available
  def python_executable_available?(python_cmd = nil)
    python_cmd ||= ENV.fetch('GUILDSYNC_PYTHON_CMD', 'python3')

    # Return cached result if available
    if PythonHelpers.executable_cache.key?(python_cmd)
      return PythonHelpers.executable_cache[python_cmd]
    end

    # Check if Python is available
    result = begin
      system("#{python_cmd} --version", out: File::NULL, err: File::NULL)
    rescue => e
      Rails.logger.debug "PythonHelpers: Error checking Python executable: #{e.message}"
      false
    end

    puts "PythonHelpers: Python executable '#{python_cmd}' available: #{result}"

    # Cache the result
    PythonHelpers.executable_cache[python_cmd] = result
    result
  end

  # Check if required Python packages are installed
  # Results are cached to avoid repeated checks
  # @param python_cmd [String] Python command to use (defaults to GUILDSYNC_PYTHON_CMD or 'python3')
  # @param imports [Array<String>] List of import statements to check
  #   Each should be a valid Python import statement (e.g., 'from surya.ocr import run_ocr')
  #   Defaults to checking surya.ocr
  # @return [Boolean] true if all packages are available
  def python_packages_available?(python_cmd = nil, imports: [ 'from surya.ocr import run_ocr' ])
    python_cmd ||= ENV.fetch('GUILDSYNC_PYTHON_CMD', 'python3')

    return false unless python_executable_available?(python_cmd)

    # Create cache key from python command and sorted imports
    cache_key = "#{python_cmd}::#{imports.sort.join('|')}"

    # Return cached result if available
    if PythonHelpers.package_cache.key?(cache_key)
      puts "PythonHelpers: Using cached result for packages '#{cache_key}': #{PythonHelpers.package_cache[cache_key]}"
      return PythonHelpers.package_cache[cache_key]
    end

    puts "PythonHelpers: Checking if Python packages are available: #{imports.join(', ')}"

    # Use a temporary file to avoid shell escaping issues
    require 'tempfile'

    # Build import statements for each package
    import_statements = imports.map { |imp| "    #{imp}" }.join("\n")

    check_script = <<~PYTHON
      import sys
      try:
      #{import_statements}
          print("OK")
      except ImportError as e:
          print(f"MISSING: {e}")
          sys.exit(1)
      except Exception as e:
          # Catch other errors (e.g., OSError from torch DLL loading on Windows)
          print(f"ERROR: {type(e).__name__}: {e}")
          sys.exit(1)
    PYTHON

    result = begin
      Tempfile.create([ 'python_check', '.py' ]) do |f|
        f.write(check_script)
        f.flush
        output = `#{python_cmd} "#{f.path}" 2>&1`.strip
        is_available = output == "OK"
        puts "PythonHelpers: Package check output: #{output}" unless is_available
        is_available
      end
    rescue => e
      Rails.logger.debug "PythonHelpers: Error checking Python packages: #{e.message}"
      false
    end

    puts "PythonHelpers: Python packages available: #{result}"

    # Cache the result
    PythonHelpers.package_cache[cache_key] = result
    result
  end

  # Check if Python and required packages are available
  # This is the main method to use in tests
  # @param python_cmd [String] Python command to use (defaults to GUILDSYNC_PYTHON_CMD or 'python3')
  # @param imports [Array<String>] List of import statements to check
  #   Each should be a valid Python import statement
  #   Defaults to checking surya recognition, foundation, and detection modules
  # @return [Boolean] true if Python and all packages are available
  def python_available?(python_cmd = nil, imports: [ 'from surya.recognition import RecognitionPredictor', 'from surya.foundation import FoundationPredictor', 'from surya.detection import DetectionPredictor' ])
    python_executable_available?(python_cmd) && python_packages_available?(python_cmd, imports: imports)
  end

  # Get a helpful skip message for when Python is not available
  # @param package_names [Array<String>] List of package names (for display purposes)
  # @return [String] Skip message with installation instructions
  def python_skip_message(package_names: [ 'surya-ocr' ])
    package_list = package_names.join(', ')
    "Python or required packages (#{package_list}) not available. " \
    "Set GUILDSYNC_PYTHON_CMD environment variable and install dependencies: " \
    "pip install -r requirements.txt"
  end
end

RSpec.configure do |config|
  config.include PythonHelpers
end
