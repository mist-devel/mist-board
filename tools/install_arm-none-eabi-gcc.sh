#!/bin/bash

# Script to install gcc as described on 
# http://retroramblings.net/?p=315

BINUTILS_VERSION=binutils-2.25.1
BINUTILS_ARCHIVE=${BINUTILS_VERSION}.tar.bz2
BINUTILS_MD5=ac493a78de4fee895961d025b7905be4

GCC_VERSION=gcc-5.2.0
GCC_ARCHIVE=${GCC_VERSION}.tar.bz2
GCC_MD5=a51bcfeb3da7dd4c623e27207ed43467

NEWLIB_VERSION=newlib-2.2.0
NEWLIB_ARCHIVE=${NEWLIB_VERSION}.tar.gz
NEWLIB_MD5=f2294ded26e910a73637ecdfbdd1ef05

if [ ! -d archives ]; then
    mkdir archives
fi

if [ ! -f archives/${BINUTILS_ARCHIVE} ]; then
    echo "Downloading ${BINUTILS_ARCHIVE} ..."
    wget -Parchives ftp://ftp.fu-berlin.de/unix/gnu/binutils/${BINUTILS_ARCHIVE}
fi

if [ `md5sum -b archives/${BINUTILS_ARCHIVE} | cut -d* -f1` != ${BINUTILS_MD5} ]; then
    echo "Archive is broken: $BINUTILS_ARCHIVE"
    exit 1;
fi

if [ ! -f archives/${GCC_ARCHIVE} ]; then
    echo "Downloading ${GCC_ARCHIVE} ..."
    wget -Parchives ftp://ftp.fu-berlin.de/unix/languages/gcc/releases/gcc-5.2.0/${GCC_ARCHIVE}
fi

if [ `md5sum -b archives/${GCC_ARCHIVE} | cut -d* -f1` != ${GCC_MD5} ]; then
    echo "Archive is broken: $GCC_ARCHIVE"
    exit 1;
fi

if [ ! -f archives/${NEWLIB_ARCHIVE} ]; then
    echo "Downloading ${NEWLIB_ARCHIVE} ..."
    wget -Parchives ftp://sourceware.org/pub/newlib/${NEWLIB_ARCHIVE}
fi

if [ `md5sum -b archives/${NEWLIB_ARCHIVE} | cut -d* -f1` != ${NEWLIB_MD5} ]; then
    echo "Archive is broken: $NEWLIB_ARCHIVE"
    exit 1;
fi

# ------------------------ build binutils ------------------
echo "Building ${BINUTILS_VERSION}"

if [ -d ${BINUTILS_VERSION} ]; then
    echo "Cleaning up previous build ..."
    rm -rf ${BINUTILS_VERSION} 
fi

tar xfj archives/${BINUTILS_ARCHIVE}
cd ${BINUTILS_VERSION}
mkdir arm-none-eabi
cd arm-none-eabi
../configure --target=arm-none-eabi --prefix=/opt/arm-none-eabi
make
sudo make install
cd ../../

# ------------------------ build gcc ------------------
export PATH=/opt/arm-none-eabi/bin:$PATH

echo "Building ${GCC_VERSION}"

if [ -d ${GCC_VERSION} ]; then
    echo "Cleaning up previous build ..."
    rm -rf ${GCC_VERSION} 
fi

tar xfj archives/${GCC_ARCHIVE}

if [ -d ${NEWLIB_VERSION} ]; then
    echo "Cleaning up previous build ..."
    rm -rf ${NEWLIB_VERSION} 
fi

tar xfz archives/${NEWLIB_ARCHIVE}


cd ${GCC_VERSION}
ln -s ../${NEWLIB_VERSION}/newlib .
mkdir arm-none-eabi
cd arm-none-eabi
../configure --target=arm-none-eabi --prefix=/opt/arm-none-eabi --enable-languages=c --with-newlib --enable-newlib-io-long-long
make
sudo make install
cd ../../
