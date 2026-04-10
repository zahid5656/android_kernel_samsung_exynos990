#!/bin/bash

set -e

# ==================== Configuration ====================
MODEL="r8s"
BOARD="SRPTF26B014KU"
CORES=$(nproc --all)
BUILD_DIR="out"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

abort() {
    log_error "Build failed!"
    exit 1
}

# ==================== Setup Clang Toolchain ====================
log_info "Setting up Clang 18 toolchain..."
CLANG_DIR="$PWD/toolchain/clang_18"

if [ ! -f "$CLANG_DIR/bin/clang" ]; then
    log_error "Clang 18 not found. Please download it first."
    abort
fi

export PATH="$CLANG_DIR/bin:$PATH"
CLANG_VERSION=$(clang --version 2>&1 | head -n 1)
log_info "Using: $CLANG_VERSION"

# ==================== Setup Build Environment ====================
export LLVM=1
export LLVM_IAS=1
export CC=clang
export LD=ld.lld
export AR=llvm-ar
export NM=llvm-nm
export OBJCOPY=llvm-objcopy
export OBJDUMP=llvm-objdump
export STRIP=llvm-strip
export HOSTCC=clang
export HOSTCXX=clang++

# Compiler flags to suppress non-critical warnings
export KCFLAGS="-Wno-error=implicit-function-declaration \
-Wno-error=strict-prototypes \
-Wno-error=incompatible-pointer-types \
-Wno-error=implicit-int \
-Wno-error=return-type"

MAKE_ARGS="LLVM=1 LLVM_IAS=1 \
CC=clang LD=ld.lld AR=llvm-ar NM=llvm-nm \
OBJCOPY=llvm-objcopy OBJDUMP=llvm-objdump STRIP=llvm-strip \
HOSTCC=clang HOSTCXX=clang++ \
ARCH=arm64 O=$BUILD_DIR"

# ==================== Setup KernelSU ====================
log_info "Setting up KernelSU-Next..."
if [ ! -d "KernelSU-Next" ]; then
    log_info "Cloning KernelSU-Next repository..."
    git clone https://github.com/KernelSU-Next/KernelSU-Next.git
fi

cd KernelSU-Next
git fetch origin dev
git checkout dev
git reset --hard origin/dev
log_info "KernelSU-Next updated to: $(git log -1 --format=%H)"
cd ..

# Copy KernelSU files to kernel
log_info "Integrating KernelSU into kernel..."
rm -rf drivers/kernelsu
mkdir -p drivers/kernelsu
cp -r KernelSU-Next/kernel/* drivers/kernelsu/ 2>/dev/null || true

# ==================== Configure Kernel ====================
log_info "Configuring kernel..."

# Add KernelSU configurations
CONFIG_FILE="arch/arm64/configs/exynos9830_defconfig"

# Ensure KSU config flags are present
grep -q "^CONFIG_KSU=y" "$CONFIG_FILE" || echo "CONFIG_KSU=y" >> "$CONFIG_FILE"
grep -q "^CONFIG_KSU_MANUAL_HOOK=y" "$CONFIG_FILE" || echo "CONFIG_KSU_MANUAL_HOOK=y" >> "$CONFIG_FILE"
grep -q "^CONFIG_KSU_ALLOWLIST_WORKAROUND=y" "$CONFIG_FILE" || echo "CONFIG_KSU_ALLOWLIST_WORKAROUND=y" >> "$CONFIG_FILE"
grep -q "^CONFIG_FAKE_UNAME=y" "$CONFIG_FILE" || echo "CONFIG_FAKE_UNAME=y" >> "$CONFIG_FILE"
grep -q "^CONFIG_FAKE_UNAME_5_10=y" "$CONFIG_FILE" || echo "CONFIG_FAKE_UNAME_5_10=y" >> "$CONFIG_FILE"

# Remove output directory for clean build
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Run configuration
log_info "Loading base configuration..."
make ${MAKE_ARGS} exynos9830_defconfig 2>&1 | grep -v "^  " | tail -5 || true

log_info "Merging r8s device configuration..."
make ${MAKE_ARGS} r8s.config 2>&1 | grep -E "^Value|^New value|^Previous" | head -10 || true

log_info "Applying KernelSU configuration..."
make ${MAKE_ARGS} ksu.config 2>&1 || true

# Handle new config options silently
log_info "Finalizing configuration..."
yes "" | make ${MAKE_ARGS} oldconfig > /dev/null 2>&1 || true

log_info "Configuration complete"

# ==================== Compile Kernel ====================
log_info "Starting kernel compilation with $CORES cores..."
log_info "This may take 30-60 minutes..."

make ${MAKE_ARGS} -j$CORES 2>&1 | tail -100 || abort

# Check if compilation succeeded
if [ ! -f "$BUILD_DIR/arch/arm64/boot/Image" ]; then
    log_error "Kernel image not found at $BUILD_DIR/arch/arm64/boot/Image"
    abort
fi

KERNEL_SIZE=$(du -h "$BUILD_DIR/arch/arm64/boot/Image" | cut -f1)
log_info "✅ Kernel successfully compiled: $KERNEL_SIZE"

# ==================== Build Ramdisk ====================
log_info "Building ramdisk..."
mkdir -p "build/out/$MODEL/zip/files" "build/out/$MODEL/zip/META-INF/com/google/android"

pushd build/ramdisk > /dev/null
find . ! -name . | LC_ALL=C sort | cpio -o -H newc -R root:root 2>/dev/null | gzip > ../out/$MODEL/ramdisk.cpio.gz || abort
log_info "Ramdisk created"
popd > /dev/null

# ==================== Create Boot Image ====================
log_info "Creating boot image..."
cp "$BUILD_DIR/arch/arm64/boot/Image" "build/out/$MODEL/boot.img"
log_info "Boot image prepared"

# ==================== Create Flash Package ====================
log_info "Creating flashable package..."
cp build/update-binary "build/out/$MODEL/zip/META-INF/com/google/android/update-binary"
cp build/updater-script "build/out/$MODEL/zip/META-INF/com/google/android/updater-script"

pushd "build/out/$MODEL/zip" > /dev/null
DATE=$(date +"%d-%m-%Y_%H-%M-%S")
PACKAGE_NAME="ArtisanKRNL_r8s_KSU_${DATE}.zip"
zip -r -qq "../$PACKAGE_NAME" . || abort
popd > /dev/null

# ==================== Final Summary ====================
echo ""
echo "=================================================="
echo "✅ BUILD COMPLETED SUCCESSFULLY!"
echo "=================================================="
echo "📦 Package: build/out/$MODEL/$PACKAGE_NAME"
PACKAGE_SIZE=$(du -h "build/out/$MODEL/$PACKAGE_NAME" | cut -f1)
echo "📊 Package size: $PACKAGE_SIZE"
echo "🔧 Kernel image: $BUILD_DIR/arch/arm64/boot/Image ($KERNEL_SIZE)"
echo ""
echo "Ready to flash! 🚀"
echo "=================================================="
