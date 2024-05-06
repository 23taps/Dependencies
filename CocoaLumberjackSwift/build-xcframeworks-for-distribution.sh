#!/usr/bin/env bash
set -e

# Builds and archives universal frameworks (arm64, armv7, x86_64)
# for the KeyboardCore Product
# CocoaLumberjack Frameworks are missing and need to be added by hand

PROJECT="Lumberjack.xcodeproj"
SCHEME="CocoaLumberjackSwift"

# Color codes
NOCOLOR='\033[0m'
GREEN='\033[0;32m'
LIGHTRED='\033[1;31m'
BOLD='\033[1m'
UNDERLINE='\033[4m'

if [ ! -d $PROJECT ]; then
    >&2 echo -e "$LIGHTRED Error: Invalid project path.$NOCOLOR"
    >&2 echo "Use '--project path/to/Project.xcodeproj' and indicate a valid path."
    exit 1
fi

[[ ! -z "$STATIC" ]] && TYPE="staticlib" || TYPE="mh_dylib"

SIMULATOROUTPUT="build/simulator/"
DEVICEOUTPUT="build/devices/"
UNIVERSALOUTPUT="build/universalXCF"

function buildFrameworks() {
    echo "building $SCHEME from workspace $PROJECT with type $TYPE"

    echo "building for simulator"

    # create folder where we place built frameworks
    rm -rf derived_data
    rm -rf build
    mkdir build

    # build framework for simulators
    # Modern Intel based macs only need x86_64.
    #To support Apple Silicon based macs, we'll need to switch to using xcframeworks instead.
    xcodebuild clean build \
      -project "$PROJECT" \
      -scheme "$SCHEME" \
      -configuration Release \
      -sdk iphonesimulator \
      -derivedDataPath derived_data \
      ONLY_ACTIVE_ARCHS=NO \
      ARCHS="x86_64" \
      SKIP_INSTALL=NO \
      ENABLE_TESTABILITY=NO \
      BUILD_LIBRARIES_FOR_DISTRIBUTION=YES \
      MACH_O_TYPE=$TYPE

    # create folder to store compiled framework for simulator
    mkdir build/simulator
    # copy compiled framework for simulator into our build folder
    cp -r derived_data/Build/Products/Release-iphonesimulator/ $SIMULATOROUTPUT

    echo "build moved to $SIMULATOROUTPUT"

    echo "building for devices"

    # build framework for devices
    xcodebuild clean build \
      -project "$PROJECT" \
      -scheme "$SCHEME" \
      -configuration Release \
      -sdk iphoneos \
      -derivedDataPath derived_data \
      ONLY_ACTIVE_ARCHS=NO \
      ARCHS="arm64 armv7" \
      SKIP_INSTALL=NO \
      ENABLE_TESTABILITY=NO \
      BUILD_LIBRARIES_FOR_DISTRIBUTION=YES \
      MACH_O_TYPE=$TYPE

    # create folder to store compiled framework for devices
    mkdir build/devices
    # copy compiled framework for devices into our build folder
    cp -r derived_data/Build/Products/Release-iphoneos/ $DEVICEOUTPUT

    echo "build moved to $DEVICEOUTPUT"
}

buildFrameworks

# create folder to store compiled universal framework
rm -rf $UNIVERSALOUTPUT
mkdir $UNIVERSALOUTPUT

FRAMEWORKPATHS=$SIMULATOROUTPUT*/
for FRAMEWORKPATH in $FRAMEWORKPATHS ; do
    if [ ${FRAMEWORKPATH: -11} == ".framework/" ]; then
        FRAMEWORK="$(basename $FRAMEWORKPATH)"
        FRAMEWORK_NAME="${FRAMEWORK%.*}"

        ####################### Create XC framework #############################
        SIMULATOR_FRAMEWORK=$SIMULATOROUTPUT$FRAMEWORK
        DEVICE_FRAMEWORK=$DEVICEOUTPUT$FRAMEWORK
        UNIVERSAL_FRAMEWORK=$UNIVERSALOUTPUT/$FRAMEWORK_NAME.xcframework

        echo "combining $FRAMEWORK_NAME into XC framework $UNIVERSAL_FRAMEWORK"

        # Create xcframwork combine of all frameworks
        xcodebuild -create-xcframework \
          -framework $SIMULATOR_FRAMEWORK \
          -framework $DEVICE_FRAMEWORK \
          -output $UNIVERSAL_FRAMEWORK

        echo -e "$BOLD*** $FRAMEWORK_NAME XC framework was successfully built ***:"
    fi
done

# cleanup
rm -rf derived_data
