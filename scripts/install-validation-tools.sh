#!/bin/bash
# Install validation tools for pre-commit hooks
# Usage: ./scripts/install-validation-tools.sh

set -euo pipefail

echo "=== Installing YAML validation tools ==="

# Detect OS
OS="$(uname -s)"
ARCH="$(uname -m)"

# Install pre-commit
echo "Installing pre-commit..."
if command -v pip3 &> /dev/null; then
    pip3 install --user pre-commit
elif command -v brew &> /dev/null; then
    brew install pre-commit
else
    echo "Error: pip3 or brew required to install pre-commit"
    exit 1
fi

# Install yamllint
echo "Installing yamllint..."
if command -v pip3 &> /dev/null; then
    pip3 install --user yamllint
elif command -v brew &> /dev/null; then
    brew install yamllint
fi

# Install kubeconform
echo "Installing kubeconform..."
if command -v brew &> /dev/null; then
    brew install kubeconform
elif command -v go &> /dev/null; then
    go install github.com/yannh/kubeconform/cmd/kubeconform@latest
else
    # Direct binary download
    VERSION="0.6.7"
    case "$OS-$ARCH" in
        Linux-x86_64)  BINARY="kubeconform-linux-amd64.tar.gz" ;;
        Linux-aarch64) BINARY="kubeconform-linux-arm64.tar.gz" ;;
        Darwin-x86_64) BINARY="kubeconform-darwin-amd64.tar.gz" ;;
        Darwin-arm64)  BINARY="kubeconform-darwin-arm64.tar.gz" ;;
        *) echo "Unsupported OS/Arch: $OS-$ARCH"; exit 1 ;;
    esac
    curl -sL "https://github.com/yannh/kubeconform/releases/download/v${VERSION}/${BINARY}" | tar xz -C /usr/local/bin
fi

# Install kube-linter
echo "Installing kube-linter..."
if command -v brew &> /dev/null; then
    brew install kube-linter
elif command -v go &> /dev/null; then
    go install golang.stackrox.io/kube-linter/cmd/kube-linter@latest
else
    # Direct binary download
    VERSION="0.7.1"
    case "$OS-$ARCH" in
        Linux-x86_64)  BINARY="kube-linter-linux.tar.gz" ;;
        Linux-aarch64) BINARY="kube-linter-linux-arm64.tar.gz" ;;
        Darwin-x86_64) BINARY="kube-linter-darwin.tar.gz" ;;
        Darwin-arm64)  BINARY="kube-linter-darwin-arm64.tar.gz" ;;
        *) echo "Unsupported OS/Arch: $OS-$ARCH"; exit 1 ;;
    esac
    curl -sL "https://github.com/stackrox/kube-linter/releases/download/v${VERSION}/${BINARY}" | tar xz -C /usr/local/bin
fi

# Install kustomize
echo "Installing kustomize..."
if command -v brew &> /dev/null; then
    brew install kustomize
elif command -v go &> /dev/null; then
    go install sigs.k8s.io/kustomize/kustomize/v5@latest
else
    # Direct binary download
    VERSION="5.4.3"
    case "$OS-$ARCH" in
        Linux-x86_64)  BINARY="kustomize_v${VERSION}_linux_amd64.tar.gz" ;;
        Linux-aarch64) BINARY="kustomize_v${VERSION}_linux_arm64.tar.gz" ;;
        Darwin-x86_64) BINARY="kustomize_v${VERSION}_darwin_amd64.tar.gz" ;;
        Darwin-arm64)  BINARY="kustomize_v${VERSION}_darwin_arm64.tar.gz" ;;
        *) echo "Unsupported OS/Arch: $OS-$ARCH"; exit 1 ;;
    esac
    curl -sL "https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2Fv${VERSION}/${BINARY}" | tar xz -C /usr/local/bin
fi

echo ""
echo "=== Installing pre-commit hooks ==="
pre-commit install

echo ""
echo "=== Verification ==="
echo "yamllint version: $(yamllint --version)"
echo "kubeconform version: $(kubeconform -v)"
echo "kube-linter version: $(kube-linter version)"
echo "kustomize version: $(kustomize version)"
echo "pre-commit version: $(pre-commit --version)"

echo ""
echo "=== Setup complete! ==="
echo "Run 'pre-commit run --all-files' to validate all files"
echo "Hooks will run automatically on 'git commit'"
