#!/bin/bash
# 🚀 QUICK REFERENCE - Kernel Build Commands
# Copy & paste these commands as needed

# ═══════════════════════════════════════════════════════════════════════════
# 🎯 BUILD KERNEL (One Time - Takes 30-60 minutes)
# ═══════════════════════════════════════════════════════════════════════════

# Verify environment before building (RECOMMENDED)
bash verify_env.sh

# Build kernel
./build.sh

# ═══════════════════════════════════════════════════════════════════════════
# 📦 OUTPUT LOCATIONS
# ═══════════════════════════════════════════════════════════════════════════

# Flashable ZIP (What you flash to phone):
# Location: build/out/r8s/ArtisanKRNL_r8s_KSU_[DATE].zip
# Size: ~960KB

# Boot image:
# Location: build/out/r8s/boot.img
# Size: ~42MB

# Raw kernel file:
# Location: out/arch/arm64/boot/Image
# Size: ~42MB

# ═══════════════════════════════════════════════════════════════════════════
# 🔄 REBUILD / CLEAN BUILD
# ═══════════════════════════════════════════════════════════════════════════

# Clean previous build and rebuild
rm -rf out/ build/out/
./build.sh

# Complete clean (removes sources too - starts from scratch)
make mrproper
./build.sh

# ═══════════════════════════════════════════════════════════════════════════
# 📋 CHECK BUILD STATUS
# ═══════════════════════════════════════════════════════════════════════════

# View build log (while building)
tail -f build_compile.log

# View final summary
cat build_summary.txt

# Check if ZIP was created
ls -lh build/out/r8s/*.zip

# ═══════════════════════════════════════════════════════════════════════════
# 🔧 ADVANCED OPTIONS
# ═══════════════════════════════════════════════════════════════════════════

# Edit kernel configuration manually
nano arch/arm64/configs/exynos9830_defconfig

# Update KernelSU to latest
cd KernelSU-Next && git pull origin dev && cd ..

# Verify configuration
grep "CONFIG_KSU=" arch/arm64/configs/exynos9830_defconfig
grep "CONFIG_LTO_CLANG=" arch/arm64/configs/exynos9830_defconfig

# Check Clang version
./toolchain/clang_18/bin/clang --version

# ═══════════════════════════════════════════════════════════════════════════
# 📱 FLASH TO DEVICE (After build completes)
# ═══════════════════════════════════════════════════════════════════════════

# 1. Connect phone, boot into TWRP recovery

# 2. Push ZIP to device
adb push build/out/r8s/ArtisanKRNL_r8s_KSU_*.zip /sdcard/

# 3. In TWRP: Install ZIP from /sdcard/ArtisanKRNL_r8s_KSU_*.zip

# 4. Reboot device (will take ~30 seconds first boot)

# 5. After reboot, device now runs your kernel!

# ═══════════════════════════════════════════════════════════════════════════
# 🐛 TROUBLESHOOTING
# ═══════════════════════════════════════════════════════════════════════════

# Build failed? Verify environment:
bash verify_env.sh

# Out of disk space?
du -sh out/ build/
rm -rf out/ build/out/

# Check compilation errors:
grep -i "error" build_compile.log | head -20

# Check warnings:
grep -i "warning" build_compile.log | wc -l

# ═══════════════════════════════════════════════════════════════════════════
# 📊 BUILD CONFIGURATION SUMMARY
# ═══════════════════════════════════════════════════════════════════════════

# Compiler:        Neutron Clang 18.0.0
# Optimization:    -O3 + LTO (Thin)
# Target:          Samsung Galaxy S20 (r8s)
# SoC:             Exynos 9830
# Architecture:    ARM64
# Kernel Base:     5.10.x
# Root System:     KernelSU (Latest dev)
# Security:        SELinux + LTO
# Performance:     Cortex-A75 tuned

# ═══════════════════════════════════════════════════════════════════════════
# ✅ STATUS CHECK
# ═══════════════════════════════════════════════════════════════════════════

# Everything ready?
echo "=== READINESS CHECK ==="
echo "Clang: $(./toolchain/clang_18/bin/clang --version | head -1)"
echo "Kernel source: $(ls Makefile Kbuild 2>/dev/null | wc -l)/2 files"
echo "Configs: $(ls arch/arm64/configs/*.config 2>/dev/null | wc -l) found"
echo "Build script: $([ -x build.sh ] && echo "✅ Executable" || echo "❌ Not executable")"
echo ""
echo "Ready to build! Run: ./build.sh"

# ═══════════════════════════════════════════════════════════════════════════
# 📚 DOCUMENTATION
# ═══════════════════════════════════════════════════════════════════════════

# Full build documentation:    BUILD_README.md
# Setup completion guide:      SETUP_COMPLETE.md
# This quick reference:        QUICK_REFERENCE.sh
# Kernel source README:        README.md

# ═══════════════════════════════════════════════════════════════════════════
# 🚀 YOU'RE ALL SET!
# ═══════════════════════════════════════════════════════════════════════════
# 
# Your kernel is ready to build with:
#
#   ./build.sh
#
# Takes 30-60 minutes, zero intervention needed.
# Output: build/out/r8s/ArtisanKRNL_r8s_KSU_[DATE].zip
#
# Not sure what to do? Read SETUP_COMPLETE.md for full guide.
# ═══════════════════════════════════════════════════════════════════════════
