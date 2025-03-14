#!/bin/bash
# manual-linux.sh: Build a barebones kernel, rootfs, and initramfs for QEMU.
# Author: [Your Name]
# Updated to meet Assignment 3 requirements.

set -e
set -u

# -----------------------------------------------------------------------------
# Variables and argument handling
# -----------------------------------------------------------------------------
# Default output directory if not specified.
OUTDIR="/tmp/aeld"

# If an argument is provided, use it as the output directory.
if [ $# -ge 1 ]; then
    OUTDIR="$1"
    echo "Using passed directory ${OUTDIR} for output"
else
    echo "Using default directory ${OUTDIR} for output"
fi

# Convert to an absolute path.
OUTDIR=$(realpath "${OUTDIR}")

# Create the output directory if it does not exist.
mkdir -p "${OUTDIR}" || { echo "Error: Could not create ${OUTDIR}"; exit 1; }

# -----------------------------------------------------------------------------
# Kernel build variables
# -----------------------------------------------------------------------------
KERNEL_REPO="https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git"
KERNEL_VERSION="v5.15.163"
ARCH=arm64
CROSS_COMPILE=aarch64-none-linux-gnu-

# -----------------------------------------------------------------------------
# Finder application and BusyBox variables
# -----------------------------------------------------------------------------
BUSYBOX_VERSION=1_33_1
# Finder application source directory: directory of this script.
FINDER_APP_DIR=$(realpath "$(dirname "$0")")

# -----------------------------------------------------------------------------
# Build the Linux Kernel
# -----------------------------------------------------------------------------
cd "${OUTDIR}"

if [ ! -d "${OUTDIR}/linux" ]; then
    echo "Cloning Linux kernel version ${KERNEL_VERSION} in ${OUTDIR}"
    git clone "${KERNEL_REPO}" --depth 1 --single-branch --branch "${KERNEL_VERSION}" linux
fi

cd linux
echo "Checking out version ${KERNEL_VERSION}"
git checkout "${KERNEL_VERSION}"

# Clean the build tree and build the kernel Image.
echo "Cleaning kernel build tree"
make -j4 ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} mrproper
echo "Configuring kernel (defconfig)"
make -j4 ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} defconfig
echo "Building kernel Image"
make -j4 ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} Image

# Copy the kernel Image to OUTDIR.
echo "Copying kernel Image to ${OUTDIR}"
cp arch/${ARCH}/boot/Image "${OUTDIR}"

cd "${OUTDIR}"

# -----------------------------------------------------------------------------
# Create the Root Filesystem (rootfs)
# -----------------------------------------------------------------------------
if [ -d "${OUTDIR}/rootfs" ]; then
    echo "Deleting existing rootfs at ${OUTDIR}/rootfs and starting over"
    sudo rm -rf "${OUTDIR}/rootfs"
fi

echo "Creating base directories for the root filesystem"
mkdir -p "${OUTDIR}/rootfs"
cd "${OUTDIR}/rootfs"
# Create essential directories.
mkdir -p bin dev etc lib lib64 proc sbin sys tmp usr var home
mkdir -p usr/bin usr/lib usr/sbin
mkdir -p var/log

# -----------------------------------------------------------------------------
# Build and Install BusyBox
# -----------------------------------------------------------------------------
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

# -----------------------------------------------------------------------------
# Add Library Dependencies for BusyBox
# -----------------------------------------------------------------------------
echo "Checking library dependencies for BusyBox"
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

# -----------------------------------------------------------------------------
# Create Device Nodes
# -----------------------------------------------------------------------------
echo "Creating device nodes"
sudo mknod -m 666 "${OUTDIR}/rootfs/dev/null" c 1 3
sudo mknod -m 666 "${OUTDIR}/rootfs/dev/ttyAMA0" c 5 1

# -----------------------------------------------------------------------------
# Build the Writer Application (Assignment 2)
# -----------------------------------------------------------------------------
echo "Building the writer application"
cd "${FINDER_APP_DIR}"
make clean
make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE}

# -----------------------------------------------------------------------------
# Copy Finder Application Files into the Root Filesystem
# -----------------------------------------------------------------------------
# Required files from Assignment 2.
REQUIRED_FILES=(autorun-qemu.sh finder-test.sh finder.sh writer writer.sh)
for file in "${REQUIRED_FILES[@]}"; do
    if [ ! -e "${FINDER_APP_DIR}/${file}" ]; then
        echo "Error: Required file ${file} not found in ${FINDER_APP_DIR}"
        exit 1
    fi
done

echo "Copying finder application scripts and executables to rootfs /home"
cp "${FINDER_APP_DIR}/autorun-qemu.sh" "${OUTDIR}/rootfs/home/"
cp "${FINDER_APP_DIR}/finder-test.sh" "${OUTDIR}/rootfs/home/"
cp "${FINDER_APP_DIR}/finder.sh" "${OUTDIR}/rootfs/home/"
cp "${FINDER_APP_DIR}/writer" "${OUTDIR}/rootfs/home/"
cp "${FINDER_APP_DIR}/writer.sh" "${OUTDIR}/rootfs/home/"

# Copy the conf directory (which should include username.txt and assignment.txt)
if [ -d "${FINDER_APP_DIR}/conf" ]; then
    cp -r "${FINDER_APP_DIR}/conf" "${OUTDIR}/rootfs/home/"
    echo "Copied conf directory to rootfs/home/"
else
    echo "Error: conf directory not found in ${FINDER_APP_DIR}"
    exit 1
fi

# Modify finder-test.sh to reference conf/assignment.txt instead of ../conf/assignment.txt.
sed -i 's|\.\./conf/assignment.txt|conf/assignment.txt|g' "${OUTDIR}/rootfs/home/finder-test.sh"

# Copy the autorun-qemu.sh script (already copied above as part of required files)

# -----------------------------------------------------------------------------
# Set Permissions and Ownership for the Root Filesystem
# -----------------------------------------------------------------------------
echo "Setting executable permissions for scripts"
chmod +x "${OUTDIR}/rootfs/home/"*.sh
chmod +x "${OUTDIR}/rootfs/home/writer"
chmod +x "${OUTDIR}/rootfs/home/finder.sh"

echo "Changing ownership of rootfs to root"
sudo chown -R root:root "${OUTDIR}/rootfs"

# -----------------------------------------------------------------------------
# Create the initramfs Image
# -----------------------------------------------------------------------------
echo "Creating initramfs.cpio.gz"
cd "${OUTDIR}/rootfs"
find . -print0 | cpio --null -ov --format=newc --owner root:root | gzip > "${OUTDIR}/initramfs.cpio.gz"

echo "Build complete."
echo "Kernel Image and initramfs are available in ${OUTDIR}"

