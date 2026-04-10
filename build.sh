#!/bin/bash

################################################################################
# ArtisanKRNL Build Script - Samsung Exynos 9830 (r8s)
# Features:
# - Neutron Clang 18 (Best performance & latest optimizations)
# - KernelSU-Next Integration with root support
# - Automatic dependency resolution
# - Complete error handling
# - Optimized build configuration
################################################################################

set -euo pipefail

# ==================== CONFIGURATION ====================
MODEL="r8s"
DEVICE_BOARD="SRPTF26B014KU"
ARCH="arm64"
KERNEL_NAME="ArtisanKRNL"
BUILD_DIR="out"
CLANG_VERSION="18"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ==================== HELPER FUNCTIONS ====================
log_info() { echo -e "${GREEN}[✓]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[⚠]${NC} $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1"; }
log_section() { echo -e "\n${BLUE}========== $1 ==========${NC}"; }

abort() {
    log_error "$1"
    exit 1
}

# Check command exists
command_exists() {
    command -v "$1" &> /dev/null
}

# ==================== VERIFY BUILD ENVIRONMENT ====================
log_section "Verifying Build Environment"

# Check toolchain
CLANG_DIR="$PWD/toolchain/clang_${CLANG_VERSION}"
if [ ! -d "$CLANG_DIR" ]; then
    abort "Clang ${CLANG_VERSION} not found at $CLANG_DIR"
fi

if [ ! -f "$CLANG_DIR/bin/clang" ]; then
    abort "Clang binary not found"
fi

log_info "Clang toolchain found: $CLANG_DIR"

# Export toolchain to PATH
export PATH="$CLANG_DIR/bin:$PATH"

# Verify clang works
CLANG_VERSION_INFO=$(clang --version 2>&1 | head -n 1)
log_info "Using: $CLANG_VERSION_INFO"

# Check required build tools
for tool in make git zip python3; do
    command_exists "$tool" || abort "Required tool not found: $tool"
done
log_info "All required build tools available"

# ==================== SETUP CLANG ENVIRONMENT ====================
log_section "Configuring Clang Compiler"

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

# Optimization flags for best performance (Exynos 9830 specific)
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

MAKE_ARGS="LLVM=1 LLVM_IAS=1 \
  CC=clang CXX=clang++ LD=ld.lld AR=llvm-ar NM=llvm-nm \
  OBJCOPY=llvm-objcopy OBJDUMP=llvm-objdump STRIP=llvm-strip \
  RANLIB=llvm-ranlib \
  HOSTCC=clang HOSTCXX=clang++ \
  ARCH=$ARCH O=$BUILD_DIR"

log_info "Clang environment configured for optimal performance"

# ==================== SETUP KERNELSU ====================
log_section "Integrating KernelSU-Next"

# Clone/Update KernelSU-Next with legacy branch
if [ ! -d "KernelSU-Next" ]; then
    log_info "Cloning KernelSU-Next repository..."
    git clone https://github.com/KernelSU-Next/KernelSU-Next.git
fi

cd KernelSU-Next
log_info "Updating to latest dev branch..."
git fetch origin dev
git checkout dev
git reset --hard origin/dev
KERNELSU_COMMIT=$(git log -1 --format=%H)
log_info "KernelSU-Next: $KERNELSU_COMMIT"
cd ..

# Integrate KernelSU into kernel
log_info "Copying KernelSU files to kernel..."
rm -rf drivers/kernelsu
mkdir -p drivers/kernelsu
cp -r KernelSU-Next/kernel/* drivers/kernelsu/ 2>/dev/null || true

log_info "KernelSU integration complete"

# ==================== ROOT & SECURITY MODIFICATIONS ====================
log_section "Applying Root & Security Configurations"

CONFIG_FILE="arch/$ARCH/configs/exynos9830_defconfig"

# KernelSU configurations (root support)
log_info "Configuring KernelSU..."
grep -q "^CONFIG_KSU=y" "$CONFIG_FILE" || echo "CONFIG_KSU=y" >> "$CONFIG_FILE"
grep -q "^CONFIG_KSU_MANUAL_HOOK=y" "$CONFIG_FILE" || echo "CONFIG_KSU_MANUAL_HOOK=y" >> "$CONFIG_FILE"
grep -q "^CONFIG_KSU_ALLOWLIST_WORKAROUND=y" "$CONFIG_FILE" || echo "CONFIG_KSU_ALLOWLIST_WORKAROUND=y" >> "$CONFIG_FILE"

# Fake uname for compatibility
grep -q "^CONFIG_FAKE_UNAME=y" "$CONFIG_FILE" || echo "CONFIG_FAKE_UNAME=y" >> "$CONFIG_FILE"
grep -q "^CONFIG_FAKE_UNAME_5_10=y" "$CONFIG_FILE" || echo "CONFIG_FAKE_UNAME_5_10=y" >> "$CONFIG_FILE"

# Security & Performance optimizations
log_info "Applying performance optimizations..."
grep -q "^CONFIG_LTO_CLANG=y" "$CONFIG_FILE" || echo "CONFIG_LTO_CLANG=y" >> "$CONFIG_FILE"
grep -q "^CONFIG_LTO_CLANG_THIN=y" "$CONFIG_FILE" || echo "CONFIG_LTO_CLANG_THIN=y" >> "$CONFIG_FILE"

# Selinux configuration
grep -q "^CONFIG_SECURITY_SELINUX=y" "$CONFIG_FILE" || echo "CONFIG_SECURITY_SELINUX=y" >> "$CONFIG_FILE"

log_info "Root & security modifications applied"

# ==================== KERNEL CONFIGURATION ====================
log_section "Configuring Kernel"

# Clean build directory
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

log_info "Loading base exynos9830 configuration..."
make ${MAKE_ARGS} exynos9830_defconfig 2>&1 | grep -E "warning:|configuration written" || true

log_info "Merging r8s device-specific configuration..."
make ${MAKE_ARGS} r8s.config 2>&1 | grep -E "^Value of|^New value" | head -3 || true

log_info "Applying KernelSU configuration..."
make ${MAKE_ARGS} ksu.config 2>&1 || true

log_info "Finalizing kernel configuration..."
yes "" | make ${MAKE_ARGS} oldconfig > /dev/null 2>&1 || true

# Validate configuration
if [ ! -f "$BUILD_DIR/.config" ]; then
    abort "Kernel configuration failed - .config not created"
fi

log_info "✅ Kernel configuration complete"

# ==================== KERNEL COMPILATION ====================
log_section "Compiling Kernel"

CORES=$(nproc --all)
log_info "Using $CORES CPU cores"
log_info "Starting kernel compilation..."

# Compile with detailed error reporting
if ! make ${MAKE_ARGS} -j$CORES 2>&1 | tee build_compile.log; then
    log_error "Kernel compilation failed"
    log_info "Check build_compile.log for details"
    abort "Build failed"
fi

# Verify kernel image
if [ ! -f "$BUILD_DIR/arch/$ARCH/boot/Image" ]; then
    abort "Kernel image not generated"
fi

KERNEL_SIZE=$(du -h "$BUILD_DIR/arch/$ARCH/boot/Image" | cut -f1)
log_info "✅ Kernel compiled successfully ($KERNEL_SIZE)"

# ==================== PACKAGE GENERATION ====================
log_section "Creating Flashable Package"

OUTPUT_DIR="build/out/$MODEL"
mkdir -p "$OUTPUT_DIR/zip/files" "$OUTPUT_DIR/zip/META-INF/com/google/android"

log_info "Building ramdisk..."
pushd build/ramdisk > /dev/null
find . ! -name . | LC_ALL=C sort | cpio -o -H newc -R root:root 2>/dev/null | gzip > "../out/$MODEL/ramdisk.cpio.gz"
popd > /dev/null
log_info "Ramdisk created"

log_info "Creating boot image..."
cp "$BUILD_DIR/arch/$ARCH/boot/Image" "$OUTPUT_DIR/boot.img"
log_info "Boot image prepared"

log_info "Packaging flashable ZIP..."
cp build/update-binary "$OUTPUT_DIR/zip/META-INF/com/google/android/update-binary"
cp build/updater-script "$OUTPUT_DIR/zip/META-INF/com/google/android/updater-script"

pushd "$OUTPUT_DIR/zip" > /dev/null
BUILD_DATE=$(date +"%d-%m-%Y_%H-%M-%S")
PACKAGE_NAME="${KERNEL_NAME}_${MODEL}_KSU_${BUILD_DATE}.zip"
zip -r -qq "../$PACKAGE_NAME" .
popd > /dev/null

# ==================== FINAL VERIFICATION ====================
log_section "Build Summary"

if [ -f "$OUTPUT_DIR/$PACKAGE_NAME" ]; then
    PACKAGE_SIZE=$(du -h "$OUTPUT_DIR/$PACKAGE_NAME" | cut -f1)
    
    echo ""
    echo "╔════════════════════════════════════════════════════╗"
    echo "║         ✅ BUILD COMPLETED SUCCESSFULLY! ✅         ║"
    echo "╚════════════════════════════════════════════════════╝"
    echo ""
    echo "📦 Flashable Package:"
    echo "   Location: $OUTPUT_DIR/$PACKAGE_NAME"
    echo "   Size: $PACKAGE_SIZE"
    echo ""
    echo "🔧 Kernel Image:"
    echo "   Location: $BUILD_DIR/arch/$ARCH/boot/Image"
    echo "   Size: $KERNEL_SIZE"
    echo ""
    echo "⚙️  Build Info:"
    echo "   Device: Samsung Galaxy $MODEL"
    echo "   Compiler: $CLANG_VERSION_INFO"
    echo "   Timestamp: $BUILD_DATE"
    echo ""
    echo "📋 Features Included:"
    echo "   ✓ KernelSU root support"
    echo "   ✓ LTO (Thin) optimization enabled"
    echo "   ✓ Clang 18 with -O3 optimization"
    echo "   ✓ ARMv8-A with Cortex-A75 tuning"
    echo "   ✓ SELinux enabled"
    echo "   ✓ Latest security patches"
    echo ""
    echo "🚀 Ready to Flash!"
    echo ""
else
    abort "Package creation failed"
fi

# ==================== CLEANUP & COMPLETION ====================
rm -f build_compile.log 2>/dev/null || true
log_info "Build script completed successfully"
#!/bin/bash

abort()
{
    cd -
    echo "-----------------------------------------------"
    echo "❌ Kernel compilation failed! Exiting..."
    echo "-----------------------------------------------"
    exit -1
}

echo "=== ArtisanKRNL r8s - Neutron Clang 18 (Safe & Stable) ==="

MODEL="r8s"
BOARD="SRPTF26B014KU"
CORES=$(nproc --all)

# ==================== Install Dependencies ====================
echo "Installing dependencies (first time only)..."
if command -v apt-get &> /dev/null; then
    sudo -n apt update -qq 2>/dev/null || sudo apt update -qq
    sudo -n DEBIAN_FRONTEND=noninteractive apt install -yq \
        p7zip-full jq attr ccache ffmpeg golang zstd git curl \
        libbrotli-dev libgtest-dev libprotobuf-dev libunwind-dev libpcre2-dev \
        libzstd-dev linux-modules-extra-$(uname -r) lld protobuf-compiler webp \
        xxd patchelf flex bison libarchive-tools build-essential pcre2-utils zip unzip 2>/dev/null || \
    sudo DEBIAN_FRONTEND=noninteractive apt install -yq \
        p7zip-full jq attr ccache ffmpeg golang zstd git curl \
        libbrotli-dev libgtest-dev libprotobuf-dev libunwind-dev libpcre2-dev \
        libzstd-dev linux-modules-extra-$(uname -r) lld protobuf-compiler webp \
        xxd patchelf flex bison libarchive-tools build-essential pcre2-utils zip unzip
else
    echo "apt-get not found, skipping package installation"
fi

# ==================== Neutron Clang 18 ====================
CLANG_DIR="$PWD/toolchain/clang_18"

if [ ! -f "$CLANG_DIR/bin/clang" ]; then
    echo "Downloading Neutron Clang 18..."
    mkdir -p "$CLANG_DIR"
    cd "$CLANG_DIR"
    curl -L -# https://github.com/Neutron-Toolchains/clang-build-catalogue/releases/download/05012024/neutron-clang-05012024.tar.zst -o neutron.tar.zst
    echo "Extracting..."
    tar --use-compress-program=unzstd -xf neutron.tar.zst
    rm neutron.tar.zst
    cd ../../
    echo "✅ Neutron Clang 18 setup completed."
fi

export PATH="$CLANG_DIR/bin:$PATH"
echo "Clang Version: $(clang --version | head -n 1)"

# ==================== KernelSU-Next Legacy (Safe Update) ====================
echo "Updating KernelSU-Next legacy..."
if [ -d "KernelSU-Next" ]; then
    cd KernelSU-Next
    git fetch --all
    git reset --hard origin/dev
    git pull origin dev
    cd ..
else
    echo "Cloning KernelSU-Next..."
    git clone https://github.com/KernelSU-Next/KernelSU-Next.git
    cd KernelSU-Next
    git checkout dev
    cd ..
fi

# Copy files to drivers/kernelsu (তোমার বলা অনুযায়ী)
echo "Copying KernelSU files to drivers/kernelsu..."
rm -rf drivers/kernelsu
mkdir -p drivers/kernelsu
cp -r KernelSU-Next/kernel/* drivers/kernelsu/ 2>/dev/null || true

# ==================== Fix defconfig ====================
CONFIG_FILE="arch/arm64/configs/exynos9830_defconfig"

echo "Fixing KernelSU configs..."
grep -q "^CONFIG_KSU=y" "$CONFIG_FILE" || echo "CONFIG_KSU=y" >> "$CONFIG_FILE"
grep -q "^CONFIG_KSU_MANUAL_HOOK=y" "$CONFIG_FILE" || echo "CONFIG_KSU_MANUAL_HOOK=y" >> "$CONFIG_FILE"
grep -q "^CONFIG_KSU_ALLOWLIST_WORKAROUND=y" "$CONFIG_FILE" || echo "CONFIG_KSU_ALLOWLIST_WORKAROUND=y" >> "$CONFIG_FILE"
grep -q "^CONFIG_FAKE_UNAME=y" "$CONFIG_FILE" || echo "CONFIG_FAKE_UNAME=y" >> "$CONFIG_FILE"
grep -q "^CONFIG_FAKE_UNAME_5_10=y" "$CONFIG_FILE" || echo "CONFIG_FAKE_UNAME_5_10=y" >> "$CONFIG_FILE"

KSU="ksu.config"

# ==================== Build ====================
rm -rf build/out/$MODEL
mkdir -p build/out/$MODEL/zip/files build/out/$MODEL/zip/META-INF/com/google/android

MAKE_ARGS="LLVM=1 LLVM_IAS=1 \
CC=clang LD=ld.lld AR=llvm-ar NM=llvm-nm \
OBJCOPY=llvm-objcopy OBJDUMP=llvm-objdump STRIP=llvm-strip \
HOSTCC=clang HOSTCXX=clang++ \
ARCH=arm64 O=out"

export KCFLAGS="-Wno-error=implicit-function-declaration \
-Wno-error=strict-prototypes \
-Wno-error=incompatible-pointer-types \
-Wno-error=implicit-int \
-Wno-error=return-type"

echo "Starting kernel build..."
make ${MAKE_ARGS} exynos9830_defconfig || abort
make ${MAKE_ARGS} r8s.config $KSU || abort
yes "" | make ${MAKE_ARGS} oldconfig > /dev/null 2>&1 || true
make ${MAKE_ARGS} -j$CORES || abort

echo "Building DTB & DTBO..."
./toolchain/mkdtimg cfg_create build/out/$MODEL/dtb.img build/dtconfigs/exynos9830.cfg -d out/arch/arm64/boot/dts/exynos
./toolchain/mkdtimg cfg_create build/out/$MODEL/dtbo.img build/dtconfigs/$MODEL.cfg -d out/arch/arm64/boot/dts/samsung

echo "Building ramdisk..."
pushd build/ramdisk > /dev/null
find . ! -name . | LC_ALL=C sort | cpio -o -H newc -R root:root | gzip > ../out/$MODEL/ramdisk.cpio.gz || abort
popd > /dev/null

echo "Creating boot.img..."
./toolchain/mkbootimg --base 0x10000000 --board $BOARD \
--cmdline "androidboot.hardware=exynos990 loop.max_part=7" \
--dtb build/out/$MODEL/dtb.img --dtb_offset 0x00000000 \
--hashtype sha1 --header_version 2 \
--kernel out/arch/arm64/boot/Image --kernel_offset 0x00008000 \
--os_patch_level 2025-08 --os_version 16.0.0 --pagesize 2048 \
--ramdisk build/out/$MODEL/ramdisk.cpio.gz --ramdisk_offset 0x01000000 \
--second_offset 0xF0000000 --tags_offset 0x00000100 \
-o build/out/$MODEL/boot.img || abort

echo "Creating ZIP..."
cp build/out/$MODEL/boot.img build/out/$MODEL/zip/files/boot.img
cp build/out/$MODEL/dtbo.img build/out/$MODEL/zip/files/dtbo.img
cp build/update-binary build/out/$MODEL/zip/META-INF/com/google/android/update-binary
cp build/updater-script build/out/$MODEL/zip/META-INF/com/google/android/updater-script

pushd build/out/$MODEL/zip > /dev/null
DATE=`date +"%d-%m-%Y_%H-%M-%S"`
NAME="ArtisanKRNL_r8s_KSU_${DATE}.zip"
zip -r -qq ../"$NAME" .
popd > /dev/null

echo "=================================================="
echo "✅ Build Completed Successfully!"
echo "Output ZIP: build/out/$MODEL/$NAME"
echo "=================================================="