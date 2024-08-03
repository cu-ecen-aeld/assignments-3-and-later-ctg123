#!/bin/bash
# Script outline to install and build kernel.
# Author: Siddhant Jajoo.
# Modified for Assignment 3 part 2

set -e
set -u

# Define colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

OUTDIR=/tmp/aeld
KERNEL_REPO=git://git.kernel.org/pub/scm/linux/kernel/git/stable/linux-stable.git
KERNEL_VERSION=v5.1.10
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

    # clean up - use with caution
    make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} mrproper
    # build steps
    make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} defconfig
    make -j4 ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} all
    make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} dtbs
fi

echo -e "${YELLOW}Adding the Image in outdir${NC}"
cp ${OUTDIR}/linux-stable/arch/${ARCH}/boot/Image ${OUTDIR}

echo -e "${YELLOW}Creating the staging directory for the root filesystem${NC}"
cd "$OUTDIR"
if [ -d "${OUTDIR}/rootfs" ]
then
	echo "Deleting rootfs directory at ${OUTDIR}/rootfs and starting over"
    sudo rm  -rf ${OUTDIR}/rootfs
fi

# TODO: Create necessary base directories
echo -e "${YELLOW}Create necessary base directories${NC}"
mkdir -p ${OUTDIR}/rootfs/{bin,dev,etc,home,lib,lib64,proc,sbin,sys,tmp,usr,var}
mkdir -p ${OUTDIR}/rootfs/usr/{bin,lib,sbin}
mkdir -p ${OUTDIR}/rootfs/var/log
#mkdir -p ${OUTDIR}/rootfs/home/conf

cd "$OUTDIR"
if [ ! -d "${OUTDIR}/busybox" ]
then
git clone git://busybox.net/busybox.git
    cd busybox
    git checkout ${BUSYBOX_VERSION}
    # TODO:  Configure busybox
    make distclean
    make defconfig
else
    cd busybox
fi

# TODO: Make and install busybox
echo -e "${YELLOW}make and install busybox${NC}"
make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} CONFIG_PREFIX=${OUTDIR}/rootfs install

if [ ! -e ${OUTDIR}/rootfs/bin/busybox ]; then
  echo "BusyBox binary not found"
  exit 1
fi

# busybox binary
# setuid root to ensure all configured applets will
# work properly
sudo chmod 4755 ${OUTDIR}/rootfs/bin/busybox

echo -e "${YELLOW}Library dependencies${NC}"
${CROSS_COMPILE}readelf -a ${OUTDIR}/rootfs/bin/busybox | grep "program interpreter"
${CROSS_COMPILE}readelf -a ${OUTDIR}/rootfs/bin/busybox | grep "Shared library"

# Add library dependencies to rootfs
SYSROOT=$(${CROSS_COMPILE}gcc -print-sysroot)
LINKER=$(${CROSS_COMPILE}readelf -a ${OUTDIR}/rootfs/bin/busybox | grep "program interpreter" | awk -F ': ' '{print $2}' | tr -d ']')
SHARED_LIBS=$(${CROSS_COMPILE}readelf -a ${OUTDIR}/rootfs/bin/busybox | grep "Shared library" | awk '{print $5}' | tr -d '[]' | tr '\n' ' ')

# Create necessary directories for libraries
mkdir -p ${OUTDIR}/rootfs/lib
mkdir -p ${OUTDIR}/rootfs/lib64

# Copy dynamic linker/loader to rootfs
cp ${SYSROOT}${LINKER} ${OUTDIR}/rootfs${LINKER}

# Function to copy libraries if they exist
copy_library() {
    LIB=$1
    if [ -f ${SYSROOT}/lib/${LIB} ]; then
        cp ${SYSROOT}/lib/${LIB} ${OUTDIR}/rootfs/lib/
    elif [ -f ${SYSROOT}/lib64/${LIB} ]; then
        cp ${SYSROOT}/lib64/${LIB} ${OUTDIR}/rootfs/lib64/
    else
        echo "Warning: ${LIB} not found in sysroot."
    fi
}

# Copy shared libraries to rootfs
for LIB in ${SHARED_LIBS}; do
    copy_library ${LIB}
done

# TODO: Make device nodes
echo -e "${YELLOW}make device nodes${NC}"

sudo mknod -m 666 ${OUTDIR}/rootfs/dev/null c 1 3
sudo mknod -m 600 ${OUTDIR}/rootfs/dev/console c 5 1

# TODO: Clean and build the writer utility
echo "${YELLOW}Clean and build the writer utility${NC}"

cd ${FINDER_APP_DIR}
make clean
make CROSS_COMPILE=${CROSS_COMPILE}

# TODO: Copy the finder related scripts and executables to the /home directory
# on the target rootfs
echo -e "${YELLOW}Copy the finder related scripts and executables to the /home directory${NC}"

cp ${FINDER_APP_DIR}/finder.sh "${OUTDIR}/rootfs/home/"
cp ${FINDER_APP_DIR}/finder-test.sh "${OUTDIR}/rootfs/home/"
cp ${FINDER_APP_DIR}/writer "${OUTDIR}/rootfs/home/"
cp ${FINDER_APP_DIR}/autorun-qemu.sh "${OUTDIR}/rootfs/home/"
#cp -Lr ${FINDER_APP_DIR}/conf/ ${OUTDIR}/rootfs/home/
mkdir -p ${OUTDIR}/rootfs/home/conf
cp -a conf/username.txt "${OUTDIR}/rootfs/home/conf"
cp -a conf/assignment.txt "${OUTDIR}/rootfs/home/conf"

# TODO: Chown the root directory
echo -e "${YELLOW}Chown the root directory${NC}"

cd ${OUTDIR}/rootfs
sudo chown -R root:root ${OUTDIR}/rootfs

# TODO: Create initramfs.cpio.gz
echo -e "${YELLOW}Create initramfs.cpio.gz${NC}"

cd ${OUTDIR}/rootfs
find . | cpio -H newc -ov --owner root:root > ${OUTDIR}/initramfs.cpio
gzip -f ${OUTDIR}/initramfs.cpio