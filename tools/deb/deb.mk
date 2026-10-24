# ---------------------------------------------------------------------------
# Generic .deb packaging for Android platform libraries (opt-in only).
#
# 仓库在自己的 deb.mk 里声明要打包的库，然后 include 本文件：
#
#   DEB_TOP := $(abspath $(CURDIR)/../..)
#   DEB_PACKAGES        := libfoo libbar
#   DEB_INCDIRS_libfoo  := include/foo          # 整个目录 -> /system/usr/include/foo/...
#   DEB_INCFILES_libfoo := include/foo.h        # 单个文件 -> /system/usr/include/foo.h
#   DEB_DESC_libfoo     := Foo library
#   include $(DEB_TOP)/build/make/tools/deb/deb.mk
#
# 三个目标（在 envsetup 的 shell 里用 `command make` 执行，避免命中 envsetup
# 定义的 make 函数）：
#
#   deb         运行时共享库  -> /system/lib/libX.so（Depends 由 ELF NEEDED 生成）
#   deb-dev     头文件        -> /system/usr/include/...
#   deb-static  静态库        -> /system/lib/libX.a
#
# 这些目标只存在于各仓库自己的 Makefile/deb.mk 中，AOSP 默认构建
# （Android.bp/Android.mk）不会引用它们。
# ---------------------------------------------------------------------------

DEB_TOP ?= $(abspath $(CURDIR)/../..)
DEB_PRODUCT_OUT ?= $(if $(ANDROID_PRODUCT_OUT),$(ANDROID_PRODUCT_OUT),$(DEB_TOP)/out/target/product/generic)
DEB_LIB_DIR := $(DEB_PRODUCT_OUT)/system/lib
DEB_STATIC_DIR := $(DEB_PRODUCT_OUT)/obj/STATIC_LIBRARIES
DEB_WORK := $(CURDIR)/out-deb
DEB_HELPER_DIR := $(patsubst %/,%,$(dir $(lastword $(MAKEFILE_LIST))))

DEB_ARCH_MAP := arm=armhf arm64=arm64 x86=i386 x86_64=amd64 mips=mipsel mips64=mips64el riscv64=riscv64

# 架构映射（TARGET_ARCH / libc.so 推断 / 默认 arm）
include $(DEB_HELPER_DIR)/arch.mk

DEB_MAINTAINER := CaremiumOS Developers <caremium-os@googlegroups.com>
DEB_VERSION ?= $(shell sed -n 's/^PLATFORM_VERSION\.OPM1 := //p' $(DEB_TOP)/build/make/core/version_defaults.mk)
ifeq ($(strip $(DEB_VERSION)),)
DEB_VERSION := 8.1.0
endif
DEB_BIONIC_VERSION := $(DEB_VERSION)

.PHONY: deb deb-dev deb-static deb-clean

deb: $(addprefix __deb-runtime-,$(DEB_PACKAGES))
deb-dev: $(addprefix __deb-dev-,$(DEB_PACKAGES)) $(addprefix __deb-header-,$(DEB_HEADERONLY_PACKAGES))
deb-static: $(addprefix __deb-static-,$(DEB_PACKAGES))

# ---- 运行时共享库 --------------------------------------------------------
__deb-runtime-%:
	@set -e; \
	pkg=$*; \
	ver=$(if $(DEB_VERSION_$*),$(DEB_VERSION_$*),$(DEB_VERSION)); \
	sos="$(if $(DEB_SO_$*),$(DEB_SO_$*),$*)"; \
	missing=0; \
	for s in $$sos; do [ -f $(DEB_LIB_DIR)/$$s.so ] || missing=1; done; \
	[ $$missing = 0 ] || $(MAKE) -C $(DEB_TOP) $(if $(DEB_BUILD_$*),$(DEB_BUILD_$*),$*); \
	root=$(DEB_WORK)/$$pkg; \
	rm -rf $$root; mkdir -p $$root/DEBIAN $$root/system/lib; \
	for s in $$sos; do cp -aL $(DEB_LIB_DIR)/$$s.so $$root/system/lib/; done; \
	depends=""; \
	[ "$$pkg" = bionic ] || depends="bionic (>= $(DEB_BIONIC_VERSION))"; \
	for s in $$sos; do \
	    for lib in $$(readelf -d $(DEB_LIB_DIR)/$$s.so | sed -n 's/.*Shared library: \[\(lib.*\)\.so\]/\1/p'); do \
	        case $$lib in \
	            libc|libm|libdl) ;; \
	            *) if [ -z "$$depends" ]; then depends="$$lib"; else depends="$$depends, $$lib"; fi ;; \
	        esac; \
	    done; \
	done; \
	[ -n "$$depends" ] || [ "$$pkg" = bionic ] || depends="bionic (>= $(DEB_BIONIC_VERSION))"; \
	size=$$(du -sk $$root | cut -f1); \
	desc="$(if $(DEB_DESC_$*),$(DEB_DESC_$*),Android $* library)"; \
	sed -e "s|@PACKAGE@|$$pkg|g" \
	    -e "s|@VERSION@|$${ver}|g" \
	    -e "s|@ARCH@|$(DEB_ARCH)|g" \
	    -e "s|@MAINTAINER@|$(DEB_MAINTAINER)|g" \
	    -e "s|@INSTALLED_SIZE@|$$size|g" \
	    -e "s|@DEPENDS@|$$depends|g" \
	    -e "s|@DESCRIPTION@|$$desc|g" \
	    $(DEB_HELPER_DIR)/control-runtime.in > $$root/DEBIAN/control; \
	[ -n "$$depends" ] || sed -i '/^Depends:/d' $$root/DEBIAN/control; \
	echo 2.0 > $(DEB_WORK)/debian-binary; \
	tar --owner=0 --group=0 --numeric-owner -czf $(DEB_WORK)/control.tar.gz -C $$root/DEBIAN .; \
	tar --owner=0 --group=0 --numeric-owner -czf $(DEB_WORK)/data.tar.gz -C $$root ./system; \
	rm -f $(CURDIR)/$${pkg}_$${ver}_$(DEB_ARCH).deb; \
	ar rc $(CURDIR)/$${pkg}_$${ver}_$(DEB_ARCH).deb \
	    $(DEB_WORK)/debian-binary $(DEB_WORK)/control.tar.gz $(DEB_WORK)/data.tar.gz; \
	echo "生成 $(CURDIR)/$${pkg}_$${ver}_$(DEB_ARCH).deb  (Depends: $$depends)"

# ---- 开发头文件 ----------------------------------------------------------
__deb-dev-%:
	@set -e; \
	pkg=$*; \
	ver=$(if $(DEB_VERSION_$*),$(DEB_VERSION_$*),$(DEB_VERSION)); \
	root=$(DEB_WORK)/$$pkg-dev; \
	rm -rf $$root; mkdir -p $$root/DEBIAN $$root/system/usr/include; \
	for d in $(DEB_INCDIRS_$*); do cp -aL $$d $$root/system/usr/include/; done; \
	for d in $(DEB_INCDIRCONTENTS_$*); do cp -aL $$d/. $$root/system/usr/include/; done; \
	for f in $(DEB_INCFILES_$*); do cp -aL $$f $$root/system/usr/include/; done; \
	size=$$(du -sk $$root | cut -f1); \
	desc="$(if $(DEB_DESC_$*),$(DEB_DESC_$*),Android $* library) (development files)"; \
	depends="$$pkg (= $${ver})"; \
	extra="$(DEB_DEV_DEPENDS_$*)"; \
	[ -z "$$extra" ] || depends="$$depends, $$extra"; \
	sed -e "s|@PACKAGE@|$$pkg-dev|g" \
	    -e "s|@DEPENDS@|$$depends|g" \
	    -e "s|@VERSION@|$${ver}|g" \
	    -e "s|@ARCH@|$(DEB_ARCH)|g" \
	    -e "s|@MAINTAINER@|$(DEB_MAINTAINER)|g" \
	    -e "s|@INSTALLED_SIZE@|$$size|g" \
	    -e "s|@DESCRIPTION@|$$desc|g" \
	    $(DEB_HELPER_DIR)/control-dev.in > $$root/DEBIAN/control; \
	echo 2.0 > $(DEB_WORK)/debian-binary; \
	tar --owner=0 --group=0 --numeric-owner -czf $(DEB_WORK)/control.tar.gz -C $$root/DEBIAN .; \
	tar --owner=0 --group=0 --numeric-owner -czf $(DEB_WORK)/data.tar.gz -C $$root ./system; \
	rm -f $(CURDIR)/$${pkg}-dev_$${ver}_$(DEB_ARCH).deb; \
	ar rc $(CURDIR)/$${pkg}-dev_$${ver}_$(DEB_ARCH).deb \
	    $(DEB_WORK)/debian-binary $(DEB_WORK)/control.tar.gz $(DEB_WORK)/data.tar.gz; \
	echo "生成 $(CURDIR)/$${pkg}-dev_$${ver}_$(DEB_ARCH).deb"

# ---- 纯头文件包（如 linux-headers） --------------------------------------
__deb-header-%:
	@set -e; \
	pkg=$*; \
	ver=$(if $(DEB_VERSION_$*),$(DEB_VERSION_$*),$(DEB_VERSION)); \
	root=$(DEB_WORK)/$$pkg; \
	rm -rf $$root; mkdir -p $$root/DEBIAN $$root/system/usr/include; \
	for d in $(DEB_INCDIRS_$*); do cp -aL $$d $$root/system/usr/include/; done; \
	for d in $(DEB_INCDIRCONTENTS_$*); do cp -aL $$d/. $$root/system/usr/include/; done; \
	for f in $(DEB_INCFILES_$*); do cp -aL $$f $$root/system/usr/include/; done; \
	size=$$(du -sk $$root | cut -f1); \
	desc="$(if $(DEB_DESC_$*),$(DEB_DESC_$*),Android $* headers)"; \
	depends="$(DEB_HEADERONLY_DEPENDS_$*)"; \
	sed -e "s|@PACKAGE@|$$pkg|g" \
	    -e "s|@DEPENDS@|$$depends|g" \
	    -e "s|@VERSION@|$${ver}|g" \
	    -e "s|@ARCH@|$(DEB_ARCH)|g" \
	    -e "s|@MAINTAINER@|$(DEB_MAINTAINER)|g" \
	    -e "s|@INSTALLED_SIZE@|$$size|g" \
	    -e "s|@DESCRIPTION@|$$desc|g" \
	    $(DEB_HELPER_DIR)/control-headers.in > $$root/DEBIAN/control; \
	[ -n "$$depends" ] || sed -i '/^Depends:/d' $$root/DEBIAN/control; \
	echo 2.0 > $(DEB_WORK)/debian-binary; \
	tar --owner=0 --group=0 --numeric-owner -czf $(DEB_WORK)/control.tar.gz -C $$root/DEBIAN .; \
	tar --owner=0 --group=0 --numeric-owner -czf $(DEB_WORK)/data.tar.gz -C $$root ./system; \
	rm -f $(CURDIR)/$${pkg}_$${ver}_$(DEB_ARCH).deb; \
	ar rc $(CURDIR)/$${pkg}_$${ver}_$(DEB_ARCH).deb \
	    $(DEB_WORK)/debian-binary $(DEB_WORK)/control.tar.gz $(DEB_WORK)/data.tar.gz; \
	echo "生成 $(CURDIR)/$${pkg}_$${ver}_$(DEB_ARCH).deb"

# ---- 静态库 --------------------------------------------------------------
__deb-static-%:
	@set -e; \
	pkg=$*; \
	ver=$(if $(DEB_VERSION_$*),$(DEB_VERSION_$*),$(DEB_VERSION)); \
	smod=$(if $(DEB_STATIC_MODULE_$*),$(DEB_STATIC_MODULE_$*),$*); \
	sname=$(if $(DEB_STATIC_NAME_$*),$(DEB_STATIC_NAME_$*),$$smod); \
	a=$(DEB_STATIC_DIR)/$${smod}_intermediates/$${sname}.a; \
	[ -f $$a ] || $(MAKE) -C $(DEB_TOP) $$smod; \
	root=$(DEB_WORK)/$$pkg-static; \
	rm -rf $$root; mkdir -p $$root/DEBIAN $$root/system/lib; \
	cp -aL $$a $$root/system/lib/; \
	size=$$(du -sk $$root | cut -f1); \
	desc="$(if $(DEB_DESC_$*),$(DEB_DESC_$*),Android $* library) (static archive)"; \
	sed -e "s|@PACKAGE@|$$pkg-static|g" \
	    -e "s|@DEV@|$$pkg-dev|g" \
	    -e "s|@VERSION@|$${ver}|g" \
	    -e "s|@ARCH@|$(DEB_ARCH)|g" \
	    -e "s|@MAINTAINER@|$(DEB_MAINTAINER)|g" \
	    -e "s|@INSTALLED_SIZE@|$$size|g" \
	    -e "s|@DESCRIPTION@|$$desc|g" \
	    $(DEB_HELPER_DIR)/control-static.in > $$root/DEBIAN/control; \
	echo 2.0 > $(DEB_WORK)/debian-binary; \
	tar --owner=0 --group=0 --numeric-owner -czf $(DEB_WORK)/control.tar.gz -C $$root/DEBIAN .; \
	tar --owner=0 --group=0 --numeric-owner -czf $(DEB_WORK)/data.tar.gz -C $$root ./system; \
	rm -f $(CURDIR)/$${pkg}-static_$${ver}_$(DEB_ARCH).deb; \
	ar rc $(CURDIR)/$${pkg}-static_$${ver}_$(DEB_ARCH).deb \
	    $(DEB_WORK)/debian-binary $(DEB_WORK)/control.tar.gz $(DEB_WORK)/data.tar.gz; \
	echo "生成 $(CURDIR)/$${pkg}-static_$${ver}_$(DEB_ARCH).deb"

deb-clean:
	rm -rf $(DEB_WORK)
	rm -f $(CURDIR)/*_*_$(DEB_ARCH).deb
