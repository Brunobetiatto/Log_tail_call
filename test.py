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
# LIMITES DE SEGURANÇA — ajuste conforme sua máquina
# ============================================================
MAX_RAM_MB     = 2000    # interrompe se processo usar mais que 2000MB
MAX_CPU_PCT    = 80     # avisa se CPU passar de 80%
MAX_TIME_SEC   = 120     # timeout por benchmark (segundos)

sys.setrecursionlimit(100000)
sys.set_int_max_str_digits(0) 

# ============================================================
# MONITOR DE RECURSOS — roda em thread separada
# ============================================================
class ResourceMonitor:
    def __init__(self):
        self.process   = psutil.Process(os.getpid())
        self.running   = False
        self.exceeded  = False
        self.reason    = ""
        self._thread   = None

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
                    # força saída do processo principal
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
        self.write("Benchmark Tail Call vs Normal — Python")
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
# IMPLEMENTAÇÕES
# ============================================================
def factorial_normal(n):
    if n == 0:
        return 1
    return n * factorial_normal(n - 1)

def factorial_tail(n):
    acc = 1
    while n > 0:
        acc *= n
        n -= 1
    return acc

def fib_normal(n):
    if n < 2:
        return n
    return fib_normal(n - 1) + fib_normal(n - 2)

def fib_tail(n):
    a, b = 0, 1
    for _ in range(n):
        a, b = b, a + b
    return a

def sum_normal(lst, i=0):
    if i >= len(lst):
        return 0
    return lst[i] + sum_normal(lst, i + 1)

def sum_tail(lst):
    acc = 0
    for x in lst:
        acc += x
    return acc

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
                # checa RAM a cada iteração
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
        logger.write(f"  {label:12s} TIMEOUT! (>{MAX_TIME_SEC}s) ✗")
        return

    if error_holder[0]:
        logger.write(f"  {label:12s} ERRO: {error_holder[0]} ✗")
        return

    ms, mem_kb = result_holder[0]
    ram_atual  = psutil.Process(os.getpid()).memory_info().rss / 1024 / 1024
    logger.write(
        f"  {label:12s} Tempo: {ms:8.1f} ms  |"
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
  Loop/Tail = while/for equivalente ao tail call\n""")

logger.section("TESTE 1: Factorial n=10 — 500.000 iterações (sem bignum)")
run_bench(logger, "Normal   ", lambda: factorial_normal(10), 500_000)
run_bench(logger, "Loop/Tail", lambda: factorial_tail(10),   500_000)

logger.section("TESTE 2: Factorial n=1000 — 10.000 iterações (com bignum)")
run_bench(logger, "Normal   ", lambda: factorial_normal(1000), 10_000)
run_bench(logger, "Loop/Tail", lambda: factorial_tail(1000),   10_000)

logger.section("TESTE 3: Fibonacci n=30 — 100 iterações (exponencial vs linear)")
run_bench(logger, "Normal   ", lambda: fib_normal(30), 100)
run_bench(logger, "Loop/Tail", lambda: fib_tail(30),   100)

logger.section("TESTE 4: Soma de lista 100.000 elementos — 200 iterações")
big_list = list(range(100_000))
run_bench(logger, "Normal   ", lambda: sum_normal(big_list), 200)
run_bench(logger, "Loop/Tail", lambda: sum_tail(big_list),   200)

logger.section("TESTE 5: Limite da stack")
overflow_test(logger, "Loop  factorial 100k ",
              lambda: factorial_tail(100_000),
              lambda r: f"{len(str(r))} dígitos")

overflow_test(logger, "Normal factorial 10k ",
              lambda: factorial_normal(10_000),
              lambda r: f"{len(str(r))} dígitos")

big_list_2 = list(range(1_000_000))
overflow_test(logger, "Loop  soma lista 1M  ",
              lambda: sum_tail(big_list_2),
              lambda r: f"soma = {r}")

overflow_test(logger, "Normal soma lista 10k",
              lambda: sum_normal(list(range(10_000))),
              lambda r: f"soma = {r}")

logger.close()