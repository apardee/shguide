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

  def caveats
    <<~EOS
      To enable shell integration (selected commands land on your prompt):

        zsh  — add to ~/.zshrc:
          eval "$(shguide --shell-init zsh)"

        bash — add to ~/.bashrc:
          eval "$(shguide --shell-init bash)"

        fish — add to ~/.config/fish/config.fish:
          shguide --shell-init fish | source

      Without shell integration, the selected command is copied to your clipboard.
    EOS
  end

  test do
    system bin/"shguide", "--version"
    system bin/"shguide", "--shell-init", "zsh"
  end
end
