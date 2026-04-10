#!/bin/bash

# ==================== Build Environment Verification ====================

echo "╔════════════════════════════════════════════════════╗"
echo "║     ArtisanKRNL Build Environment Verification     ║"
echo "╚════════════════════════════════════════════════════╝"
echo ""

PASS=0
FAIL=0
WARN=0

check_pass() {
    echo -e "  ✅ $1"
    ((PASS++))
}

check_fail() {
    echo -e "  ❌ $1"
    ((FAIL++))
}

check_warn() {
    echo -e "  ⚠️  $1"
    ((WARN++))
}

# ==================== Check Directory Structure ====================
echo "📁 Checking Directory Structure..."

[ -d "toolchain" ] && check_pass "toolchain/ exists" || check_fail "toolchain/ NOT FOUND"
[ -d "arch" ] && check_pass "arch/ exists" || check_fail "arch/ NOT FOUND"
[ -d "build" ] && check_pass "build/ exists" || check_fail "build/ NOT FOUND"
[ -d "drivers" ] && check_pass "drivers/ exists" || check_fail "drivers/ NOT FOUND"

# ==================== Check Clang Installation ====================
echo ""
echo "🔧 Checking Clang Toolchain..."

CLANG_DIR="toolchain/clang_18"
if [ -d "$CLANG_DIR" ]; then
    check_pass "Clang 18 directory found"
    
    if [ -f "$CLANG_DIR/bin/clang" ]; then
        check_pass "clang binary found"
        CLANG_VERSION=$($CLANG_DIR/bin/clang --version | head -1)
        echo "    Version: $CLANG_VERSION"
    else
        check_fail "clang binary NOT FOUND"
    fi
    
    if [ -f "$CLANG_DIR/bin/clang++" ]; then
        check_pass "clang++ binary found"
    else
        check_fail "clang++ binary NOT FOUND"
    fi
    
    if [ -f "$CLANG_DIR/bin/ld.lld" ]; then
        check_pass "ld.lld linker found"
    else
        check_fail "ld.lld linker NOT FOUND"
    fi
    
    if [ -f "$CLANG_DIR/bin/llvm-ar" ]; then
        check_pass "llvm-ar found"
    else
        check_fail "llvm-ar NOT FOUND"
    fi
else
    check_fail "Clang 18 directory NOT FOUND"
fi

# ==================== Check Required Build Tools ====================
echo ""
echo "⚙️  Checking Required Tools..."

command -v make > /dev/null && check_pass "make installed" || check_fail "make NOT FOUND"
command -v git > /dev/null && check_pass "git installed" || check_fail "git NOT FOUND"
command -v python3 > /dev/null && check_pass "python3 installed" || check_fail "python3 NOT FOUND"
command -v zip > /dev/null && check_pass "zip installed" || check_fail "zip NOT FOUND"

# ==================== Check Build Scripts ====================
echo ""
echo "📝 Checking Build Scripts..."

[ -f "build.sh" ] && [ -x "build.sh" ] && check_pass "build.sh is executable" || check_fail "build.sh NOT executable"
[ -f "BUILD_README.md" ] && check_pass "BUILD_README.md exists" || check_warn "BUILD_README.md missing"

# ==================== Check Kernel Configuration ====================
echo ""
echo "🔐 Checking Kernel Configurations..."

CONFIG_FILE="arch/arm64/configs/exynos9830_defconfig"
[ -f "$CONFIG_FILE" ] && check_pass "Base defconfig found" || check_fail "Base defconfig NOT FOUND"
[ -f "arch/arm64/configs/r8s.config" ] && check_pass "Device config found" || check_fail "Device config NOT FOUND"
[ -f "arch/arm64/configs/ksu.config" ] && check_pass "KernelSU config found" || check_warn "KernelSU config missing"

# ==================== Check KernelSU ====================
echo ""
echo "🔓 Checking KernelSU Integration..."

if [ -d "KernelSU-Next" ]; then
    check_pass "KernelSU-Next directory found"
    [ -d "KernelSU-Next/kernel" ] && check_pass "KernelSU kernel source found" || check_fail "KernelSU kernel source NOT FOUND"
else
    check_warn "KernelSU-Next not yet cloned (will be done during build)"
fi

# ==================== Check Build Artifacts ====================
echo ""
echo "📦 Checking Previous Build Artifacts..."

if [ -d "out" ]; then
    check_warn "Previous build output found (out/)"
    [ -f "out/arch/arm64/boot/Image" ] && check_warn "Previous kernel image exists (will be overwritten)"
else
    check_pass "No previous build output (clean start)"
fi

# ==================== Check Disk Space ====================
echo ""
echo "💾 Checking Disk Space..."

AVAILABLE=$(df . | awk 'NR==2 {print $4}')  # in KB
AVAILABLE_GB=$((AVAILABLE / 1048576))  # Convert to GB

if [ "$AVAILABLE_GB" -ge 50 ]; then
    check_pass "Sufficient disk space ($AVAILABLE_GB GB available)"
else
    check_fail "Insufficient disk space (need 50GB, have $AVAILABLE_GB GB)"
fi

# ==================== Check System Resources ====================
echo ""
echo "🖥️  Checking System Resources..."

CORES=$(nproc --all)
RAM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
RAM_GB=$((RAM_KB / 1048576))

echo "    Cores: $CORES"
echo "    RAM: ${RAM_GB}GB"

[ "$CORES" -ge 4 ] && check_pass "Sufficient CPU cores" || check_warn "Only $CORES cores (4+ recommended)"
[ "$RAM_GB" -ge 8 ] && check_pass "Sufficient RAM" || check_warn "Only ${RAM_GB}GB RAM (8GB+ recommended)"

# ==================== Final Summary ====================
echo ""
echo "╔════════════════════════════════════════════════════╗"
echo "║                  Verification Summary              ║"
echo "╚════════════════════════════════════════════════════╝"
echo ""
echo "✅ Passed:  $PASS"
echo "❌ Failed:  $FAIL"
echo "⚠️  Warnings: $WARN"
echo ""

if [ $FAIL -eq 0 ]; then
    echo "🎉 Build environment is READY!"
    echo ""
    echo "Run: ./build.sh"
    echo ""
    exit 0
else
    echo "⚠️  Please fix the failures above before building"
    echo ""
    exit 1
fi
