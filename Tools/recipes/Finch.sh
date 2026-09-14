# Finch — Objective-C OpenAL sound-effect engine. Upstream is archived, has no
# published releases, no package manifest, and a 2018 Xcode project with
# obsolete settings, so the implementation files named by its podspec are
# compiled directly into a static library.
#
# Static, not dynamic, on purpose: Finch is linked into the Games target today
# and must not acquire a dynamic framework's separate resource bundle location,
# because it derives its default sound bundle from its own class location.
REPO="https://github.com/zoul/Finch.git"
VERSION="1.0.3"
TAG="1.0.3"
COMMIT="6f40fe8c61e5322eff540b488f449ec105fc42ae"

KIND="static-library"

OUTPUT_SUBDIR="Finch-1.0.3-xcframework"
MANIFEST_NAME="Finch-xcframework.json"
MANIFEST_KEYS=("1.0.3")

# From the upstream podspec: `Finch/**/*.{h,m}` minus `*Test*`.
SOURCE_FILES=(
    "Finch/FIError.m"
    "Finch/FISampleBuffer.m"
    "Finch/FISampleDecoder.m"
    "Finch/FISampleFormat.m"
    "Finch/FISound.m"
    "Finch/FISoundContext.m"
    "Finch/FISoundDevice.m"
    "Finch/FISoundEngine.m"
    "Finch/FISoundSource.m"
)
HEADER_FILES=(
    "Finch/FIError.h"
    "Finch/FISampleBuffer.h"
    "Finch/FISampleDecoder.h"
    "Finch/FISampleFormat.h"
    "Finch/FISound.h"
    "Finch/FISoundContext.h"
    "Finch/FISoundDevice.h"
    "Finch/FISoundEngine.h"
    "Finch/FISoundSource.h"
)
LINK_FRAMEWORKS=("OpenAL" "AudioToolbox" "AVFoundation" "Foundation")
