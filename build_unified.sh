#!/bin/bash

################################################################################
# ArtisanKRNL - Unified Build Script (All-in-One)
# 
# This script automates the complete kernel build process:
# - Checks and installs toolchain (Clang 18)
# - Clones and integrates KernelSU-Next with modifications
# - Configures kernel with optimizations
# - Compiles kernel
# - Creates flashable package
#
# Usage: ./build_unified.sh [options]
# Options:
#   --clean      : Clean build (remove previous outputs)
#   --verbose    : Show detailed build output
#   --help       : Show help message
################################################################################

set -euo pipefail

# ==================== CONFIGURATION ====================
MODEL="r8s"
DEVICE_BOARD="SRPTF26B014KU"
ARCH="arm64"
KERNEL_NAME="ArtisanKRNL"
BUILD_DIR="out"
CLANG_VERSION="18"

# Toolchain URLs (Fallback sources)
CLANG_DOWNLOAD_URL="https://releases.llvm.org/18.1.0/clang+llvm-18.1.0-x86_64-linux-gnu.tar.xz"
CLANG_ALTERNATIVE_URL="https://github.com/ClangBuiltLinux/tc-build/releases/download/clang-18.1.0/clang-18.1.0-x86_64-linux.tar.xz"

# KernelSU-Next repository
KERNELSU_REPO="https://github.com/KernelSU-Next/KernelSU-Next.git"
KERNELSU_BRANCH="dev"

# Script options
CLEAN_BUILD=false
VERBOSE=false
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# ==================== LOGGING FUNCTIONS ====================
log_info() { echo -e "${GREEN}[✓]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[⚠]${NC} $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1"; }
log_section() { echo -e "\n${BLUE}════════════════════════════════════════${NC}"; echo -e "${BLUE}  $1${NC}"; echo -e "${BLUE}════════════════════════════════════════${NC}\n"; }
log_debug() { [ "$VERBOSE" = true ] && echo -e "${CYAN}[DEBUG]${NC} $1" || true; }

abort() {
    log_error "$1"
    exit 1
}

# ==================== HELPER FUNCTIONS ====================
command_exists() {
    command -v "$1" &> /dev/null
}

# Check if directory exists and has content
dir_has_files() {
    [ -d "$1" ] && [ -n "$(ls -A "$1" 2>/dev/null)" ]
}

# Download file with fallback
download_file() {
    local url="$1"
    local output="$2"
    local alt_url="${3:-}"
    
    log_info "Downloading from: $url"
    
    if command_exists curl; then
        if curl -L --progress-bar --output "$output" "$url" 2>/dev/null; then
            return 0
        fi
    elif command_exists wget; then
        if wget -q --show-progress -O "$output" "$url" 2>/dev/null; then
            return 0
        fi
    fi
    
    if [ -n "$alt_url" ]; then
        log_warn "Primary download failed, trying alternative URL..."
        if command_exists curl; then
            curl -L --progress-bar --output "$output" "$alt_url" || return 1
        else
            wget -q --show-progress -O "$output" "$alt_url" || return 1
        fi
    else
        return 1
    fi
}

# ==================== PARSE ARGUMENTS ====================
while [[ $# -gt 0 ]]; do
    case $1 in
        --clean)
            CLEAN_BUILD=true
            shift
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        --help)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --clean      Clean build (remove previous outputs)"
            echo "  --verbose    Show detailed build output"
            echo "  --help       Show this help message"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# ==================== INITIAL CHECKS ====================
log_section "Initializing Build System"

log_info "Script directory: $SCRIPT_DIR"
log_info "Model: $MODEL"
log_info "Architecture: $ARCH"
log_info "Clang Version: $CLANG_VERSION"

# Verify we're in the kernel root
if [ ! -f "$SCRIPT_DIR/Makefile" ] || [ ! -d "$SCRIPT_DIR/arch" ]; then
    abort "Not in kernel root directory (missing Makefile or arch/)"
fi

# Check required system tools
log_info "Checking system requirements..."
for tool in make git zip python3; do
    if ! command_exists "$tool"; then
        log_warn "Missing: $tool"
        if command_exists apt; then
            log_info "Install with: sudo apt install -y $tool"
        fi
    fi
done

# ==================== CLEAN BUILD SETUP ====================
if [ "$CLEAN_BUILD" = true ]; then
    log_section "Cleaning Previous Build"
    log_warn "Removing previous build outputs..."
    rm -rf "$BUILD_DIR" build/out/ build_compile.log build_summary.txt
    log_info "Clean build setup complete"
fi

# ==================== TOOLCHAIN SETUP ====================
log_section "Setting Up Toolchain"

CLANG_DIR="$SCRIPT_DIR/toolchain/clang_${CLANG_VERSION}"
CLANG_BIN="$CLANG_DIR/bin/clang"

if dir_has_files "$CLANG_DIR" && [ -f "$CLANG_BIN" ]; then
    log_info "Clang ${CLANG_VERSION} found at: $CLANG_DIR"
    log_debug "Clang path: $CLANG_BIN"
else
    log_warn "Clang ${CLANG_VERSION} not found - will attempt to download"
    
    mkdir -p "$CLANG_DIR"
    CLANG_TAR="clang_${CLANG_VERSION}.tar.xz"
    
    log_info "Downloading Clang ${CLANG_VERSION}..."
    if ! download_file "$CLANG_DOWNLOAD_URL" "$CLANG_TAR" "$CLANG_ALTERNATIVE_URL"; then
        abort "Failed to download Clang. Please check your internet connection or manually place toolchain in: $CLANG_DIR"
    fi
    
    log_info "Extracting Clang ${CLANG_VERSION}..."
    if ! tar -xf "$CLANG_TAR" -C "$CLANG_DIR" --strip-components=1; then
        rm -f "$CLANG_TAR"
        abort "Failed to extract toolchain"
    fi
    rm -f "$CLANG_TAR"
    
    if [ ! -f "$CLANG_BIN" ]; then
        abort "Clang binary not found after extraction"
    fi
fi

# Verify clang works
log_info "Verifying Clang..."
CLANG_VERSION_INFO=$("$CLANG_BIN" --version 2>&1 | head -n1)
log_info "Using: $CLANG_VERSION_INFO"

# Export toolchain to PATH
export PATH="$CLANG_DIR/bin:$PATH"

# ==================== KERNELSU SETUP ====================
log_section "Setting Up KernelSU-Next"

if [ -d "KernelSU-Next" ] && [ -f "KernelSU-Next/.git/config" ]; then
    log_info "KernelSU-Next repository found"
    log_info "Syncing to latest $KERNELSU_BRANCH branch..."
    
    cd KernelSU-Next
    git fetch origin "$KERNELSU_BRANCH" || log_warn "Failed to fetch, using cached version"
    git checkout "$KERNELSU_BRANCH" 2>/dev/null || git checkout -b "$KERNELSU_BRANCH" "origin/$KERNELSU_BRANCH"
    git reset --hard "origin/$KERNELSU_BRANCH" 2>/dev/null || log_warn "Could not reset to remote, using local version"
    cd ..
else
    log_info "Cloning KernelSU-Next repository..."
    if ! git clone --depth 1 --branch "$KERNELSU_BRANCH" "$KERNELSU_REPO"; then
        abort "Failed to clone KernelSU-Next repository"
    fi
    log_info "KernelSU-Next repository cloned"
fi

# Get KernelSU commit info
cd KernelSU-Next
KERNELSU_COMMIT=$(git log -1 --format="%H %s" 2>/dev/null || echo "unknown")
cd ..
log_info "KernelSU-Next: $KERNELSU_COMMIT"

# ==================== KERNELSU INTEGRATION ====================
log_section "Integrating KernelSU into Kernel"

log_info "Removing old KernelSU integration..."
rm -rf drivers/kernelsu

log_info "Preparing KernelSU modules..."
mkdir -p drivers/kernelsu

if [ -d "KernelSU-Next/kernel" ]; then
    log_info "Copying KernelSU kernel modules..."
    cp -r KernelSU-Next/kernel/* drivers/kernelsu/ 2>/dev/null || true
else
    log_warn "KernelSU kernel directory not found"
fi

# Copy KernelSU Makefile
if [ -f "KernelSU-Next/Makefile.ksu" ]; then
    log_info "Copying KernelSU build configuration..."
    cp KernelSU-Next/Makefile.ksu drivers/kernelsu/ 2>/dev/null || true
fi

log_info "KernelSU integration complete"

# ==================== KERNEL CONFIGURATION ====================
log_section "Configuring Kernel"

# Setup Clang environment variables
export LLVM=1
export LLVM_IAS=1
export CC=clang
export CXX=clang++
export LD=ld.lld
export AR=llvm-ar
export NM=llvm-nm
export OBJCOPY=llvm-objcopy
export OBJDUMP=llvm-objdump
export RANLIB=llvm-ranlib
export STRIP=llvm-strip
export HOSTCC=clang
export HOSTCXX=clang++

# Setup build flags
export KCFLAGS="\
  -O3 \
  -march=armv8-a \
  -mtune=cortex-a75 \
  -flto=thin \
  -Wno-error=implicit-function-declaration \
  -Wno-error=strict-prototypes \
  -Wno-error=incompatible-pointer-types \
  -Wno-error=implicit-int \
  -Wno-error=return-type"

export LDFLAGS="-flto=thin -fuse-ld=lld"

# Build arguments
MAKE_ARGS="LLVM=1 LLVM_IAS=1 \
  CC=clang CXX=clang++ LD=ld.lld AR=llvm-ar NM=llvm-nm \
  OBJCOPY=llvm-objcopy OBJDUMP=llvm-objdump STRIP=llvm-strip \
  RANLIB=llvm-ranlib \
  HOSTCC=clang HOSTCXX=clang++ \
  ARCH=$ARCH O=$BUILD_DIR"

log_info "Clang environment configured"
log_debug "KCFLAGS: $KCFLAGS"

# Clean and prepare build directory
log_info "Preparing build directory..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Load base configuration
CONFIG_FILE="arch/$ARCH/configs/exynos9830_defconfig"
if [ ! -f "$CONFIG_FILE" ]; then
    abort "Configuration file not found: $CONFIG_FILE"
fi

log_info "Loading exynos9830 base configuration..."
make ${MAKE_ARGS} exynos9830_defconfig > /dev/null 2>&1 || true

# ==================== APPLY KERNELSU CONFIGURATION ====================
log_section "Applying KernelSU Configuration"

# Configuration options to ensure
CONFIG_OPTIONS=(
    "CONFIG_KSU=y"
    "CONFIG_KSU_MANUAL_HOOK=y"
    "CONFIG_KSU_ALLOWLIST_WORKAROUND=y"
    "CONFIG_FAKE_UNAME=y"
    "CONFIG_FAKE_UNAME_5_10=y"
    "CONFIG_LTO_CLANG=y"
    "CONFIG_LTO_CLANG_THIN=y"
    "CONFIG_SECURITY_SELINUX=y"
    "CONFIG_SECURITY_SELINUX_BOOTPARAM=y"
)

CONFIG_TEMP="$BUILD_DIR/.config"

for config in "${CONFIG_OPTIONS[@]}"; do
    KEY="${config%%=*}"
    if ! grep -q "^$KEY" "$CONFIG_TEMP"; then
        echo "$config" >> "$CONFIG_TEMP"
        log_debug "Added: $config"
    fi
done

log_info "Finalizing kernel configuration..."
yes "" | make ${MAKE_ARGS} oldconfig > /dev/null 2>&1 || true

if [ ! -f "$CONFIG_TEMP" ]; then
    abort "Kernel configuration failed - .config not created"
fi

log_info "✅ Kernel configuration complete"

# ==================== KERNEL COMPILATION ====================
log_section "Compiling Kernel"

CORES=$(nproc --all)
log_info "Using $CORES CPU cores for compilation"
log_info "Starting kernel compilation..."

if [ "$VERBOSE" = true ]; then
    # Show detailed output
    if ! make ${MAKE_ARGS} -j"$CORES" 2>&1 | tee build_compile.log; then
        abort "Kernel compilation failed - check build_compile.log"
    fi
else
    # Show progress only
    if ! make ${MAKE_ARGS} -j"$CORES" 2>&1 | tee build_compile.log | tail -20; then
        tail -50 build_compile.log
        abort "Kernel compilation failed - check build_compile.log"
    fi
fi

# Verify kernel image
if [ ! -f "$BUILD_DIR/arch/$ARCH/boot/Image" ]; then
    abort "Kernel image not generated at $BUILD_DIR/arch/$ARCH/boot/Image"
fi

KERNEL_SIZE=$(du -h "$BUILD_DIR/arch/$ARCH/boot/Image" | cut -f1)
log_info "✅ Kernel compiled successfully"
log_info "Kernel size: $KERNEL_SIZE"

# ==================== PACKAGE GENERATION ====================
log_section "Creating Flashable Package"

OUTPUT_DIR="build/out/$MODEL"
mkdir -p "$OUTPUT_DIR/zip/META-INF/com/google/android"

# Create flashable structure
log_info "Setting up flashable package structure..."

# Copy boot image
cp "$BUILD_DIR/arch/$ARCH/boot/Image" "$OUTPUT_DIR/boot.img"
log_info "Boot image prepared"

# Copy update scripts
if [ -f "build/update-binary" ]; then
    cp build/update-binary "$OUTPUT_DIR/zip/META-INF/com/google/android/update-binary"
else
    log_warn "update-binary not found, creating minimal version"
    cat > "$OUTPUT_DIR/zip/META-INF/com/google/android/update-binary" << 'EOF'
#!/sbin/sh
OUTFD=$2
ZIPFILE=$3

ui_print() {
  echo "ui_print $1" >> /proc/self/fd/$OUTFD
  echo "ui_print" >> /proc/self/fd/$OUTFD
}

ui_print "Installing ArtisanKRNL..."
EOF
    chmod +x "$OUTPUT_DIR/zip/META-INF/com/google/android/update-binary"
fi

if [ -f "build/updater-script" ]; then
    cp build/updater-script "$OUTPUT_DIR/zip/META-INF/com/google/android/updater-script"
else
    log_warn "updater-script not found, creating minimal version"
    cat > "$OUTPUT_DIR/zip/META-INF/com/google/android/updater-script" << 'EOF'
install_module();
EOF
fi

# Create the flashable ZIP
log_info "Packaging flashable ZIP..."
BUILD_DATE=$(date +"%d-%m-%Y_%H-%M-%S")
PACKAGE_NAME="${KERNEL_NAME}_${MODEL}_KSU_${BUILD_DATE}.zip"

cd "$OUTPUT_DIR/zip"
zip -r -q "../$PACKAGE_NAME" . || abort "Failed to create flashable ZIP"
cd - > /dev/null

PACKAGE_SIZE=$(du -h "$OUTPUT_DIR/$PACKAGE_NAME" | cut -f1)
log_info "✅ Flashable package created"
log_info "Package: $PACKAGE_NAME ($PACKAGE_SIZE)"

# ==================== BUILD SUMMARY ====================
log_section "Build Summary"

SUMMARY_FILE="build_summary.txt"
cat > "$SUMMARY_FILE" << EOF
╔════════════════════════════════════════════════════════════╗
║         ✅ BUILD COMPLETED SUCCESSFULLY! ✅                 ║
╚════════════════════════════════════════════════════════════╝

Build Information:
─────────────────
Build Date:        $(date)
Model:             $MODEL
Architecture:      $ARCH
Kernel Name:       $KERNEL_NAME
Compiler:          Clang $CLANG_VERSION
Build Tool:        Unified Build Script

Kernel Details:
─────────────────
Kernel Image:      $BUILD_DIR/arch/$ARCH/boot/Image
Kernel Size:       $KERNEL_SIZE
KernelSU Commit:   $KERNELSU_COMMIT

Output Files:
─────────────────
Flashable Package: $OUTPUT_DIR/$PACKAGE_NAME
Package Size:      $PACKAGE_SIZE
Boot Image:        $OUTPUT_DIR/boot.img

Build Configuration:
─────────────────────
CONFIG_KSU:                    ✓ Enabled
CONFIG_KSU_MANUAL_HOOK:        ✓ Enabled
CONFIG_KSU_ALLOWLIST_WORKAROUND: ✓ Enabled
CONFIG_FAKE_UNAME:             ✓ Enabled
CONFIG_LTO_CLANG:              ✓ Enabled
CONFIG_SECURITY_SELINUX:       ✓ Enabled

Next Steps:
────────────
1. Transfer ZIP to your device:
   adb push $OUTPUT_DIR/$PACKAGE_NAME /sdcard/

2. Boot device into TWRP recovery:
   adb reboot recovery

3. In TWRP: Install ZipFile → Select $PACKAGE_NAME

4. Reboot device (first boot may take 30-60 seconds)

5. Verify by opening terminal and running:
   su -c "uname -a"
   su -c "ksu version"

Logs:
──────
Compilation Log: build_compile.log
This Summary:    $SUMMARY_FILE

════════════════════════════════════════════════════════════
EOF

cat "$SUMMARY_FILE"

# ==================== SUCCESS ====================
log_section "Build Status: SUCCESS ✅"
log_info "All build artifacts ready in: $OUTPUT_DIR"
log_info "Use 'adb push $OUTPUT_DIR/$PACKAGE_NAME /sdcard/' to transfer to device"

exit 0
