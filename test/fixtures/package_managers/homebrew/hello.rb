class Hello < Formula
  desc "Says hello"
  homepage "https://github.com/example/hello"
  version "1.0.0"
  license "MIT"

  on_macos do
    on_arm do
      url "https://github.com/example/hello/releases/download/v1.0.0/Hello-arm64-darwin.tar.gz"
      sha256 "HASH FROM Hello-arm64-darwin.tar.gz.sha256"
    end
  end

  on_linux do
    on_intel do
      url "https://github.com/example/hello/releases/download/v1.0.0/Hello-x86_64-linux.tar.gz"
      sha256 "HASH FROM Hello-x86_64-linux.tar.gz.sha256"
    end
    on_arm do
      url "https://github.com/example/hello/releases/download/v1.0.0/Hello-aarch64-linux.tar.gz"
      sha256 "HASH FROM Hello-aarch64-linux.tar.gz.sha256"
    end
  end

  def install
    libexec.install Dir["*"]
    bin.install_symlink libexec/"Hello" => "hello"
  end

  test do
    assert_match "Hello", shell_output("#{bin}/hello")
  end
end
