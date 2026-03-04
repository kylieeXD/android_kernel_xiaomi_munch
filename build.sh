#!/bin/bash
SECONDS=0
set -eo pipefail

# Set current path
KERNEL_PATH="$PWD"

# Set kernel path
OUTPUT_PATH="out/arch/arm64/boot"

# Set kernel images file
OBJ="${OUTPUT_PATH}/Image"
DTBO="${OUTPUT_PATH}/dtbo.img"
DTB="${OUTPUT_PATH}/dtb"

# Set kernel date
DATE="$(TZ=Asia/Jakarta date +%Y%m%d%H%M)"

# Set kernel name
if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
	KERNEL_NAME="rethinking-$1-$2.zip"
else
	KERNEL_NAME="rethinking-$1-$DATE.zip"
fi

# Set kernel defconfig
DEFCONFIG="arch/arm64/configs/vendor/munch_defconfig"

# Simple sed function
set_cfg() {
	local key="$1"; local val="$2"
	if [ "$val" = "y" ]; then sed -i "s/^# $key is not set/$key=y/; s/^$key=.*/$key=y/" "$DEFCONFIG"
	else sed -i "s/^$key=.*/# $key is not set/" "$DEFCONFIG"; fi
}

# Setup Root
case "$1" in
	KSU)
		set_cfg CONFIG_KSU y ;;
	NoKSU)
		set_cfg CONFIG_KSU n ;;
	*) echo "Unknown root: $1"; exit 1 ;;
esac

# Upload script
function UPLOAD_ARTIFACT() {
	RESPONSE=$(curl -s -F "file=@$1" "https://store1.gofile.io/contents/uploadfile" \
	|| curl -s -F "file=@$1" "https://store2.gofile.io/contents/uploadfile")
	echo "Download link: $(echo "$RESPONSE" | grep -oP '"downloadPage":"\K[^"]+')"
}

# Kernel Compiler
function KERNEL_COMPILE() {
	# Set environment variables
	export USE_CCACHE=1
	export KBUILD_BUILD_HOST=builder
	export KBUILD_BUILD_USER=khayloaf

	# Create output directory and do a clean build
	rm -rf out anykernel && mkdir -p out

	# Download clang if not present
	if [[ ! -d clang ]]; then mkdir -p clang
		wget https://github.com/Impqxr/aosp_clang_ci/releases/download/13289611/clang-13289611-linux-x86.tar.xz -O clang.tar.gz
		tar -xf clang.tar.gz -C clang && if [ -d clang/clang-* ]; then mv clang/clang-*/* clang; fi && rm -rf clang.tar.gz
	fi

	# Add clang bin directory to PATH
	export PATH="${PWD}/clang/bin:$PATH"

	# Make the config
	make O=out ARCH=arm64 vendor/munch_defconfig

	# Build the kernel with clang
	make -j$(nproc --all) O=out ARCH=arm64 CC=clang LD=ld.lld AS=llvm-as AR=llvm-ar NM=llvm-nm OBJCOPY=llvm-objcopy OBJDUMP=llvm-objdump STRIP=llvm-strip CROSS_COMPILE=aarch64-linux-gnu- CROSS_COMPILE_COMPAT=arm-linux-gnueabi- LLVM=1 LLVM_IAS=1
}

# Kernel Results
function KERNEL_RESULT() {
	# Run compiler
	KERNEL_COMPILE

	# Create anykernel
	rm -rf anykernel
	git clone https://github.com/kylieeXD/AK3-Munch.git -b "$1" anykernel

	# Copying image
	cp "$DTB" "anykernel/kernels/"
	cp "$DTBO" "anykernel/kernels/"
	cp "$OBJ" "anykernel/kernels/"

	# Created zip kernel
	cd anykernel && zip -r9 "$2" *

	# Upload kernel and log to artifact
	if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
		cp "$2" "$3"
	else
		echo "Uploading kernel..." && UPLOAD_ARTIFACT "$2"
	fi

	# Back to kernel root
	cd - >/dev/null
}

# Run all function
rm -rf compile.log
KERNEL_RESULT "main" "$KERNEL_NAME" "$3" | tee compile.log

# Done bang
echo -e "Completed in $((SECONDS / 60)) minute(s) and $((SECONDS % 60)) second(s) !\n"
