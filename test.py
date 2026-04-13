# bench.py
# Rodar com: python3 bench.py

import time
import gc
import sys
import tracemalloc
import threading
import os
import psutil
from datetime import datetime

# ============================================================
# LIMITES DE SEGURANÇA
# ============================================================
MAX_RAM_MB   = 2000
MAX_CPU_PCT  = 80
MAX_TIME_SEC = 120

sys.setrecursionlimit(100000)
sys.set_int_max_str_digits(0)

# ============================================================
# MONITOR DE RECURSOS
# ============================================================
class ResourceMonitor:
    def __init__(self):
        self.process  = psutil.Process(os.getpid())
        self.running  = False
        self.exceeded = False
        self.reason   = ""
        self._thread  = None

    def start(self):
        self.running  = False
        self.exceeded = False
        self.reason   = ""
        self._thread  = threading.Thread(target=self._loop, daemon=True)
        self._thread.start()

    def stop(self):
        self.running = False

    def _loop(self):
        self.running = True
        while self.running:
            try:
                ram_mb  = self.process.memory_info().rss / 1024 / 1024
                cpu_pct = self.process.cpu_percent(interval=0.1)
                if ram_mb > MAX_RAM_MB:
                    self.exceeded = True
                    self.reason   = f"RAM excedida: {ram_mb:.0f}MB > {MAX_RAM_MB}MB"
                    self.running  = False
                    os.kill(os.getpid(), 9)
                if cpu_pct > MAX_CPU_PCT:
                    self.reason = f"CPU alta: {cpu_pct:.0f}%"
            except Exception:
                pass
            time.sleep(0.1)

monitor = ResourceMonitor()

# ============================================================
# LOGGER
# ============================================================
class BenchLogger:
    def __init__(self, filename="bench_results_python.log"):
        self.file     = open(filename, "w", encoding="utf-8")
        self.filename = filename

    def write(self, line=""):
        print(line)
        self.file.write(line + "\n")
        self.file.flush()

    def start(self):
        ram_total = psutil.virtual_memory().total / 1024 / 1024
        ram_avail = psutil.virtual_memory().available / 1024 / 1024
        cpu_count = psutil.cpu_count()
        self.write("========================================")
        self.write("Benchmark — Recursão Tail Call em Python")
        self.write(str(datetime.utcnow()))
        self.write(f"RAM total: {ram_total:.0f}MB  |  Disponível: {ram_avail:.0f}MB  |  CPUs: {cpu_count}")
        self.write(f"Limites: RAM<{MAX_RAM_MB}MB  |  CPU<{MAX_CPU_PCT}%  |  Timeout<{MAX_TIME_SEC}s")
        self.write("========================================\n")

    def close(self):
        self.write("\n========================================")
        self.write("Fim do benchmark")
        self.write(str(datetime.utcnow()))
        self.write("========================================")
        self.file.close()
        print(f"\nLog salvo em: {self.filename}")

    def section(self, title):
        self.write(f"\n{title}")
        self.write("-" * len(title))

# ============================================================
# Algorithm 1 — Factorial with accumulator (self-tail)
# ============================================================

# Sem tail call
def factorial_normal(n):
    if n == 0:
        return 1
    return n * factorial_normal(n - 1)

# Algorithm 1: FACTORIAL(n, acc)
#   if n = 0 then return acc
#   else return FACTORIAL(n − 1, n × acc)
# Python não tem TCO — simulamos com loop
def factorial_tail(n):
    acc = 1
    while n > 0:
        acc *= n
        n -= 1
    return acc

# ============================================================
# Algorithm 2 — Mutually recursive even/odd
# ============================================================

# Versão normal — mutuamente recursiva
def even_normal(n):
    if n == 0:
        return True
    return odd_normal(n - 1)

def odd_normal(n):
    if n == 0:
        return False
    return even_normal(n - 1)

# Algorithm 2: ISEVEN e ISODD
#   ISEVEN(n): if n=0 → true,  else → ISODD(n−1)
#   ISODD(n):  if n=0 → false, else → ISEVEN(n−1)
# Loop equivalente — Python não tem TCO mútuo
def is_even_loop(n):
    while True:
        if n == 0: return True
        n -= 1
        if n == 0: return False
        n -= 1

# ============================================================
# Algorithm 3 — Three-state machine (A → B → C → A)
# ============================================================

# Versão normal — mutuamente recursiva
def state_a_normal(k):
    if k == 0: return "finished"
    return state_b_normal(k - 1)

def state_b_normal(k):
    if k == 0: return "finished"
    return state_c_normal(k - 1)

def state_c_normal(k):
    if k == 0: return "finished"
    return state_a_normal(k - 1)

# Algorithm 3: STATEA → STATEB → STATEC → STATEA
#   Loop equivalente — único jeito de não estoura stack em Python
def state_a_loop(k):
    state = "A"
    while True:
        if k == 0: return "finished"
        k -= 1
        if   state == "A": state = "B"
        elif state == "B": state = "C"
        else:              state = "A"

# ============================================================
# BENCHMARK ENGINE COM PROTEÇÕES
# ============================================================
def run_bench(logger, label, func, iterations):
    result_holder = [None]
    error_holder  = [None]
    done_event    = threading.Event()

    def worker():
        try:
            gc.collect()
            tracemalloc.start()
            t0 = time.perf_counter()
            for _ in range(iterations):
                func()
                if monitor.exceeded:
                    error_holder[0] = monitor.reason
                    return
            t1 = time.perf_counter()
            _, peak = tracemalloc.get_traced_memory()
            tracemalloc.stop()
            result_holder[0] = ((t1 - t0) * 1000, peak / 1024.0)
        except RecursionError:
            error_holder[0] = "RecursionError (stack overflow)"
        except MemoryError:
            error_holder[0] = "MemoryError (RAM esgotada)"
        except Exception as e:
            error_holder[0] = str(e)
        finally:
            done_event.set()

    monitor.start()
    t = threading.Thread(target=worker, daemon=True)
    t.start()
    finished = done_event.wait(timeout=MAX_TIME_SEC)
    monitor.stop()

    if not finished:
        tracemalloc.stop()
        logger.write(f"  {label:14s} TIMEOUT! (>{MAX_TIME_SEC}s) ✗")
        return
    if error_holder[0]:
        logger.write(f"  {label:14s} ERRO: {error_holder[0]} ✗")
        return

    ms, mem_kb = result_holder[0]
    ram_atual  = psutil.Process(os.getpid()).memory_info().rss / 1024 / 1024
    logger.write(
        f"  {label:14s} Tempo: {ms:8.1f} ms  |"
        f"  Mem pico: {mem_kb:10.1f} KB  |"
        f"  RAM processo: {ram_atual:.0f}MB"
    )

def overflow_test(logger, label, func, result_fn):
    sys.stdout.write(f"  {label} ... ")
    sys.stdout.flush()
    logger.file.write(f"  {label} ... ")

    result_holder = [None]
    error_holder  = [None]
    done_event    = threading.Event()

    def worker():
        try:
            result_holder[0] = func()
        except RecursionError:
            error_holder[0] = "STACK OVERFLOW! ✗  (RecursionError)"
        except MemoryError:
            error_holder[0] = "MEMORY ERROR! ✗"
        except Exception as e:
            error_holder[0] = str(e)
        finally:
            done_event.set()

    monitor.start()
    t = threading.Thread(target=worker, daemon=True)
    t.start()
    finished = done_event.wait(timeout=MAX_TIME_SEC)
    monitor.stop()

    if not finished:
        logger.write(f"TIMEOUT! (>{MAX_TIME_SEC}s) ✗")
        return
    if error_holder[0]:
        logger.write(error_holder[0])
        return
    logger.write(f"OK! ({result_fn(result_holder[0])})")

# ============================================================
# TESTES
# ============================================================
logger = BenchLogger()
logger.start()

logger.write("""NOTA: Python não tem TCO (decisão deliberada do Guido van Rossum).
  Loop/Tail = while equivalente ao tail call das outras linguagens\n""")

# ----------------------------------------------------------
# TESTE 1 — Algorithm 1: Factorial with accumulator
# ----------------------------------------------------------
logger.section("TESTE 1: Algorithm 1 — Factorial (self-tail)")

logger.write("  n=10, 500.000 iterações (sem bignum)")
run_bench(logger, "Normal      ", lambda: factorial_normal(10), 500_000)
run_bench(logger, "Loop/Tail   ", lambda: factorial_tail(10),   500_000)

logger.write("")
logger.write("  n=1000, 10.000 iterações (com bignum)")
run_bench(logger, "Normal      ", lambda: factorial_normal(1000), 10_000)
run_bench(logger, "Loop/Tail   ", lambda: factorial_tail(1000),   10_000)


# ----------------------------------------------------------
# TESTE 2 — Algorithm 2: Mutually recursive even/odd
# ----------------------------------------------------------
logger.section("TESTE 2: Algorithm 2 — Mutually recursive even/odd")

logger.write("  n=1000, 500.000 iterações")
run_bench(logger, "Normal even ", lambda: even_normal(1_000), 500_000)
run_bench(logger, "Loop   even ", lambda: is_even_loop(1_000), 500_000)
run_bench(logger, "Normal odd  ", lambda: odd_normal(1_000),  500_000)
run_bench(logger, "Loop   odd  ", lambda: is_even_loop(1_000),  500_000)


# ----------------------------------------------------------
# TESTE 3 — Algorithm 3: Three-state machine A→B→C→A
# ----------------------------------------------------------
logger.section("TESTE 3: Algorithm 3 — Three-state machine (A→B→C→A)")

logger.write("  k=999 (múltiplo de 3), 500.000 iterações")
run_bench(logger, "Normal A→B→C", lambda: state_a_normal(999), 500_000)
run_bench(logger, "Loop   A→B→C", lambda: state_a_loop(999),   500_000)


logger.close()