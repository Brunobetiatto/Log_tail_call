#!/bin/bash
# Versão rápida: 2 pontos no sweep, 2 runs por ponto.
# Útil para validar o pipeline antes de rodar o experimento completo.
# Tempo estimado: 3-5 min vs 30-60 min do run.sh completo.

export BENCH_QUICK=1
bash run.sh
