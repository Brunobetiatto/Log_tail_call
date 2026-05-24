# bench.exs
# Rodar com: elixir bench.exs

# ============================================================
# REPRODUTIBILIDADE
# ============================================================
:rand.seed(:exsplus, {42, 42, 42})

# ============================================================
# CPU FREQUENCY READER
# ============================================================
defmodule CpuFreq do
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
          :error   -> 2.5
        end
      _ ->
        2.5
    end
  end
end

# ============================================================
# LOGGER
# ============================================================
defmodule BenchLogger do
  def start do
    {:ok, file} = File.open("bench_results_elixir.csv", [:write, :utf8])
    write(file, "Data,Algoritmo,Implementacao,N,Iteracoes,Run,Ciclos_CPU,Ciclos_por_iter,Memoria_KB,Freq_GHz")
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
# Algorithm 1 -- Factorial
# ============================================================
defmodule Factorial do
  def normal(0), do: 1
  def normal(n), do: n * normal(n - 1)

  def tail(n), do: tail(n, 1)
  defp tail(0, acc), do: acc
  defp tail(n, acc), do: tail(n - 1, n * acc)
end

# ============================================================
# Algorithm 2 -- Mutually recursive even/odd
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
# Algorithm 3 -- Three-state machine
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
  @max_time_sec   60
  @runs_per_point (if System.get_env("BENCH_QUICK") == "1", do: 2, else: 10)

  def run_single(file, algo, impl, n, iterations, run_id, freq_ghz, func) do
    :erlang.garbage_collect()
    heap_before = heap_bytes()
    :erlang.statistics(:runtime)

    timestamp = DateTime.utc_now() |> DateTime.to_string()

    # Executa em uma task com timeout
    task = Task.async(fn ->
      try do
        Enum.each(1..iterations, fn _ -> func.() end)
        :ok
      catch
        :error, :system_limit -> {:error, "STACK OVERFLOW"}
        kind, reason          -> {:error, "ERRO: #{inspect({kind, reason})}"}
      end
    end)

    case Task.yield(task, @max_time_sec * 1000) || Task.shutdown(task, :brutal_kill) do
      {:ok, :ok} ->
        {_, cpu_diff_ms} = :erlang.statistics(:runtime)
        heap_after = heap_bytes()
        cpu_seconds  = cpu_diff_ms / 1000.0
        cycles_total = cpu_seconds * freq_ghz * 1.0e9
        cycles_per_iter = if iterations > 0, do: cycles_total / iterations, else: 0.0
        mem_kb = max((heap_after - heap_before) / 1024.0, 0.0)

        line = "\"#{timestamp}\",\"#{algo}\",\"#{impl}\",#{n},#{iterations},#{run_id},#{round(cycles_total)},#{Float.round(cycles_per_iter * 1.0, 2)},#{Float.round(mem_kb * 1.0, 1)},#{Float.round(freq_ghz, 4)}"
        BenchLogger.write(file, line)
        :ok

      {:ok, {:error, reason}} ->
        line = "\"#{timestamp}\",\"#{algo}\",\"#{impl}\",#{n},#{iterations},#{run_id},\"#{reason}\",\"\",\"\",#{Float.round(freq_ghz, 4)}"
        BenchLogger.write(file, line)
        reason

      nil ->
        line = "\"#{timestamp}\",\"#{algo}\",\"#{impl}\",#{n},#{iterations},#{run_id},\"TIMEOUT\",\"\",\"\",#{Float.round(freq_ghz, 4)}"
        BenchLogger.write(file, line)
        "TIMEOUT"
    end
  end

  def run_sweep(file, algo, impl, n, sweep, freq_ghz, func) do
    Enum.reduce(sweep, 0, fn iter_count, consecutive_fails ->
      if consecutive_fails >= 2 do
        Enum.each(1..@runs_per_point, fn r ->
          ts = DateTime.utc_now() |> DateTime.to_string()
          line = "\"#{ts}\",\"#{algo}\",\"#{impl}\",#{n},#{iter_count},#{r},\"SKIPPED\",\"\",\"\",0.0000"
          BenchLogger.write(file, line)
        end)
        consecutive_fails
      else
        fails = run_point(file, algo, impl, n, iter_count, freq_ghz, func)
        if fails >= div(@runs_per_point, 2) + rem(@runs_per_point, 2) do
          consecutive_fails + 1
        else
          0
        end
      end
    end)
  end

  defp run_point(file, algo, impl, n, iter_count, freq_ghz, func) do
    Enum.reduce_while(1..@runs_per_point, {0, 1}, fn r, {fails, _} ->
      status = run_single(file, algo, impl, n, iter_count, r, freq_ghz, func)
      new_fails = if status in ["TIMEOUT", "STACK OVERFLOW"], do: fails + 1, else: fails

      cond do
        new_fails >= 2 and r < @runs_per_point ->
          Enum.each((r + 1)..@runs_per_point, fn skip ->
            ts = DateTime.utc_now() |> DateTime.to_string()
            line = "\"#{ts}\",\"#{algo}\",\"#{impl}\",#{n},#{iter_count},#{skip},\"SKIPPED\",\"\",\"\",0.0000"
            BenchLogger.write(file, line)
          end)
          {:halt, {new_fails, r}}
        true ->
          {:cont, {new_fails, r}}
      end
    end)
    |> case do
      {fails, _} -> fails
    end
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
IO.puts("Frequencia da CPU detectada: #{:erlang.float_to_binary(freq_ghz, decimals: 3)} GHz\n")

file = BenchLogger.start()

quick = System.get_env("BENCH_QUICK") == "1"
{sweep_cheap, sweep_fact_bign} =
  if quick do
    IO.puts("[BENCH_QUICK=1] usando sweep reduzido e 2 runs por ponto")
    {[10_000, 100_000], [200, 1_000]}
  else
    {[10_000, 30_000, 100_000, 300_000, 1_000_000], [200, 500, 1_000, 3_000, 10_000]}
  end

# ----- Factorial -----
Bench.run_sweep(file, "Factorial", "Normal",     10,    sweep_cheap,     freq_ghz, fn -> Factorial.normal(10) end)
Bench.run_sweep(file, "Factorial", "Tail (acc)", 10,    sweep_cheap,     freq_ghz, fn -> Factorial.tail(10) end)
Bench.run_sweep(file, "Factorial", "Normal",     1_000, sweep_fact_bign, freq_ghz, fn -> Factorial.normal(1_000) end)
Bench.run_sweep(file, "Factorial", "Tail (acc)", 1_000, sweep_fact_bign, freq_ghz, fn -> Factorial.tail(1_000) end)

# ----- Mutually Recursive -----
Bench.run_sweep(file, "Mutually Rec (Even)", "Normal", 1_000, sweep_cheap, freq_ghz, fn -> EvenOdd.even_normal(1_000) end)
Bench.run_sweep(file, "Mutually Rec (Even)", "Tail",   1_000, sweep_cheap, freq_ghz, fn -> EvenOdd.is_even(1_000) end)
Bench.run_sweep(file, "Mutually Rec (Odd)",  "Normal", 1_000, sweep_cheap, freq_ghz, fn -> EvenOdd.odd_normal(1_000) end)
Bench.run_sweep(file, "Mutually Rec (Odd)",  "Tail",   1_000, sweep_cheap, freq_ghz, fn -> EvenOdd.is_odd(1_000) end)

# ----- State Machine -----
Bench.run_sweep(file, "State Machine", "Normal", 999, sweep_cheap, freq_ghz, fn -> StateMachine.state_a_normal(999) end)
Bench.run_sweep(file, "State Machine", "Tail",   999, sweep_cheap, freq_ghz, fn -> StateMachine.state_a(999) end)

BenchLogger.close(file)
