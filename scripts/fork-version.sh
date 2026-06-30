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

# Prints the fork version: <upstream release tag>+<short sha of the merge
# base with upstream>. The merge base makes it survive amends and change
# only on a rebase onto newer upstream. Tag a release with:
#
#   git tag "v$(scripts/fork-version.sh)" && git push origin "v$(scripts/fork-version.sh)"
#
# Usage: fork-version.sh [ref]   (default: HEAD)
# Override the upstream ref with FORK_UPSTREAM_REF (default upstream/main).

set -euo pipefail

ref="${1:-HEAD}"
upstream="${FORK_UPSTREAM_REF:-upstream/main}"

if ! git rev-parse --verify --quiet "${upstream}^{commit}" >/dev/null; then
    echo "error: upstream ref '${upstream}' not found; set it up with:" >&2
    echo "  git remote add upstream https://github.com/apple/container.git" >&2
    echo "  git fetch upstream main --tags" >&2
    exit 1
fi

if ! base_commit="$(git merge-base "${ref}" "${upstream}")"; then
    echo "error: no common ancestor between ${ref} and ${upstream}; fetch the full history with:" >&2
    echo "  git fetch --unshallow upstream main" >&2
    exit 1
fi

if ! base_tag="$(git describe --tags --abbrev=0 --match '[0-9]*.[0-9]*.[0-9]*' "${base_commit}" 2>/dev/null)" || [ -z "${base_tag}" ]; then
    echo "error: no upstream release tag found in the ancestry of ${base_commit}; fetch tags with:" >&2
    echo "  git fetch upstream --tags" >&2
    exit 1
fi

echo "${base_tag}+$(git rev-parse --short "${base_commit}")"
