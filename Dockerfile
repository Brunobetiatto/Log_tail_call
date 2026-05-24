# Usa uma imagem oficial do Ubuntu
FROM ubuntu:22.04

# Evita prompts interativos durante a instalação de pacotes
ENV DEBIAN_FRONTEND=noninteractive

# Atualiza os pacotes e instala apenas as linguagens e dependências do sistema
RUN apt-get update && apt-get install -y \
    build-essential \
    curl \
    wget \
    python3 python3-pip \
    ruby-full \
    elixir \
    ocaml \
    ocaml-native-compilers \
    racket \
    && rm -rf /var/lib/apt/lists/*

# Instala Node.js LTS via NodeSource (Ubuntu 22.04 traz Node 12 por padrão)
RUN curl -fsSL https://deb.nodesource.com/setup_lts.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# Define o diretório de trabalho dentro do container
WORKDIR /app

# Copia o requirements.txt e instala as bibliotecas do Python
COPY requirements.txt .
RUN pip3 install --no-cache-dir -r requirements.txt

# Instala as dependências do Node (seedrandom para reprodutibilidade)
COPY package.json .
RUN npm install --omit=dev

# Copia todo o código do seu projeto para dentro do container
COPY . .

# Corrige line endings Windows (CRLF → LF) e dá permissão de execução
RUN sed -i 's/\r$//' run.sh run_quick.sh && chmod +x run.sh run_quick.sh

# Comando padrão ao iniciar o container
CMD ["bash", "run.sh"]