#!/bin/bash

set -e

OPTIND=1

# Config

# For default registry and number of cores.
if [ ! -e config.sh ]; then
  echo "No config.sh, copying default values from config.sh.in."
  cp config.sh.in config.sh
fi
source ./config.sh

if [ -z "${BUILD_NAME}" ]; then
  export BUILD_NAME="custom_build"
fi

if [ -z "${NUM_CORES}" ]; then
  export NUM_CORES=16
fi

if [ -z "${GODOT_REPO}" ]; then
  export GODOT_REPO="https://github.com/godotengine/godot.git"
fi

platform=""
registry="${REGISTRY}"
arch=""
username=""
password=""
godot_version=""
git_treeish="master"
build_classical=1
build_mono=1
build_steam=0
force_download=0
skip_download=1
skip_git_checkout=0

while getopts "h?r:u:p:v:g:b:o:a:fsc" opt; do
  case "$opt" in
  h|\?)
    echo "Usage: $0 [OPTIONS...]"
    echo
    echo "  -r registry"
    echo "  -u username"
    echo "  -p password"
    echo "  -v godot version (e.g. 3.1-alpha5) [mandatory]"
    echo "  -g git treeish (e.g. master)"
    echo "  -b all|classical|mono (default: all)"
    echo "  -f force redownload of all images"
    echo "  -s skip downloading"
    echo "  -c skip checkout"
    echo "  -o platform"
    echo "  -a arch"
    echo
    exit 1
    ;;
  r)
    registry=$OPTARG
    ;;
  u)
    username=$OPTARG
    ;;
  p)
    password=$OPTARG
    ;;
  v)
    godot_version=$OPTARG
    ;;
  g)
    git_treeish=$OPTARG
    ;;
  b)
    if [ "$OPTARG" == "classical" ]; then
      build_mono=0
    elif [ "$OPTARG" == "mono" ]; then
      build_classical=0
    fi
    ;;
  o)
    platform=$OPTARG
    ;;
  a)
    arch=$OPTARG
    ;;
  f)
    force_download=1
    ;;
  s)
    skip_download=1
    ;;
  c)
    skip_git_checkout=1
    ;;
  esac
done

export podman=${PODMAN}

if [ -z "${godot_version}" ]; then
  echo "-v <version> is mandatory!"
  exit 1
fi

IFS=- read version status <<< "$godot_version"
echo "Building Godot ${version} ${status} from commit or branch ${git_treeish}."
#read -p "Is this correct (y/n)? " choice
#case "$choice" in
#  y|Y ) echo "yes";;
#  n|N ) echo "No, aborting."; exit 0;;
#  * ) echo "Invalid choice, aborting."; exit 1;;
#esac
export GODOT_VERSION_STATUS="${status}"

if [ "${status}" == "stable" ]; then
  build_steam=1
fi

if [ ! -z "${username}" ] && [ ! -z "${password}" ]; then
  if ${podman} login ${registry} -u "${username}" -p "${password}"; then
    export logged_in=true
  fi
fi

if [ $skip_download == 0 ]; then
  echo "Fetching images"
  for image in windows linux web; do
    if [ ${force_download} == 1 ] || ! ${podman} image exists godot/$image; then
      if ! ${podman} pull ${registry}/godot/${image}; then
        echo "ERROR: image $image does not exist and can't be downloaded"
        exit 1
      fi
    fi
  done

  if [ ! -z "${logged_in}" ]; then
    echo "Fetching private images"

    for image in macosx android ios; do
      if [ ${force_download} == 1 ] || ! ${podman} image exists godot-private/$image; then
        if ! ${podman} pull ${registry}/godot-private/${image}; then
          echo "ERROR: image $image does not exist and can't be downloaded"
          exit 1
        fi
      fi
    done
  fi
fi

# macOS needs MoltenVK
if [ ! -d "deps/moltenvk" ]; then
  echo "Missing MoltenVK for macOS, downloading it."
  mkdir -p deps/moltenvk
  pushd deps/moltenvk
  curl -L -o moltenvk.tar https://github.com/godotengine/moltenvk-osxcross/releases/download/vulkan-sdk-1.3.283.0-2/MoltenVK-all.tar
  tar xf moltenvk.tar && rm -f moltenvk.tar
  mv MoltenVK/MoltenVK/include/ MoltenVK/
  mv MoltenVK/MoltenVK/static/MoltenVK.xcframework/ MoltenVK/
  popd
fi

# Windows and macOS need ANGLE
if [ ! -d "deps/angle" ]; then
  echo "Missing ANGLE libraries, downloading them."
  mkdir -p deps/angle
  pushd deps/angle
  base_url=https://github.com/godotengine/godot-angle-static/releases/download/chromium%2F6601.2/godot-angle-static
  curl -L -o windows_arm64.zip $base_url-arm64-llvm-release.zip
  curl -L -o windows_x86_64.zip $base_url-x86_64-gcc-release.zip
  curl -L -o windows_x86_32.zip $base_url-x86_32-gcc-release.zip
  curl -L -o macos_arm64.zip $base_url-arm64-macos-release.zip
  curl -L -o macos_x86_64.zip $base_url-x86_64-macos-release.zip
  unzip -o windows_arm64.zip && rm -f windows_arm64.zip
  unzip -o windows_x86_64.zip && rm -f windows_x86_64.zip
  unzip -o windows_x86_32.zip && rm -f windows_x86_32.zip
  unzip -o macos_arm64.zip && rm -f macos_arm64.zip
  unzip -o macos_x86_64.zip && rm -f macos_x86_64.zip
  popd
fi

if [ ! -d "deps/mesa" ]; then
  echo "Missing Mesa/NIR libraries, downloading them."
  mkdir -p deps/mesa
  pushd deps/mesa
  curl -L -o mesa_arm64.zip https://github.com/godotengine/godot-nir-static/releases/download/23.1.9-1/godot-nir-static-arm64-llvm-release.zip
  curl -L -o mesa_x86_64.zip https://github.com/godotengine/godot-nir-static/releases/download/23.1.9-1/godot-nir-static-x86_64-gcc-release.zip
  curl -L -o mesa_x86_32.zip https://github.com/godotengine/godot-nir-static/releases/download/23.1.9-1/godot-nir-static-x86_32-gcc-release.zip
  unzip -o mesa_arm64.zip && rm -f mesa_arm64.zip
  unzip -o mesa_x86_64.zip && rm -f mesa_x86_64.zip
  unzip -o mesa_x86_32.zip && rm -f mesa_x86_32.zip
  popd
fi

if [ ! -d "deps/swappy" ]; then
  echo "Missing Swappy libraries, downloading them."
  mkdir -p deps/swappy
  pushd deps/swappy
  curl -L -O https://github.com/darksylinc/godot-swappy/releases/download/v2023.3.0.0/godot-swappy.7z
  7z x godot-swappy.7z && rm godot-swappy.7z
  popd
fi

# Keystore for Android editor signing
# Optional - the config.sh will be copied but if it's not filled in,
# it will do an unsigned build.
if [ ! -d "deps/keystore" ]; then
  mkdir -p deps/keystore
  cp config.sh deps/keystore/
  if [ ! -z "$GODOT_ANDROID_SIGN_KEYSTORE" ]; then
    cp "$GODOT_ANDROID_SIGN_KEYSTORE" deps/keystore/
    sed -i deps/keystore/config.sh -e "s@$GODOT_ANDROID_SIGN_KEYSTORE@/root/keystore/$GODOT_ANDROID_SIGN_KEYSTORE@"
  fi
fi

if [ "${skip_git_checkout}" == 0 ]; then
  git clone ${GODOT_REPO} git || /bin/true
  pushd git
  git checkout -b ${git_treeish} origin/${git_treeish} || git checkout ${git_treeish}
  git reset --hard
  git clean -fdx
  git pull origin ${git_treeish} || /bin/true

  # Validate version
  correct_version=$(python3 << EOF
import version;
if hasattr(version, "patch") and version.patch != 0:
  git_version = f"{version.major}.{version.minor}.{version.patch}"
else:
  git_version = f"{version.major}.{version.minor}"
print(git_version == "${version}")
EOF
  )
  if [[ "$correct_version" != "True" ]]; then
    echo "Version in version.py doesn't match the passed ${version}."
    exit 1
  fi

  sh misc/scripts/make_tarball.sh -v ${godot_version} -g ${git_treeish}
  popd
fi

export basedir="$(pwd)"
mkdir -p ${basedir}/out
mkdir -p ${basedir}/out/logs
mkdir -p ${basedir}/mono-glue

export podman_run="${podman} run -i --rm --env ARCH=${arch} --env BUILD_NAME=${BUILD_NAME} --env GODOT_VERSION_STATUS=${GODOT_VERSION_STATUS} --env NUM_CORES=${NUM_CORES} --env CLASSICAL=${build_classical} --env MONO=${build_mono} -v ${basedir}/godot-${godot_version}.tar.gz:/root/godot.tar.gz -v ${basedir}/mono-glue:/root/mono-glue -w /root/"
export img_version=$IMAGE_VERSION

if [ "${platform}" == "mono" ]; then
${podman} pull ${registry}/godot-linux:${img_version}
mkdir -p ${basedir}/mono-glue
${podman_run} -v ${basedir}/build-mono-glue:/root/build ${registry}/godot-linux:${img_version} bash build/build.sh 2>&1 | tee ${basedir}/out/logs/mono-glue
fi

if [ "${platform}" == "windows" ]; then
${podman} pull ${registry}/godot-windows:${img_version}
mkdir -p ${basedir}/out/windows
${podman_run} -v ${basedir}/build-windows:/root/build -v ${basedir}/out/windows:/root/out -v ${basedir}/deps/angle:/root/angle -v ${basedir}/deps/mesa:/root/mesa --env STEAM=${build_steam} ${registry}/godot-windows:${img_version} bash build/build.sh 2>&1 | tee ${basedir}/out/logs/windows
fi

if [ "${platform}" == "linux" ]; then
${podman} pull ${registry}/godot-linux:${img_version}
mkdir -p ${basedir}/out/linux
${podman_run} -v ${basedir}/build-linux:/root/build -v ${basedir}/out/linux:/root/out ${registry}/godot-linux:${img_version} bash build/build.sh 2>&1 | tee ${basedir}/out/logs/linux
fi

if [ "${platform}" == "web" ]; then
${podman} pull ${registry}/godot-web:${img_version}
mkdir -p ${basedir}/out/web
${podman_run} -v ${basedir}/build-web:/root/build -v ${basedir}/out/web:/root/out ${registry}/godot-web:${img_version} bash build/build.sh 2>&1 | tee ${basedir}/out/logs/web
fi

if [ "${platform}" == "macos" ]; then
${podman} pull ${registry}/godot-macos:${img_version}
mkdir -p ${basedir}/out/macos
${podman_run} -v ${basedir}/build-macos:/root/build -v ${basedir}/out/macos:/root/out -v ${basedir}/deps/moltenvk:/root/moltenvk -v ${basedir}/deps/angle:/root/angle ${registry}/godot-osx:${img_version} bash build/build.sh 2>&1 | tee ${basedir}/out/logs/macos
fi

if [ "${platform}" == "android" ]; then
${podman} pull ${registry}/godot-android:${img_version}
mkdir -p ${basedir}/out/android
${podman_run} -v ${basedir}/build-android:/root/build -v ${basedir}/out/android:/root/out -v ${basedir}/deps/swappy:/root/swappy -v ${basedir}/deps/keystore:/root/keystore ${registry}/godot-android:${img_version} bash build/build.sh 2>&1 | tee ${basedir}/out/logs/android
fi

if [ "${platform}" == "ios" ]; then
${podman} pull ${registry}/godot-ios:${img_version}
mkdir -p ${basedir}/out/ios
${podman_run} -v ${basedir}/build-ios:/root/build -v ${basedir}/out/ios:/root/out ${registry}/godot-ios:${img_version} bash build/build.sh 2>&1 | tee ${basedir}/out/logs/ios
fi

uid=$(id -un)
gid=$(id -gn)
if [ ! -z "$SUDO_UID" ]; then
  uid="${SUDO_UID}"
  gid="${SUDO_GID}"
fi
#chown -R -f $uid:$gid ${basedir}/git ${basedir}/out ${basedir}/mono-glue ${basedir}/godot*.tar.gz
