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

ESTRUTURA DO REPOSITÓRIO
-------------------------

./languages/
    Código-fonte das implementações de benchmark, um arquivo por linguagem:

    test.py       – Benchmark em Python 3. Implementa os 3 algoritmos nas
                    variantes Normal e Loop/Tail. Usa tracemalloc para medir
                    memória e psutil para monitorar CPU. Escreve o CSV de saída
                    no diretório de trabalho atual.
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
                    Execução: ruby languages/test.rb
                    Saída: bench_results_ruby.csv

    test_ocaml    – Binário OCaml pré-compilado (Linux x86-64). Pode ser executado
                    diretamente sem recompilação: ./languages/test_ocaml

    test.cmi      – Arquivo de interface compilada OCaml (artefato binário de compilação).
    test.cmx      – Arquivo objeto nativo OCaml (artefato binário de compilação).
    test.o        – Arquivo objeto ELF relocável (artefato binário de compilação).


./bench_results/
    Datasets CSV produzidos pelos scripts de benchmark. Todos os arquivos
    seguem o schema:
      Data, Algoritmo, Implementacao, N, Iteracoes, Tempo_ms, Memoria_KB

    bench_results_python.csv  – Resultados das execuções em CPython 3
    bench_results_node.csv    – Resultados das execuções em Node.js (V8)
    bench_results_elixir.csv  – Resultados das execuções em Elixir (BEAM)
    bench_results_scheme.csv  – Resultados das execuções em Racket (Scheme)
    bench_results_ocaml.csv   – Resultados das execuções em OCaml (nativo)
    bench_results_ruby.csv    – Resultados das execuções em Ruby

    Cada linha corresponde a uma medição de (algoritmo, implementação, N,
    contagem de iterações). Linhas podem conter "STACK OVERFLOW" ou "TIMEOUT"
    na coluna Tempo_ms quando uma execução excedeu os limites de segurança.


./outputs/
    Figuras geradas a partir dos dados de benchmark e dos scripts de análise.

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

    bench_charts (1).py       – Script de geração dos 5 gráficos listados acima.
                                Lê os CSVs da pasta bench_results/.
                                Execução: python3 "outputs/bench_charts (1).py"
                                (deve ser executado a partir da raiz do repositório)

    bench_growth_charts.py    – Script secundário de geração de gráficos. Produz
                                gráficos de crescimento log-log (ciclos de CPU vs.
                                iterações) por algoritmo e uma figura combinada 3×2.
                                Execução: python3 outputs/bench_growth_charts.py
                                Saída: outputs/growth_*.png


./latex/
    Fonte LaTeX e saída compilada do documento de revisão bibliográfica.
    
    test.tex  – Fonte LaTeX. "Estado da Arte". Revisa TCO, Proper Tail Recursion e trabalhos relacionados.
    main.bib  – Bibligrafia BibTeX (referências citadas em test.tex).
    Estado da Arte.pdf  – PDF compilado do Estado da Arte.


CONFIGURAÇÃO E SCRIPTS DE EXECUÇÃO
------------------------------------

bench_config.json
    Configuração compartilhada do experimento. Documenta os valores do sweep
    de iterações, número de runs por ponto (runs_per_point = 10), seed aleatória
    (seed = 42), limite de tempo por medição (60 s) e o schema dos CSVs de saída.
    Todos os scripts de benchmark seguem esta configuração para reprodutibilidade.

run.sh
    Script principal de orquestração. Executa todos os benchmarks em sequência,
    compila o OCaml e gera os gráficos de crescimento via bench_growth_charts.py.
    Uso: bash run.sh
    Tempo estimado: 30–60 minutos (sweep completo, 10 runs por ponto).

run_quick.sh
    Script de validação rápida. Define BENCH_QUICK=1, reduzindo o sweep para
    2 pontos e 2 runs por ponto. Útil para verificar se o pipeline funciona
    antes de comprometer com uma execução longa.
    Uso: bash run_quick.sh
    Tempo estimado: 3–5 minutos.

Dockerfile
    Imagem Docker baseada em Ubuntu 22.04. Instala todos os runtimes necessários
    (Python 3, Node.js LTS, Elixir, OCaml, Racket, Ruby), dependências Python
    via requirements.txt e dependências Node.js via package.json.
    O CMD padrão executa bash run.sh automaticamente ao iniciar o container.

docker-compose.yml
    Definição de serviço Docker Compose. Monta o diretório do projeto em /app
    dentro do container para que os CSVs e figuras gerados sejam escritos de
    volta no sistema de arquivos do host. Também monta /sys em modo leitura para
    detecção precisa da frequência da CPU via psutil.
    Uso: docker compose up --build

requirements.txt
    Dependências Python: psutil, matplotlib, pandas, numpy, seaborn.
    Instalar: pip install -r requirements.txt

package.json
    Definição do pacote Node.js. Declara a dependência seedrandom (^3.0.5),
    usada para semeadura reprodutível do PRNG em test.js.
    Instalar: npm install


COMO REPRODUZIR OS RESULTADOS
-------------------------------

Opção A – Docker (recomendado, ambiente totalmente isolado):
    docker compose up --build
    Todos os benchmarks rodam automaticamente. Os CSVs e figuras são gravados
    na pasta do projeto via o volume montado.

Opção B – Execução nativa (requer todos os runtimes instalados localmente):
    pip install -r requirements.txt
    npm install
    bash run.sh          # execução completa (~30–60 min)
    # ou
    bash run_quick.sh    # validação do pipeline (~3–5 min)

Opção C – Linguagem individual (qualquer benchmark pode rodar de forma isolada):
    Consulte as descrições individuais acima. Cada script escreve seu CSV no
    diretório de trabalho atual.

Parâmetros de execução:
    Seed:                42 (todas as linguagens)
    Runs por ponto:      10 (completo) | 2 (BENCH_QUICK=1)
    Sweep de iterações:  10.000 / 30.000 / 100.000 / 300.000 / 1.000.000
    Fatorial bignum:     200 / 500 / 1.000 / 3.000 / 10.000
    Limites de segurança: timeout de 60 s, limite de RAM por linguagem
