# Homebrew formula for this fork. vmnet-helper is installed as a
# dependency for bridged networking.
#
# The stable spec installs prebuilt release binaries and needs no Xcode.
# A --HEAD install builds from source and requires Xcode 26.
#
# Install:
#   brew tap nirs/vmnet-helper
#   brew trust nirs/vmnet-helper
#   brew tap s3rj1k/container https://github.com/s3rj1k/container
#   brew install s3rj1k/container/container-vmnet          # prebuilt
#   brew install --HEAD s3rj1k/container/container-vmnet   # from source
class ContainerVmnet < Formula
  desc "Linux containers as lightweight VMs on Apple silicon (fork with bridged networking)"
  homepage "https://github.com/s3rj1k/container"
  license "Apache-2.0"

  # Rolling alias for the newest release; contents change per release, so
  # Homebrew can't pin a checksum and warns on install. Update with:
  #   brew cleanup container-vmnet && brew reinstall s3rj1k/container/container-vmnet
  url "https://github.com/s3rj1k/container/releases/latest/download/container-arm64.tar.gz"
  version "latest"

  head do
    # Explicit `using: :git` keeps the URL a git clone even when CI
    # rewrites it to a file:// path.
    url "https://github.com/s3rj1k/container.git", branch: "main", using: :git
    depends_on xcode: ["26.0", :build]
  end

  depends_on arch: :arm64
  depends_on :macos
  depends_on "nirs/vmnet-helper/vmnet-helper"

  conflicts_with cask: "container", because: "both install a `container` binary"
  conflicts_with formula: "apple/apple/container", because: "both install a `container` binary"

  def install
    if build.head?
      # Build with SwiftPM and stage the layout by hand; the Makefile path
      # drives pkgbuild, unsuited to the Homebrew sandbox. --disable-sandbox
      # because sandboxes don't nest on macOS (standard for Swift formulae).
      system "/usr/bin/swift", "build", "--disable-sandbox", "-c", "release"
      build_bin = Utils.safe_popen_read("/usr/bin/swift", "build", "--disable-sandbox", "-c", "release", "--show-bin-path").chomp

      mkdir_p "bin"
      cp "#{build_bin}/container", "bin/"
      cp "#{build_bin}/container-apiserver", "bin/"
      system "codesign", "--force", "--sign", "-", "--timestamp=none",
        "--identifier", "com.apple.container.cli", "bin/container"
      system "codesign", "--force", "--sign", "-", "--timestamp=none",
        "--identifier", "com.apple.container.apiserver", "bin/container-apiserver"

      plugins = {
        "container-core-images" => ["Sources/Plugins/CoreImages", nil],
        "container-network-vmnet" => ["Sources/Plugins/NetworkVmnet", "signing/container-network-vmnet.entitlements"],
        "container-network-vmnet-helper" => ["Sources/Plugins/NetworkVmnetHelper", nil],
        "container-runtime-linux" => ["Sources/Plugins/RuntimeLinux", "signing/container-runtime-linux.entitlements"],
        "machine-apiserver" => ["Sources/Plugins/MachineAPIServer", nil],
      }
      plugins.each do |name, (source_dir, entitlements)|
        plugin_dir = "libexec/container/plugins/#{name}"
        mkdir_p "#{plugin_dir}/bin"
        cp "#{build_bin}/#{name}", "#{plugin_dir}/bin/"
        cp "#{source_dir}/config.toml", plugin_dir
        sign_args = ["--force", "--sign", "-", "--timestamp=none", "--prefix=com.apple.container."]
        sign_args += ["--entitlements", entitlements] if entitlements
        system "codesign", *sign_args, "#{plugin_dir}/bin/#{name}"
      end

      # machine-apiserver ships runtime resources alongside its binary.
      # `container system start` registers the plugin and the machine API
      # server expects these present, so install them like the Makefile does.
      machine_resources = "libexec/container/plugins/machine-apiserver/resources"
      mkdir_p machine_resources
      ["init", "create-user.sh"].each do |resource|
        cp "Sources/Plugins/MachineAPIServer/Resources/#{resource}", machine_resources
        chmod 0755, "#{machine_resources}/#{resource}"
      end
    else
      # The tarball ships ad hoc signatures, which are valid on any
      # machine. Re-sign the entitled binaries anyway to guard against
      # extraction quirks. codesign ships with macOS, no Xcode needed.
      system "codesign", "--force", "--sign", "-", "--timestamp=none",
        "--entitlements", "signing/container-runtime-linux.entitlements",
        "libexec/container/plugins/container-runtime-linux/bin/container-runtime-linux"
      system "codesign", "--force", "--sign", "-", "--timestamp=none",
        "--entitlements", "signing/container-network-vmnet.entitlements",
        "libexec/container/plugins/container-network-vmnet/bin/container-network-vmnet"
    end

    # The CLI resolves plugins from the grandparent of its real executable,
    # so keep the staged layout under libexec/ and exec through a shim.
    (libexec/"bin").install "bin/container", "bin/container-apiserver"
    (libexec/"libexec").install "libexec/container"

    (bin/"container").write <<~EOS
      #!/bin/bash
      exec "#{opt_libexec}/bin/container" "$@"
    EOS
    chmod 0755, bin/"container"
  end

  def caveats
    <<~EOS
      Start the system services with:
        container system start

      The first start offers to download and install the Linux kernel image.

      The stable install tracks the newest release. Update it with:
        brew cleanup container-vmnet && brew reinstall s3rj1k/container/container-vmnet

      Bridged networking is for container machines. Create a network with the
      container-network-vmnet-helper plugin, then attach a machine to it:
        container network create lan --plugin container-network-vmnet-helper \\
          --subnet 192.168.1.0/24 --option interface=en0 --option gateway=192.168.1.1
        container machine set -n lanbox network=lan,ip=192.168.1.51

      Machines use the builtin NAT network by default (takes effect on next
      boot). List "default" alongside a bridge to keep NAT too:
        container machine set -n lanbox network=default network=lan,ip=192.168.1.51
      An empty value (network=) resets to NAT.

      This conflicts with the official installer package. Uninstall that
      first with /usr/local/bin/uninstall-container.sh if present.
    EOS
  end

  test do
    assert_match "container", shell_output("#{bin}/container --version")
  end
end
