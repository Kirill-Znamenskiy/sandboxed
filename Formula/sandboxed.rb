class Sandboxed < Formula
  include Language::Python::Virtualenv

  desc "Run command-line tools inside disposable project containers"
  homepage "https://github.com/Kirill-Znamenskiy/sandboxed"
  url "https://codeload.github.com/Kirill-Znamenskiy/sandboxed/tar.gz/refs/tags/v0.0.1"
  version "0.0.1"
  sha256 "d25d5a6532c021958d46255c60ea1a2c5a20df94e485df029938c65dd76ea548"
  license "MIT"

  depends_on "python@3.13"

  resource "pyyaml" do
    url "https://files.pythonhosted.org/packages/54/ed/79a089b6be93607fa5cdaedf301d7dfb23af5f25c398d5ead2525b063e17/pyyaml-6.0.2.tar.gz"
    sha256 "d584d9ec91ad65861cc08d42e834324ef890a082e591037abe114850ff7bbc3e"
  end

  def install
    libexec.install "src", "targets"

    venv = virtualenv_create(libexec/"venv", "python3.13")
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
