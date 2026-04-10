# 🚀 Unified Kernel Build System

Complete all-in-one solution for compiling Samsung Exynos 9830 kernel with KernelSU-Next integration.

## 📋 Quick Start

### Local Build

```bash
# Clone repository (if not already done)
git clone https://github.com/Android-Artisan/android_kernel_samsung_exynos990.git
cd android_kernel_samsung_exynos990

# Run unified build script
./build_unified.sh

# Or with options
./build_unified.sh --clean      # Clean build (remove previous outputs)
./build_unified.sh --verbose    # Show detailed output
./build_unified.sh --help       # Show help
```

### GitHub Actions Build

Automatically builds on:
- **Push** to main/bpf111/master branches (with kernel/driver changes)
- **Pull Requests** to main/bpf111/master branches
- **Manual Trigger** via "Run workflow" button

## 🎯 Features

### build_unified.sh

#### ✅ Automated Setup
- **Toolchain Management**
  - Detects Clang 18 availability
  - Auto-downloads if not found (~500MB)
  - Fallback URLs for reliability
  - Verification of toolchain integrity

- **KernelSU-Next Integration**
  - Automatic repository cloning
  - Latest `dev` branch sync
  - Proper kernel module integration
  - Configuration auto-patching

- **All-in-One**
  - No external dependencies
  - Single command to build everything
  - Complete error handling
  - Detailed logging

#### ⚙️ Build Process
1. Environment verification
2. Toolchain setup/download
3. KernelSU-Next clone/sync
4. Kernel configuration
5. Compilation
6. Flashable package creation

#### 📊 Output
```
build/out/r8s/
├── ArtisanKRNL_r8s_KSU_[DATE].zip    # Flashable ZIP (~960KB)
├── boot.img                           # Boot image (~42MB)
└── META-INF/                          # Recovery scripts
```

### GitHub Actions Workflow

#### 🔄 Automated CI/CD Features
- **Parallel Jobs**
  - Build kernel
  - Validate configuration
  - Lint shell scripts
  - Security scanning
  
- **Smart Caching**
  - Toolchain cache (1-hour retention)
  - ccache for C/C++ compilation
  - KernelSU repository cache

- **Artifacts & Releases**
  - Automatic artifact uploads
  - Build logs included
  - GitHub release creation (on tags)
  - Retention policies

## 📖 Detailed Usage

### Local Build Options

#### Standard Build
```bash
./build_unified.sh
```
- Uses existing toolchain or downloads if needed
- Shows progress summary
- Takes ~60 minutes on 4-core CPU

#### Clean Build
```bash
./build_unified.sh --clean
```
- Removes all previous build outputs
- Starts completely fresh
- Useful for troubleshooting
- Ensures no stale objects

#### Verbose Build
```bash
./build_unified.sh --verbose
```
- Displays full compilation output
- Line-by-line make output
- Helpful for debugging issues
- Shows all warnings/notes

#### Help
```bash
./build_unified.sh --help
```
- Shows available options
- Usage examples
- Exit code 0 (clean exit)

### Configuration Control

#### Pre-Build Customization

Edit `arch/arm64/configs/exynos9830_defconfig` before building:

```bash
# View KernelSU settings
grep CONFIG_KSU arch/arm64/configs/exynos9830_defconfig

# Disable SELinux enforcement (if needed)
# Change: CONFIG_SECURITY_SELINUX_BOOTPARAM=y
# To:     CONFIG_SECURITY_SELINUX_BOOTPARAM=n

# Then rebuild
./build_unified.sh --clean
```

#### Build Environment Variables

Override settings on command line:

```bash
# Use specific LLVM version (if available)
export LLVM_VERSION=18
./build_unified.sh

# Control optimization level (default -O3)
export KCFLAGS="-O2 -march=armv8-a"
./build_unified.sh
```

### Output Locations

After successful build:

```
build/out/r8s/
├── ArtisanKRNL_r8s_KSU_11-04-2026_14-30-45.zip  # Flashable package
├── boot.img                                      # Boot partition
└── zip/                                          # Recovery files

out/
├── arch/arm64/boot/Image                        # Uncompressed kernel
├── arch/arm64/boot/Image.gz                     # Compressed kernel (if created)
└── .config                                       # Used configuration

Logs:
├── build_compile.log                            # Full compilation log
├── build_summary.txt                            # Build summary
└── build_output.log                             # Complete build output (if verbose)
```

### Flashing to Device

#### Prerequisites
- Device in TWRP recovery or fastboot
- ADB installed and working
- USB debugging enabled

#### Steps

```bash
# 1. Transfer ZIP to device
adb push build/out/r8s/ArtisanKRNL_r8s_KSU_*.zip /sdcard/

# 2. Boot to TWRP recovery
adb reboot recovery

# 3. In TWRP:
#    - Install → Select kernel ZIP from /sdcard/
#    - Swipe to confirm
#    - Reboot

# 4. First boot takes 30-60 seconds
# 5. Verify installation
adb shell su -c "uname -a"
adb shell su -c "ksu version"
```

## 🔧 GitHub Actions Workflow

### Workflow Triggers

#### Automatic Triggers
```yaml
# Triggers on push to these branches
- main
- bpf111
- master

# Only if these files changed
- arch/**
- drivers/**
- kernel/**
- build.config*
- build_unified.sh
- .github/workflows/build-kernel.yml
```

#### Manual Trigger
Go to **Actions** tab → **Build Kernel** → **Run workflow**

Select build type:
- `standard` - Normal build
- `clean` - Clean build
- `verbose` - Verbose output

### Workflow Jobs

#### 1. build-kernel (Main Job)
- Runs on `ubuntu-latest`
- 3-hour timeout
- Steps:
  1. Checkout code
  2. Install dependencies
  3. Cache toolchain
  4. Setup ccache (C/C++ caching)
  5. Sync KernelSU-Next
  6. Run build_unified.sh
  7. Upload artifacts
  8. Create release (on tags)

#### 2. validate-config
- Validates configuration files
- Checks KernelSU presence
- Verifies build script integrity

#### 3. lint-scripts
- Runs shellcheck on build scripts
- Detects shell syntax errors
- Non-blocking (warnings allowed)

#### 4. security-scan
- Runs Trivy security scanner
- Checks for vulnerabilities
- Uploads to GitHub Security tab

### Artifact Management

#### Retention Policies
- **Build Logs**: 30 days
- **Kernel Images**: 7 days
- **Flashable Packages**: 30 days

#### Download Artifacts

On **Actions** page → Click workflow run → Download from "Artifacts" section:

- `build-logs-universal9830` - Compilation logs
- `kernel-image-universal9830` - Raw kernel binary
- `flashable-package-universal9830` - Flashable ZIP

### Creating a Release

Tag your commits to automatically create GitHub releases:

```bash
git tag -a v1.0 -m "Release v1.0"
git push origin v1.0
```

Workflow will:
- Build kernel
- Create GitHub release
- Upload artifacts to release
- Include changelog

## 🛠️ Troubleshooting

### Build Fails with "Clang not found"

```bash
# Option 1: Re-download toolchain
rm -rf toolchain/clang_18
./build_unified.sh

# Option 2: Download manually
cd toolchain
wget https://releases.llvm.org/18.1.0/clang+llvm-18.1.0-x86_64-linux-gnu.tar.xz
tar -xf clang+llvm-*.tar.xz
```

### "Out of disk space" Error

Check and clean:
```bash
# Check space
df -h
du -sh out/ build/

# Clean previous builds
rm -rf out/ build/out/ build_compile.log
./build_unified.sh --clean
```

### KernelSU Not Found During Build

```bash
# Re-sync KernelSU
rm -rf KernelSU-Next
./build_unified.sh
```

### Build Hangs or Takes Too Long

```bash
# Check system resources
top -b -n 1 | head -20
nproc --all  # Check CPU cores

# Rebuild with limited parallelism
make -j2  # If getting OOM errors
```

### Kernel Image Not Generated

```bash
# Check for compilation errors
tail -100 build_compile.log

# Try clean build
./build_unified.sh --clean

# Check config
make ARCH=arm64 exynos9830_defconfig
make ARCH=arm64 check_config  # If available
```

## 📚 Documentation Structure

```
root/
├── build_unified.sh              # Main unified build script
├── BUILD_UNIFIED_README.md       # This file (Unified system docs)
├── BUILD_README.md               # Legacy documentation
├── QUICK_REFERENCE.sh            # Quick command reference
│
├── build/                        # Build system files
│   ├── ramdisk/                  # Root filesystem
│   ├── update-binary             # Recovery update script
│   └── updater-script            # Recovery configuration
│
├── .github/workflows/
│   └── build-kernel.yml          # GitHub Actions workflow
│
└── arch/arm64/configs/
    └── exynos9830_defconfig      # Kernel configuration
```

## 📋 System Requirements

### Minimum
- Ubuntu 18.04+ (or equivalent Linux)
- 4 CPU cores
- 8GB RAM
- 50GB free disk space

### Recommended
- Ubuntu 20.04 LTS
- 8+ CPU cores
- 16GB RAM
- 100GB free disk space
- SSD (faster builds)

### Network
- Stable internet (for toolchain download)
- ~500MB download on first build

## 🔐 Security Notes

- KernelSU provides root access (intended)
- SELinux enabled but buildprop can be used to disable enforcement
- Kernel modules verified through Git history
- Build artifacts signed per TWRP requirements

## 📝 Build Process Summary

```
1. VERIFY ENVIRONMENT
   └─ Check system requirements
   └─ Verify we're in kernel root

2. SETUP TOOLCHAIN
   └─ Check Clang 18 availability
   └─ Download if needed (~500MB)
   └─ Verify integrity

3. SETUP KERNELSU
   └─ Clone/sync KernelSU-Next repo
   └─ Fetch latest dev branch
   └─ Integrate into kernel/drivers

4. CONFIGURE KERNEL
   └─ Load exynos9830 base config
   └─ Apply KernelSU options
   └─ Apply optimization flags
   └─ Finalize configuration

5. COMPILE KERNEL
   └─ Parallel compilation (all cores)
   └─ Optimization level: -O3
   └─ LTO enabled (Thin)
   └─ Generate kernel image

6. CREATE PACKAGE
   └─ Build ramdisk
   └─ Create boot image
   └─ Package recovery scripts
   └─ Create flashable ZIP

7. VERIFY & REPORT
   └─ Check all artifacts created
   └─ Generate build summary
   └─ Clean up temporary files
```

## 🚀 Performance Tips

### Faster Builds
```bash
# Use ccache (C/C++ compiler cache)
export CCACHE_DIR=~/.ccache
ccache -M 5G  # Set cache size to 5GB

# Parallel compilation
export MAKEJ=$(nproc --all)

# Re-enable ccache after build
ccache -s  # See cache statistics
```

### Incremental Builds
```bash
# Don't use --clean if only making small changes
# Kernel build system is smart about rebuilding

# For changes to specific files
make ARCH=arm64 drivers/kernelsu/  # Rebuild only KernelSU

# Back to full build when needed
./build_unified.sh --clean
```

## 🤝 Contributing

To improve the build system:

1. Edit `build_unified.sh` or `.github/workflows/build-kernel.yml`
2. Test locally: `./build_unified.sh --verbose`
3. For CI/CD: Push branch and create PR
4. Workflow runs automatically
5. Check "Logs" tab for issues

## 📞 Support

For issues with:
- **Local builds**: Check `build_compile.log`
- **GitHub Actions**: Check workflow logs in "Actions" tab
- **KernelSU**: Visit https://github.com/KernelSU-Next/KernelSU-Next/issues
- **Flashing**: Check TWRP documentation

## 📄 License

Kernel compilation system follows the same license as Linux kernel (GPL v2).
