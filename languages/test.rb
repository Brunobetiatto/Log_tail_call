# bench.rb
# Rodar com: ruby bench.rb

require 'objspace'
require 'timeout'

# ============================================================
# REPRODUTIBILIDADE
# ============================================================
SEED = 42
srand(SEED)

# ============================================================
# CPU FREQ
# ============================================================
def cpu_freq_ghz
  output = File.read('/proc/cpuinfo').match(/cpu MHz\s*:\s*([\d.]+)/)&.captures&.first
  output ? output.to_f / 1000.0 : 2.0
rescue
  2.0
end

# ============================================================
# Habilita TCO (precisa estar antes das definicoes)
# ============================================================
RubyVM::InstructionSequence.compile_option = {
  tailcall_optimization: true,
  trace_instruction: false
}

# ============================================================
# LIMITES DE SEGURANCA
# ============================================================
MAX_TIME_SEC   = 60

QUICK          = ENV['BENCH_QUICK'] == '1'
RUNS_PER_POINT = QUICK ? 2 : 10

# ============================================================
# SWEEP DE ITERACOES (escala log)
# ============================================================
if QUICK
  SWEEP_CHEAP            = [10_000, 100_000]
  SWEEP_FACTORIAL_BIGNUM = [200, 1_000]
  puts "[BENCH_QUICK=1] usando sweep reduzido e 2 runs por ponto"
else
  SWEEP_CHEAP            = [10_000, 30_000, 100_000, 300_000, 1_000_000]
  SWEEP_FACTORIAL_BIGNUM = [200, 500, 1_000, 3_000, 10_000]
end

# ============================================================
# LOGGER (Formato CSV)
# ============================================================
class BenchLogger
  def initialize(filename = "bench_results_ruby.csv")
    @file = File.open(filename, "w", encoding: "utf-8")
    @filename = filename
  end

  def write(line)
    puts line
    @file.puts line
    @file.flush
  end

  def start
    write("Data,Algoritmo,Implementacao,N,Iteracoes,Run,Ciclos_CPU,Ciclos_por_iter,Memoria_KB,Freq_GHz")
  end

  def close
    @file.close
    puts "\nLog salvo em: #{@filename}"
  end
end

# ============================================================
# Algorithm 1 -- Factorial
# ============================================================
def factorial_normal(n)
  return 1 if n == 0
  n * factorial_normal(n - 1)
end

def factorial_tail(n, acc = 1)
  return acc if n == 0
  factorial_tail(n - 1, n * acc)
end

def factorial_loop(n)
  acc = 1
  while n > 0
    acc *= n
    n -= 1
  end
  acc
end

# ============================================================
# Algorithm 2 -- Mutually recursive even/odd
# ============================================================
def even_normal(n)
  return true if n == 0
  odd_normal(n - 1)
end

def odd_normal(n)
  return false if n == 0
  even_normal(n - 1)
end

def is_even(n)
  return true if n == 0
  is_odd(n - 1)
end

def is_odd(n)
  return false if n == 0
  is_even(n - 1)
end

def is_even_loop(n)
  while true
    return true if n == 0
    n -= 1
    return false if n == 0
    n -= 1
  end
end

def is_odd_loop(n)
  while true
    return false if n == 0
    n -= 1
    return true if n == 0
    n -= 1
  end
end

# ============================================================
# Algorithm 3 -- Three-state machine
# ============================================================
def state_a_normal(k)
  return :finished if k == 0
  state_b_normal(k - 1)
end

def state_b_normal(k)
  return :finished if k == 0
  state_c_normal(k - 1)
end

def state_c_normal(k)
  return :finished if k == 0
  state_a_normal(k - 1)
end

def state_a(k)
  return :finished if k == 0
  state_b(k - 1)
end

def state_b(k)
  return :finished if k == 0
  state_c(k - 1)
end

def state_c(k)
  return :finished if k == 0
  state_a(k - 1)
end

def state_a_loop(k)
  state = :A
  while true
    return :finished if k == 0
    k -= 1
    case state
    when :A then state = :B
    when :B then state = :C
    when :C then state = :A
    end
  end
end

# ============================================================
# BENCHMARK ENGINE
# ============================================================
def run_single(logger, algo, impl, n, iterations, run_id, &block)
  freq_ghz   = cpu_freq_ghz
  GC.start
  mem_before = ObjectSpace.memsize_of_all / 1024.0
  cpu_before = Process.clock_gettime(Process::CLOCK_PROCESS_CPUTIME_ID)
  timestamp  = Time.now.strftime("%Y-%m-%d %H:%M:%S")

  error_msg = nil
  begin
    Timeout.timeout(MAX_TIME_SEC) do
      iterations.times { block.call }
    end
  rescue SystemStackError
    error_msg = "STACK OVERFLOW"
  rescue Timeout::Error
    error_msg = "TIMEOUT"
  rescue StandardError => e
    error_msg = "ERRO: #{e.message}"
  end

  if error_msg
    logger.write(sprintf("\"%s\",\"%s\",\"%s\",%d,%d,%d,\"%s\",\"\",\"\",%.4f",
                        timestamp, algo, impl, n, iterations, run_id, error_msg, freq_ghz))
    return error_msg
  end

  cpu_after = Process.clock_gettime(Process::CLOCK_PROCESS_CPUTIME_ID)
  GC.start
  mem_after = ObjectSpace.memsize_of_all / 1024.0
  mem_kb = mem_after - mem_before
  mem_kb = 0.0 if mem_kb < 0

  cpu_seconds     = cpu_after - cpu_before
  cycles          = cpu_seconds * freq_ghz * 1e9
  cycles_per_iter = cycles / iterations

  logger.write(sprintf("\"%s\",\"%s\",\"%s\",%d,%d,%d,%.0f,%.2f,%.1f,%.4f",
                      timestamp, algo, impl, n, iterations, run_id, cycles, cycles_per_iter, mem_kb, freq_ghz))
  "OK"
end

def run_sweep(logger, algo, impl, n, sweep, &block)
  consecutive_fails = 0
  sweep.each do |iter_count|
    if consecutive_fails >= 2
      (1..RUNS_PER_POINT).each do |r|
        ts = Time.now.strftime("%Y-%m-%d %H:%M:%S")
        logger.write(sprintf("\"%s\",\"%s\",\"%s\",%d,%d,%d,\"SKIPPED\",\"\",\"\",0.0000", ts, algo, impl, n, iter_count, r))
      end
      next
    end

    fails = 0
    (1..RUNS_PER_POINT).each do |r|
      status = run_single(logger, algo, impl, n, iter_count, r, &block)
      if ["TIMEOUT", "STACK OVERFLOW"].include?(status)
        fails += 1
        if fails >= 2 && r < RUNS_PER_POINT
          ((r + 1)..RUNS_PER_POINT).each do |skip|
            ts = Time.now.strftime("%Y-%m-%d %H:%M:%S")
            logger.write(sprintf("\"%s\",\"%s\",\"%s\",%d,%d,%d,\"SKIPPED\",\"\",\"\",0.0000", ts, algo, impl, n, iter_count, skip))
          end
          break
        end
      end
    end
    if fails >= (RUNS_PER_POINT / 2.0).ceil
      consecutive_fails += 1
    else
      consecutive_fails = 0
    end
  end
end

# ============================================================
# TESTES
# ============================================================
logger = BenchLogger.new
logger.start

# ----- Factorial -----
run_sweep(logger, "Factorial", "Normal",     10,   SWEEP_CHEAP)            { factorial_normal(10) }
run_sweep(logger, "Factorial", "Tail (TCO)", 10,   SWEEP_CHEAP)            { factorial_tail(10) }
run_sweep(logger, "Factorial", "Loop",       10,   SWEEP_CHEAP)            { factorial_loop(10) }
run_sweep(logger, "Factorial", "Normal",     1000, SWEEP_FACTORIAL_BIGNUM) { factorial_normal(1000) }
run_sweep(logger, "Factorial", "Tail (TCO)", 1000, SWEEP_FACTORIAL_BIGNUM) { factorial_tail(1000) }
run_sweep(logger, "Factorial", "Loop",       1000, SWEEP_FACTORIAL_BIGNUM) { factorial_loop(1000) }

# ----- Mutually Recursive -----
run_sweep(logger, "Mutually Rec (Even)", "Normal",     1000, SWEEP_CHEAP) { even_normal(1000) }
run_sweep(logger, "Mutually Rec (Even)", "Tail (TCO)", 1000, SWEEP_CHEAP) { is_even(1000) }
run_sweep(logger, "Mutually Rec (Even)", "Loop",       1000, SWEEP_CHEAP) { is_even_loop(1000) }

run_sweep(logger, "Mutually Rec (Odd)", "Normal",     1000, SWEEP_CHEAP) { odd_normal(1000) }
run_sweep(logger, "Mutually Rec (Odd)", "Tail (TCO)", 1000, SWEEP_CHEAP) { is_odd(1000) }
run_sweep(logger, "Mutually Rec (Odd)", "Loop",       1000, SWEEP_CHEAP) { is_odd_loop(1000) }

# ----- State Machine -----
run_sweep(logger, "State Machine", "Normal",     999, SWEEP_CHEAP) { state_a_normal(999) }
run_sweep(logger, "State Machine", "Tail (TCO)", 999, SWEEP_CHEAP) { state_a(999) }
run_sweep(logger, "State Machine", "Loop",       999, SWEEP_CHEAP) { state_a_loop(999) }

logger.close
