#!/bin/bash

set -e -o pipefail -u

: ${BUILD_ARCH_OR_TYPE:=host}
: ${DEFAULT_ANDROID_API_LEVEL:=21}
: ${ANDROID_NDK:=~/lib/android-ndk-r26b}
: ${FLANG_MAKE_PROCESSES:=1}

patch -p1 -d $(pwd)/out/llvm-project < flang-undef-macros.patch

ANDROID_TRIPLE="$BUILD_ARCH_OR_TYPE-linux-android"
CC_HOST_PLATFORM=$BUILD_ARCH_OR_TYPE-linux-android$DEFAULT_ANDROID_API_LEVEL
if [ $BUILD_ARCH_OR_TYPE = arm ]; then
	ANDROID_TRIPLE="armv7a-linux-androideabi"
	CC_HOST_PLATFORM=armv7a-linux-androideabi$DEFAULT_ANDROID_API_LEVEL
elif [ $BUILD_ARCH_OR_TYPE = host ]; then
	CC_HOST_PLATFORM=x86_64-linux-gnu
fi

# Build tablegen
mkdir -p build-tblgen
pushd build-tblgen
cmake -G Ninja "-DCMAKE_BUILD_TYPE=Release" \
				"-DLLVM_ENABLE_PROJECTS=clang;mlir" \
				$(pwd)/../out/llvm-project/llvm
ninja -j $(nproc) clang-tblgen mlir-tblgen
export PATH="$(pwd)/bin:$PATH"
popd # build-tblgen

# See http://llvm.org/docs/CMake.html:
_EXTRA_CONFIGURE_ARGS="
-DCMAKE_BUILD_TYPE=MinSizeRel
-DLLVM_ENABLE_PIC=ON
-DLLVM_LINK_LLVM_DYLIB=ON
-DLLVM_TARGETS_TO_BUILD=all
-DLLVM_ENABLE_FFI=ON
-DFLANG_DEFAULT_LINKER=lld
-DMLIR_INSTALL_AGGREGATE_OBJECTS=OFF
-DFLANG_ENABLE_WERROR=On
-DFLANG_INCLUDE_TESTS=OFF
-DLLVM_ENABLE_ASSERTIONS=On
-DLLVM_LIT_ARGS=-v
-DLLVM_DIR=$(pwd)/out/stage2-install/lib/cmake/llvm
-DCLANG_DIR=$(pwd)/out/stage2-install/lib/cmake/clang
-DClang_DIR=$(pwd)/out/stage2-install/lib/cmake/clang
-DMLIR_DIR=$(pwd)/out/stage2-install/lib/cmake/mlir
-DCLANG_TABLEGEN=$(pwd)/build-tblgen/bin/clang-tblgen
-DMLIR_TABLEGEN_EXE=$(pwd)/build-tblgen/bin/mlir-tblgen
-DLLVM_HOST_TRIPLE=${CC_HOST_PLATFORM/-/-unknown-}
"

_HOST_RPATH='$ORIGIN:$ORIGIN/../lib/x86_64-unknown-linux-gnu:$ORIGIN/../lib'

_CONFIGURE_ARGS=()
_CONFIGURE_ARGS+=("-DCMAKE_C_COMPILER=$(pwd)/out/stage2-install/bin/clang")
_CONFIGURE_ARGS+=("-DCMAKE_CXX_COMPILER=$(pwd)/out/stage2-install/bin/clang++")
_CONFIGURE_ARGS+=("-DCMAKE_LINKER=$(pwd)/out/stage2-install/bin/ld.lld")
_CONFIGURE_ARGS+=("-DCMAKE_CXX_FLAGS=-stdlib=libc++ -Wl,-rpath=$_HOST_RPATH")
_CONFIGURE_ARGS+=("-DCMAKE_EXE_LINKER_FLAGS=-stdlib=libc++ -Wl,-rpath=$_HOST_RPATH")
_CONFIGURE_ARGS+=("-DCMAKE_INSTALL_RPATH=$_HOST_RPATH")

_BUILD_TARGET=""
if [ "$BUILD_ARCH_OR_TYPE" != "host" ]; then
	# TODO: Use the newly built toolchain
	export NDK_STANDALONE_TOOLCHAIN_DIR="$ANDROID_NDK/toolchains/llvm/prebuilt/linux-x86_64"
	CMAKE_PROC=$BUILD_ARCH_OR_TYPE
	test $CMAKE_PROC == "arm" && CMAKE_PROC='armv7-a'
	_CONFIGURE_ARGS=("-DCMAKE_SYSTEM_NAME=Android")
	_CONFIGURE_ARGS+=("-DCMAKE_SYSTEM_PROCESSOR=$CMAKE_PROC")
	_CONFIGURE_ARGS+=("-DCMAKE_SYSTEM_VERSION=$DEFAULT_ANDROID_API_LEVEL")
	_CONFIGURE_ARGS+=("-DCMAKE_ANDROID_NDK=$ANDROID_NDK")
	_CONFIGURE_ARGS+=("-DCMAKE_SKIP_INSTALL_RPATH=ON")
	echo "" > $NDK_STANDALONE_TOOLCHAIN_DIR/sysroot/usr/include/zstd.h
	echo "!<arch>" > $NDK_STANDALONE_TOOLCHAIN_DIR/sysroot/usr/lib/$ANDROID_TRIPLE/libzstd.a
	_BUILD_TARGET="Fortran_main FortranRuntime FortranDecimal"
else
	export LD_LIBRARY_PATH="$(pwd)/out/stage2-install/lib:${LD_LIBRARY_PATH:-}"
fi

mkdir -p build-$BUILD_ARCH_OR_TYPE-install

mkdir -p build-$BUILD_ARCH_OR_TYPE
pushd build-$BUILD_ARCH_OR_TYPE
cmake -G Ninja "${_CONFIGURE_ARGS[@]}" \
				-DCMAKE_INSTALL_PREFIX=$(pwd)/../build-$BUILD_ARCH_OR_TYPE-install \
				-DDOXYGEN_EXECUTABLE= \
				-DBUILD_TESTING=OFF \
				$_EXTRA_CONFIGURE_ARGS \
				$(pwd)/../out/llvm-project/flang
ninja -j $FLANG_MAKE_PROCESSES $_BUILD_TARGET
if [ "$BUILD_ARCH_OR_TYPE" == "host" ]; then
	ninja -j $FLANG_MAKE_PROCESSES install
else
	cp lib/lib*.a $(pwd)/../build-$BUILD_ARCH_OR_TYPE-install/
fi
popd # build-$BUILD_ARCH_OR_TYPE

mkdir -p ./output-flang
tar -cjf ./output-flang/package-flang-$BUILD_ARCH_OR_TYPE.tar.bz2 build-$BUILD_ARCH_OR_TYPE-install
