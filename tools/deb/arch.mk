# ---------------------------------------------------------------------------
# 目标架构 -> Debian 架构名映射（学 Debian：64 位 ARM 用 arm64 而不是 aarch64）
#
# 需要先定义 DEB_PRODUCT_OUT。架构判定优先级：
#   1. 环境变量 TARGET_ARCH（可在 shell 里 export TARGET_ARCH=arm64）
#   2. 从已构建的 $(DEB_PRODUCT_OUT)/system/lib{,64}/libc.so 用 file 推断
#   3. 默认 arm
#
# 提供：DEB_TARGET_ARCH、DEB_ARCH、DEB_BIONIC_ARCH、DEB_KERNEL_ARCH
# ---------------------------------------------------------------------------

DEB_ARCH_MAP := arm=armhf arm64=arm64 x86=i386 x86_64=amd64 mips=mipsel mips64=mips64el riscv64=riscv64

DEB_ARCH_FROM_ELF := $(shell f=$(DEB_PRODUCT_OUT)/system/lib64/libc.so; \
    [ -f "$$f" ] || f=$(DEB_PRODUCT_OUT)/system/lib/libc.so; \
    file -b "$$f" 2>/dev/null | sed -n \
        -e 's/^ELF 64-bit LSB shared object, ARM aarch64.*/arm64/p' \
        -e 's/^ELF 64-bit LSB shared object, x86-64.*/x86_64/p' \
        -e 's/^ELF 32-bit LSB shared object, ARM,.*/arm/p' \
        -e 's/^ELF 32-bit LSB shared object, Intel 80386.*/x86/p')

DEB_TARGET_ARCH ?= $(if $(TARGET_ARCH),$(TARGET_ARCH),$(if $(DEB_ARCH_FROM_ELF),$(DEB_ARCH_FROM_ELF),arm))
DEB_ARCH ?= $(patsubst $(DEB_TARGET_ARCH)=%,%,$(filter $(DEB_TARGET_ARCH)=%,$(DEB_ARCH_MAP)))
ifeq ($(strip $(DEB_ARCH)),)
DEB_ARCH := armhf
endif

# bionic 的架构头目录 / kernel uapi 的 asm 目录
DEB_BIONIC_ARCH_MAP := arm=arch-arm arm64=arch-arm64 x86=arch-x86 x86_64=arch-x86_64 mips=arch-mips mips64=arch-mips64
DEB_BIONIC_ARCH ?= $(patsubst $(DEB_TARGET_ARCH)=%,%,$(filter $(DEB_TARGET_ARCH)=%,$(DEB_BIONIC_ARCH_MAP)))
DEB_KERNEL_ARCH_MAP := arm=asm-arm arm64=asm-arm64 x86=asm-x86 x86_64=asm-x86 mips=asm-mips mips64=asm-mips
DEB_KERNEL_ARCH ?= $(patsubst $(DEB_TARGET_ARCH)=%,%,$(filter $(DEB_TARGET_ARCH)=%,$(DEB_KERNEL_ARCH_MAP)))
ifeq ($(strip $(DEB_BIONIC_ARCH)),)
DEB_BIONIC_ARCH := arch-arm
endif
ifeq ($(strip $(DEB_KERNEL_ARCH)),)
DEB_KERNEL_ARCH := asm-arm
endif
