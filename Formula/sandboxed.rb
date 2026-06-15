class Sandboxed < Formula
  include Language::Python::Virtualenv

  desc "Run command-line tools inside disposable project containers"
  homepage "https://github.com/Kirill-Znamenskiy/sandboxed"
  url "https://codeload.github.com/Kirill-Znamenskiy/sandboxed/tar.gz/refs/tags/v0.0.1"
  version "0.0.1"
  sha256 "d25d5a6532c021958d46255c60ea1a2c5a20df94e485df029938c65dd76ea548"
  license "MIT"

  depends_on "python"

  resource "pyyaml" do
    url "https://files.pythonhosted.org/packages/05/8e/961c0007c59b8dd7729d542c61a4d537767a59645b82a0b521206e1e25c2/pyyaml-6.0.3.tar.gz"
    sha256 "d76623373421df22fb4cf8817020cbb7ef15c725b9d5e45f17e189bfc384190f"
  end

  def install
    libexec.install "src", "targets"

    venv = virtualenv_create(libexec/"venv", "python3")
    venv.pip_install resource("pyyaml")

    ["sandboxed", "sbxd"].each do |command_name|
      (bin/command_name).write <<~SH
        #!/bin/bash
        export SANDBOXED_HOME="#{libexec}"
        export SANDBOXED_PYTHON="#{libexec}/venv/bin/python"
        exec "#{libexec}/src/sandboxed.sh" "$@"
      SH
      chmod 0755, bin/command_name
    end
  end

  test do
    output = shell_output("#{bin}/sandboxed --just-print=config opencode")
    assert_match "target: opencode", output
    assert_match "targets/opencode/compose.yaml", output
  end
end
