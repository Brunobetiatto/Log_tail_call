# bench.exs
# Rodar com: elixir bench.exs

# ============================================================
# CPU FREQUENCY READER
# ============================================================
defmodule CpuFreq do
  @doc """
  Retorna a frequência da CPU em GHz.
  Lê de /proc/cpuinfo no Linux ou via sysctl no macOS.
  """
  def get_ghz do
    case read_linux() do
      nil -> read_macos()
      ghz -> ghz
    end
  end

  defp read_linux do
    case File.read("/proc/cpuinfo") do
      {:ok, content} ->
        content
        |> String.split("\n")
        |> Enum.find_value(fn line ->
          if String.starts_with?(line, "cpu MHz") do
            line
            |> String.split(":")
            |> List.last()
            |> String.trim()
            |> Float.parse()
            |> case do
              {mhz, _} -> mhz / 1000.0
              :error    -> nil
            end
          end
        end)
      _ ->
        nil
    end
  end

  defp read_macos do
    case System.cmd("sysctl", ["-n", "hw.cpufrequency"], stderr_to_stdout: true) do
      {output, 0} ->
        output
        |> String.trim()
        |> Integer.parse()
        |> case do
          {hz, _} -> hz / 1.0e9
          :error   -> 2.5   # fallback razoável se falhar tudo
        end
      _ ->
        2.5
    end
  end
end

# ============================================================
# LOGGER (Formato CSV — mesmo schema do Python)
# ============================================================
defmodule BenchLogger do
  def start do
    {:ok, file} = File.open("bench_results_elixir.csv", [:write, :utf8])
    write(file, "Data,Algoritmo,Implementacao,N,Iteracoes,Ciclos_CPU,Ciclos_por_iter,Memoria_KB")
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
# BENCHMARK ENGINE
# ============================================================
defmodule Bench do
  @doc """
  Mede ciclos de CPU usando :erlang.statistics(:runtime), que retorna
  tempo de CPU do processo em ms — equivalente ao time.process_time() do Python.
  Ciclos = cpu_ms / 1000 * freq_ghz * 1e9
  """
  def run(file, algo, impl, n, iterations, freq_ghz, func) do
    :erlang.garbage_collect()

    # Memória antes (heap do processo em bytes)
    heap_before = heap_bytes()

    # Reseta o diff de CPU time — próxima chamada retornará o delta
    :erlang.statistics(:runtime)

    Enum.each(1..iterations, fn _ -> func.() end)

    # {Total_ms, Diff_ms_since_last_call}
    {_, cpu_diff_ms} = :erlang.statistics(:runtime)

    heap_after = heap_bytes()

    # Conversão: ms de CPU → ciclos (mesma fórmula do Python)
    cpu_seconds  = cpu_diff_ms / 1000.0
    cycles_total = cpu_seconds * freq_ghz * 1.0e9
    cycles_per_iter = if iterations > 0, do: cycles_total / iterations, else: 0.0

    mem_kb = max((heap_after - heap_before) / 1024.0, 0.0)

    timestamp = DateTime.utc_now() |> DateTime.to_string()

    line =
      :io_lib.format(
        "\"~ts\",\"~ts\",\"~ts\",~w,~w,~.0f,~.2f,~.1f",
        [timestamp, algo, impl, n, iterations, cycles_total, cycles_per_iter, mem_kb]
      )
      |> IO.chardata_to_string()

    BenchLogger.write(file, line)
  end

  defp heap_bytes do
    {_, words} = :erlang.process_info(self(), :total_heap_size)
    words * :erlang.system_info(:wordsize)
  end
end

# ============================================================
# MAIN
# ============================================================
freq_ghz = CpuFreq.get_ghz()
IO.puts("Frequência da CPU detectada: #{:erlang.float_to_binary(freq_ghz, decimals: 3)} GHz\n")

file = BenchLogger.start()

# ----------------------------------------------------------
# TESTE 1 — Factorial
# ----------------------------------------------------------
Bench.run(file, "Factorial", "Normal",     10,    500_000, freq_ghz, fn -> Factorial.normal(10) end)
Bench.run(file, "Factorial", "Tail (acc)", 10,    500_000, freq_ghz, fn -> Factorial.tail(10) end)
Bench.run(file, "Factorial", "Normal",     1_000,  10_000, freq_ghz, fn -> Factorial.normal(1_000) end)
Bench.run(file, "Factorial", "Tail (acc)", 1_000,  10_000, freq_ghz, fn -> Factorial.tail(1_000) end)

# ----------------------------------------------------------
# TESTE 2 — Mutually recursive even/odd
# ----------------------------------------------------------
Bench.run(file, "Mutually Rec (Even)", "Normal", 1_000, 500_000, freq_ghz, fn -> EvenOdd.even_normal(1_000) end)
Bench.run(file, "Mutually Rec (Even)", "Tail",   1_000, 500_000, freq_ghz, fn -> EvenOdd.is_even(1_000) end)
Bench.run(file, "Mutually Rec (Odd)",  "Normal", 1_000, 500_000, freq_ghz, fn -> EvenOdd.odd_normal(1_000) end)
Bench.run(file, "Mutually Rec (Odd)",  "Tail",   1_000, 500_000, freq_ghz, fn -> EvenOdd.is_odd(1_000) end)

# ----------------------------------------------------------
# TESTE 3 — Three-state machine
# ----------------------------------------------------------
Bench.run(file, "State Machine", "Normal", 999, 500_000, freq_ghz, fn -> StateMachine.state_a_normal(999) end)
Bench.run(file, "State Machine", "Tail",   999, 500_000, freq_ghz, fn -> StateMachine.state_a(999) end)

BenchLogger.close(file)
