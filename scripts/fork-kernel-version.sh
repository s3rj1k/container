#!/usr/bin/env bash
# Copyright © 2026 Apple Inc. and the container project authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#   https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Prints the kernel version to build. With an argument it echoes that
# version back, otherwise it finds the newest longterm (LTS) release on
# kernel.org.
#
# Run as fork-kernel-version.sh [version]

set -euo pipefail

ver="${1:-}"

if [ -z "${ver}" ]; then
    ver="$(curl -fsSL https://www.kernel.org/releases.json \
        | jq -r '.releases[] | select(.moniker == "longterm") | .version' \
        | sort -V | tail -1)"
fi

if [ -z "${ver}" ]; then
    echo "error: no longterm kernel release found on kernel.org" >&2
    exit 1
fi

echo "${ver}"
