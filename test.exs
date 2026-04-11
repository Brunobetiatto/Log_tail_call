# bench.exs
# Rodar com: elixir bench.exs

defmodule BenchLogger do
  def start do
    {:ok, file} = File.open("bench_results_elixir.log", [:write, :utf8])
    timestamp = DateTime.utc_now() |> DateTime.to_string()
    write(file, "========================================")
    write(file, "Benchmark Tail Call vs Normal")
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

defmodule Factorial do
  def normal(0), do: 1
  def normal(n), do: n * normal(n - 1)

  def tail(n), do: tail(n, 1)
  defp tail(0, acc), do: acc
  defp tail(n, acc), do: tail(n - 1, n * acc)
end

defmodule Fibonacci do
  def normal(n) when n < 2, do: n
  def normal(n), do: normal(n - 1) + normal(n - 2)

  def tail(n), do: tail(n, 0, 1)
  defp tail(0, a, _), do: a
  defp tail(n, a, b), do: tail(n - 1, b, a + b)
end

defmodule SumList do
  def normal([]), do: 0
  def normal([h | t]), do: h + normal(t)

  def tail(list), do: tail(list, 0)
  defp tail([], acc), do: acc
  defp tail([h | t], acc), do: tail(t, acc + h)
end

defmodule Bench do
  def section(file, title) do
    BenchLogger.write(file, "\n#{title}")
    BenchLogger.write(file, String.duplicate("-", String.length(title)))
  end

  def run(file, label, func, iterations) do
    :erlang.garbage_collect()

    {_, words_before, _} = :erlang.statistics(:garbage_collection)
    heap_before = :erlang.process_info(self(), :total_heap_size) |> elem(1)
    mem_before = (heap_before + words_before) * :erlang.system_info(:wordsize)

    t0 = System.monotonic_time(:millisecond)
    Enum.each(1..iterations, fn _ -> func.() end)
    t1 = System.monotonic_time(:millisecond)

    {_, words_after, _} = :erlang.statistics(:garbage_collection)
    heap_after = :erlang.process_info(self(), :total_heap_size) |> elem(1)
    mem_after = (heap_after + words_after) * :erlang.system_info(:wordsize)

    ms  = t1 - t0
    mem = (mem_after - mem_before) / 1024.0

    line = :io_lib.format("  ~-12s Tempo: ~6.1f ms  |  Mem alocada: ~12.1f KB",
                          [label, ms * 1.0, mem])
          |> IO.chardata_to_string()

    BenchLogger.write(file, line)
  end

  def overflow(file, label, func) do
    IO.write("  #{label} ... ")
    IO.write(file, "  #{label} ... ")

    try do
      result = func.()
      digits = result |> Integer.to_string() |> String.length()
      BenchLogger.write(file, "OK! (#{digits} dígitos)")
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
# TESTE 1 — Factorial n=10 sem bignum
# ============================================================
Bench.section(file, "TESTE 1: Factorial n=10 — 500.000 iterações (sem bignum)")
Bench.run(file, "Normal   ", fn -> Factorial.normal(10) end, 500_000)
Bench.run(file, "Tail Call", fn -> Factorial.tail(10) end,   500_000)

# ============================================================
# TESTE 2 — Factorial n=1000 com bignum
# ============================================================
Bench.section(file, "TESTE 2: Factorial n=1000 — 10.000 iterações (com bignum)")
Bench.run(file, "Normal   ", fn -> Factorial.normal(1000) end, 10_000)
Bench.run(file, "Tail Call", fn -> Factorial.tail(1000) end,   10_000)

# ============================================================
# TESTE 3 — Fibonacci exponencial vs linear
# ============================================================
Bench.section(file, "TESTE 3: Fibonacci n=30 — 100 iterações (exponencial vs linear)")
Bench.run(file, "Normal   ", fn -> Fibonacci.normal(30) end, 100)
Bench.run(file, "Tail Call", fn -> Fibonacci.tail(30) end,   100)

# ============================================================
# TESTE 4 — Soma de lista grande
# ============================================================
Bench.section(file, "TESTE 4: Soma de lista 100.000 elementos — 200 iterações")
big_list = Enum.to_list(0..99_999)
Bench.run(file, "Normal   ", fn -> SumList.normal(big_list) end, 200)
Bench.run(file, "Tail Call", fn -> SumList.tail(big_list) end,   200)

# ============================================================
# TESTE 5 — Stack overflow
# ============================================================
Bench.section(file, "TESTE 5: Limite da stack — n=100.000")
Bench.overflow(file, "Tail  factorial 100k ", fn -> Factorial.tail(1000_000) end)
Bench.overflow(file, "Normal factorial 100k", fn -> Factorial.normal(1000_000) end)

big_list_2 = Enum.to_list(0..999_999)
Bench.overflow(file, "Tail  soma lista 1M  ", fn -> SumList.tail(big_list_2) end)
Bench.overflow(file, "Normal soma lista 1M ", fn -> SumList.normal(big_list_2) end)

# ============================================================
# Fecha log
# ============================================================
BenchLogger.close(file)
