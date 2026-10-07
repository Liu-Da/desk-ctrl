#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
# Command Line Tools include Swift Testing but the build engine may not locate its macro plugin.
desk_swift_path="$(xcrun --find swift)"
desk_testing_plugin="${desk_swift_path:h:h}/lib/swift/host/plugins/testing/libTestingMacros.dylib"
desk_check_flags=(--disable-xctest)
if [[ -f "$desk_testing_plugin" ]]; then
    desk_check_flags+=(-Xswiftc -load-plugin-library -Xswiftc "$desk_testing_plugin")
fi
swift test "${desk_check_flags[@]}"
