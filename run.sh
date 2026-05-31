#!/bin/bash
set -e # Para o script se algo der erro

echo "=== Iniciando execução dos benchmarks ==="
echo "Sweep de iterações em escala log, 10 runs por ponto, seed=42"
echo "Configuração documentada em bench_config.json"
echo ""

# 1. Roda as linguagens que não precisam de compilação separada
echo "--- Racket (Scheme) ---"
racket languages/main.rkt

echo "--- Elixir ---"
elixir languages/test.exs

echo "--- Node.js ---"
node languages/test.js

echo "--- Python ---"
python3 -u languages/test.py

echo "--- Ruby ---"
ruby languages/test.rb

# 2. Compila e roda o OCaml
echo "--- OCaml ---"
ocamlopt -o languages/test_ocaml unix.cmxa languages/test.ml
./languages/test_ocaml

# 3. Gera os gráficos comparativos
echo ""
echo "=== Gerando gráficos ==="
mkdir -p outputs

python3 -u analysis/bench_charts.py
python3 -u analysis/bench_growth_charts.py

echo ""
echo "=== Benchmarks e gráficos gerados com sucesso! ==="
echo "PNGs em: outputs/"
