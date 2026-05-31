  Tail Call Optimization – Benchmark Empírico
  Bacharelado em Ciência da Computação – PUCPR – Turma 7B – Equipe 2
  Bruno Betiatto, Mohamad Diab, Lucca Magalhães, Vinícius Borges, Gabriel Schneider
================================================================================

DESCRIÇÃO DO PROJETO
--------------------
Este projeto avalia empiricamente o impacto real da Otimização de Chamada em
Cauda (Tail Call Optimization – TCO) no tempo de execução, uso de memória e
escalabilidade em seis runtimes de linguagens de programação: Python, Node.js
(JavaScript), Elixir, Scheme (Racket), OCaml e Ruby.

Três algoritmos recursivos em cauda são medidos em cada linguagem:
  - Algoritmo 1: Fatorial com acumulador (self-tail call)
  - Algoritmo 2: Recursão mútua even/odd (par/ímpar)
  - Algoritmo 3: Máquina de três estados (A -> B -> C -> A)

Cada algoritmo é implementado em duas (ou três) variantes: a versão recursiva
direta (Normal) e a versão otimizada (Tail-call / Loop), permitindo comparação
controlada do comportamento de pilha e custo de CPU entre os runtimes.

Obeservações
-------------------------
Nem todas as linguagens aparecem em todas as categorias dos
gráficos. Node.js aparece principalmente como Normal e Loop, pois o ambiente
Node/V8 não oferece suporte confiável a proper tail calls em JavaScript comum.
OCaml, Scheme/Racket e Elixir aparecem principalmente como Normal e Tail-call,
pois nessas linguagens a repetição funcional é frequentemente representada por
recursão de cauda. A ausência de uma linguagem no painel Loop indica ausência
de uma implementação Loop separada no benchmark, não ausência de capacidade de
repetição na linguagem.

Nos gráficos de crescimento, Python foi excluído para evitar distorções por
timeout, stack overflow e limitações práticas de recursão.

ESTRUTURA DO REPOSITÓRIO
-------------------------

./languages/
    Código-fonte das implementações de benchmark, um arquivo por linguagem:

    test.py       – Benchmark em Python 3. Implementa os 3 algoritmos nas
                    variantes Normal e Loop/Tail. Usa tracemalloc para medir
                    memória e psutil para monitorar CPU.
                    Execução: python3 languages/test.py
                    Saída: bench_results_python.csv

    test.js       – Benchmark em Node.js (modo estrito, engine V8). Implementa
                    os 3 algoritmos nas variantes Normal e Loop/Tail. Usa BigInt
                    para o fatorial a fim de evitar overflow inteiro.
                    Execução: node languages/test.js
                    Saída: bench_results_node.csv

    test.exs      – Script Elixir (BEAM/OTP). Implementa os 3 algoritmos nas
                    variantes Normal e Tail. Usa Task com timeout para segurança
                    e mede memória de heap via :erlang.process_info.
                    Execução: elixir languages/test.exs
                    Saída: bench_results_elixir.csv

    main.rkt      – Script Racket/Scheme. Implementa os 3 algoritmos nas
                    variantes Normal e Tail. O Racket exige Proper Tail Recursion,
                    tornando-o a baseline primária de pilha O(1).
                    Execução: racket languages/main.rkt
                    Saída: bench_results_scheme.csv

    test.ml       – Fonte OCaml (compilação nativa). Implementa os 3 algoritmos
                    nas variantes Normal e Tail. Precisa ser compilado antes
                    de executar.
                    Compilar: ocamlopt -o languages/test_ocaml unix.cmxa languages/test.ml
                    Executar: ./languages/test_ocaml
                    Saída: bench_results_ocaml.csv

    test.rb       – Script Ruby. Implementa os 3 algoritmos nas variantes Normal,
                  Tail (TCO) e Loop explícito. Ativa o TCO em tempo de compilação
                  via RubyVM::InstructionSequence.compile_option.
                  A versão Loop inclui Fatorial, Recursão Mútua e Máquina de Estados.

    test_ocaml    – Binário OCaml pré-compilado (Linux x86-64). Pode ser executado
                    diretamente sem recompilação: ./languages/test_ocaml

    test.cmi      – Arquivo de interface compilada OCaml (artefato binário de compilação).
    test.cmx      – Arquivo objeto nativo OCaml (artefato binário de compilação).
    test.o        – Arquivo objeto ELF relocável (artefato binário de compilação).


./bench_results/
    Datasets CSV produzidos pelos scripts de benchmark. Todos os arquivos
    seguem o schema atual:
      Data, Algoritmo, Implementacao, N, Iteracoes, Run, Ciclos_CPU,
      Ciclos_por_iter, Memoria_KB, Freq_GHz

    bench_results_python.csv  – Resultados das execuções em CPython 3
    bench_results_node.csv    – Resultados das execuções em Node.js (V8)
    bench_results_elixir.csv  – Resultados das execuções em Elixir (BEAM)
    bench_results_scheme.csv  – Resultados das execuções em Racket (Scheme)
    bench_results_ocaml.csv   – Resultados das execuções em OCaml (nativo)
    bench_results_ruby.csv    – Resultados das execuções em Ruby

    Cada linha corresponde a uma medição de (algoritmo, implementação, N,
    contagem de iterações). Linhas podem conter "STACK OVERFLOW", "TIMEOUT" ou "SKIPPED"
    na coluna Ciclos_CPU quando uma execução excedeu os limites de segurança
    ou foi ignorada após falhas consecutivas.


./outputs/
    Figuras geradas a partir dos dados de benchmark pelos scripts em analysis/.

    1_tempo_normalizado.png   – Comparação de tempo de execução normalizado entre
                                todas as linguagens e algoritmos (Python = 1,0 como base).

    2_speedup_vs_python.png   – Fator de speedup em relação ao Python para cada
                                combinação linguagem × algoritmo.

    3_fatorial_escala.png     – Gráfico de escalabilidade do algoritmo Fatorial:
                                tempo de execução em função do tamanho de entrada N.

    4_memoria.png             – Comparação de pico de uso de memória entre todas
                                as linguagens e algoritmos.

    benchmark_comparativo.png – Visão comparativa geral (tempo, memória,
                                escalabilidade) em uma única figura multi-painel.

    growth_Factorial_N10.png       – Crescimento do Fatorial com N=10,
                                  em ciclos de CPU vs. iterações.

    growth_Factorial_N1000.png     – Crescimento do Fatorial com N=1000,
                                      em ciclos de CPU vs. iterações.
    
    growth_Mutually_Rec_Even.png   – Crescimento da recursão mútua Even,
                                      em ciclos de CPU vs. iterações.
    
    growth_Mutually_Rec_Odd.png    – Crescimento da recursão mútua Odd,
                                      em ciclos de CPU vs. iterações.
    
    growth_State_Machine.png       – Crescimento da máquina de estados,
                                      em ciclos de CPU vs. iterações.
    
    growth_all_algorithms.png      – Figura combinada com todos os gráficos
                                      de crescimento.


./analysis/
    Scripts Python de análise e geração de gráficos. Leem os CSVs de
    bench_results/ e escrevem as figuras em outputs/.

    bench_charts.py           – Gera os 5 gráficos comparativos em outputs/
                                (1_tempo_normalizado.png até benchmark_comparativo.png).
                                Execução: python3 analysis/bench_charts.py
                                (executar a partir da raiz do repositório)

    bench_growth_charts.py    – Gera gráficos de crescimento log-log
                              (ciclos de CPU vs. iterações) por algoritmo,
                              separados por implementação: Normal, Tail-call
                              e Loop. Também gera uma figura combinada com
                              todos os algoritmos.
                              Execução: python3 analysis/bench_growth_charts.py
                              Saída: outputs/growth_*.png


./latex/
    Fonte LaTeX e saída compilada do documento de revisão bibliográfica.

    test.tex             – Fonte LaTeX do Estado da Arte (estilo ABNT, português).
                           Revisa TCO, Proper Tail Recursion e trabalhos relacionados.
    main.bib             – Bibliografia BibTeX (referências citadas em test.tex).
    Estado da Arte.pdf   – PDF compilado do Estado da Arte.


CONFIGURAÇÃO E SCRIPTS DE EXECUÇÃO
------------------------------------

  bench_config.json    Configuração central do experimento: seed=42,
                       runs_per_point=10, timeout=60s, sweep de iterações
                       e schema dos CSVs. Todos os scripts seguem este arquivo.

  run.sh               Orquestrador principal. Roda todos os benchmarks em
                       sequência, compila o OCaml e gera os gráficos.
                       Uso: bash run.sh   (~30–60 min)

  run_quick.sh         Versão rápida: BENCH_QUICK=1, 2 pontos e 2 runs.
                       Útil para validar o pipeline antes da execução completa.
                       Uso: bash run_quick.sh   (~3–5 min)

  Dockerfile           Imagem Ubuntu 22.04 com todos os runtimes instalados
                       (Python, Node.js LTS, Elixir, OCaml, Racket, Ruby).
                       Executa run.sh automaticamente ao iniciar o container.

  docker-compose.yml   Sobe o container e monta a pasta do projeto em /app,
                       para que CSVs e figuras gerados apareçam no host.
                       Uso: docker compose up --build

  requirements.txt     Dependências Python: psutil, matplotlib, pandas,
                       numpy, seaborn.
                       Instalar: pip install -r requirements.txt

  package.json         Dependência Node.js: seedrandom ^3.0.5 (PRNG
                       reprodutível em test.js).
                       Instalar: npm install


COMO REPRODUZIR OS RESULTADOS
-------------------------------

  Opção A – Docker  (recomendado, ambiente isolado)
  -------------------------------------------------
    docker compose up --build
    Os CSVs e figuras são gravados automaticamente na pasta do projeto.

    Também é possível executar explicitamente:
      docker compose run --rm benchmark-env bash run.sh
        Versão completa do benchmark.

      docker compose run --rm benchmark-env bash run_quick.sh
        Versão rápida para validação do pipeline.

  Opção B – Execução nativa
  --------------------------
    1. pip install -r requirements.txt
    2. npm install
    3. bash run.sh              # completo (~30–60 min)
       bash run_quick.sh        # validação rápida (~3–5 min)

    Para gerar apenas os gráficos (dados já coletados):
       python3 analysis/bench_charts.py
       python3 analysis/bench_growth_charts.py

  Opção C – Linguagem individual
  --------------------------------
    Cada script em languages/ pode ser executado de forma isolada.
    O CSV de saída é gravado no diretório de trabalho atual.

  Parâmetros do experimento
  --------------------------
    Seed                  42 (todas as linguagens)
    Runs por ponto        10  (completo) | 2 (BENCH_QUICK=1)
    Sweep de iterações    10.000 / 30.000 / 100.000 / 300.000 / 1.000.000
    Fatorial bignum       200 / 500 / 1.000 / 3.000 / 10.000
    Timeout por medição   60 s
