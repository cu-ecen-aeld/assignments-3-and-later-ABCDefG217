#!/bin/bash
# Script outline to install and build kernel.
# Author: Siddhant Jajoo.

set -e
set -u

OUTDIR=/tmp/aeld
KERNEL_REPO=git://git.kernel.org/pub/scm/linux/kernel/git/stable/linux-stable.git
KERNEL_VERSION=v5.15.163
BUSYBOX_VERSION=1_33_1
FINDER_APP_DIR=$(realpath $(dirname $0))
ARCH=arm64
CROSS_COMPILE=aarch64-none-linux-gnu-

if [ $# -lt 1 ]
then
	echo "Using default directory ${OUTDIR} for output"
else
	OUTDIR=$1
	echo "Using passed directory ${OUTDIR} for output"
fi

mkdir -p ${OUTDIR}

cd "$OUTDIR"
if [ ! -d "${OUTDIR}/linux-stable" ]; then
    #Clone only if the repository does not exist.
	echo "CLONING GIT LINUX STABLE VERSION ${KERNEL_VERSION} IN ${OUTDIR}"
	git clone ${KERNEL_REPO} --depth 1 --single-branch --branch ${KERNEL_VERSION}
fi
if [ ! -e ${OUTDIR}/linux-stable/arch/${ARCH}/boot/Image ]; then
    cd linux-stable
    echo "Checking out version ${KERNEL_VERSION}"
    git checkout ${KERNEL_VERSION}

    # TODO: Add your kernel build steps here
    make -j4 ARCH=arm64 CROSS_COMPILE=aarch64-none-linux-gnu- mrproper
    make -j4 ARCH=arm64 CROSS_COMPILE=aarch64-none-linux-gnu- defconfig
    #make -j4 ARCH=arm64 CROSS_COMPILE=aarch64-none-linux-gnu- all
    make -j4 ARCH=arm64 CROSS_COMPILE=aarch64-none-linux-gnu- Image
    #make -j4 ARCH=arm64 CROSS_COMPILE=aarch64-none-linux-gnu- modules
    #make -j4 ARCH=arm64 CROSS_COMPILE=aarch64-none-linux-gnu- dtbs
    # TODO: Done
fi

echo "Adding the Image in outdir"
cp ${OUTDIR}/linux-stable/arch/arm64/boot/Image ${OUTDIR}

echo "Creating the staging directory for the root filesystem"
cd "$OUTDIR"
if [ -d "${OUTDIR}/rootfs" ]
then
	echo "Deleting rootfs directory at ${OUTDIR}/rootfs and starting over"
    sudo rm  -rf ${OUTDIR}/rootfs
fi

# TODO: Create necessary base directories
mkdir -p "${OUTDIR}/rootfs"
cd "${OUTDIR}/rootfs"
mkdir -p bin dev etc lib lib64 proc sbin sys tmp usr var home
mkdir -p usr/bin usr/lib usr/sbin
mkdir -p var/log
# TODO: Done

cd "$OUTDIR"
if [ ! -d "${OUTDIR}/busybox" ]
then
git clone git://busybox.net/busybox.git
    cd busybox
    git fetch --tags
    git checkout ${BUSYBOX_VERSION} || git checkout master
    # TODO:  Configure busybox
    make distclean
    make defconfig
    # TODO: Done
else
    cd busybox
    make distclean
    make defconfig
fi

# TODO: Make and install busybox

make -j4 ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE}
make CONFIG_PREFIX="${OUTDIR}/rootfs" ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} install
# TODO: Done


echo "Library dependencies"
${CROSS_COMPILE}readelf -a ${OUTDIR}/rootfs/bin/busybox | grep "program interpreter"
${CROSS_COMPILE}readelf -a ${OUTDIR}/rootfs/bin/busybox | grep "Shared library"

# TODO: Add library dependencies to rootfs
TOOLCHAIN_PATH=$(dirname $(dirname $(which ${CROSS_COMPILE}gcc)))
TOOLCHAIN_LIB="${TOOLCHAIN_PATH}/aarch64-none-linux-gnu/libc/lib/"
TOOLCHAIN_LIB64="${TOOLCHAIN_PATH}/aarch64-none-linux-gnu/libc/lib64/"
# Extract program interpreter
program_interpreter=$(${CROSS_COMPILE}readelf -a ${OUTDIR}/rootfs/bin/busybox | grep "program interpreter" | awk -F': ' '{print $2}' | tr -d '[]' | sed 's|/lib/||')
shared_libraries=$(${CROSS_COMPILE}readelf -a ${OUTDIR}/rootfs/bin/busybox | grep "Shared library" | awk -F'[][]' '{print $2}')
mkdir -p ${OUTDIR}/rootfs/lib ${OUTDIR}/rootfs/lib64

# Copy the program interpreter
if [ -f "${TOOLCHAIN_LIB}${program_interpreter}" ]; then
    cp "${TOOLCHAIN_LIB}${program_interpreter}" "${OUTDIR}/rootfs/lib/"
    echo "Copied program interpreter: ${program_interpreter}"
else
    echo "Error: Program interpreter ${program_interpreter} not found in ${TOOLCHAIN_LIB64}!"
fi

# Copy shared libraries from the toolchain
for lib in $shared_libraries; do
    if [ -f "${TOOLCHAIN_LIB}${lib}" ]; then
        cp "${TOOLCHAIN_LIB}${lib}" "${OUTDIR}/rootfs/lib/"
        echo "Copied: ${lib} to lib/"
    elif [ -f "${TOOLCHAIN_LIB64}${lib}" ]; then
        cp "${TOOLCHAIN_LIB64}${lib}" "${OUTDIR}/rootfs/lib64/"
        echo "Copied: ${lib} to lib64/"
    else
        echo "Error: Library ${lib} not found in toolchain!"
    fi
done


# TODO: Make device nodes
sudo mknod -m 666 ${OUTDIR}/rootfs/dev/null c 1 3
sudo mknod -m 666 ${OUTDIR}/rootfs/dev/ttyAMA0 c 5 1

# TODO: Clean and build the writer utility
cd ${FINDER_APP_DIR}
make clean
make ARCH=arm64 CROSS_COMPILE=aarch64-none-linux-gnu-


# TODO: Copy the finder related scripts and executables to the /home directory
# on the target rootfs
echo "--------------------------------------XXXX------------------------------------"
cp autorun-qemu.sh ${OUTDIR}/rootfs/home/
cp autorun-qemu.sh ${OUTDIR}/rootfs/home/
cp finder-test.sh ${OUTDIR}/rootfs/home/
cp -r conf/ ${OUTDIR}/rootfs/home/
cp writer ${OUTDIR}/rootfs/home/
cp writer.sh ${OUTDIR}/rootfs/home/
cp finder.sh ${OUTDIR}/rootfs/home/



# TODO: Chown the root directory
sudo chown -R root:root ${OUTDIR}/rootfs


# TODO: Create initramfs.cpio.gz
cd ${OUTDIR}/rootfs
find . -print0 | cpio --null -H newc -ov --owner root:root | gzip > ${OUTDIR}/initramfs.cpio.gz
# cd ${OUTDIR}
