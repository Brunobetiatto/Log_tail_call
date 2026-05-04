# bench.rb
# Rodar com: ruby bench.rb

require 'objspace'
require 'timeout'

# ============================================================
# O "BOTÃO SECRETO" DO RUBY
# ============================================================
# Ativa a Otimização de Chamada de Cauda (TCO) na Máquina Virtual.
# Precisa ser definida ANTES dos métodos serem declarados no arquivo.
RubyVM::InstructionSequence.compile_option = {
  tailcall_optimization: true,
  trace_instruction: false
}

# ============================================================
# LIMITES DE SEGURANÇA
# ============================================================
MAX_TIME_SEC = 120

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
    # Escreve o cabeçalho das colunas do CSV
    write("Data,Algoritmo,Implementacao,N,Iteracoes,Tempo_ms,Memoria_KB")
  end

  def close
    @file.close
    puts "\nLog salvo em: #{@filename}"
  end
end

# ============================================================
# Algorithm 1 — Factorial with accumulator (self-tail)
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
# Algorithm 2 — Mutually recursive even/odd
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

# ============================================================
# Algorithm 3 — Three-state machine (A → B → C → A)
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
# BENCHMARK ENGINE COM PROTEÇÕES
# ============================================================
def run_bench(logger, algo, impl, n, iterations, &block)
  GC.start
  mem_before = ObjectSpace.memsize_of_all / 1024.0

  t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  timestamp = Time.now.strftime("%Y-%m-%d %H:%M:%S")

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
    logger.write("\"#{timestamp}\",\"#{algo}\",\"#{impl}\",#{n},#{iterations},\"#{error_msg}\",\"\"")
    return
  end

  t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  
  # Força o Garbage Collector pra medir o delta de memória
  GC.start
  mem_after = ObjectSpace.memsize_of_all / 1024.0
  mem_kb = mem_after - mem_before
  
  # Como o GC pode limpar variáveis externas, evitamos deltas negativos confusos
  mem_kb = 0.0 if mem_kb < 0 

  ms = (t1 - t0) * 1000.0

  logger.write(sprintf("\"%s\",\"%s\",\"%s\",%d,%d,%.1f,%.1f", timestamp, algo, impl, n, iterations, ms, mem_kb))
end

# ============================================================
# TESTES
# ============================================================

logger = BenchLogger.new
logger.start

# ----------------------------------------------------------
# TESTE 1 — Algorithm 1: Factorial with accumulator
# ----------------------------------------------------------
# n=10, 500.000 iterações
run_bench(logger, "Factorial", "Normal", 10, 500_000) { factorial_normal(10) }
run_bench(logger, "Factorial", "Tail (TCO)", 10, 500_000) { factorial_tail(10) }
run_bench(logger, "Factorial", "Loop", 10, 500_000) { factorial_loop(10) }

# n=1000, 10.000 iterações (Ruby tem Bignums nativos automáticos)
run_bench(logger, "Factorial", "Normal", 1000, 10_000) { factorial_normal(1000) }
run_bench(logger, "Factorial", "Tail (TCO)", 1000, 10_000) { factorial_tail(1000) }
run_bench(logger, "Factorial", "Loop", 1000, 10_000) { factorial_loop(1000) }

# ----------------------------------------------------------
# TESTE 2 — Algorithm 2: Mutually recursive even/odd
# ----------------------------------------------------------
# n=1000, 500.000 iterações
run_bench(logger, "Mutually Rec (Even)", "Normal", 1000, 500_000) { even_normal(1000) }
run_bench(logger, "Mutually Rec (Even)", "Tail (TCO)", 1000, 500_000) { is_even(1000) }
run_bench(logger, "Mutually Rec (Even)", "Loop", 1000, 500_000) { is_even_loop(1000) }

run_bench(logger, "Mutually Rec (Odd)", "Normal", 1000, 500_000) { odd_normal(1000) }
run_bench(logger, "Mutually Rec (Odd)", "Tail (TCO)", 1000, 500_000) { is_odd(1000) }

# ----------------------------------------------------------
# TESTE 3 — Algorithm 3: Three-state machine A→B→C→A
# ----------------------------------------------------------
# k=999 (múltiplo de 3), 500.000 iterações
run_bench(logger, "State Machine", "Normal", 999, 500_000) { state_a_normal(999) }
run_bench(logger, "State Machine", "Tail (TCO)", 999, 500_000) { state_a(999) }
run_bench(logger, "State Machine", "Loop", 999, 500_000) { state_a_loop(999) }

logger.close