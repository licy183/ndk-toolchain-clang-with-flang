#!/bin/bash

set -e -o pipefail -u

# Fetch source
mkdir -p ~/bin
export PATH=~/bin:$PATH
curl https://storage.googleapis.com/git-repo-downloads/repo > ~/bin/repo
chmod a+x ~/bin/repo
git config --global user.name "Your Name"
git config --global user.email "you@example.com"
git config --global color.ui false
mkdir -p llvm-toolchain && cd llvm-toolchain
repo init -u https://android.googlesource.com/platform/manifest
# Modified the manifest xml, to ensure only contain linux component
sed -E 's/(^.*?(darwin|mingw|windows).*$)/<!-- \1 -->/g' ../manifest_12027248.xml > .repo/manifests/test.xml
repo init -m test.xml
repo sync -c

# Remove duplicated repo cache
# rm -rf .repo

# Remove older version prebuilts
rm -rf $(find prebuilts/clang/host/linux-x86/clang* -maxdepth 0 | grep -v "clang-r522817" | grep -v "clang-stable")

# Patch to build mlir
patch -p1 < ../build-mlir.patch

# Build
pushd toolchain/llvm_android
python build.py --no-build lldb,windows --no-musl --bootstrap-use-prebuilt --skip-tests --skip-runtimes
popd

tar -cjf package-install.tar.bz2 out/install
tar -cjf package-llvm-project.tar.bz2 out/llvm-project
tar -cjf package-stage2-install.tar.bz2 out/stage2-install

mkdir -p ../output
mv *.tar.bz2 ../output/
