FROM kathara/base

# ── Dependências ──────────────────────────────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
        wget \
        tcpdump \
        iproute2 \
        net-tools \
        curl \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# ── Bitcoin Core 26.0 (x86_64) ───────────────────────────────────────────────
# SHA256 verificado em https://bitcoincore.org/bin/bitcoin-core-26.0/SHA256SUMS
ARG BTC_VERSION=26.0
ARG BTC_ARCH=x86_64-linux-gnu

RUN wget -q https://bitcoincore.org/bin/bitcoin-core-${BTC_VERSION}/bitcoin-${BTC_VERSION}-${BTC_ARCH}.tar.gz \
    && tar -xzf bitcoin-${BTC_VERSION}-${BTC_ARCH}.tar.gz \
    && install -m 0755 -o root -g root -t /usr/local/bin \
        bitcoin-${BTC_VERSION}/bin/bitcoind \
        bitcoin-${BTC_VERSION}/bin/bitcoin-cli \
    && rm -rf bitcoin-${BTC_VERSION}*

# ── Diretório de capturas ─────────────────────────────────────────────────────
RUN mkdir -p /captures

WORKDIR /root
