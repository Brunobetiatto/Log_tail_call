// bench.js
// Rodar com: node bench.js

const fs = require("fs");
const os = require("os");
const { performance } = require("perf_hooks");

// ============================================================
// LIMITES DE SEGURANÇA
// ============================================================
const MAX_RAM_MB   = 500;
const MAX_TIME_SEC = 10;

// ============================================================
// LOGGER (Formato CSV)
// ============================================================
class BenchLogger {
  constructor(filename = "bench_results_node.csv") {
    this.stream   = fs.createWriteStream(filename, { encoding: "utf-8" });
    this.filename = filename;
  }

  write(line = "") {
    console.log(line);
    this.stream.write(line + "\n");
  }

  start() {
    // Escreve o cabeçalho das colunas do CSV
    this.write("Data,Algoritmo,Implementacao,N,Iteracoes,Tempo_ms,Memoria_KB");
  }

  close() {
    this.stream.end();
    console.log(`\nLog salvo em: ${this.filename}`);
  }
}

// ============================================================
// MONITOR DE RAM
// ============================================================
function getRamMB() {
  return process.memoryUsage().rss / 1024 / 1024;
}

// ============================================================
// Algorithm 1 — Factorial with accumulator (self-tail)
// ============================================================

function factorialNormal(n) {
  if (n === 0n) return 1n;
  return n * factorialNormal(n - 1n);
}

function factorialTail(n) {
  let acc = 1n;
  while (n > 0n) {
    acc *= n;
    n--;
  }
  return acc;
}

// ============================================================
// Algorithm 2 — Mutually recursive even/odd
// ============================================================

function evenNormal(n) {
  if (n === 0) return true;
  return oddNormal(n - 1);
}

function oddNormal(n) {
  if (n === 0) return false;
  return evenNormal(n - 1);
}

function isEvenLoop(n) {
  while (true) {
    if (n === 0) return true;
    n--;
    if (n === 0) return false;
    n--;
  }
}

// ============================================================
// Algorithm 3 — Three-state machine (A → B → C → A)
// ============================================================

function stateANormal(k) {
  if (k === 0) return "finished";
  return stateBNormal(k - 1);
}

function stateBNormal(k) {
  if (k === 0) return "finished";
  return stateCNormal(k - 1);
}

function stateCNormal(k) {
  if (k === 0) return "finished";
  return stateANormal(k - 1);
}

function stateALoop(k) {
  let state = "A";
  while (true) {
    if (k === 0) return "finished";
    k--;
    if (state === "A")      state = "B";
    else if (state === "B") state = "C";
    else                    state = "A";
  }
}

// ============================================================
// BENCHMARK ENGINE
// ============================================================
function runBench(logger, algo, impl, n, iterations, func) {
  const before   = process.memoryUsage();
  const t0       = performance.now();
  const deadline = Date.now() + MAX_TIME_SEC * 1000;
  const timestamp = new Date().toISOString();

  try {
    for (let i = 0; i < iterations; i++) {
      func();

      // Checagens de segurança a cada 1000 iterações para não pesar no loop
      if (i % 1000 === 0) {
        if (Date.now() > deadline) throw new Error("TIMEOUT");
        if (getRamMB() > MAX_RAM_MB) throw new Error("OOM (RAM Excedida)");
      }
    }

    const t1        = performance.now();
    const after     = process.memoryUsage();
    const ms        = t1 - t0;
    const heapDelta = (after.heapUsed - before.heapUsed) / 1024;

    logger.write(
      `"${timestamp}","${algo}","${impl}",${n},${iterations},${ms.toFixed(1)},${heapDelta.toFixed(1)}`
    );
  } catch (e) {
    let errorMsg = e.message;
    if (e instanceof RangeError) {
      errorMsg = "STACK OVERFLOW";
    }
    
    // Em caso de erro, escreve a mensagem na coluna de Tempo e deixa a Memória vazia
    logger.write(
      `"${timestamp}","${algo}","${impl}",${n},${iterations},"${errorMsg}",""`
    );
  }
}

// ============================================================
// TESTES
// ============================================================
const logger = new BenchLogger();
logger.start();

// ----------------------------------------------------------
// TESTE 1 — Algorithm 1: Factorial with accumulator
// ----------------------------------------------------------
// n=10, 500.000 iterações (sem bignum)
runBench(logger, "Factorial", "Normal", 10, 500_000, () => factorialNormal(10n));
runBench(logger, "Factorial", "Loop/Tail", 10, 500_000, () => factorialTail(10n));

// n=1000, 10.000 iterações (com bignum)
// Passamos o N como string/número na assinatura para o CSV, mas o BigInt vai na closure
runBench(logger, "Factorial", "Normal", 1000, 10_000, () => factorialNormal(1000n));
runBench(logger, "Factorial", "Loop/Tail", 1000, 10_000, () => factorialTail(1000n));

// ----------------------------------------------------------
// TESTE 2 — Algorithm 2: Mutually recursive even/odd
// ----------------------------------------------------------
// n=1000, 500.000 iterações
runBench(logger, "Mutually Rec (Even)", "Normal", 1000, 500_000, () => evenNormal(1_000));
runBench(logger, "Mutually Rec (Even)", "Loop", 1000, 500_000, () => isEvenLoop(1_000));

runBench(logger, "Mutually Rec (Odd)", "Normal", 1000, 500_000, () => oddNormal(1_000));

// ----------------------------------------------------------
// TESTE 3 — Algorithm 3: Three-state machine A→B→C→A
// ----------------------------------------------------------
// k=999 (múltiplo de 3), 500.000 iterações
runBench(logger, "State Machine", "Normal", 999, 500_000, () => stateANormal(999));
runBench(logger, "State Machine", "Loop", 999, 500_000, () => stateALoop(999));

logger.close();