// bench.js
// Rodar com: node bench.js

const fs = require("fs");
const os = require("os");
const { performance } = require("perf_hooks");
const v8 = require("v8");

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
    const mem = os.totalmem() / 1024 / 1024;
    const avail = os.freemem() / 1024 / 1024;
    this.write("========================================");
    this.write("Benchmark Tail Call vs Normal — Node.js");
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
// IMPLEMENTAÇÕES
// ============================================================

// --- Factorial ---
// Node.js tem TCO no strict mode em algumas versões,
// mas na prática é não confiável — usamos loop explícito
function factorialNormal(n) {
  if (n === 0n) return 1n;
  return n * factorialNormal(n - 1n);  // BigInt nativo
}

function factorialTail(n) {
  let acc = 1n;
  while (n > 0n) {
    acc *= n;
    n--;
  }
  return acc;
}

// --- Fibonacci ---
function fibNormal(n) {
  if (n < 2) return n;
  return fibNormal(n - 1) + fibNormal(n - 2);
}

function fibTail(n) {
  let a = 0, b = 1;
  for (let i = 0; i < n; i++) {
    [a, b] = [b, a + b];
  }
  return a;
}

// --- Soma de lista ---
function sumNormal(arr, i = 0) {
  if (i >= arr.length) return 0;
  return arr[i] + sumNormal(arr, i + 1);  // índice evita cópia como Python
}

function sumTail(arr) {
  let acc = 0;
  for (const x of arr) acc += x;
  return acc;
}

// ============================================================
// BENCHMARK ENGINE
// ============================================================
function runBench(logger, label, func, iterations) {
  checkRam(label, logger);

  const before = process.memoryUsage();
  const t0     = performance.now();
  const deadline = Date.now() + MAX_TIME_SEC * 1000;

  try {
    for (let i = 0; i < iterations; i++) {
      func();

      // checa timeout a cada 1000 iterações
      if (i % 1000 === 0 && Date.now() > deadline) {
        logger.write(`  ${label.padEnd(12)} TIMEOUT! (>${MAX_TIME_SEC}s) ✗`);
        return;
      }

      // checa RAM a cada 1000 iterações
      if (i % 1000 === 0 && getRamMB() > MAX_RAM_MB) {
        logger.write(`  ${label.padEnd(12)} RAM excedida! ✗`);
        return;
      }
    }

    const t1    = performance.now();
    const after = process.memoryUsage();
    const ms    = t1 - t0;
    const heapDelta = (after.heapUsed - before.heapUsed) / 1024;
    const ram   = getRamMB();

    logger.write(
      `  ${label.padEnd(12)} Tempo: ${ms.toFixed(1).padStart(8)} ms  |` +
      `  Heap Δ: ${heapDelta.toFixed(1).padStart(10)} KB  |` +
      `  RAM processo: ${ram.toFixed(0)}MB`
    );
  } catch (e) {
    if (e instanceof RangeError) {
      logger.write(`  ${label.padEnd(12)} STACK OVERFLOW! ✗`);
    } else {
      logger.write(`  ${label.padEnd(12)} ERRO: ${e.message} ✗`);
    }
  }
}

function overflowTest(logger, label, func, resultFn) {
  process.stdout.write(`  ${label} ... `);
  logger.stream.write(`  ${label} ... `);
  checkRam(label, logger);

  const deadline = Date.now() + MAX_TIME_SEC * 1000;

  try {
    const monitorInterval = setInterval(() => {
      if (Date.now() > deadline || getRamMB() > MAX_RAM_MB) {
        clearInterval(monitorInterval);
        logger.write("TIMEOUT ou RAM excedida! ✗");
        process.exit(1);
      }
    }, 200);

    const result = func();
    clearInterval(monitorInterval);
    logger.write(`OK! (${resultFn(result)})`);
  } catch (e) {
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

logger.write(`NOTA: Node.js tem TCO apenas em strict mode e condições específicas.
  Na prática é não confiável e desabilitado no V8.
  Normal    = recursão real (empilha frames)
  Loop/Tail = while/for equivalente ao tail call
  BigInt    = inteiros de precisão arbitrária (nativo no Node 10+)\n`);

// TESTE 1
logger.section("TESTE 1: Factorial n=10 — 500.000 iterações (sem bignum)");
runBench(logger, "Normal   ", () => factorialNormal(10n), 500_000);
runBench(logger, "Loop/Tail", () => factorialTail(10n),   500_000);

// TESTE 2
logger.section("TESTE 2: Factorial n=1000 — 10.000 iterações (com bignum)");
runBench(logger, "Normal   ", () => factorialNormal(1000n), 10_000);
runBench(logger, "Loop/Tail", () => factorialTail(1000n),   10_000);

// TESTE 3
logger.section("TESTE 3: Fibonacci n=30 — 100 iterações (exponencial vs linear)");
runBench(logger, "Normal   ", () => fibNormal(30), 100);
runBench(logger, "Loop/Tail", () => fibTail(30),   100);

// TESTE 4
logger.section("TESTE 4: Soma de lista 100.000 elementos — 200 iterações");
const bigList = Array.from({ length: 100_000 }, (_, i) => i);
runBench(logger, "Normal   ", () => sumNormal(bigList), 200);
runBench(logger, "Loop/Tail", () => sumTail(bigList),   200);

// TESTE 5
logger.section("TESTE 5: Limite da stack");

overflowTest(logger, "Loop  factorial 100k ",
  () => factorialTail(100_000n),
  r  => `${r.toString().length} dígitos`);

overflowTest(logger, "Normal factorial 15k ",
  () => factorialNormal(15_000n),    // estoura antes de 15k
  r  => `${r.toString().length} dígitos`);

const bigList2 = Array.from({ length: 1_000_000 }, (_, i) => i);
overflowTest(logger, "Loop  soma lista 1M  ",
  () => sumTail(bigList2),
  r  => `soma = ${r}`);

overflowTest(logger, "Normal soma lista 10k",
  () => sumNormal(Array.from({ length: 10_000 }, (_, i) => i)),
  r  => `soma = ${r}`);

logger.close();