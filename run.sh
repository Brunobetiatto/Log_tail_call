#!/bin/bash
set -e # Para o script se algo der erro

echo "=== Iniciando execução dos benchmarks ==="

# 1. Roda as linguagens que não precisam de compilação separada
racket languages/main.rkt
elixir languages/test.exs
node languages/test.js
python3 -u languages/test.py
ruby languages/test.rb

# 2. Compila e roda o OCaml
echo "Rodando OCaml..."
ocamlopt -o languages/test_ocaml unix.cmxa languages/test.ml
./languages/test_ocaml

# 3. Prepara o ambiente para os resultados visuais
echo "Criando diretório para os gráficos..."
mkdir -p "analysis univariate plot"

# 4. Gera os gráficos 
echo "Gerando os gráficos com Python..."
python3 -u "outputs/bench_charts (1).py"

echo "=== Benchmarks e gráficos gerados com sucesso! ==="