#!/bin/bash
#
# inject-version.sh
# Injects the version number into the Swift source for release builds
#

VERSION="$1"
if [ -z "$VERSION" ]; then
    echo "Error: Version number required"
    echo "Usage: $0 <version>"
    exit 1
fi

# Update the Version.swift file with the release version
VERSION_FILE="RomKitCLI/Version.swift"

# Create a release version of Version.swift
cat > "$VERSION_FILE" << EOF
//
//  Version.swift
//  RomKit CLI - Version Management
//
//  Provides version information for the CLI tool
//  AUTO-GENERATED FILE - DO NOT EDIT
//

import Foundation

/// Version information for RomKit CLI
public struct Version {
    /// The version string to display
    public static let current = "$VERSION"
}
EOF

echo "✅ Injected version $VERSION into $VERSION_FILE"