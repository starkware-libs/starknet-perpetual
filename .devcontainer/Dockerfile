FROM node:slim

# Install required packages
RUN apt-get update && apt-get install -y \
    git \
    curl \
    zsh \
    build-essential \
    vim \
    bash \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user
RUN useradd -m -s /bin/bash vscode && \
    chown -R vscode:vscode /home/vscode

# Update npm and install corepack as root
RUN npm install -g npm corepack && \
    chown -R vscode:vscode /usr/local/lib/node_modules

# Switch to non-root user
USER vscode

ENV HOME=/home/vscode
ENV PATH=${PATH}:${HOME}/.local/bin:/usr/local/bin

# Create local bin directory
RUN mkdir -p ${HOME}/.local/bin

# Activate Yarn
RUN corepack prepare yarn@stable --activate

# Install oh-my-zsh
RUN curl --proto '=https' --tlsv1.2 -sSf https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh | sh -s 

# Install Starkli
RUN curl --proto '=https' --tlsv1.2 -sSf https://get.starkli.sh | sh -s
ENV PATH=${PATH}:${HOME}/.starkli/bin
RUN starkliup

# Install Scarb
RUN curl --proto '=https' --tlsv1.2 -sSf https://docs.swmansion.com/scarb/install.sh | sh -s -- -v 2.11.4

# Install Starknet Foundry
RUN curl --proto '=https' --tlsv1.2 -sSf https://raw.githubusercontent.com/foundry-rs/starknet-foundry/master/scripts/install.sh | sh -s
RUN snfoundryup -v 0.45.0

# Download starknet-devnet binary based on host architecture
ENV DEVNET_VERSION=0.3.0
RUN ARCH=$(uname -m) && \
  echo "Architecture detected: ${ARCH}" && \
  if [ "${ARCH}" = "x86_64" ]; then \
    echo "Installing binary for x86_64"; \
    curl -sSfL https://github.com/0xSpaceShard/starknet-devnet/releases/download/v${DEVNET_VERSION}/starknet-devnet-x86_64-unknown-linux-musl.tar.gz | tar -xvz -C ${HOME}/.local/bin; \
  elif [ "${ARCH}" = "aarch64" ]; then \
    echo "Installing binary for ARM64"; \
    curl -sSfL https://github.com/0xSpaceShard/starknet-devnet/releases/download/v${DEVNET_VERSION}/starknet-devnet-aarch64-unknown-linux-gnu.tar.gz | tar -xvz -C ${HOME}/.local/bin; \
  else \
    echo "Unknown architecture: ${ARCH}"; \
    exit 1; \
  fi

RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y

WORKDIR /workspace