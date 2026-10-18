class FlowbackCli < Formula
  desc "Command-line interface for Flowback focus and context orchestrator"
  homepage "https://rapheljr.github.io/flowback/"
  url "https://github.com/rapheljr/flowback/archive/refs/tags/v0.4.1.tar.gz"
  version "0.4.1"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"
  license "MIT"
  head "https://github.com/rapheljr/flowback.git", branch: "main"

  depends_on macos: :sonoma

  def install
    system "swift", "build", "-c", "release", "--disable-sandbox", "--product", "flowback-cli"
    bin.install ".build/release/flowback-cli" => "flowback"
  end

  test do
    assert_match "flowback v#{version}", shell_output("#{bin}/flowback --version")
    assert_match "Flowback", shell_output("#{bin}/flowback --help")
  end
end
