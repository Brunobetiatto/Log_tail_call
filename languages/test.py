# bench.py
# Rodar com: python3 bench.py

import time
import gc
import sys
import random
import tracemalloc
import threading
import os
import psutil
from datetime import datetime

# ============================================================
# REPRODUTIBILIDADE
# ============================================================
SEED = 42
random.seed(SEED)

# ============================================================
# LIMITES DE SEGURANCA
# ============================================================
MAX_RAM_MB   = 2000
MAX_CPU_PCT  = 80
MAX_TIME_SEC = 60

QUICK = os.environ.get('BENCH_QUICK', '0') == '1'
RUNS_PER_POINT = 2 if QUICK else 10

sys.setrecursionlimit(100000)
sys.set_int_max_str_digits(0)

# ============================================================
# SWEEP DE ITERACOES (escala log)
# ============================================================
if QUICK:
    SWEEP_CHEAP            = [10_000, 100_000]
    SWEEP_FACTORIAL_BIGNUM = [200, 1_000]
    print("[BENCH_QUICK=1] usando sweep reduzido e 2 runs por ponto")
else:
    SWEEP_CHEAP            = [10_000, 30_000, 100_000, 300_000, 1_000_000]
    SWEEP_FACTORIAL_BIGNUM = [200, 500, 1_000, 3_000, 10_000]

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
        self.write("Data,Algoritmo,Implementacao,N,Iteracoes,Run,Ciclos_CPU,Ciclos_por_iter,Memoria_KB,Freq_GHz")

    def close(self):
        self.file.close()
        print(f"\nLog salvo em: {self.filename}")

# ============================================================
# CPU FREQ
# ============================================================
def cpu_freq_ghz():
    try:
        freq = psutil.cpu_freq()
        if freq and freq.current:
            return freq.current / 1000.0
    except Exception:
        pass
    return 2.0

# ============================================================
# Algorithm 1 -- Factorial with accumulator (self-tail)
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
# Algorithm 2 -- Mutually recursive even/odd
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
# Algorithm 3 -- Three-state machine (A -> B -> C -> A)
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
# BENCHMARK ENGINE COM PROTECOES
# ============================================================
def run_single(algo, impl, n, iterations, run_id, func, freq_ghz):
    result_holder = [None]
    error_holder  = [None]
    done_event    = threading.Event()

    def worker():
        try:
            gc.collect()
            tracemalloc.start()
            t0 = time.process_time()
            for _ in range(iterations):
                func()
                if monitor.exceeded:
                    error_holder[0] = monitor.reason
                    return
            t1 = time.process_time()
            _, peak = tracemalloc.get_traced_memory()
            tracemalloc.stop()
            cpu_seconds = t1 - t0
            cycles = cpu_seconds * freq_ghz * 1e9
            result_holder[0] = (cycles, peak / 1024.0)
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

    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

    if not finished:
        tracemalloc.stop()
        return f'"{timestamp}","{algo}","{impl}",{n},{iterations},{run_id},"TIMEOUT","","",{freq_ghz:.4f}'

    if error_holder[0]:
        return f'"{timestamp}","{algo}","{impl}",{n},{iterations},{run_id},"{error_holder[0]}","","",{freq_ghz:.4f}'

    cycles_total, mem_kb = result_holder[0]
    cycles_per_iter = cycles_total / iterations
    return f'"{timestamp}","{algo}","{impl}",{n},{iterations},{run_id},{cycles_total:.0f},{cycles_per_iter:.2f},{mem_kb:.1f},{freq_ghz:.4f}'


def run_sweep(logger, algo, impl, n, sweep, func_factory):
    """Roda 10 runs para cada iter_count no sweep e loga cada um."""
    consecutive_timeouts = 0
    for iter_count in sweep:
        # Se ja deu 2 timeouts seguidos, pula o resto do sweep (ja sabemos que vai estourar)
        if consecutive_timeouts >= 2:
            for run_id in range(1, RUNS_PER_POINT + 1):
                ts = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
                logger.write(f'"{ts}","{algo}","{impl}",{n},{iter_count},{run_id},"SKIPPED","","",0.0000')
            continue

        timeouts_at_this_point = 0
        for run_id in range(1, RUNS_PER_POINT + 1):
            freq = cpu_freq_ghz()
            line = run_single(algo, impl, n, iter_count, run_id, func_factory(), freq)
            logger.write(line)
            if '"TIMEOUT"' in line or '"STACK OVERFLOW"' in line:
                timeouts_at_this_point += 1
                # Se o primeiro run ja deu erro, nao adianta repetir 10x
                if timeouts_at_this_point >= 2 and run_id < RUNS_PER_POINT:
                    for skip_id in range(run_id + 1, RUNS_PER_POINT + 1):
                        ts = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
                        logger.write(f'"{ts}","{algo}","{impl}",{n},{iter_count},{skip_id},"SKIPPED","","",0.0000')
                    break

        if timeouts_at_this_point >= RUNS_PER_POINT // 2:
            consecutive_timeouts += 1
        else:
            consecutive_timeouts = 0


# ============================================================
# TESTES
# ============================================================
logger = BenchLogger()
logger.start()

# ----- Factorial -----
run_sweep(logger, "Factorial", "Normal",     10,   SWEEP_CHEAP,            lambda: lambda: factorial_normal(10))
run_sweep(logger, "Factorial", "Loop/Tail",  10,   SWEEP_CHEAP,            lambda: lambda: factorial_tail(10))
run_sweep(logger, "Factorial", "Normal",     1000, SWEEP_FACTORIAL_BIGNUM, lambda: lambda: factorial_normal(1000))
run_sweep(logger, "Factorial", "Loop/Tail",  1000, SWEEP_FACTORIAL_BIGNUM, lambda: lambda: factorial_tail(1000))

# ----- Mutually Recursive -----
run_sweep(logger, "Mutually Rec (Even)", "Normal", 1000, SWEEP_CHEAP, lambda: lambda: even_normal(1000))
run_sweep(logger, "Mutually Rec (Even)", "Loop",   1000, SWEEP_CHEAP, lambda: lambda: is_even_loop(1000))

run_sweep(logger, "Mutually Rec (Odd)", "Normal", 1000, SWEEP_CHEAP, lambda: lambda: odd_normal(1000))
run_sweep(logger, "Mutually Rec (Odd)", "Loop",   1000, SWEEP_CHEAP, lambda: lambda: is_even_loop(1000))

# ----- State Machine -----
run_sweep(logger, "State Machine", "Normal", 999, SWEEP_CHEAP, lambda: lambda: state_a_normal(999))
run_sweep(logger, "State Machine", "Loop",   999, SWEEP_CHEAP, lambda: lambda: state_a_loop(999))

logger.close()
