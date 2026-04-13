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
// LOGGER
// ============================================================
class BenchLogger {
  constructor(filename = "bench_results_node.log") {
    this.stream   = fs.createWriteStream(filename, { encoding: "utf-8" });
    this.filename = filename;
  }

  write(line = "") {
    console.log(line);
    this.stream.write(line + "\n");
  }

  start() {
    const mem   = os.totalmem() / 1024 / 1024;
    const avail = os.freemem()  / 1024 / 1024;
    this.write("========================================");
    this.write("Benchmark — Recursão Tail Call em Node.js");
    this.write(new Date().toISOString());
    this.write(`RAM total: ${mem.toFixed(0)}MB  |  Disponível: ${avail.toFixed(0)}MB`);
    this.write(`Limites: RAM<${MAX_RAM_MB}MB  |  Timeout<${MAX_TIME_SEC}s`);
    this.write("========================================\n");
  }

  close() {
    this.write("\n========================================");
    this.write("Fim do benchmark");
    this.write(new Date().toISOString());
    this.write("========================================");
    this.stream.end();
    console.log(`\nLog salvo em: ${this.filename}`);
  }

  section(title) {
    this.write(`\n${title}`);
    this.write("-".repeat(title.length));
  }
}

// ============================================================
// MONITOR DE RAM
// ============================================================
function getRamMB() {
  return process.memoryUsage().rss / 1024 / 1024;
}

function checkRam(label, logger) {
  const ram = getRamMB();
  if (ram > MAX_RAM_MB) {
    logger.write(`  ABORTADO: RAM excedida ${ram.toFixed(0)}MB > ${MAX_RAM_MB}MB ✗`);
    logger.close();
    process.exit(1);
  }
}

// ============================================================
// Algorithm 1 — Factorial with accumulator (self-tail)
// ============================================================

// Sem tail call
function factorialNormal(n) {
  if (n === 0n) return 1n;
  return n * factorialNormal(n - 1n);
}

// Algorithm 1: FACTORIAL(n, acc)
//   if n = 0 then return acc
//   else return FACTORIAL(n − 1, n × acc)
// Node não tem TCO confiável — simulamos com loop
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

// Versão normal
function evenNormal(n) {
  if (n === 0) return true;
  return oddNormal(n - 1);
}

function oddNormal(n) {
  if (n === 0) return false;
  return evenNormal(n - 1);
}

// Algorithm 2: ISEVEN e ISODD mutuamente recursivos
//   ISEVEN(n): if n=0 → true,  else → ISODD(n−1)
//   ISODD(n):  if n=0 → false, else → ISEVEN(n−1)
// Node não garante TCO — com n grande vai dar stack overflow
// mesmo sendo tail position no código
function isEven(n) {
  if (n === 0) return true;
  return isOdd(n - 1);
}

function isOdd(n) {
  if (n === 0) return false;
  return isEven(n - 1);
}

// Versão loop — equivalente ao tail call
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

// Versão normal
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

// Algorithm 3: máquina de três estados
//   STATEA(k): if k=0 → finished, else → STATEB(k−1)
//   STATEB(k): if k=0 → finished, else → STATEC(k−1)
//   STATEC(k): if k=0 → finished, else → STATEA(k−1)
// Versão loop — equivalente ao tail call
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
function runBench(logger, label, func, iterations) {
  checkRam(label, logger);

  const before   = process.memoryUsage();
  const t0       = performance.now();
  const deadline = Date.now() + MAX_TIME_SEC * 1000;

  try {
    for (let i = 0; i < iterations; i++) {
      func();

      if (i % 1000 === 0 && Date.now() > deadline) {
        logger.write(`  ${label.padEnd(14)} TIMEOUT! (>${MAX_TIME_SEC}s) ✗`);
        return;
      }
      if (i % 1000 === 0 && getRamMB() > MAX_RAM_MB) {
        logger.write(`  ${label.padEnd(14)} RAM excedida! ✗`);
        return;
      }
    }

    const t1        = performance.now();
    const after     = process.memoryUsage();
    const ms        = t1 - t0;
    const heapDelta = (after.heapUsed - before.heapUsed) / 1024;
    const ram       = getRamMB();

    logger.write(
      `  ${label.padEnd(14)} Tempo: ${ms.toFixed(1).padStart(8)} ms  |` +
      `  Heap Δ: ${heapDelta.toFixed(1).padStart(10)} KB  |` +
      `  RAM: ${ram.toFixed(0)}MB`
    );
  } catch (e) {
    if (e instanceof RangeError) {
      logger.write(`  ${label.padEnd(14)} STACK OVERFLOW! ✗`);
    } else {
      logger.write(`  ${label.padEnd(14)} ERRO: ${e.message} ✗`);
    }
  }
}

function overflowTest(logger, label, func, resultFn) {
  process.stdout.write(`  ${label} ... `);
  logger.stream.write(`  ${label} ... `);
  checkRam(label, logger);

  const deadline        = Date.now() + MAX_TIME_SEC * 1000;
  const monitorInterval = setInterval(() => {
    if (Date.now() > deadline || getRamMB() > MAX_RAM_MB) {
      clearInterval(monitorInterval);
      logger.write("TIMEOUT ou RAM excedida! ✗");
      process.exit(1);
    }
  }, 200);

  try {
    const result = func();
    clearInterval(monitorInterval);
    logger.write(`OK! (${resultFn(result)})`);
  } catch (e) {
    clearInterval(monitorInterval);
    if (e instanceof RangeError) {
      logger.write("STACK OVERFLOW! ✗  (RangeError: Maximum call stack size exceeded)");
    } else {
      logger.write(`ERRO: ${e.message} ✗`);
    }
  }
}

// ============================================================
// TESTES
// ============================================================
const logger = new BenchLogger();
logger.start();

logger.write(`NOTA: Node.js V8 não garante TCO — mesmo código em tail position
  empilha frames e estoura com n~15.000. Loop é o equivalente real.
  Normal    = recursão pura (estoura cedo)
  Loop/Tail = while/for equivalente ao tail call das outras linguagens\n`);

// ----------------------------------------------------------
// TESTE 1 — Algorithm 1: Factorial with accumulator
// ----------------------------------------------------------
logger.section("TESTE 1: Algorithm 1 — Factorial (self-tail)");

logger.write("  n=10, 500.000 iterações (sem bignum)");
runBench(logger, "Normal      ", () => factorialNormal(10n), 500_000);
runBench(logger, "Loop/Tail   ", () => factorialTail(10n),   500_000);

logger.write("");
logger.write("  n=1000, 10.000 iterações (com bignum)");
runBench(logger, "Normal      ", () => factorialNormal(1000n), 10_000);
runBench(logger, "Loop/Tail   ", () => factorialTail(1000n),   10_000);

// ----------------------------------------------------------
// TESTE 2 — Algorithm 2: Mutually recursive even/odd
// ----------------------------------------------------------
logger.section("TESTE 2: Algorithm 2 — Mutually recursive even/odd");

logger.write("  n=1000, 500.000 iterações");
runBench(logger, "Normal even ", () => evenNormal(1_000), 500_000);
runBench(logger, "Loop   even ", () => isEvenLoop(1_000), 500_000);
runBench(logger, "Normal odd  ", () => oddNormal(1_000),  500_000);

// ----------------------------------------------------------
// TESTE 3 — Algorithm 3: Three-state machine A→B→C→A
// ----------------------------------------------------------
logger.section("TESTE 3: Algorithm 3 — Three-state machine (A→B→C→A)");

logger.write("  k=999 (múltiplo de 3), 500.000 iterações");
runBench(logger, "Normal A→B→C", () => stateANormal(999), 500_000);
runBench(logger, "Loop   A→B→C", () => stateALoop(999),   500_000);


logger.close();