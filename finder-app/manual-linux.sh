#!/bin/bash
# Script outline to install and build kernel.
# Author: Siddhant Jajoo.

set -e
set -u

OUTDIR=/tmp/aeld
KERNEL_REPO=git://git.kernel.org/pub/scm/linux/kernel/git/stable/linux-stable.git
KERNEL_VERSION=v5.1.10
BUSYBOX_VERSION=1_33_1
FINDER_APP_DIR=$(realpath $(dirname $0))
ARCH=arm64
CROSS_COMPILE=aarch64-none-linux-gnu-
TOOLCHAIN_SYS_ROOT=$(aarch64-none-linux-gnu-gcc -print-sysroot -v 2>/dev/null)

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

    make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} mrproper
    make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} defconfig
    make -j$(nproc) ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} all
    make -j$(nproc) ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} modules
    make -j$(nproc) ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} dtbs
fi

echo "Adding the Image in outdir"
cp ${OUTDIR}/linux-stable/vmlinux ${OUTDIR}/
cp ${OUTDIR}/linux-stable/arch/${ARCH}/boot/Image ${OUTDIR}/
# cp ${OUTDIR}/linux-stable/arch/${ARCH}/boot/zImage ${OUTDIR}/
# cp ${OUTDIR}/linux-stable/arch/${ARCH}/boot/uImage ${OUTDIR}/

echo "Creating the staging directory for the root filesystem"
cd "$OUTDIR"
if [ -d "${OUTDIR}/rootfs" ]
then
    echo "Deleting rootfs directory at ${OUTDIR}/rootfs and starting over"
    sudo rm  -rf ${OUTDIR}/rootfs
fi

mkdir -p $OUTDIR/rootfs
cd $OUTDIR/rootfs
mkdir -p bin dev etc home lib lib64 proc sbin sys tmp
mkdir -p usr/bin usr/lin usr/sbin
mkdir -p var/log

cd "$OUTDIR"
if [ ! -d "${OUTDIR}/busybox" ]
then
    git clone git://busybox.net/busybox.git
    cd busybox
    git checkout ${BUSYBOX_VERSION}
    make distclean
    make defconfig
else
    cd busybox
fi

make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE}
make CONFIG_PREFIX=${OUTDIR}/rootfs/ ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} install

cd ${OUTDIR}/rootfs
echo "Library dependencies"
${CROSS_COMPILE}readelf -a bin/busybox | grep "program interpreter"
${CROSS_COMPILE}readelf -a bin/busybox | grep "Shared library"

cp ${TOOLCHAIN_SYS_ROOT}/lib/ld-linux-aarch64.so.1 ./lib/

cp ${TOOLCHAIN_SYS_ROOT}/lib64/libm.so.6 ./lib64/
cp ${TOOLCHAIN_SYS_ROOT}/lib64/libresolv.so.2 ./lib64/
cp ${TOOLCHAIN_SYS_ROOT}/lib64/libc.so.6 ./lib64/

sudo mknod -m 666 ./dev/null c 1 3
sudo mknod -m 600 ./dev/console c 5 1

make -C ${FINDER_APP_DIR} CROSS_COMPILE=${CROSS_COMPILE} clean
make -C ${FINDER_APP_DIR} CROSS_COMPILE=${CROSS_COMPILE}

cp ${FINDER_APP_DIR}/finder.sh ./home/
cp ${FINDER_APP_DIR}/finder-test.sh ./home/
cp ${FINDER_APP_DIR}/writer ./home/
cp ${FINDER_APP_DIR}/autorun-qemu.sh ./home/
mkdir -p ./home/conf
cp ${FINDER_APP_DIR}/../conf/* ./home/conf/
sed -i 's?../conf/assignment.txt?conf/assignment.txt?g' ./home/finder-test.sh

sudo chown -R root:root *

find . | cpio -H newc -ov --owner root:root > ${OUTDIR}/initramfs.cpio
cd ${OUTDIR}
gzip -f initramfs.cpio