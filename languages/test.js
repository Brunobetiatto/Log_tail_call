// bench.js
// Rodar com: node bench.js

const fs = require("fs");
const os = require("os");
const seedrandom = require("seedrandom");

// ============================================================
// REPRODUTIBILIDADE
// ============================================================
const SEED = 42;
// Substitui Math.random global por um PRNG seedado.
// Os algoritmos nao usam random, mas isso garante que qualquer
// chamada indireta (V8, libs) tambem fique deterministica.
seedrandom(String(SEED), { global: true });

// ============================================================
// CPU FREQ
// ============================================================
function getCpuFreqGHz() {
  try {
    const content = fs.readFileSync("/proc/cpuinfo", "utf8");
    const match = content.match(/cpu MHz\s*:\s*([0-9.]+)/);
    if (match) return parseFloat(match[1]) / 1000;
  } catch (_) {}
  const cpus = os.cpus();
  const speed = (cpus && cpus.length > 0) ? cpus[0].speed : 0;
  return speed > 0 ? speed / 1000 : 2.0;
}

// ============================================================
// LIMITES DE SEGURANCA
// ============================================================
const MAX_RAM_MB     = 500;
const MAX_TIME_SEC   = 60;

const QUICK = process.env.BENCH_QUICK === '1';
const RUNS_PER_POINT = QUICK ? 2 : 10;

// ============================================================
// SWEEP DE ITERACOES (escala log)
// ============================================================
const SWEEP_CHEAP            = QUICK ? [10_000, 100_000]
                                     : [10_000, 30_000, 100_000, 300_000, 1_000_000];
const SWEEP_FACTORIAL_BIGNUM = QUICK ? [200, 1_000]
                                     : [200, 500, 1_000, 3_000, 10_000];
if (QUICK) console.log("[BENCH_QUICK=1] usando sweep reduzido e 2 runs por ponto");

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
    this.write("Data,Algoritmo,Implementacao,N,Iteracoes,Run,Ciclos_CPU,Ciclos_por_iter,Memoria_KB,Freq_GHz");
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
// Algorithm 1 -- Factorial with accumulator (self-tail)
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
// Algorithm 2 -- Mutually recursive even/odd
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
// Algorithm 3 -- Three-state machine (A -> B -> C -> A)
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
function runSingle(logger, algo, impl, n, iterations, runId, func) {
  const freqGhz   = getCpuFreqGHz();
  const memBefore = process.memoryUsage();
  const cpuBefore = process.cpuUsage();
  const deadline  = Date.now() + MAX_TIME_SEC * 1000;
  const timestamp = new Date().toISOString();

  try {
    for (let i = 0; i < iterations; i++) {
      func();
      if (i % 1000 === 0) {
        if (Date.now() > deadline) throw new Error("TIMEOUT");
        if (getRamMB() > MAX_RAM_MB) throw new Error("OOM (RAM Excedida)");
      }
    }

    const cpuUsed       = process.cpuUsage(cpuBefore);
    const memAfter      = process.memoryUsage();
    const cpuSeconds    = (cpuUsed.user + cpuUsed.system) / 1e6;
    const cycles        = cpuSeconds * freqGhz * 1e9;
    const cyclesPerIter = cycles / iterations;
    const heapDelta     = (memAfter.heapUsed - memBefore.heapUsed) / 1024;

    logger.write(
      `"${timestamp}","${algo}","${impl}",${n},${iterations},${runId},${cycles.toFixed(0)},${cyclesPerIter.toFixed(2)},${heapDelta.toFixed(1)},${freqGhz.toFixed(4)}`
    );
    return "OK";
  } catch (e) {
    let errorMsg = e.message;
    if (e instanceof RangeError) errorMsg = "STACK OVERFLOW";
    logger.write(
      `"${timestamp}","${algo}","${impl}",${n},${iterations},${runId},"${errorMsg}","","",${freqGhz.toFixed(4)}`
    );
    return errorMsg;
  }
}

function runSweep(logger, algo, impl, n, sweep, funcFactory) {
  let consecutiveFails = 0;
  for (const iterCount of sweep) {
    if (consecutiveFails >= 2) {
      for (let r = 1; r <= RUNS_PER_POINT; r++) {
        const ts = new Date().toISOString();
        logger.write(`"${ts}","${algo}","${impl}",${n},${iterCount},${r},"SKIPPED","","",0.0000`);
      }
      continue;
    }

    let fails = 0;
    for (let r = 1; r <= RUNS_PER_POINT; r++) {
      const status = runSingle(logger, algo, impl, n, iterCount, r, funcFactory());
      if (status === "TIMEOUT" || status === "STACK OVERFLOW" || status === "OOM (RAM Excedida)") {
        fails++;
        if (fails >= 2 && r < RUNS_PER_POINT) {
          for (let skip = r + 1; skip <= RUNS_PER_POINT; skip++) {
            const ts = new Date().toISOString();
            logger.write(`"${ts}","${algo}","${impl}",${n},${iterCount},${skip},"SKIPPED","","",0.0000`);
          }
          break;
        }
      }
    }
    if (fails >= Math.ceil(RUNS_PER_POINT / 2)) consecutiveFails++;
    else consecutiveFails = 0;
  }
}

// ============================================================
// TESTES
// ============================================================
const logger = new BenchLogger();
logger.start();

// ----- Factorial -----
runSweep(logger, "Factorial", "Normal",    10,   SWEEP_CHEAP,            () => () => factorialNormal(10n));
runSweep(logger, "Factorial", "Loop/Tail", 10,   SWEEP_CHEAP,            () => () => factorialTail(10n));
runSweep(logger, "Factorial", "Normal",    1000, SWEEP_FACTORIAL_BIGNUM, () => () => factorialNormal(1000n));
runSweep(logger, "Factorial", "Loop/Tail", 1000, SWEEP_FACTORIAL_BIGNUM, () => () => factorialTail(1000n));

// ----- Mutually Recursive -----
runSweep(logger, "Mutually Rec (Even)", "Normal", 1000, SWEEP_CHEAP, () => () => evenNormal(1000));
runSweep(logger, "Mutually Rec (Even)", "Loop",   1000, SWEEP_CHEAP, () => () => isEvenLoop(1000));

runSweep(logger, "Mutually Rec (Odd)", "Normal", 1000, SWEEP_CHEAP, () => () => oddNormal(1000));
runSweep(logger, "Mutually Rec (Odd)", "Loop",   1000, SWEEP_CHEAP, () => () => isEvenLoop(1000));

// ----- State Machine -----
runSweep(logger, "State Machine", "Normal", 999, SWEEP_CHEAP, () => () => stateANormal(999));
runSweep(logger, "State Machine", "Loop",   999, SWEEP_CHEAP, () => () => stateALoop(999));

logger.close();
