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
                if ram_mb > MAX_RAM_MB:
                    self.exceeded = True
                    self.reason   = "OOM (RAM Excedida)"
                    self.running  = False
                    os.kill(os.getpid(), 9)
            except Exception:
                pass
            time.sleep(0.1)

monitor = ResourceMonitor()

# ============================================================
# LOGGER (Formato CSV)
# ============================================================
class BenchLogger:
    def __init__(self, filename="bench_results_python.csv"):
        self.file     = open(filename, "w", encoding="utf-8")
        self.filename = filename

    def write(self, line=""):
        print(line)
        self.file.write(line + "\n")
        self.file.flush()

    def start(self):
        # Escreve o cabeçalho das colunas do CSV
        self.write("Data,Algoritmo,Implementacao,N,Iteracoes,Tempo_ms,Memoria_KB")

    def close(self):
        self.file.close()
        print(f"\nLog salvo em: {self.filename}")

# ============================================================
# Algorithm 1 — Factorial with accumulator (self-tail)
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

# ============================================================
# Algorithm 2 — Mutually recursive even/odd
# ============================================================

def even_normal(n):
    if n == 0:
        return True
    return odd_normal(n - 1)

def odd_normal(n):
    if n == 0:
        return False
    return even_normal(n - 1)

def is_even_loop(n):
    while True:
        if n == 0: return True
        n -= 1
        if n == 0: return False
        n -= 1

# ============================================================
# Algorithm 3 — Three-state machine (A → B → C → A)
# ============================================================

def state_a_normal(k):
    if k == 0: return "finished"
    return state_b_normal(k - 1)

def state_b_normal(k):
    if k == 0: return "finished"
    return state_c_normal(k - 1)

def state_c_normal(k):
    if k == 0: return "finished"
    return state_a_normal(k - 1)

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
def run_bench(logger, algo, impl, n, iterations, func):
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
            error_holder[0] = "STACK OVERFLOW"
        except MemoryError:
            error_holder[0] = "MEMORY ERROR"
        except Exception as e:
            error_holder[0] = f"ERRO: {str(e)}"
        finally:
            done_event.set()

    monitor.start()
    t = threading.Thread(target=worker, daemon=True)
    t.start()
    finished = done_event.wait(timeout=MAX_TIME_SEC)
    monitor.stop()

    # Formatação da data atual para o CSV
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

    # Se a thread não terminou a tempo
    if not finished:
        tracemalloc.stop()
        logger.write(f'"{timestamp}","{algo}","{impl}",{n},{iterations},"TIMEOUT",""')
        return
    
    # Se houve estouro de pilha ou memória
    if error_holder[0]:
        logger.write(f'"{timestamp}","{algo}","{impl}",{n},{iterations},"{error_holder[0]}",""')
        return

    # Execução bem-sucedida
    ms, mem_kb = result_holder[0]
    logger.write(f'"{timestamp}","{algo}","{impl}",{n},{iterations},{ms:.1f},{mem_kb:.1f}')


# ============================================================
# TESTES
# ============================================================
logger = BenchLogger()
logger.start()

# ----------------------------------------------------------
# TESTE 1 — Algorithm 1: Factorial with accumulator
# ----------------------------------------------------------
# n=10, 500.000 iterações (sem bignum)
run_bench(logger, "Factorial", "Normal", 10, 500_000, lambda: factorial_normal(10))
run_bench(logger, "Factorial", "Loop/Tail", 10, 500_000, lambda: factorial_tail(10))

# n=1000, 10.000 iterações (com bignum)
run_bench(logger, "Factorial", "Normal", 1000, 10_000, lambda: factorial_normal(1000))
run_bench(logger, "Factorial", "Loop/Tail", 1000, 10_000, lambda: factorial_tail(1000))


# ----------------------------------------------------------
# TESTE 2 — Algorithm 2: Mutually recursive even/odd
# ----------------------------------------------------------
# n=1000, 500.000 iterações
run_bench(logger, "Mutually Rec (Even)", "Normal", 1000, 500_000, lambda: even_normal(1_000))
run_bench(logger, "Mutually Rec (Even)", "Loop", 1000, 500_000, lambda: is_even_loop(1_000))

run_bench(logger, "Mutually Rec (Odd)", "Normal", 1000, 500_000, lambda: odd_normal(1_000))
run_bench(logger, "Mutually Rec (Odd)", "Loop", 1000, 500_000, lambda: is_even_loop(1_000))


# ----------------------------------------------------------
# TESTE 3 — Algorithm 3: Three-state machine A→B→C→A
# ----------------------------------------------------------
# k=999 (múltiplo de 3), 500.000 iterações
run_bench(logger, "State Machine", "Normal", 999, 500_000, lambda: state_a_normal(999))
run_bench(logger, "State Machine", "Loop", 999, 500_000, lambda: state_a_loop(999))

logger.close()