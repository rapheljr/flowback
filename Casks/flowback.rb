cask "flowback" do
  version "1.0.0"
  sha256 "b2dfc0f053f7cee2acfa49885243ab7a106371f06ba060570e37465566da8534"

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
