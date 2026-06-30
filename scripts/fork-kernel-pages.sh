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

# Builds the GitHub Pages tree for a freshly built kernel. container can only
# consume a kernel over the web from a tar archive, so this packages the Image
# and the config into kernel.tar.gz and writes a checksum file, a latest.json
# manifest, and an index page. The raw Image is never published on its own.
#
# Run as fork-kernel-pages.sh VERSION IMAGE CONFIG OUTDIR

set -euo pipefail

if [ "$#" -ne 4 ]; then
    echo "usage: $0 VERSION IMAGE CONFIG OUTDIR" >&2
    exit 1
fi

ver="$1"
image="$2"
config="$3"
out="$4"

member="kernel/Image"
tarname="kernel.tar.gz"

# Stage the members under the path that container extracts with the binary
# flag, then pack them.
stage="$(mktemp -d)"
trap 'rm -rf "${stage}"' EXIT
mkdir -p "${stage}/kernel"
cp "${image}" "${stage}/kernel/Image"
cp "${config}" "${stage}/kernel/config"

mkdir -p "${out}"
tar -czf "${out}/${tarname}" -C "${stage}" kernel/Image kernel/config

sha="$(sha256sum "${out}/${tarname}" | awk '{ print $1 }')"
size="$(stat -c %s "${out}/${tarname}")"
built="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

(cd "${out}" && sha256sum "${tarname}" >sha256sums.txt)

cat >"${out}/latest.json" <<JSON
{
  "version": "${ver}",
  "arch": "arm64",
  "tar": "${tarname}",
  "member": "${member}",
  "sha256": "${sha}",
  "size": ${size},
  "built": "${built}"
}
JSON

cat >"${out}/index.html" <<HTML
<!doctype html>
<title>LTS kernel builds</title>
<h1>Latest LTS kernel</h1>
<p>Version <strong>${ver}</strong> (arm64), built ${built}.</p>
<p>Install it with container.</p>
<pre id="cmd">container system kernel set --tar https://HOST/${tarname} --binary ${member}</pre>
<button class="copy" data-target="cmd" type="button" hidden>Copy</button>
<pre id="netcmd">container machine set kernel-arg=dummy.numdummies=0 kernel-arg=ifb.numifbs=0 kernel-arg=bonding.max_bonds=0</pre>
<button class="copy" data-target="netcmd" type="button" hidden>Copy</button>
<script>
(function () {
  var tar = new URL("${tarname}", location.href).href;
  document.getElementById("cmd").textContent =
    "container system kernel set --tar " + tar + " --binary ${member}";
  var buttons = document.querySelectorAll("button.copy");
  for (var i = 0; i < buttons.length; i++) {
    (function (btn) {
      btn.hidden = false;
      btn.addEventListener("click", function () {
        var text = document.getElementById(btn.getAttribute("data-target")).textContent;
        navigator.clipboard.writeText(text).then(function () {
          btn.textContent = "Copied";
          setTimeout(function () { btn.textContent = "Copy"; }, 1500);
        });
      });
    })(buttons[i]);
  }
})();
</script>
<ul>
  <li><a href="${tarname}">${tarname}</a></li>
  <li><a href="latest.json">latest.json</a></li>
  <li><a href="sha256sums.txt">sha256sums.txt</a></li>
</ul>
<p>sha256 ${sha}</p>
HTML

echo "wrote ${out} for kernel ${ver}" >&2
