#!/bin/bash

set -e  # Exit on error

# Check if version parameter is provided
if [ -z "$1" ]; then
    echo "Usage: $0 <version>"
    echo "Example: $0 5.52.1"
    exit 1
fi

VERSION="$1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(pwd)"

# Determine the folder name (assuming format: Purchases-{version})
# Try to find the folder dynamically
VERSION_FOLDER=""
for folder in Purchases-${VERSION}*; do
    if [ -d "$folder" ]; then
        VERSION_FOLDER="$folder"
        break
    fi
done

if [ -z "$VERSION_FOLDER" ]; then
    echo "Error: Could not find folder matching Purchases-${VERSION}"
    exit 1
fi

echo "Processing version $VERSION in folder: $VERSION_FOLDER"

# Navigate to version folder
cd "$VERSION_FOLDER"

# Check if zip file exists
ZIP_FILE="RevenueCat.xcframework.zip"
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

# Extract the zip (creates RevenueCat/ folder)
echo "Extracting $ORIGINAL_ZIP..."
unzip -q "$ORIGINAL_ZIP" -d .

# Find the xcframework (it might be directly extracted or in RevenueCat/ subfolder)
XCFRAMEWORK_PATH=""
if [ -d "RevenueCat.xcframework" ]; then
    XCFRAMEWORK_PATH="RevenueCat.xcframework"
elif [ -d "RevenueCat/RevenueCat.xcframework" ]; then
    XCFRAMEWORK_PATH="RevenueCat/RevenueCat.xcframework"
else
    echo "Error: Could not find RevenueCat.xcframework after extraction"
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
        
        # Skip folders that should be preserved (like _CodeSignature)
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
        
        # Check if this is a slice we want to keep
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
if [ -d "RevenueCat/archives" ]; then
    echo "Removing archives folder..."
    rm -rf "RevenueCat/archives"
fi

# Remove root-level dSYMs folder if it exists
if [ -d "RevenueCat/RevenueCat.dSYMs" ]; then
    echo "Removing root-level RevenueCat.dSYMs folder..."
    rm -rf "RevenueCat/RevenueCat.dSYMs"
fi

# Update Info.plist to only include kept slices
INFO_PLIST="$XCFRAMEWORK_PATH/Info.plist"
if [ ! -f "$INFO_PLIST" ]; then
    echo "Error: Info.plist not found at $INFO_PLIST"
    exit 1
fi

echo "Updating Info.plist to keep only iOS slices..."

# Convert array to comma-separated string
KEEP_SLICES_STR=$(IFS=','; echo "${KEEP_SLICES[*]}")

# Use Python to parse and modify the plist
python3 - "$INFO_PLIST" "$KEEP_SLICES_STR" << 'PYTHON_SCRIPT'
import plistlib
import sys

info_plist_path = sys.argv[1]
keep_slices = sys.argv[2].split(',')

# Read the plist
with open(info_plist_path, 'rb') as f:
    plist = plistlib.load(f)

# Filter AvailableLibraries to only keep the slices we want
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

# Write back the plist
with open(info_plist_path, 'wb') as f:
    plistlib.dump(plist, f)

print(f"Updated Info.plist: kept {len(filtered_libraries)} out of {len(original_libraries)} libraries")
PYTHON_SCRIPT

# Create optimized zip with _optimized suffix initially
OPTIMIZED_ZIP="${ZIP_FILE%.zip}_optimized.zip"
echo "Creating optimized zip file..."

# Remove old optimized zip if it exists
if [ -f "$OPTIMIZED_ZIP" ]; then
    rm "$OPTIMIZED_ZIP"
fi

# Get the xcframework directory name
XCFRAMEWORK_DIR=$(basename "$XCFRAMEWORK_PATH")
XCFRAMEWORK_PARENT=$(dirname "$XCFRAMEWORK_PATH")

# Create zip from the version folder (current directory)
# We need to zip the xcframework so it extracts to the correct structure
if [ "$XCFRAMEWORK_PARENT" == "." ]; then
    # xcframework is at root of version folder, zip it directly
    zip -q -r "$OPTIMIZED_ZIP" "$XCFRAMEWORK_DIR"
else
    # xcframework is in a subfolder (e.g., RevenueCat/RevenueCat.xcframework)
    # We need to zip it so when extracted, it creates RevenueCat.xcframework at root
    # Change to the parent directory and zip from there
    pushd "$XCFRAMEWORK_PARENT" > /dev/null
    zip -q -r "../$OPTIMIZED_ZIP" "$XCFRAMEWORK_DIR"
    popd > /dev/null
fi

# Verify the zip was created
if [ ! -f "$OPTIMIZED_ZIP" ]; then
    echo "Error: Failed to create optimized zip file"
    exit 1
fi

echo "Created optimized $OPTIMIZED_ZIP"

# Update Purchases.json
JSON_FILE="$BASE_DIR/Purchases.json"
if [ ! -f "$JSON_FILE" ]; then
    echo "Warning: Purchases.json not found at $JSON_FILE"
else
    echo "Updating Purchases.json..."

    # Use Python to update JSON (preserving formatting as much as possible)
    python3 - "$JSON_FILE" "$VERSION" "$VERSION_FOLDER" << 'PYTHON_JSON'
import json
import sys

json_file = sys.argv[1]
version = sys.argv[2]
base_url = "https://github.com/23taps/Dependencies/raw/master/Purchases/{}/RevenueCat.xcframework.zip"
version_folder = sys.argv[3]

# Read existing JSON
with open(json_file, 'r') as f:
    data = json.load(f)

# Check if version already exists
if version in data:
    print(f"  Version {version} already exists in Purchases.json")
else:
    # Add new version
    url = base_url.format(version_folder)
    data[version] = url
    
    # Sort versions (convert to float for numeric comparison, handle as string for semantic)
    # Simple approach: keep as string keys but sort them
    sorted_data = {}
    for key in sorted(data.keys(), key=lambda x: [int(i) for i in x.split('.')]):
        sorted_data[key] = data[key]
    
    # Write back JSON with indentation
    with open(json_file, 'w') as f:
        json.dump(sorted_data, f, indent=4)
        f.write('\n')  # Add trailing newline
    
    print(f"  Added version {version} to Purchases.json")
PYTHON_JSON
fi

# If we got here, everything succeeded
# Now finalize: remove original zip and rename optimized one
echo "Finalizing..."
if [ -f "$ORIGINAL_ZIP" ]; then
    rm "$ORIGINAL_ZIP"
    echo "  Removed original zip: $ORIGINAL_ZIP"
fi

if [ -f "$OPTIMIZED_ZIP" ]; then
    mv "$OPTIMIZED_ZIP" "$ZIP_FILE"
    echo "  Renamed $OPTIMIZED_ZIP to $ZIP_FILE"
fi

# Cleanup: remove all extracted files and folders except the final zip
echo "Cleaning up extracted files..."
# Remove RevenueCat folder if it exists
if [ -d "RevenueCat" ]; then
    rm -rf "RevenueCat"
    echo "  Removed RevenueCat/ folder"
fi

# Remove any directly extracted xcframework if it exists (shouldn't happen, but just in case)
if [ -d "RevenueCat.xcframework" ] && [ "$XCFRAMEWORK_PATH" != "RevenueCat.xcframework" ]; then
    rm -rf "RevenueCat.xcframework"
    echo "  Removed RevenueCat.xcframework/ folder"
fi

# Remove __MACOSX folder if it exists (created by macOS unzip)
if [ -d "__MACOSX" ]; then
    rm -rf "__MACOSX"
    echo "  Removed __MACOSX/ folder"
fi

echo ""
echo "✓ Optimization complete!"
echo "  Final zip: $ZIP_FILE"
echo "  Kept slices: ${KEEP_SLICES[*]}"
