# bench.exs
# Rodar com: elixir bench.exs

defmodule BenchLogger do
  def start do
    {:ok, file} = File.open("bench_results_elixir.csv", [:write, :utf8])

    # Escreve o cabeçalho das colunas do CSV
    write(file, "Data,Algoritmo,Implementacao,N,Iteracoes,Tempo_ms,Memoria_KB")
    file
  end

  def write(file, line) do
    IO.puts(line)
    IO.puts(file, line)
  end

  def close(file) do
    File.close(file)
    IO.puts("\nLog salvo em: bench_results_elixir.csv")
  end
end

# ============================================================
# Algorithm 1 — Factorial with accumulator (self-tail)
# ============================================================
defmodule Factorial do
  def normal(0), do: 1
  def normal(n), do: n * normal(n - 1)

  def tail(n), do: tail(n, 1)
  defp tail(0, acc), do: acc
  defp tail(n, acc), do: tail(n - 1, n * acc)
end

# ============================================================
# Algorithm 2 — Mutually recursive even/odd
# ============================================================
defmodule EvenOdd do
  def even_normal(0), do: true
  def even_normal(n), do: odd_normal(n - 1)

  def odd_normal(0), do: false
  def odd_normal(n), do: even_normal(n - 1)

  def is_even(0), do: true
  def is_even(n), do: is_odd(n - 1)

  def is_odd(0), do: false
  def is_odd(n), do: is_even(n - 1)
end

# ============================================================
# Algorithm 3 — Three-state machine (A → B → C → A)
# ============================================================
defmodule StateMachine do
  def state_a_normal(0), do: :finished
  def state_a_normal(k), do: state_b_normal(k - 1)

  def state_b_normal(0), do: :finished
  def state_b_normal(k), do: state_c_normal(k - 1)

  def state_c_normal(0), do: :finished
  def state_c_normal(k), do: state_a_normal(k - 1)

  def state_a(0), do: :finished
  def state_a(k), do: state_b(k - 1)

  def state_b(0), do: :finished
  def state_b(k), do: state_c(k - 1)

  def state_c(0), do: :finished
  def state_c(k), do: state_a(k - 1)
end

# ============================================================
# Benchmark Engine
# ============================================================
defmodule Bench do
  def run(file, algo, impl, n, iterations, func) do
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

    timestamp = DateTime.utc_now() |> DateTime.to_string()

    # Formata a string preservando as aspas no texto para proteger o CSV
    # Usamos ~ts para strings de texto e ~.1f para float com 1 casa decimal
    line = :io_lib.format("\"~ts\",\"~ts\",\"~ts\",~w,~w,~.1f,~.1f",
                          [timestamp, algo, impl, n, iterations, ms * 1.0, mem])
           |> IO.chardata_to_string()

    BenchLogger.write(file, line)
  end
end

# ============================================================
# Inicia log e Testes
# ============================================================
file = BenchLogger.start()

# ----------------------------------------------------------
# TESTE 1 — Algorithm 1: Factorial with accumulator
# ----------------------------------------------------------
# n=10, 500.000 iterações (sem bignum)
Bench.run(file, "Factorial", "Normal", 10, 500_000, fn -> Factorial.normal(10) end)
Bench.run(file, "Factorial", "Tail (acc)", 10, 500_000, fn -> Factorial.tail(10) end)

# n=1000, 10.000 iterações (com bignum)
Bench.run(file, "Factorial", "Normal", 1_000, 10_000, fn -> Factorial.normal(1_000) end)
Bench.run(file, "Factorial", "Tail (acc)", 1_000, 10_000, fn -> Factorial.tail(1_000) end)

# ----------------------------------------------------------
# TESTE 2 — Algorithm 2: Mutually recursive even/odd
# ----------------------------------------------------------
# n=1000, 500.000 iterações
Bench.run(file, "Mutually Rec (Even)", "Normal", 1_000, 500_000, fn -> EvenOdd.even_normal(1_000) end)
Bench.run(file, "Mutually Rec (Even)", "Tail", 1_000, 500_000, fn -> EvenOdd.is_even(1_000) end)

Bench.run(file, "Mutually Rec (Odd)", "Normal", 1_000, 500_000, fn -> EvenOdd.odd_normal(1_000) end)
Bench.run(file, "Mutually Rec (Odd)", "Tail", 1_000, 500_000, fn -> EvenOdd.is_odd(1_000) end)

# ----------------------------------------------------------
# TESTE 3 — Algorithm 3: Three-state machine A→B→C→A
# ----------------------------------------------------------
# k=999 (múltiplo de 3), 500.000 iterações
Bench.run(file, "State Machine", "Normal", 999, 500_000, fn -> StateMachine.state_a_normal(999) end)
Bench.run(file, "State Machine", "Tail", 999, 500_000, fn -> StateMachine.state_a(999) end)

# Fecha e salva arquivo
BenchLogger.close(file)
