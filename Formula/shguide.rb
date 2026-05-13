# Homebrew formula for shguide.
#
# To install before the first tagged release:
#   brew install --HEAD <tap>/shguide
#
# Once v0.1.0 is tagged, set the url to a release tarball and add a sha256.

class Shguide < Formula
  desc "macOS CLI for formulating and explaining shell commands via Apple Foundation Models"
  homepage "https://github.com/apardee/shguide"
  license "MIT"
  head "https://github.com/apardee/shguide.git", branch: "main"

  depends_on :macos => :tahoe
  depends_on :arch => :arm64
  depends_on xcode: ["26.0", :build]

  def install
    system "swift", "build", "--disable-sandbox", "-c", "release"
    bin.install ".build/release/shguide"
    bin.install ".build/release/shguide-eval"
    pkgshare.install "Datasets"
    doc.install Dir["docs/*"]
  end

  test do
    assert_match "0.1.0", shell_output("#{bin}/shguide --version")
    assert_match "shell:", shell_output("#{bin}/shguide --config")
  end
end
