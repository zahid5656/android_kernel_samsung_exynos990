#!/bin/bash

set -e

abort()
{
    cd -
    echo "-----------------------------------------------"
    echo "❌ Kernel compilation failed! Exiting..."
    echo "-----------------------------------------------"
    exit 1
}

echo "=== ArtisanKRNL r8s - Neutron Clang 18 (Kernel Only) ==="

MODEL="r8s"
BOARD="SRPTF26B014KU"
CORES=$(nproc --all)

# Setup Clang toolchain path
export PATH="$PWD/toolchain/clang_18/bin:$PATH"
echo "Clang Version: $(clang --version | head -n 1)"

# Setup build environment
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

# ==================== Setup KernelSU ====================
echo "Updating KernelSU-Next..."
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

# Copy files to drivers/kernelsu
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

echo "Starting kernel configuration..."
make ${MAKE_ARGS} exynos9830_defconfig || abort
make ${MAKE_ARGS} r8s.config $KSU || abort
yes "" | make ${MAKE_ARGS} oldconfig > /dev/null 2>&1 || true

echo "Starting kernel build (using $CORES cores)..."
make ${MAKE_ARGS} -j$CORES || abort

echo "Building DTB & DTBO..."
if [ -f "./toolchain/mkdtimg" ]; then
    ./toolchain/mkdtimg cfg_create build/out/$MODEL/dtb.img build/dtconfigs/exynos9830.cfg -d out/arch/arm64/boot/dts/exynos || abort
    ./toolchain/mkdtimg cfg_create build/out/$MODEL/dtbo.img build/dtconfigs/$MODEL.cfg -d out/arch/arm64/boot/dts/samsung || abort
else
    echo "⚠️  mkdtimg tool not found, skipping DTB creation"
    mkdir -p build/out/$MODEL
    touch build/out/$MODEL/dtb.img
    touch build/out/$MODEL/dtbo.img
fi

echo "Building ramdisk..."
pushd build/ramdisk > /dev/null
find . ! -name . | LC_ALL=C sort | cpio -o -H newc -R root:root | gzip > ../out/$MODEL/ramdisk.cpio.gz || abort
popd > /dev/null

echo "Creating boot.img..."
if [ -f "./toolchain/mkbootimg" ]; then
    ./toolchain/mkbootimg --base 0x10000000 --board $BOARD \
    --cmdline "androidboot.hardware=exynos990 loop.max_part=7" \
    --dtb build/out/$MODEL/dtb.img --dtb_offset 0x00000000 \
    --hashtype sha1 --header_version 2 \
    --kernel out/arch/arm64/boot/Image --kernel_offset 0x00008000 \
    --os_patch_level 2025-08 --os_version 16.0.0 --pagesize 2048 \
    --ramdisk build/out/$MODEL/ramdisk.cpio.gz --ramdisk_offset 0x01000000 \
    --second_offset 0xF0000000 --tags_offset 0x00000100 \
    -o build/out/$MODEL/boot.img || abort
else
    echo "⚠️  mkbootimg tool not found, using kernel image directly"
    mkdir -p build/out/$MODEL
    cp out/arch/arm64/boot/Image build/out/$MODEL/boot.img
fi

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
