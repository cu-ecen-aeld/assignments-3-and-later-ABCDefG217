#!/bin/bash
# Script outline to install and build kernel.
# Author: Siddhant Jajoo.

set -e
set -u
set -x

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

    # Kernel build steps
    # clean
    make ARCH=arm64 CROSS_COMPILE=${CROSS_COMPILE} mrproper
    # defconfig
    make ARCH=arm64 CROSS_COMPILE=${CROSS_COMPILE} defconfig
    # all
    make -j4 ARCH=arm64 CROSS_COMPILE=${CROSS_COMPILE} all
    # device tree
    make ARCH=arm64 CROSS_COMPILE=${CROSS_COMPILE} dtbs
    # copy image to outdir

fi

echo "Adding the Image in outdir"
cp  ${OUTDIR}/linux-stable/arch/${ARCH}/boot/Image "$OUTDIR"/.

echo "Creating the staging directory for the root filesystem"
ROOTFS_DIR="$OUTDIR"/rootfs

if [ -d "$ROOTFS_DIR" ]
then
	echo "Deleting rootfs directory at ${ROOTFS_DIR} and starting over"
    sudo rm  -rf "$ROOTFS_DIR"
fi

# Create necessary base directories
mkdir -p "$ROOTFS_DIR"/bin
mkdir -p "$ROOTFS_DIR"/dev
mkdir -p "$ROOTFS_DIR"/etc
mkdir -p "$ROOTFS_DIR"/home/conf
mkdir -p "$ROOTFS_DIR"/lib
mkdir -p "$ROOTFS_DIR"/lib64
mkdir -p "$ROOTFS_DIR"/proc
mkdir -p "$ROOTFS_DIR"/sbin
mkdir -p "$ROOTFS_DIR"/sys
mkdir -p "$ROOTFS_DIR"/tmp
mkdir -p "$ROOTFS_DIR"/usr
mkdir -p "$ROOTFS_DIR"/var
mkdir -p "$ROOTFS_DIR"/usr/bin
mkdir -p "$ROOTFS_DIR"/usr/lib
mkdir -p "$ROOTFS_DIR"/usr/sbin
mkdir -p "$ROOTFS_DIR"/var/log

cd "$OUTDIR"
if [ ! -d "${OUTDIR}/busybox" ]
then
git clone git://busybox.net/busybox.git
    cd busybox
    git checkout ${BUSYBOX_VERSION}
    # TODO:  Configure busybox
else
    cd busybox
fi

# Make and install busybox
echo "Building busybox"
pwd
make distclean
make defconfig
make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE}
make CONFIG_PREFIX="${ROOTFS_DIR}" ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} install

echo "Library dependencies"
echo Program Interpreter
${CROSS_COMPILE}readelf -a "$ROOTFS_DIR"/bin/busybox | grep "program interpreter"
echo Shared Library
${CROSS_COMPILE}readelf -a "$ROOTFS_DIR"/bin/busybox | grep "Shared library"

# Add library dependencies to rootfs
# These are included in repo
cp "$FINDER_APP_DIR"/deps/ld-linux-aarch64.so.1 "$ROOTFS_DIR"/lib/.
cp "$FINDER_APP_DIR"/deps/libc.so.6 "$ROOTFS_DIR"/lib64/.
cp "$FINDER_APP_DIR"/deps/libm.so.6 "$ROOTFS_DIR"/lib64/.
cp "$FINDER_APP_DIR"/deps/libresolv.so.2 "$ROOTFS_DIR"/lib64/.

# Make device nodes
sudo mknod -m 666 "$ROOTFS_DIR"/dev/null c 1 3
sudo mknod -m 666 "$ROOTFS_DIR"/dev/tty0  c 1 5

# Clean and build the writer utility
cd "$FINDER_APP_DIR"
make clean
CROSS_COMPILE=${CROSS_COMPILE} make all
cd "$OUTDIR"

# Copy the finder related scripts and executables to the /home directory
# on the target rootfs

# copy writer and finder binaries
cp -a "$FINDER_APP_DIR"/writer "$ROOTFS_DIR"/home/.
cp -a "$FINDER_APP_DIR"/finder "$ROOTFS_DIR"/home/.

# copy finder.sh
cp -a "$FINDER_APP_DIR"/finder.sh "$ROOTFS_DIR"/home/.

# copy username.txt and assignment.txt
cp -a "$FINDER_APP_DIR"/conf/username.txt "$ROOTFS_DIR"/home/conf/.
cp -a "$FINDER_APP_DIR"/conf/assignment.txt "$ROOTFS_DIR"/home/conf/.

# copy finder-test.sh
cp -a "$FINDER_APP_DIR"/finder-test.sh "$ROOTFS_DIR"/home/.

# copy autorun-qemu.sh
cp -a "$FINDER_APP_DIR"/autorun-qemu.sh "$ROOTFS_DIR"/home/.

# Chown the root directory
sudo chown -R root "$OUTDIR/rootfs"

# Create initramfs file
cd "$ROOTFS_DIR"
find . | cpio -H newc -ov --owner root:root > $OUTDIR/initramfs.cpio
cd "$OUTDIR"
gzip -f initramfs.cpio
