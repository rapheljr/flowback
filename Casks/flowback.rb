cask "flowback" do
  version "0.4.0"
  sha256 "7fdcc8a5597aba48c82128a747530b3820e970f67f9ba334093ab93647d0ed8e"

  url "https://github.com/rapheljr/flowback/releases/download/v#{version}/Flowback-#{version}-macos.zip"
  name "Flowback"
  desc "Focus and context orchestration across developer applications"
  homepage "https://rapheljr.github.io/flowback/"

  depends_on macos: :sonoma

  app "Flowback.app"
  binary "#{appdir}/Flowback.app/Contents/Resources/flowback"

  uninstall quit: "com.flowback.app"

  zap trash: [
    "~/.flowback",
    "~/Library/Preferences/com.flowback.app.plist",
    "~/Library/Saved Application State/com.flowback.app.savedState",
  ]
end
