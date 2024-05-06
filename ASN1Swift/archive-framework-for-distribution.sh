#!/bin/bash

set -x
set -e

NAME="ASN1Swift"
# Pass scheme name as the first argument to the script
#NAME=$1

BUILDFOLDER="build"

rm -rf $BUILDFOLDER
mkdir -p $BUILDFOLDER

DEVICE="Release-iphoneos"
SIM="Release-iphonesimulator"
UNI="uinversal"

# Build the scheme for all platforms that we plan to support
for PLATFORM in "iOS" "iOS Simulator"; do

    case $PLATFORM in
    "iOS")
    RELEASE_FOLDER=$DEVICE
    ARCHS="arm64 armv7"
    ;;
    "iOS Simulator")
    RELEASE_FOLDER=$SIM
    ARCHS="x86_64"
    ;;
    esac

    ARCHIVE_PATH="$BUILDFOLDER/$RELEASE_FOLDER"

    # Rewrite Package.swift so that it declaras dynamic libraries, since the approach does not work with static libraries
    perl -i -p0e 's/type: .static,//g' Package.swift
    perl -i -p0e 's/type: .dynamic,//g' Package.swift
    perl -i -p0e 's/(library[^,]*,)/$1 type: .dynamic,/g' Package.swift

    xcodebuild archive -workspace . -scheme $NAME \
            -destination "generic/platform=$PLATFORM" \
            -archivePath $ARCHIVE_PATH \
            -derivedDataPath ".build" \
            PRODUCT_BUNDLE_IDENTIFIER="com.emoji.$NAME" \
            ARCHS="$ARCHS" \
            SKIP_INSTALL=NO \
            BUILD_LIBRARY_FOR_DISTRIBUTION=YES

    FRAMEWORK_PATH="$ARCHIVE_PATH.xcarchive/Products/usr/local/lib/$NAME.framework"
    MODULES_PATH="$FRAMEWORK_PATH/Modules"
    mkdir -p $MODULES_PATH

    BUILD_PRODUCTS_PATH=".build/Build/Intermediates.noindex/ArchiveIntermediates/$NAME/BuildProductsPath"
    RELEASE_PATH="$BUILD_PRODUCTS_PATH/$RELEASE_FOLDER"
    SWIFT_MODULE_PATH="$RELEASE_PATH/$NAME.swiftmodule"
    RESOURCES_BUNDLE_PATH="$RELEASE_PATH/${NAME}_${NAME}.bundle"

    # Copy Swift modules
    if [ -d $SWIFT_MODULE_PATH ]
    then
        cp -r $SWIFT_MODULE_PATH $MODULES_PATH
    else
        # In case there are no modules, assume C/ObjC library and create module map
        echo "module $NAME { export * }" > $MODULES_PATH/module.modulemap
        # TODO: Copy headers
    fi

    # Copy resources bundle, if exists
    if [ -e $RESOURCES_BUNDLE_PATH ]
    then
        cp -r $RESOURCES_BUNDLE_PATH $FRAMEWORK_PATH
    fi

done

####################### Create universal framework #############################
FRAMEWORK_SUBPATH="Products/usr/local/lib"
DEVICE_FRAMEWORK="$BUILDFOLDER/$DEVICE.xcarchive/$FRAMEWORK_SUBPATH/$NAME.framework"
SIMULATOR_FRAMEWORK="$BUILDFOLDER/$SIM.xcarchive/$FRAMEWORK_SUBPATH/$NAME.framework"
UINVERSAL_FRAMEWORK="$BUILDFOLDER/$UNI/$NAME.framework"

mkdir -p $BUILDFOLDER/$UNI

# copy devices framework into universal folder
cp -r $DEVICE_FRAMEWORK $UINVERSAL_FRAMEWORK

# create framework binary compatible with simulators and devices, and replace binary in unviersal framework
lipo -create "$SIMULATOR_FRAMEWORK/$NAME" "$DEVICE_FRAMEWORK/$NAME" \
  -output "$UINVERSAL_FRAMEWORK/$NAME"

# copy simulator Swift public interface to universal framework
if [ -d $SIMULATOR_FRAMEWORK/Modules/$NAME.swiftmodule ]; then
    cp -r $SIMULATOR_FRAMEWORK/Modules/$NAME.swiftmodule/* $UINVERSAL_FRAMEWORK/Modules/$NAME.swiftmodule
fi

## cleanup
#rm -rf derived_data

# zip up the universal framework
(cd $BUILDFOLDER/$UNI && zip -r -X ../$NAME.framework.zip $NAME.framework)


echo -e "$BOLD*** Universal framework was successfully built ***:"
echo -e "$UNDERLINE./build/$NAME.framework.zip$NOCOLOR"
