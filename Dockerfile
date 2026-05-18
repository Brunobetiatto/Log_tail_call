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
    nodejs npm \
    ruby-full \
    elixir \
    ocaml \
    racket \
    && rm -rf /var/lib/apt/lists/*

# Define o diretório de trabalho dentro do container
WORKDIR /app

# Copia o requirements.txt e instala as bibliotecas do Python
COPY requirements.txt .
RUN pip3 install --no-cache-dir -r requirements.txt

# Copia todo o código do seu projeto para dentro do container
COPY . .

# Dá permissão de execução para o script principal
RUN chmod +x run.sh

# Comando padrão ao iniciar o container
CMD ["./run.sh"]