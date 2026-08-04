# PowerShell script for Windows
# Setup Python virtual environment for application services

param(
    [switch]$Force,
    [switch]$Deploy
)

# Note: We intentionally do NOT set $ErrorActionPreference = "Stop" globally.
# The script handles errors explicitly with if/try-catch, and "Stop" causes
# PowerShell to treat native command stderr (e.g. Python tracebacks) as
# terminating errors, which breaks our import verification checks.

# Configuration
$MIN_PYTHON_VERSION = "3.10"
$RECOMMENDED_PYTHON_VERSION = "3.11"
$REQUIREMENTS_FILE = "requirements.txt"
$TRANSFORMERS_VERSION = "4.56.0"
$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
$APP_DIR = Split-Path -Parent $SCRIPT_DIR
$REQUIREMENTS_PATH = Join-Path $APP_DIR $REQUIREMENTS_FILE

function Write-Info {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Blue
}

function Write-Success {
    param([string]$Message)
    Write-Host "[SUCCESS] $Message" -ForegroundColor Green
}

function Write-WarnMsg {
    param([string]$Message)
    Write-Host "[WARNING] $Message" -ForegroundColor Yellow
}

function Write-ErrorMsg {
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
}

function Install-RequiredTransformers {
    param([string]$PythonExe)

    # Surya currently requires transformers <5 due to a known incompatibility.
    # See https://github.com/datalab-to/surya/issues/484 for details.
    Write-Info "Enforcing transformers==$TRANSFORMERS_VERSION for Surya compatibility..."
    & $PythonExe -m pip install --upgrade "transformers==$TRANSFORMERS_VERSION" | Out-Host
    if ($LASTEXITCODE -ne 0) {
        Write-ErrorMsg "Failed to install transformers==$TRANSFORMERS_VERSION"
        return $false
    }

    Write-Success "transformers==$TRANSFORMERS_VERSION installed successfully."
    return $true
}

function Test-PythonVersion {
    param([string]$PythonCmd)
    
    try {
        $versionOutput = & $PythonCmd --version 2>&1
        if ($LASTEXITCODE -eq 0) {
            $version = ($versionOutput -split ' ')[1]
            $versionParts = $version -split '\.'
            $major = [int]$versionParts[0]
            $minor = [int]$versionParts[1]
            $requiredMajor = [int]($MIN_PYTHON_VERSION -split '\.')[0]
            $requiredMinor = [int]($MIN_PYTHON_VERSION -split '\.')[1]
            
            if ($major -gt $requiredMajor -or ($major -eq $requiredMajor -and $minor -ge $requiredMinor)) {
                return $version
            }
        }
    } catch {
        return $null
    }
    return $null
}

function Find-Python {
    $candidates = @("python3.11", "python3.10", "python3", "python", "py -3.11", "py -3.10", "py -3")
    foreach ($cmd in $candidates) {
        $cmdParts = $cmd -split ' '
        if ($cmdParts.Count -eq 1) {
            if (Get-Command $cmd -ErrorAction SilentlyContinue) {
                if ($version = Test-PythonVersion $cmd) {
                    return $cmd, $version
                }
            }
        } else {
            # Handle "py -3.11" style commands
            if (Get-Command $cmdParts[0] -ErrorAction SilentlyContinue) {
                $fullCmd = $cmd -join ' '
                if ($version = Test-PythonVersion $fullCmd) {
                    return $fullCmd, $version
                }
            }
        }
    }
    return $null, $null
}

function Update-EnvFile {
    param([string]$PythonPath)
    
    $envFile = Join-Path $APP_DIR ".env"
    $envVarName = "GUILDSYNC_PYTHON_CMD"
    
    # Normalize path separators for Windows (use forward slashes or escaped backslashes)
    # .env files typically use forward slashes or escaped backslashes
    $normalizedPath = $PythonPath -replace '\\', '/'
    
    if (Test-Path $envFile) {
        # Create backup of .env file before making changes
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $backupFile = Join-Path $APP_DIR ".env.backup_$timestamp"
        try {
            Copy-Item -Path $envFile -Destination $backupFile -ErrorAction Stop
            Write-Info "Created backup of .env file: .env.backup_$timestamp"
        } catch {
            Write-ErrorMsg "Failed to create backup of .env file: $_"
            Write-ErrorMsg "Cannot safely update .env file without backup."
            Write-Info "Please manually add the following to your .env file:"
            Write-Info "  $envVarName=`"$normalizedPath`""
            return $false
        }
        
        # Read existing content (preserve empty lines)
        $rawContent = Get-Content $envFile -Raw
        if ($null -eq $rawContent) {
            $rawContent = ""
        }
        
        # Split into lines, preserving empty lines
        # Handle both Windows (\r\n) and Unix (\n) line endings
        $lineArray = if ($rawContent -match "`r`n") {
            $rawContent -split "`r`n"
        } else {
            $rawContent -split "`n"
        }
        
        # If file was empty, lineArray might be @("") or @(), normalize to empty array
        if ($lineArray.Count -eq 1 -and $lineArray[0] -eq "") {
            $lineArray = @()
        }
        
        # Check if variable already exists
        $found = $false
        $newLines = @()
        
        foreach ($line in $lineArray) {
            # Check if this line is the variable we're looking for (with or without quotes)
            if ($line -match "^$envVarName\s*=") {
                $newLines += "$envVarName=`"$normalizedPath`""
                $found = $true
            } else {
                # Only add non-empty lines, or preserve empty lines
                $newLines += $line
            }
        }
        
        if ($found) {
            Write-Info "Updating existing $envVarName in .env file..."
        } else {
            Write-Info "Adding $envVarName to .env file..."
            # Add newline before new entry if file wasn't empty
            if ($newLines.Count -gt 0 -and $newLines[-1] -ne "") {
                $newLines += ""
            }
            $newLines += "$envVarName=`"$normalizedPath`""
        }
        
        # Write back to file (join with newlines to preserve line breaks)
        # Use Windows line endings for consistency
        $content = $newLines -join "`r`n"
        try {
            # Use UTF8 encoding without BOM for .env files
            [System.IO.File]::WriteAllText($envFile, $content, [System.Text.UTF8Encoding]::new($false))
            Write-Success "Updated .env file with $envVarName=`"$normalizedPath`""
            return $true
        } catch {
            Write-ErrorMsg "Failed to write to .env file: $_"
            return $false
        }
    } else {
        # Create new .env file
        Write-Info "Creating new .env file..."
        try {
            # Use UTF8 encoding without BOM for .env files
            $content = "$envVarName=`"$normalizedPath`""
            [System.IO.File]::WriteAllText($envFile, $content, [System.Text.UTF8Encoding]::new($false))
            Write-Success "Created .env file with $envVarName=`"$normalizedPath`""
            return $true
        } catch {
            Write-ErrorMsg "Failed to create .env file: $_"
            return $false
        }
    }
}

function Setup-Venv {
    param([string]$PythonCmd)
    
    Write-Info "Setting up Python environment with venv..."
    
    $venvPath = Join-Path $APP_DIR ".venv"
    
    if (Test-Path $venvPath) {
        Write-WarnMsg "Virtual environment already exists at $venvPath"

        $pythonExePath = Join-Path $venvPath "Scripts\python.exe"
        if (Test-Path $pythonExePath) {
            # Verify imports first (attempts pip install for anything missing)
            if (Test-PythonImports $pythonExePath) {
                Write-Success "Existing virtual environment is healthy."
                if (-not (Update-EnvFile $pythonExePath)) {
                    return $false
                }
                return $true
            }
            Write-WarnMsg "Existing virtual environment failed import verification."
        } else {
            Write-WarnMsg "Python executable not found in existing virtual environment."
        }

        # At this point the existing venv is broken and needs to be recreated
        if ($Deploy) {
            Write-WarnMsg "Deploy mode: automatically recreating virtual environment..."
        } elseif ($Force) {
            Write-WarnMsg "Force flag set. Removing existing environment without confirmation..."
        } else {
            $response = Read-Host "Recreate the virtual environment? (y/N)"
            if ($response -ne 'y' -and $response -ne 'Y') {
                Write-ErrorMsg "Cannot proceed with broken virtual environment."
                return $false
            }
        }

        try {
            Remove-Item -Recurse -Force $venvPath -ErrorAction Stop
        } catch {
            Write-ErrorMsg "Failed to remove existing virtual environment: $_"
            return $false
        }
    }
    
    # Create virtual environment
    Write-Info "Creating virtual environment with $PythonCmd..."
    
    # Handle Python commands that may have spaces (e.g., "py -3.11")
    if ($PythonCmd -match '^(.+?)\s+(.+)$') {
        # Command has arguments (e.g., "py -3.11")
        $pythonExe = $matches[1]
        $pythonArgs = $matches[2]
        # For venv creation, we need to pass args separately: py -3.11 -m venv path
        $allArgs = @($pythonArgs, "-m", "venv", $venvPath)
        & $pythonExe $allArgs | Out-Host
    } else {
        # Simple command (e.g., "python" or "python3")
        # Use array syntax to ensure proper argument passing
        & $PythonCmd @("-m", "venv", $venvPath) | Out-Host
    }
    
    if ($LASTEXITCODE -ne 0) {
        Write-ErrorMsg "Failed to create virtual environment"
        return $false
    }
    
    Write-Success "Virtual environment created successfully!"
    
    # Activate and install dependencies
    Write-Info "Installing Python dependencies..."
    $activateScript = Join-Path $venvPath "Scripts\Activate.ps1"
    if (-not (Test-Path $activateScript)) {
        Write-ErrorMsg "Virtual environment activation script not found at: $activateScript"
        return $false
    }
    
    # Note: Activation script modifies environment, but we'll use python.exe directly
    $pythonExe = Join-Path $venvPath "Scripts\python.exe"
    if (-not (Test-Path $pythonExe)) {
        Write-ErrorMsg "Python executable not found in virtual environment at: $pythonExe"
        return $false
    }
    
    & $pythonExe -m pip install --upgrade pip | Out-Host
    
    if (Test-Path $REQUIREMENTS_PATH) {
        # Install PyTorch separately with GPU support if available
        # Check if CUDA is available by trying to run nvidia-smi
        $cudaAvailable = $false
        try {
            $nvidiaSmi = Get-Command nvidia-smi -ErrorAction SilentlyContinue
            if ($nvidiaSmi) {
                Write-Info "Checking for NVIDIA GPU..."
                $null = & nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>&1
                if ($LASTEXITCODE -eq 0) {
                    $cudaAvailable = $true
                    Write-Info "NVIDIA GPU detected. Installing PyTorch with CUDA support..."
                    # Try to detect CUDA version (common versions: 11.8, 12.1)
                    # Default to cu118 (CUDA 11.8) as it's widely compatible
                    # User can manually reinstall if needed
                    & $pythonExe -m pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu118 | Out-Host
                    if ($LASTEXITCODE -ne 0) {
                        Write-WarnMsg "Failed to install PyTorch with CUDA. Falling back to CPU version..."
                        & $pythonExe -m pip install torch --index-url https://download.pytorch.org/whl/cpu | Out-Host
                        if ($LASTEXITCODE -ne 0) {
                            Write-ErrorMsg "Failed to install PyTorch CPU version. Error code: $LASTEXITCODE"
                            return $false
                        }
                    } else {
                        Write-Success "PyTorch with CUDA support installed successfully!"
                    }
                } else {
                    Write-Info "nvidia-smi found but GPU query failed. Using CPU version of PyTorch."
                }
            } else {
                Write-Info "nvidia-smi not found. Using CPU version of PyTorch."
            }
        } catch {
            Write-WarnMsg "Error checking for NVIDIA GPU: $($_.Exception.Message)"
            Write-Info "Falling back to CPU version of PyTorch."
        }
        
        if (-not $cudaAvailable) {
            Write-Info "No GPU detected or nvidia-smi not available. Installing PyTorch CPU version..."
            & $pythonExe -m pip install torch --index-url https://download.pytorch.org/whl/cpu | Out-Host
        }
        
        # Install other requirements (torch is already commented out in requirements.txt)
        & $pythonExe -m pip install -r $REQUIREMENTS_PATH | Out-Host
        if ($LASTEXITCODE -ne 0) {
            Write-ErrorMsg "Failed to install requirements"
            return $false
        }

        if (-not (Install-RequiredTransformers $pythonExe)) {
            return $false
        }
        Write-Success "Dependencies installed successfully!"
    } else {
        Write-ErrorMsg "Requirements file not found at: $REQUIREMENTS_PATH"
        return $false
    }
    
    $pythonExePath = Join-Path $venvPath "Scripts\python.exe"
    
    # Update .env file
    if (-not (Update-EnvFile $pythonExePath)) {
        return $false
    }
    
    # Verify all required imports are available
    if (-not (Test-PythonImports $pythonExePath)) {
        Write-ErrorMsg "Virtual environment setup FAILED import verification."
        return $false
    }
    
    Write-Success "Virtual environment setup complete!"
    Write-Info "To activate: .\.venv\Scripts\Activate.ps1"
    Write-Info "Python path: $pythonExePath"
    Write-Info ""
    Write-Info "The GUILDSYNC_PYTHON_CMD environment variable has been automatically set in .env"
    return $true
}

# Helper: run a python import check without triggering NativeCommandError.
# $ErrorActionPreference = "Stop" treats native stderr as a terminating error,
# so we merge stderr into stdout and capture it to prevent that.
function Test-SinglePythonImport {
    param([string]$PythonExe, [string]$Statement)
    $null = & $PythonExe -c $Statement 2>&1
    return ($LASTEXITCODE -eq 0)
}

# Function to verify all required Python imports are available.
# These correspond to the imports in lib/scripts/surya_ocr.py lines 5-9.
# On failure, runs pip install -r requirements.txt, then re-verifies.
function Test-PythonImports {
    param([string]$PythonExe)

    Write-Info "Verifying required Python imports..."

    $allImports = @(
        @{ Module = "PIL";                        Symbol = "Image";                 Package = "Pillow" }
        @{ Module = "surya.recognition";          Symbol = "RecognitionPredictor";  Package = "surya-ocr" }
        @{ Module = "surya.foundation";           Symbol = "FoundationPredictor";   Package = "surya-ocr" }
        @{ Module = "surya.detection";            Symbol = "DetectionPredictor";    Package = "surya-ocr" }
        @{ Module = "surya.common.surya.schema";  Symbol = "TaskNames";            Package = "surya-ocr" }
    )

    # First pass: check all imports
    $anyFailed = $false
    foreach ($import in $allImports) {
        $stmt = "from $($import.Module) import $($import.Symbol)"
        if (-not (Test-SinglePythonImport $PythonExe $stmt)) {
            Write-WarnMsg "  MISSING: $stmt  (package: $($import.Package))"
            $anyFailed = $true
        } else {
            Write-Success "  $stmt"
        }
    }

    if (-not $anyFailed) {
        Write-Success "All required Python imports verified successfully."
        return $true
    }

    # Something is missing -- run pip install -r requirements.txt
    Write-WarnMsg "One or more imports missing. Running pip install -r requirements.txt..."
    & $PythonExe -m pip install -r $REQUIREMENTS_PATH | Out-Host
    if ($LASTEXITCODE -ne 0) {
        Write-ErrorMsg "pip install -r requirements.txt failed."
        return $false
    }

    if (-not (Install-RequiredTransformers $PythonExe)) {
        return $false
    }

    # Second pass: re-verify all imports
    Write-Info "Re-verifying imports after install..."
    $failed = $false
    foreach ($import in $allImports) {
        $stmt = "from $($import.Module) import $($import.Symbol)"
        if (Test-SinglePythonImport $PythonExe $stmt) {
            Write-Success "  $stmt"
        } else {
            Write-ErrorMsg "  FAILED: $stmt  (package: $($import.Package))"
            $failed = $true
        }
    }

    if ($failed) {
        Write-ErrorMsg "One or more required imports still failed after pip install."
        return $false
    }

    Write-Success "All required Python imports verified successfully."
    return $true
}

# Main
Write-Info "Python Environment Setup"
Write-Info "========================"

if (-not (Test-Path $REQUIREMENTS_PATH)) {
    Write-ErrorMsg "Requirements file not found at: $REQUIREMENTS_PATH"
    exit 1
}

# Check for Python
Write-Info "Checking for Python..."
$pythonCmd, $version = Find-Python
if ($pythonCmd) {
    Write-Info "Found Python: $pythonCmd ($version)"
    if (Setup-Venv $pythonCmd) {
        exit 0
    } else {
        Write-ErrorMsg "Python environment setup failed."
        exit 1
    }
}

# No Python found
Write-ErrorMsg "Python $MIN_PYTHON_VERSION or higher not found!"
Write-Info "Please install Python $MIN_PYTHON_VERSION or higher:"
Write-Info "  - Download from: https://www.python.org/downloads/"
Write-Info "  - Or use Windows Store: python3.11"
exit 1

