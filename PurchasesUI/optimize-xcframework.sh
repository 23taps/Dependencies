#!/bin/bash

set -e  # Exit on error

# Check if version parameter is provided
if [ -z "$1" ]; then
    echo "Usage: $0 <version>"
    echo "Example: $0 5.72.0"
    exit 1
fi

VERSION="$1"
FRAMEWORK_NAME="RevenueCatUI"
ZIP_FILE="${FRAMEWORK_NAME}.xcframework.zip"
VERSION_PREFIX="PurchasesUI"
VERSION_FOLDER=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(pwd)"

# Determine the folder name (assuming format: PurchasesUI-{version})
for folder in ${VERSION_PREFIX}-${VERSION}*; do
    if [ -d "$folder" ]; then
        VERSION_FOLDER="$folder"
        break
    fi
done

if [ -z "$VERSION_FOLDER" ]; then
    echo "Error: Could not find folder matching ${VERSION_PREFIX}-${VERSION}"
    exit 1
fi

echo "Processing version $VERSION in folder: $VERSION_FOLDER"

# Navigate to version folder
cd "$VERSION_FOLDER"

# Check if zip file exists
if [ ! -f "$ZIP_FILE" ]; then
    echo "Error: $ZIP_FILE not found in $VERSION_FOLDER"
    exit 1
fi

# Rename original zip
ORIGINAL_ZIP="${ZIP_FILE%.zip}_original.zip"
if [ -f "$ORIGINAL_ZIP" ]; then
    echo "Warning: $ORIGINAL_ZIP already exists, skipping rename"
else
    mv "$ZIP_FILE" "$ORIGINAL_ZIP"
    echo "Renamed $ZIP_FILE to $ORIGINAL_ZIP"
fi

# Extract the zip
echo "Extracting $ORIGINAL_ZIP..."
unzip -q "$ORIGINAL_ZIP" -d .

# Find the xcframework (it might be directly extracted or in RevenueCatUI/ subfolder)
XCFRAMEWORK_PATH=""
if [ -d "${FRAMEWORK_NAME}.xcframework" ]; then
    XCFRAMEWORK_PATH="${FRAMEWORK_NAME}.xcframework"
elif [ -d "${FRAMEWORK_NAME}/${FRAMEWORK_NAME}.xcframework" ]; then
    XCFRAMEWORK_PATH="${FRAMEWORK_NAME}/${FRAMEWORK_NAME}.xcframework"
else
    echo "Error: Could not find ${FRAMEWORK_NAME}.xcframework after extraction"
    exit 1
fi

echo "Found xcframework at: $XCFRAMEWORK_PATH"

# Define slices to keep
KEEP_SLICES=("ios-arm64" "ios-arm64_x86_64-simulator")

# Remove unwanted platform slices
# Preserve _CodeSignature and Info.plist at the root of xcframework
PRESERVE_FOLDERS=("_CodeSignature")
echo "Removing unwanted platform slices..."
for slice_dir in "$XCFRAMEWORK_PATH"/*; do
    if [ -d "$slice_dir" ]; then
        slice_name=$(basename "$slice_dir")

        preserve_folder=false
        for preserve in "${PRESERVE_FOLDERS[@]}"; do
            if [ "$slice_name" == "$preserve" ]; then
                preserve_folder=true
                break
            fi
        done

        if [ "$preserve_folder" == true ]; then
            echo "  Preserving folder: $slice_name"
            continue
        fi

        keep_slice=false
        for keep in "${KEEP_SLICES[@]}"; do
            if [ "$slice_name" == "$keep" ]; then
                keep_slice=true
                break
            fi
        done

        if [ "$keep_slice" == false ]; then
            echo "  Removing slice: $slice_name"
            rm -rf "$slice_dir"
        else
            echo "  Keeping slice: $slice_name"
        fi
    fi
done

# Remove archives folder if it exists
if [ -d "${FRAMEWORK_NAME}/archives" ]; then
    echo "Removing archives folder..."
    rm -rf "${FRAMEWORK_NAME}/archives"
fi

# Remove root-level dSYMs folder if it exists
if [ -d "${FRAMEWORK_NAME}/${FRAMEWORK_NAME}.dSYMs" ]; then
    echo "Removing root-level ${FRAMEWORK_NAME}.dSYMs folder..."
    rm -rf "${FRAMEWORK_NAME}/${FRAMEWORK_NAME}.dSYMs"
fi

# Update Info.plist to only include kept slices
INFO_PLIST="$XCFRAMEWORK_PATH/Info.plist"
if [ ! -f "$INFO_PLIST" ]; then
    echo "Error: Info.plist not found at $INFO_PLIST"
    exit 1
fi

echo "Updating Info.plist to keep only iOS slices..."
KEEP_SLICES_STR=$(IFS=','; echo "${KEEP_SLICES[*]}")

python3 - "$INFO_PLIST" "$KEEP_SLICES_STR" << 'PYTHON_SCRIPT'
import plistlib
import sys

info_plist_path = sys.argv[1]
keep_slices = sys.argv[2].split(',')

with open(info_plist_path, 'rb') as f:
    plist = plistlib.load(f)

if 'AvailableLibraries' in plist:
    original_libraries = plist['AvailableLibraries']
    filtered_libraries = []

    for library in original_libraries:
        library_id = library.get('LibraryIdentifier', '')
        if library_id in keep_slices:
            filtered_libraries.append(library)
            print(f"  Keeping library: {library_id}")
        else:
            print(f"  Removing library: {library_id}")

    plist['AvailableLibraries'] = filtered_libraries

with open(info_plist_path, 'wb') as f:
    plistlib.dump(plist, f)

print(f"Updated Info.plist: kept {len(filtered_libraries)} out of {len(original_libraries)} libraries")
PYTHON_SCRIPT

# Remove old code signature since we modified Info.plist
echo "Removing old code signature..."
if [ -d "$XCFRAMEWORK_PATH/_CodeSignature" ]; then
    rm -rf "$XCFRAMEWORK_PATH/_CodeSignature"
    echo "  Removed _CodeSignature folder"
fi

# Re-sign the xcframework with an ad-hoc signature
echo "Re-signing xcframework..."
for slice_dir in "$XCFRAMEWORK_PATH"/*; do
    if [ -d "$slice_dir" ]; then
        slice_name=$(basename "$slice_dir")

        if [ "$slice_name" == "_CodeSignature" ] || [ "$slice_name" == "Info.plist" ]; then
            continue
        fi

        framework_path=""
        if [ -d "$slice_dir/${FRAMEWORK_NAME}.framework" ]; then
            framework_path="$slice_dir/${FRAMEWORK_NAME}.framework"
        fi

        if [ -n "$framework_path" ] && [ -d "$framework_path" ]; then
            echo "  Signing framework in slice: $slice_name"

            if [ -d "$framework_path/_CodeSignature" ]; then
                rm -rf "$framework_path/_CodeSignature"
            fi

            codesign --force --sign - --timestamp=none "$framework_path" 2>/dev/null || true
        fi
    fi
done

echo "Signing xcframework root..."
codesign --force --sign - --timestamp=none "$XCFRAMEWORK_PATH" 2>/dev/null || true
echo "  Re-signing complete"

# Create optimized zip
OPTIMIZED_ZIP="${ZIP_FILE%.zip}_optimized.zip"
echo "Creating optimized zip file..."

if [ -f "$OPTIMIZED_ZIP" ]; then
    rm "$OPTIMIZED_ZIP"
fi

XCFRAMEWORK_DIR=$(basename "$XCFRAMEWORK_PATH")
XCFRAMEWORK_PARENT=$(dirname "$XCFRAMEWORK_PATH")

if [ "$XCFRAMEWORK_PARENT" == "." ]; then
    zip -q -r "$OPTIMIZED_ZIP" "$XCFRAMEWORK_DIR"
else
    pushd "$XCFRAMEWORK_PARENT" > /dev/null
    zip -q -r "../$OPTIMIZED_ZIP" "$XCFRAMEWORK_DIR"
    popd > /dev/null
fi

if [ ! -f "$OPTIMIZED_ZIP" ]; then
    echo "Error: Failed to create optimized zip file"
    exit 1
fi

echo "Created optimized $OPTIMIZED_ZIP"

# Update PurchasesUI.json
JSON_FILE="$BASE_DIR/PurchasesUI.json"
if [ ! -f "$JSON_FILE" ]; then
    echo "Warning: PurchasesUI.json not found at $JSON_FILE"
else
    echo "Updating PurchasesUI.json..."
    python3 - "$JSON_FILE" "$VERSION" "$VERSION_FOLDER" << 'PYTHON_JSON'
import json
import sys

json_file = sys.argv[1]
version = sys.argv[2]
base_url = "https://github.com/23taps/Dependencies/raw/master/PurchasesUI/{}/RevenueCatUI.xcframework.zip"
version_folder = sys.argv[3]

with open(json_file, 'r') as f:
    data = json.load(f)

if version in data:
    print(f"  Version {version} already exists in PurchasesUI.json")
else:
    url = base_url.format(version_folder)
    data[version] = url

    sorted_data = {}
    for key in sorted(data.keys(), key=lambda x: [int(i) for i in x.split('.')]):
        sorted_data[key] = data[key]

    with open(json_file, 'w') as f:
        json.dump(sorted_data, f, indent=4)
        f.write('\n')

    print(f"  Added version {version} to PurchasesUI.json")
PYTHON_JSON
fi

echo "Finalizing..."
if [ -f "$ORIGINAL_ZIP" ]; then
    rm "$ORIGINAL_ZIP"
    echo "  Removed original zip: $ORIGINAL_ZIP"
fi

if [ -f "$OPTIMIZED_ZIP" ]; then
    mv "$OPTIMIZED_ZIP" "$ZIP_FILE"
    echo "  Renamed $OPTIMIZED_ZIP to $ZIP_FILE"
fi

echo "Cleaning up extracted files..."
if [ -d "$FRAMEWORK_NAME" ]; then
    rm -rf "$FRAMEWORK_NAME"
    echo "  Removed ${FRAMEWORK_NAME}/ folder"
fi

if [ -d "${FRAMEWORK_NAME}.xcframework" ]; then
    rm -rf "${FRAMEWORK_NAME}.xcframework"
    echo "  Removed ${FRAMEWORK_NAME}.xcframework/ folder"
fi

if [ -d "__MACOSX" ]; then
    rm -rf "__MACOSX"
    echo "  Removed __MACOSX/ folder"
fi

echo ""
echo "✓ Optimization complete!"
echo "  Final zip: $ZIP_FILE"
echo "  Kept slices: ${KEEP_SLICES[*]}"
