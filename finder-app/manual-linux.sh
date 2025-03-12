#!/bin/bash
set -e
set -u

# 參數設置
if [ $# -lt 1 ]; then
    OUTDIR=/tmp/aeld
    echo "Using default directory ${OUTDIR} for output"
else
    OUTDIR=$(realpath $1)
    echo "Using passed directory ${OUTDIR} for output"
fi

mkdir -p ${OUTDIR} || { echo "Failed to create ${OUTDIR}"; exit 1; }

# 下載並構建 Kernel
KERNEL_REPO=https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git
KERNEL_VERSION=v5.15.163
ARCH=arm64
CROSS_COMPILE=aarch64-none-linux-gnu-

cd "$OUTDIR"
if [ ! -d "${OUTDIR}/linux-stable" ]; then
    echo "Cloning Linux kernel version ${KERNEL_VERSION}..."
    git clone ${KERNEL_REPO} --depth 1 --single-branch --branch ${KERNEL_VERSION} linux-stable
fi

cd linux-stable
git checkout ${KERNEL_VERSION}

echo "Building the kernel..."
make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} defconfig
make -j$(nproc) ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} all

echo "Copying Kernel Image to ${OUTDIR}"
cp arch/${ARCH}/boot/Image ${OUTDIR}/

# 創建 rootfs
echo "Creating root filesystem directory: ${OUTDIR}/rootfs"
cd ${OUTDIR}
mkdir -p rootfs/{bin,sbin,etc,proc,sys,usr/bin,usr/sbin,lib,lib64,dev,home}

# 下載 BusyBox
cd ${OUTDIR}
if [ ! -d "busybox" ]; then
    echo "Cloning BusyBox..."
    git clone git://busybox.net/busybox.git
fi

cd busybox
git checkout ${BUSYBOX_VERSION}
make distclean
make defconfig
make -j$(nproc) ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE}
make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} CONFIG_PREFIX=${OUTDIR}/rootfs install

# 複製函式庫
echo "Copying library dependencies..."
SYSROOT=$(${CROSS_COMPILE}gcc --print-sysroot)
cp ${SYSROOT}/lib/ld-2.31.so ${OUTDIR}/rootfs/lib/
cp ${SYSROOT}/lib/libc-2.31.so ${OUTDIR}/rootfs/lib/

# 創建 /dev 節點
echo "Creating device nodes..."
cd ${OUTDIR}/rootfs
sudo mknod -m 666 dev/null c 1 3
sudo mknod -m 600 dev/console c 5 1

# 交叉編譯 writer
echo "Building writer application..."
cd ${FINDER_APP_DIR}
make clean
make CROSS_COMPILE=${CROSS_COMPILE}
cp writer ${OUTDIR}/rootfs/home/

# 複製 finder 相關腳本
echo "Copying finder application and configuration files..."
cp ${FINDER_APP_DIR}/finder.sh ${OUTDIR}/rootfs/home/
cp ${FINDER_APP_DIR}/finder-test.sh ${OUTDIR}/rootfs/home/
cp ${FINDER_APP_DIR}/conf/username.txt ${OUTDIR}/rootfs/home/
cp ${FINDER_APP_DIR}/conf/assignment.txt ${OUTDIR}/rootfs/home/

# 複製 autorun-qemu.sh
echo "Copying autorun-qemu.sh to home directory..."
cp ${FINDER_APP_DIR}/autorun-qemu.sh ${OUTDIR}/rootfs/home/

# 設定 rootfs 的權限
echo "Setting ownership for root directory..."
cd ${OUTDIR}/rootfs
sudo chown -R root:root *

# 生成 initramfs
echo "Creating standalone initramfs..."
find . | cpio -o --format=newc > ${OUTDIR}/initramfs.cpio
gzip -f ${OUTDIR}/initramfs.cpio

# 確保 initramfs 存在
if [ -f "${OUTDIR}/initramfs.cpio.gz" ]; then
    echo "initramfs.cpio.gz successfully created!"
else
    echo "Error: initramfs.cpio.gz was not created!"
    exit 1
fi

echo "All tasks completed successfully!"

