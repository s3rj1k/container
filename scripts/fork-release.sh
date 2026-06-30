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

# Tags HEAD with the fork version (scripts/fork-version.sh) and pushes it,
# triggering the release workflow. Re-running after an amend moves the same
# tag and replaces the release.
#
# Usage: fork-release.sh [--dry-run]

set -euo pipefail

dry_run=0
if [ "${1:-}" = "--dry-run" ]; then
	dry_run=1
fi

run()
{
	if [ "${dry_run}" = 1 ]; then
		echo "would run: $*"
	else
		"$@"
	fi
}

script_dir="$(cd "$(dirname "$0")" && pwd)"

if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
	echo "error: uncommitted changes present, commit or stash them first:" >&2
	git status --short --untracked-files=no >&2
	exit 1
fi

tag="v$("${script_dir}/fork-version.sh")"
head_commit="$(git rev-parse --short HEAD)"

if ! git merge-base --is-ancestor HEAD origin/main 2> /dev/null; then
	echo "warning: HEAD (${head_commit}) is not on origin/main, the release will still build from the tag" >&2
fi

if existing="$(git rev-parse --quiet --verify "refs/tags/${tag}^{commit}")"; then
	if [ "${existing}" = "$(git rev-parse HEAD)" ]; then
		echo "tag ${tag} already points at HEAD (${head_commit})"
	else
		echo "moving tag ${tag} from $(git rev-parse --short "${existing}") to HEAD (${head_commit})"
		run git tag -f -m "${tag}" "${tag}"
	fi
	run git push -f origin "${tag}"
else
	echo "creating tag ${tag} at HEAD (${head_commit})"
	run git tag -m "${tag}" "${tag}"
	run git push origin "${tag}"
fi

remote_url="$(git remote get-url origin)"
repo_path="${remote_url#*github.com[:/]}"
repo_path="${repo_path%.git}"
echo "release run: https://github.com/${repo_path}/actions/workflows/fork-release.yml"
