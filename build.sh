#!/bin/bash

set -e -o pipefail -u

mkdir -p ~/bin
export PATH=~/bin:$PATH
curl https://storage.googleapis.com/git-repo-downloads/repo > ~/bin/repo
chmod a+x ~/bin/repo
git config --global user.name "Your Name"
git config --global user.email "you@example.com"
git config --global color.ui false
mkdir -p llvm-toolchain && cd llvm-toolchain
repo init -u https://android.googlesource.com/platform/manifest
# Modified the manifest xml, to ensure not contain darwin prebuilt
# XXX: Windows prebuilt?
sed -E 's/(^.*?(darwin).*$)/<!-- \1 -->/g' ../manifest_10552028.xml > .repo/manifests/test.xml
repo init -m test.xml
repo sync -c

# Add patch for flang
jq --argjson a "$(cat toolchain/llvm_android/patches/PATCHES.json)" \
    --argjson b "$(cat ../additional-patch.json)" -n '$a + $b' \
    > toolchain/llvm_android/patches/PATCHES.json
cp ../flang-undef-macros.patch toolchain/llvm_android/patches/
cp ../D142965.patch toolchain/llvm_android/patches/

patch -p1 < ../Build-flang.patch

# Build again
pushd toolchain/llvm_android
python build.py --no-build lldb,windows --no-musl --single-stage --skip-tests
popd

tar -cjf package-install.tar.bz2 out/install
tar -cjf package-llvm-project.tar.bz2 out/llvm-project
tar -cjf package-stage2-install.tar.bz2 out/stage2-install

mkdir -p ../output
mv *.tar.bz2 ../output/
