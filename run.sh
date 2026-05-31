#!/bin/bash
set -e

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

echo "--- Ruby ---"
ruby languages/test.rb

# 2. Compila e roda o OCaml
echo "--- OCaml ---"
ocamlopt -o languages/test_ocaml unix.cmxa languages/test.ml
./languages/test_ocaml

# 3. Move os CSVs gerados para bench_results/
echo ""
echo "=== Movendo CSVs para bench_results/ ==="
for f in bench_results_*.csv; do
    [ -f "$f" ] && mv "$f" bench_results/ && echo "  movido: $f"
done

# 4. Gera os gráficos
echo ""
echo "=== Gerando gráficos ==="
mkdir -p outputs
python3 -u analysis/bench_charts.py
python3 -u analysis/bench_growth_charts.py

echo ""
echo "=== Benchmarks e gráficos gerados com sucesso! ==="
echo "CSVs em: bench_results/"
echo "PNGs em: outputs/"c