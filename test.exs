# bench.exs
# Rodar com: elixir bench.exs

defmodule BenchLogger do
  def start do
    {:ok, file} = File.open("bench_results_elixir.log", [:write, :utf8])
    timestamp = DateTime.utc_now() |> DateTime.to_string()
    write(file, "========================================")
    write(file, "Benchmark — Recursão Tail Call em Elixir")
    write(file, "#{timestamp}")
    write(file, "========================================\n")
    file
  end

  def write(file, line) do
    IO.puts(line)
    IO.puts(file, line)
  end

  def close(file) do
    write(file, "\n========================================")
    write(file, "Fim do benchmark")
    write(file, DateTime.utc_now() |> DateTime.to_string())
    write(file, "========================================")
    File.close(file)
    IO.puts("\nLog salvo em: bench_results_elixir.log")
  end
end

# ============================================================
# Algorithm 1 — Factorial with accumulator (self-tail)
# ============================================================
defmodule Factorial do
  # Sem tail call — recursão normal
  def normal(0), do: 1
  def normal(n), do: n * normal(n - 1)

  # Algorithm 1: FACTORIAL(n, acc)
  #   if n = 0 then return acc
  #   else return FACTORIAL(n − 1, n × acc)
  def tail(n), do: tail(n, 1)
  defp tail(0, acc), do: acc
  defp tail(n, acc), do: tail(n - 1, n * acc)
end

# ============================================================
# Algorithm 2 — Mutually recursive even/odd
# ============================================================
defmodule EvenOdd do
  # Versão normal — sem ser mutuamente recursiva
  def even_normal(0), do: true
  def even_normal(n), do: odd_normal(n - 1)

  def odd_normal(0), do: false
  def odd_normal(n), do: even_normal(n - 1)

  # Algorithm 2: ISEVEN e ISODD mutuamente recursivos
  # ISEVEN(n): if n=0 → true, else → ISODD(n−1)
  # ISODD(n):  if n=0 → false, else → ISEVEN(n−1)
  # Em Elixir, chamadas em posição de cauda entre módulos
  # também são otimizadas pela BEAM
  def is_even(0), do: true
  def is_even(n), do: is_odd(n - 1)   # tail position → TCO

  def is_odd(0), do: false
  def is_odd(n), do: is_even(n - 1)   # tail position → TCO
end

# ============================================================
# Algorithm 3 — Three-state machine (A → B → C → A)
# ============================================================
defmodule StateMachine do
  # Versão normal — sem garantia de TCO entre estados
  def state_a_normal(0), do: :finished
  def state_a_normal(k), do: state_b_normal(k - 1)

  def state_b_normal(0), do: :finished
  def state_b_normal(k), do: state_c_normal(k - 1)

  def state_c_normal(0), do: :finished
  def state_c_normal(k), do: state_a_normal(k - 1)

  # Algorithm 3: máquina de três estados com TCO
  # STATEA(k): if k=0 → finished, else → STATEB(k−1)
  # STATEB(k): if k=0 → finished, else → STATEC(k−1)
  # STATEC(k): if k=0 → finished, else → STATEA(k−1)
  def state_a(0), do: :finished
  def state_a(k), do: state_b(k - 1)   # tail position → TCO

  def state_b(0), do: :finished
  def state_b(k), do: state_c(k - 1)   # tail position → TCO

  def state_c(0), do: :finished
  def state_c(k), do: state_a(k - 1)   # tail position → TCO
end

# ============================================================
# Benchmark Engine
# ============================================================
defmodule Bench do
  def section(file, title) do
    BenchLogger.write(file, "\n#{title}")
    BenchLogger.write(file, String.duplicate("-", String.length(title)))
  end

  def run(file, label, func, iterations) do
    :erlang.garbage_collect()

    {_, words_before, _} = :erlang.statistics(:garbage_collection)
    heap_before = :erlang.process_info(self(), :total_heap_size) |> elem(1)
    mem_before  = (heap_before + words_before) * :erlang.system_info(:wordsize)

    t0 = System.monotonic_time(:millisecond)
    Enum.each(1..iterations, fn _ -> func.() end)
    t1 = System.monotonic_time(:millisecond)

    {_, words_after, _} = :erlang.statistics(:garbage_collection)
    heap_after = :erlang.process_info(self(), :total_heap_size) |> elem(1)
    mem_after  = (heap_after + words_after) * :erlang.system_info(:wordsize)

    ms  = t1 - t0
    mem = (mem_after - mem_before) / 1024.0

    line = :io_lib.format("  ~-14s Tempo: ~6.1f ms  |  Mem alocada: ~12.1f KB",
                          [label, ms * 1.0, mem])
           |> IO.chardata_to_string()

    BenchLogger.write(file, line)
  end

  def overflow(file, label, func, result_fn) do
    IO.write("  #{label} ... ")
    IO.write(file, "  #{label} ... ")
    try do
      result = func.()
      BenchLogger.write(file, "OK! (#{result_fn.(result)})")
    rescue
      e -> BenchLogger.write(file, "STACK OVERFLOW! ✗  (#{Exception.message(e)})")
    end
  end
end

# ============================================================
# Inicia log
# ============================================================
file = BenchLogger.start()

# ============================================================
# TESTE 1 — Algorithm 1: Factorial with accumulator
# ============================================================
Bench.section(file, "TESTE 1: Algorithm 1 — Factorial (self-tail)")
BenchLogger.write(file, "  n=10, 500.000 iterações (sem bignum)")
Bench.run(file, "Normal      ", fn -> Factorial.normal(10) end, 500_000)
Bench.run(file, "Tail (acc)  ", fn -> Factorial.tail(10) end,   500_000)

BenchLogger.write(file, "")
BenchLogger.write(file, "  n=1000, 10.000 iterações (com bignum)")
Bench.run(file, "Normal      ", fn -> Factorial.normal(1_000) end, 10_000)
Bench.run(file, "Tail (acc)  ", fn -> Factorial.tail(1_000) end,   10_000)

# ============================================================
# TESTE 2 — Algorithm 2: Mutually recursive even/odd
# ============================================================
Bench.section(file, "TESTE 2: Algorithm 2 — Mutually recursive even/odd")
BenchLogger.write(file, "  n=1000, 500.000 iterações")
Bench.run(file, "Normal even ", fn -> EvenOdd.even_normal(1_000) end, 500_000)
Bench.run(file, "Tail   even ", fn -> EvenOdd.is_even(1_000) end,     500_000)
Bench.run(file, "Normal odd  ", fn -> EvenOdd.odd_normal(1_000) end,  500_000)
Bench.run(file, "Tail   odd  ", fn -> EvenOdd.is_odd(1_000) end,      500_000)


# ============================================================
# TESTE 3 — Algorithm 3: Three-state machine A→B→C→A
# ============================================================
Bench.section(file, "TESTE 3: Algorithm 3 — Three-state machine (A→B→C→A)")
BenchLogger.write(file, "  k=999 (múltiplo de 3), 500.000 iterações")
Bench.run(file, "Normal A→B→C", fn -> StateMachine.state_a_normal(999) end, 500_000)
Bench.run(file, "Tail   A→B→C", fn -> StateMachine.state_a(999) end,        500_000)


# ============================================================
# Fecha log
# ============================================================
BenchLogger.close(file)
