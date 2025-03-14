#!/bin/bash
# Script to build the kernel, BusyBox, and create the initramfs for QEMU.
# Modified version based on Siddhant Jajoo's original.
# Author: [Your Name]

set -e
set -u

# Variables
OUTDIR=/tmp/aeld
KERNEL_REPO=git://git.kernel.org/pub/scm/linux/kernel/git/stable/linux-stable.git
KERNEL_VERSION=v5.15.163
BUSYBOX_VERSION=1_33_1
FINDER_APP_DIR=$(realpath "$(dirname "$0")")
ARCH=arm64
CROSS_COMPILE=aarch64-none-linux-gnu-

# Allow OUTDIR override from command-line argument.
if [ $# -ge 1 ]; then
    OUTDIR=$1
    echo "Using passed directory ${OUTDIR} for output"
else
    echo "Using default directory ${OUTDIR} for output"
fi

mkdir -p "${OUTDIR}"

# Clone Linux stable if not already present.
cd "${OUTDIR}"
if [ ! -d "${OUTDIR}/linux-stable" ]; then
    echo "Cloning Linux stable version ${KERNEL_VERSION} in ${OUTDIR}"
    git clone "${KERNEL_REPO}" --depth 1 --single-branch --branch "${KERNEL_VERSION}"
fi

# Build the kernel Image if it doesn't exist.
if [ ! -e "${OUTDIR}/linux-stable/arch/${ARCH}/boot/Image" ]; then
    cd linux-stable
    echo "Checking out version ${KERNEL_VERSION}"
    git checkout "${KERNEL_VERSION}"

    echo "Cleaning kernel build tree"
    make -j4 ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} mrproper
    echo "Configuring kernel with defconfig"
    make -j4 ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} defconfig
    echo "Building kernel Image"
    make -j4 ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} Image
    cd "${OUTDIR}"
fi

echo "Copying kernel Image to ${OUTDIR}"
cp "${OUTDIR}/linux-stable/arch/${ARCH}/boot/Image" "${OUTDIR}"

# Create the staging directory for the root filesystem.
cd "${OUTDIR}"
if [ -d "${OUTDIR}/rootfs" ]; then
    echo "Deleting existing rootfs at ${OUTDIR}/rootfs and starting over"
    sudo rm -rf "${OUTDIR}/rootfs"
fi

echo "Creating base directories for the root filesystem"
mkdir -p "${OUTDIR}/rootfs"
cd "${OUTDIR}/rootfs"
mkdir -p bin dev etc lib lib64 proc sbin sys tmp usr var home
mkdir -p usr/bin usr/lib usr/sbin
mkdir -p var/log

# Clone and build BusyBox.
cd "${OUTDIR}"
if [ ! -d "${OUTDIR}/busybox" ]; then
    echo "Cloning BusyBox"
    git clone git://busybox.net/busybox.git
    cd busybox
    git fetch --tags
    git checkout "${BUSYBOX_VERSION}" || git checkout master
    echo "Configuring BusyBox"
    make distclean
    make defconfig
else
    cd busybox
    make distclean
    make defconfig
fi

echo "Building BusyBox"
make -j4 ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE}
echo "Installing BusyBox to rootfs"
make CONFIG_PREFIX="${OUTDIR}/rootfs" ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} install

# Check and add library dependencies.
echo "Library dependencies for BusyBox:"
${CROSS_COMPILE}readelf -a "${OUTDIR}/rootfs/bin/busybox" | grep "program interpreter"
${CROSS_COMPILE}readelf -a "${OUTDIR}/rootfs/bin/busybox" | grep "Shared library"

TOOLCHAIN_PATH=$(dirname "$(dirname "$(which ${CROSS_COMPILE}gcc)")")
TOOLCHAIN_LIB="${TOOLCHAIN_PATH}/aarch64-none-linux-gnu/libc/lib/"
TOOLCHAIN_LIB64="${TOOLCHAIN_PATH}/aarch64-none-linux-gnu/libc/lib64/"

program_interpreter=$(${CROSS_COMPILE}readelf -a "${OUTDIR}/rootfs/bin/busybox" | \
    grep "program interpreter" | awk -F': ' '{print $2}' | tr -d '[]' | sed 's|/lib/||')
shared_libraries=$(${CROSS_COMPILE}readelf -a "${OUTDIR}/rootfs/bin/busybox" | \
    grep "Shared library" | awk -F'[][]' '{print $2}')

mkdir -p "${OUTDIR}/rootfs/lib" "${OUTDIR}/rootfs/lib64"

# Copy the program interpreter.
if [ -f "${TOOLCHAIN_LIB}${program_interpreter}" ]; then
    cp "${TOOLCHAIN_LIB}${program_interpreter}" "${OUTDIR}/rootfs/lib/"
    echo "Copied program interpreter: ${program_interpreter}"
else
    echo "Error: Program interpreter ${program_interpreter} not found in ${TOOLCHAIN_LIB}"
fi

# Copy shared libraries.
for lib in $shared_libraries; do
    if [ -f "${TOOLCHAIN_LIB}${lib}" ]; then
        cp "${TOOLCHAIN_LIB}${lib}" "${OUTDIR}/rootfs/lib/"
        echo "Copied ${lib} to lib/"
    elif [ -f "${TOOLCHAIN_LIB64}${lib}" ]; then
        cp "${TOOLCHAIN_LIB64}${lib}" "${OUTDIR}/rootfs/lib64/"
        echo "Copied ${lib} to lib64/"
    else
        echo "Error: Library ${lib} not found in toolchain!"
    fi
done

# Create device nodes.
echo "Creating device nodes"
sudo mknod -m 666 "${OUTDIR}/rootfs/dev/null" c 1 3
sudo mknod -m 666 "${OUTDIR}/rootfs/dev/ttyAMA0" c 5 1

# Build the writer utility.
echo "Building the writer utility"
cd "${FINDER_APP_DIR}"
make clean
make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE}

# Verify required finder application files exist.
REQUIRED_FILES=(autorun-qemu.sh finder-test.sh finder.sh writer writer.sh)
for file in "${REQUIRED_FILES[@]}"; do
    if [ ! -e "${FINDER_APP_DIR}/${file}" ]; then
        echo "Error: Required file ${file} not found in ${FINDER_APP_DIR}"
        exit 1
    fi
done

# Copy finder related scripts and executables to /home in rootfs.
echo "Copying finder related scripts to rootfs /home"
cp "${FINDER_APP_DIR}/autorun-qemu.sh" "${OUTDIR}/rootfs/home/"
cp "${FINDER_APP_DIR}/finder-test.sh" "${OUTDIR}/rootfs/home/"
cp "${FINDER_APP_DIR}/finder.sh" "${OUTDIR}/rootfs/home/"
cp "${FINDER_APP_DIR}/writer" "${OUTDIR}/rootfs/home/"
cp "${FINDER_APP_DIR}/writer.sh" "${OUTDIR}/rootfs/home/"

# Copy the conf directory if it exists.
if [ -d "${FINDER_APP_DIR}/conf" ]; then
    cp -r "${FINDER_APP_DIR}/conf" "${OUTDIR}/rootfs/home/"
else
    echo "Warning: conf directory not found in ${FINDER_APP_DIR}"
fi

# Set executable permissions on scripts.
chmod +x "${OUTDIR}/rootfs/home/"*.sh
chmod +x "${OUTDIR}/rootfs/home/writer"
chmod +x "${OUTDIR}/rootfs/home/finder.sh"

# Change ownership of rootfs.
echo "Changing ownership of rootfs to root"
sudo chown -R root:root "${OUTDIR}/rootfs"

# Create the initramfs image.
echo "Creating initramfs.cpio.gz"
cd "${OUTDIR}/rootfs"
find . -print0 | cpio --null -ov --format=newc --owner root:root | gzip > "${OUTDIR}/initramfs.cpio.gz"

echo "Build complete. Kernel Image and initramfs are available in ${OUTDIR}"

