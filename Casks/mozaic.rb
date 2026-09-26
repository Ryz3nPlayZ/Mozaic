cask "mozaic" do
  version "0.4.1"
  sha256 "e63d0d61bb6d0c2c5a61db54fd10606a1816b70e822c867588d0a301a5dd49b1"

  url "https://github.com/Ryz3nPlayZ/Mozaic/releases/download/v#{version}/mozaic-v#{version}.dmg"
  name "Mozaic"
  desc "Native YouTube Music client"
  homepage "https://github.com/Ryz3nPlayZ/Mozaic"

  deprecate! date: "2026-01-06", because: "has moved to the tap at https://github.com/sozercan/homebrew-repo"

  auto_updates false
  depends_on macos: :tahoe

  app "Mozaic.app"

  caveats <<~EOS
    ⚠️  This tap is deprecated and will no longer receive updates.

    To migrate to the new tap:
      brew untap Ryz3nPlayZ/Mozaic
      brew install sozercan/repo/mozaic
  EOS

  postflight_steps do
    run "/usr/bin/xattr", args: ["-cr", "{{appdir}}/Mozaic.app"], sudo: false
  end

  zap trash: [
    "~/Library/Application Support/Mozaic",
    "~/Library/Caches/com.zemuliu.Mozaic",
    "~/Library/Preferences/com.zemuliu.Mozaic.plist",
    "~/Library/Saved Application State/com.zemuliu.Mozaic.savedState",
    "~/Library/WebKit/com.zemuliu.Mozaic",
  ]
end
