#!/bin/bash
# Setup Python virtual environment for application services
# This script sets up a Python environment with the required dependencies
# Prioritizes conda if available, otherwise uses venv/pyenv

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
MIN_PYTHON_VERSION="3.10"
RECOMMENDED_PYTHON_VERSION="3.11"
ENV_NAME="guildsync-python"
REQUIREMENTS_FILE="requirements.txt"
TRANSFORMERS_VERSION="4.56.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REQUIREMENTS_PATH="$APP_DIR/$REQUIREMENTS_FILE"

# Function to print colored messages
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Surya currently requires transformers <5 due to a known incompatibility.
# See https://github.com/datalab-to/surya/issues/484 for details.
# Explicitly enforce the supported transformers version after requirements install.
enforce_transformers_version() {
    local python_exe=$1
    print_info "Enforcing transformers==$TRANSFORMERS_VERSION for Surya compatibility..."
    if ! "$python_exe" -m pip install --upgrade "transformers==$TRANSFORMERS_VERSION"; then
        print_error "Failed to install transformers==$TRANSFORMERS_VERSION"
        return 1
    fi
    print_success "transformers==$TRANSFORMERS_VERSION installed successfully."
    return 0
}

# Function to check Python version
check_python_version() {
    local python_cmd=$1
    if command -v "$python_cmd" &> /dev/null; then
        local version=$($python_cmd --version 2>&1 | awk '{print $2}')
        local major=$(echo "$version" | cut -d. -f1)
        local minor=$(echo "$version" | cut -d. -f2)
        local required_major=$(echo "$MIN_PYTHON_VERSION" | cut -d. -f1)
        local required_minor=$(echo "$MIN_PYTHON_VERSION" | cut -d. -f2)
        
        if [ "$major" -gt "$required_major" ] || ([ "$major" -eq "$required_major" ] && [ "$minor" -ge "$required_minor" ]); then
            echo "$version"
            return 0
        fi
    fi
    return 1
}

# Function to find Python executable
# On macOS, Python 3 is typically available as 'python3'
# This function checks candidates in order: specific versions, then generic python3, then python
find_python() {
    local candidates=("python3.11" "python3.10" "python3" "python")
    for cmd in "${candidates[@]}"; do
        if version=$(check_python_version "$cmd"); then
            echo "$cmd"
            return 0
        fi
    done
    return 1
}

# Function to update .env file
update_env_file() {
    local python_exe=$1
    local env_file="$APP_DIR/.env"
    local env_var_name="GUILDSYNC_PYTHON_CMD"
    
    if [ -f "$env_file" ]; then
        # Create backup of .env file before making changes
        local timestamp=$(date +"%Y%m%d_%H%M%S")
        local backup_file="$APP_DIR/.env.backup_$timestamp"
        if cp "$env_file" "$backup_file" 2>/dev/null; then
            print_info "Created backup of .env file: .env.backup_$timestamp"
        else
            print_error "Failed to create backup of .env file"
            print_error "Cannot safely update .env file without backup."
            print_info "Please manually add the following to your .env file:"
            print_info "  $env_var_name=\"$python_exe\""
            return 1
        fi
        
        # Check if variable already exists
        if grep -q "^$env_var_name=" "$env_file"; then
            # Update existing variable
            print_info "Updating existing $env_var_name in .env file..."
            if [[ "$OSTYPE" == "darwin"* ]]; then
                # macOS uses BSD sed
                if ! sed -i '' "s|^$env_var_name=.*|$env_var_name=\"$python_exe\"|" "$env_file" 2>/dev/null; then
                    print_error "Failed to update .env file"
                    return 1
                fi
            else
                # Linux uses GNU sed
                if ! sed -i "s|^$env_var_name=.*|$env_var_name=\"$python_exe\"|" "$env_file" 2>/dev/null; then
                    print_error "Failed to update .env file"
                    return 1
                fi
            fi
        else
            # Add new variable
            print_info "Adding $env_var_name to .env file..."
            if ! echo "$env_var_name=\"$python_exe\"" >> "$env_file" 2>/dev/null; then
                print_error "Failed to append to .env file"
                return 1
            fi
        fi
        print_success "Updated .env file with $env_var_name=\"$python_exe\""
        return 0
    else
        # Create new .env file
        print_info "Creating new .env file..."
        if ! echo "$env_var_name=\"$python_exe\"" > "$env_file" 2>/dev/null; then
            print_error "Failed to create .env file"
            return 1
        fi
        print_success "Created .env file with $env_var_name=\"$python_exe\""
        return 0
    fi
}

# Function to setup with conda
setup_conda() {
    print_info "Setting up Python environment with conda..."
    
    # Check if conda is properly initialized
    if ! command -v conda &> /dev/null; then
        print_error "Conda command not found or not initialized"
        return 1
    fi
    
    # Check if conda environment already exists
    if conda env list 2>/dev/null | grep -q "^$ENV_NAME "; then
        print_warning "Conda environment '$ENV_NAME' already exists."

        # Try to activate and verify imports
        if eval "$(conda shell.bash hook)" && conda activate "$ENV_NAME" 2>/dev/null; then
            local python_exe=$(which python)
            # Verify imports first (attempts pip install for anything missing)
            if verify_python_imports "$python_exe"; then
                print_success "Existing conda environment is healthy."
                if ! update_env_file "$python_exe"; then
                    return 1
                fi
                return 0
            fi
            print_warning "Existing conda environment failed import verification."
        else
            print_warning "Failed to activate existing conda environment."
        fi

        # At this point the existing conda env is broken and needs to be recreated
        if [ "$NON_INTERACTIVE" = true ]; then
            print_warning "Deploy mode: automatically recreating conda environment..."
        else
            read -p "Recreate the conda environment? (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                print_error "Cannot proceed with broken conda environment."
                return 1
            fi
        fi

        if ! conda env remove -n "$ENV_NAME" -y; then
            print_error "Failed to remove existing conda environment"
            return 1
        fi
    fi
    
    # Create conda environment with Python 3.11 (or latest available)
    print_info "Creating conda environment '$ENV_NAME' with Python $RECOMMENDED_PYTHON_VERSION..."
    if conda create -n "$ENV_NAME" python="$RECOMMENDED_PYTHON_VERSION" -y; then
        print_success "Conda environment created successfully!"
    else
        print_warning "Failed to create with Python $RECOMMENDED_PYTHON_VERSION, trying Python 3.10..."
        if ! conda create -n "$ENV_NAME" python="3.10" -y; then
            print_error "Failed to create conda environment"
            return 1
        fi
    fi
    
    # Activate and install dependencies
    print_info "Installing Python dependencies..."
    if ! eval "$(conda shell.bash hook)"; then
        print_error "Failed to initialize conda shell hook"
        return 1
    fi
    
    if ! conda activate "$ENV_NAME"; then
        print_error "Failed to activate conda environment '$ENV_NAME'"
        return 1
    fi
    
    # Upgrade pip
    if ! python -m pip install --upgrade pip; then
        print_error "Failed to upgrade pip"
        return 1
    fi
    
    # Install requirements
    if [ -f "$REQUIREMENTS_PATH" ]; then
        # Install PyTorch separately with GPU support if available
        # Check if CUDA is available by trying to run nvidia-smi
        if command -v nvidia-smi &> /dev/null && nvidia-smi &> /dev/null; then
            print_info "NVIDIA GPU detected. Installing PyTorch with CUDA support..."
            # Try to detect CUDA version (common versions: 11.8, 12.1)
            # Default to cu118 (CUDA 11.8) as it's widely compatible
            # User can manually reinstall if needed
            if ! python -m pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu118; then
                print_warning "Failed to install PyTorch with CUDA. Falling back to CPU version..."
                if ! python -m pip install torch --index-url https://download.pytorch.org/whl/cpu; then
                    print_error "Failed to install PyTorch CPU version."
                    return 1
                fi
            fi
        else
            print_info "No GPU detected or nvidia-smi not available. Installing PyTorch CPU version..."
            if ! python -m pip install torch --index-url https://download.pytorch.org/whl/cpu; then
                print_error "Failed to install PyTorch CPU version."
                return 1
            fi
        fi
        
        # Install other requirements (torch is already commented out in requirements.txt)
        if ! python -m pip install -r "$REQUIREMENTS_PATH"; then
            print_error "Failed to install requirements"
            return 1
        fi

        print_success "Dependencies installed successfully!"
    else
        print_error "Requirements file not found at: $REQUIREMENTS_PATH"
        return 1
    fi
    
    # Get the Python executable path from the conda environment
    local python_exe=$(which python)
    
    # Update .env file
    if ! update_env_file "$python_exe"; then
        return 1
    fi
    
    # Verify all required imports are available
    if ! verify_python_imports "$python_exe"; then
        print_error "Conda environment setup FAILED import verification."
        return 1
    fi
    
    print_success "Conda environment setup complete!"
    print_info "To activate: conda activate $ENV_NAME"
    print_info "Python executable: $python_exe"
    print_info "Python version: $("$python_exe" --version)"
    echo
    print_info "The GUILDSYNC_PYTHON_CMD environment variable has been automatically set in .env"
}

# Function to setup with venv
setup_venv() {
    local python_cmd=$1
    print_info "Setting up Python environment with venv..."
    
    # Check if venv already exists
    local venv_path="$APP_DIR/.venv"
    if [ -d "$venv_path" ]; then
        print_warning "Virtual environment already exists at $venv_path"

        local python_exe="$venv_path/bin/python"
        if [ -f "$python_exe" ]; then
            # Verify imports first (attempts pip install for anything missing)
            if verify_python_imports "$python_exe"; then
                print_success "Existing virtual environment is healthy."
                if ! update_env_file "$python_exe"; then
                    return 1
                fi
                return 0
            fi
            print_warning "Existing virtual environment failed import verification."
        else
            print_warning "Python executable not found in existing virtual environment."
        fi

        # At this point the existing venv is broken and needs to be recreated
        if [ "$NON_INTERACTIVE" = true ]; then
            print_warning "Deploy mode: automatically recreating virtual environment..."
        else
            read -p "Recreate the virtual environment? (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                print_error "Cannot proceed with broken virtual environment."
                return 1
            fi
        fi

        if ! rm -rf "$venv_path"; then
            print_error "Failed to remove existing virtual environment"
            return 1
        fi
    fi
    
    # Create virtual environment
    print_info "Creating virtual environment with $python_cmd..."
    if $python_cmd -m venv "$venv_path"; then
        print_success "Virtual environment created successfully!"
    else
        print_error "Failed to create virtual environment"
        return 1
    fi
    
    # Use the venv python executable directly (more reliable than activation in CI/deploy)
    local python_exe="$venv_path/bin/python"
    if [ ! -f "$python_exe" ]; then
        print_error "Python executable not found in virtual environment at: $python_exe"
        return 1
    fi
    
    print_info "Installing Python dependencies..."
    
    # Ensure pip is available in the venv (Ubuntu may create venvs without pip
    # if python3-pip or ensurepip is not installed)
    if ! "$python_exe" -m pip --version &>/dev/null; then
        print_warning "pip not found in virtual environment. Bootstrapping with ensurepip..."
        if ! "$python_exe" -m ensurepip --upgrade 2>/dev/null; then
            print_warning "ensurepip failed. Attempting get-pip.py..."
            local get_pip_path="$venv_path/get-pip.py"
            if command -v curl &>/dev/null; then
                curl -sSL https://bootstrap.pypa.io/get-pip.py -o "$get_pip_path"
            elif command -v wget &>/dev/null; then
                wget -qO "$get_pip_path" https://bootstrap.pypa.io/get-pip.py
            else
                print_error "Neither curl nor wget available. Cannot bootstrap pip."
                print_error "On Ubuntu/Debian, install with: sudo apt-get install python3-pip python3-venv"
                return 1
            fi
            if ! "$python_exe" "$get_pip_path"; then
                print_error "Failed to bootstrap pip via get-pip.py."
                print_error "On Ubuntu/Debian, install with: sudo apt-get install python3-pip python3-venv"
                rm -f "$get_pip_path"
                return 1
            fi
            rm -f "$get_pip_path"
        fi
        print_success "pip bootstrapped successfully."
    fi
    
    # Upgrade pip
    if ! "$python_exe" -m pip install --upgrade pip; then
        print_error "Failed to upgrade pip"
        return 1
    fi
    
    # Install requirements
    if [ -f "$REQUIREMENTS_PATH" ]; then
        # Install PyTorch separately with GPU support if available
        # Check if CUDA is available by trying to run nvidia-smi
        if command -v nvidia-smi &> /dev/null && nvidia-smi &> /dev/null; then
            print_info "NVIDIA GPU detected. Installing PyTorch with CUDA support..."
            # Try to detect CUDA version (common versions: 11.8, 12.1)
            # Default to cu118 (CUDA 11.8) as it's widely compatible
            # User can manually reinstall if needed
            if ! "$python_exe" -m pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu118; then
                print_warning "Failed to install PyTorch with CUDA. Falling back to CPU version..."
                if ! "$python_exe" -m pip install torch --index-url https://download.pytorch.org/whl/cpu; then
                    print_error "Failed to install PyTorch CPU version."
                    return 1
                fi
            fi
        else
            print_info "No GPU detected or nvidia-smi not available. Installing PyTorch CPU version..."
            if ! "$python_exe" -m pip install torch --index-url https://download.pytorch.org/whl/cpu; then
                print_error "Failed to install PyTorch CPU version."
                return 1
            fi
        fi
        
        # Install other requirements (torch is already commented out in requirements.txt)
        if ! "$python_exe" -m pip install -r "$REQUIREMENTS_PATH"; then
            print_error "Failed to install requirements"
            return 1
        fi

        print_success "Dependencies installed successfully!"
    else
        print_error "Requirements file not found at: $REQUIREMENTS_PATH"
        return 1
    fi
    
    # Update .env file
    if ! update_env_file "$python_exe"; then
        return 1
    fi
    
    # Verify all required imports are available
    if ! verify_python_imports "$python_exe"; then
        print_error "Virtual environment setup FAILED import verification."
        return 1
    fi
    
    print_success "Virtual environment setup complete!"
    print_info "To activate: source $venv_path/bin/activate"
    print_info "Python executable: $python_exe"
    print_info "Python version: $("$python_exe" --version)"
    echo
    print_info "The GUILDSYNC_PYTHON_CMD environment variable has been automatically set in .env"
}

# Function to verify all required Python imports are available
# These correspond to the imports in lib/scripts/surya_ocr.py (lines 5-9)
# On failure, runs pip install -r requirements.txt, then re-verifies.
verify_python_imports() {
    local python_exe=$1
    print_info "Verifying required Python imports..."

    local all_imports=(
        "PIL:Image:Pillow"
        "surya.recognition:RecognitionPredictor:surya-ocr"
        "surya.foundation:FoundationPredictor:surya-ocr"
        "surya.detection:DetectionPredictor:surya-ocr"
        "surya.common.surya.schema:TaskNames:surya-ocr"
    )

    # First pass: check all imports
    local any_failed=0
    for entry in "${all_imports[@]}"; do
        local module=$(echo "$entry" | cut -d: -f1)
        local symbol=$(echo "$entry" | cut -d: -f2)
        local package=$(echo "$entry" | cut -d: -f3)
        if "$python_exe" -c "from $module import $symbol" 2>/dev/null; then
            print_success "  from $module import $symbol"
        else
            print_warning "  MISSING: from $module import $symbol  (package: $package)"
            any_failed=1
        fi
    done

    if [ "$any_failed" -eq 0 ]; then
        if ! enforce_transformers_version "$python_exe"; then
            return 1
        fi
        print_success "All required Python imports verified successfully."
        return 0
    fi

    # Something is missing -- attempt pip install -r requirements.txt
    # First check if pip is even available (existing venvs may lack it on Ubuntu)
    if ! "$python_exe" -m pip --version &>/dev/null; then
        print_error "pip is not available in this environment. Cannot install missing packages."
        return 1
    fi

    print_warning "One or more imports missing. Running pip install -r requirements.txt..."
    if ! "$python_exe" -m pip install -r "$REQUIREMENTS_PATH"; then
        print_error "pip install -r requirements.txt failed."
        return 1
    fi

    if ! enforce_transformers_version "$python_exe"; then
        return 1
    fi

    # Second pass: re-verify all imports
    print_info "Re-verifying imports after install..."
    local failed=0
    for entry in "${all_imports[@]}"; do
        local module=$(echo "$entry" | cut -d: -f1)
        local symbol=$(echo "$entry" | cut -d: -f2)
        local package=$(echo "$entry" | cut -d: -f3)
        if "$python_exe" -c "from $module import $symbol" 2>/dev/null; then
            print_success "  from $module import $symbol"
        else
            print_error "  FAILED: from $module import $symbol  (package: $package)"
            failed=1
        fi
    done

    if [ "$failed" -eq 1 ]; then
        print_error "One or more required imports still failed after pip install."
        return 1
    fi

    print_success "All required Python imports verified successfully."
    return 0
}

# Main setup function
main() {
    print_info "Python Environment Setup"
    print_info "========================"
    
    # Check if requirements file exists
    if [ ! -f "$REQUIREMENTS_PATH" ]; then
        print_error "Requirements file not found at: $REQUIREMENTS_PATH"
        exit 1
    fi
    
    # Check for conda first (priority)
    if command -v conda &> /dev/null; then
        print_info "Conda detected. Using conda for environment management..."
        setup_conda
        exit $?
    fi
    
    # Check for Python
    print_info "Conda not found. Checking for Python..."
    if python_cmd=$(find_python); then
        version=$(check_python_version "$python_cmd")
        print_info "Found Python: $python_cmd ($version)"
        setup_venv "$python_cmd"
        exit $?
    fi
    
    # No Python found
    print_error "Python $MIN_PYTHON_VERSION or higher not found!"
    print_info "Please install Python $MIN_PYTHON_VERSION or higher:"
    print_info "  - macOS: brew install python@3.11"
    print_info "  - Ubuntu/Debian: sudo apt-get install python3.11 python3.11-venv"
    print_info "  - Or download from: https://www.python.org/downloads/"
    exit 1
}

# Parse arguments
NON_INTERACTIVE=false
for arg in "$@"; do
    case $arg in
        --deploy|--non-interactive)
            NON_INTERACTIVE=true
            ;;
    esac
done

# Run main function
main "$@"

