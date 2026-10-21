cask "flowback" do
  version "0.4.1"
  sha256 "77f441f7e457917a9e4cf03d99cdacf0acc5675eafd38e85e5672ba29bd15df8"

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
