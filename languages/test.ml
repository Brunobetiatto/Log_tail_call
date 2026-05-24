(* bench.ml
   Compilar e rodar com:
       ocamlopt -o test_ocaml unix.cmxa test.ml
       ./test_ocaml
*)

(* ============================================================
   REPRODUTIBILIDADE
   ============================================================ *)
let _ = Random.init 42

(* ============================================================
   LOGGER (Formato CSV)
   ============================================================ *)
let filename = "bench_results_ocaml.csv"

let start_logger () =
  let oc = open_out filename in
  let header = "Data,Algoritmo,Implementacao,N,Iteracoes,Run,Ciclos_CPU,Ciclos_por_iter,Memoria_KB,Freq_GHz" in
  Printf.fprintf oc "%s\n" header;
  Printf.printf "%s\n" header;
  flush oc;
  oc

let close_logger oc =
  close_out oc;
  Printf.printf "\nLog salvo em: %s\n" filename

let get_cpu_freq_ghz () =
  try
    let ic = open_in "/proc/cpuinfo" in
    let freq = ref 2000.0 in
    (try
      while true do
        let line = input_line ic in
        if String.length line > 7 && String.sub line 0 7 = "cpu MHz" then begin
          let parts = String.split_on_char ':' line in
          freq := float_of_string (String.trim (List.nth parts 1));
          raise Exit
        end
      done
    with Exit | End_of_file -> ());
    close_in ic;
    !freq /. 1000.0
  with _ -> 2.0

let get_timestamp () =
  let tm = Unix.localtime (Unix.time ()) in
  Printf.sprintf "%04d-%02d-%02d %02d:%02d:%02d"
    (tm.Unix.tm_year + 1900) (tm.Unix.tm_mon + 1) tm.Unix.tm_mday
    tm.Unix.tm_hour tm.Unix.tm_min tm.Unix.tm_sec

(* ============================================================
   CONFIGURACAO
   ============================================================ *)
let max_time_sec = 60.0

let quick =
  match Sys.getenv_opt "BENCH_QUICK" with
  | Some "1" -> true
  | _ -> false

let runs_per_point = if quick then 2 else 10
let sweep_cheap =
  if quick then [10_000; 100_000]
  else [10_000; 30_000; 100_000; 300_000; 1_000_000]
let sweep_factorial_bignum =
  if quick then [200; 1_000]
  else [200; 500; 1_000; 3_000; 10_000]

let () = if quick then print_endline "[BENCH_QUICK=1] usando sweep reduzido e 2 runs por ponto"

exception Timed_out

(* ============================================================
   Algorithm 1 -- Factorial
   ============================================================ *)
let rec factorial_normal n =
  if n = 0 then 1
  else n * factorial_normal (n - 1)

let factorial_tail n =
  let rec loop n acc =
    if n = 0 then acc
    else loop (n - 1) (n * acc)
  in
  loop n 1

(* ============================================================
   Algorithm 2 -- Mutually recursive even/odd
   ============================================================ *)
let rec even_normal n =
  if n = 0 then true
  else odd_normal (n - 1)
and odd_normal n =
  if n = 0 then false
  else even_normal (n - 1)

let rec is_even n =
  if n = 0 then true
  else is_odd (n - 1)
and is_odd n =
  if n = 0 then false
  else is_even (n - 1)

(* ============================================================
   Algorithm 3 -- Three-state machine
   ============================================================ *)
let rec state_a_normal k =
  if k = 0 then "finished"
  else state_b_normal (k - 1)
and state_b_normal k =
  if k = 0 then "finished"
  else state_c_normal (k - 1)
and state_c_normal k =
  if k = 0 then "finished"
  else state_a_normal (k - 1)

let rec state_a k =
  if k = 0 then "finished"
  else state_b (k - 1)
and state_b k =
  if k = 0 then "finished"
  else state_c (k - 1)
and state_c k =
  if k = 0 then "finished"
  else state_a (k - 1)

(* ============================================================
   BENCHMARK ENGINE
   ============================================================ *)
let cpu_freq_ghz = get_cpu_freq_ghz ()

let run_single logger algo impl n iterations run_id func =
  Gc.compact ();
  let mem_before = Gc.allocated_bytes () in
  let t_wall_start = Unix.gettimeofday () in
  let t0 = Unix.times () in
  let timestamp = get_timestamp () in

  try
    for i = 1 to iterations do
      ignore (func ());
      if i mod 1000 = 0 && Unix.gettimeofday () -. t_wall_start > max_time_sec then
        raise Timed_out
    done;

    let t1 = Unix.times () in
    let mem_after = Gc.allocated_bytes () in

    let cpu_seconds = (t1.Unix.tms_utime -. t0.Unix.tms_utime)
                    +. (t1.Unix.tms_stime -. t0.Unix.tms_stime) in
    let cycles          = cpu_seconds *. cpu_freq_ghz *. 1e9 in
    let cycles_per_iter = cycles /. float_of_int iterations in
    let mem_kb = (mem_after -. mem_before) /. 1024.0 in

    let line = Printf.sprintf "\"%s\",\"%s\",\"%s\",%d,%d,%d,%.0f,%.2f,%.1f,%.4f"
        timestamp algo impl n iterations run_id cycles cycles_per_iter mem_kb cpu_freq_ghz in
    Printf.fprintf logger "%s\n" line;
    Printf.printf "%s\n" line;
    flush logger;
    "OK"

  with
  | Stack_overflow ->
      let line = Printf.sprintf "\"%s\",\"%s\",\"%s\",%d,%d,%d,\"STACK OVERFLOW\",\"\",\"\",%.4f"
          timestamp algo impl n iterations run_id cpu_freq_ghz in
      Printf.fprintf logger "%s\n" line;
      Printf.printf "%s\n" line;
      flush logger;
      "STACK OVERFLOW"
  | Timed_out ->
      let line = Printf.sprintf "\"%s\",\"%s\",\"%s\",%d,%d,%d,\"TIMEOUT\",\"\",\"\",%.4f"
          timestamp algo impl n iterations run_id cpu_freq_ghz in
      Printf.fprintf logger "%s\n" line;
      Printf.printf "%s\n" line;
      flush logger;
      "TIMEOUT"
  | e ->
      let line = Printf.sprintf "\"%s\",\"%s\",\"%s\",%d,%d,%d,\"ERRO: %s\",\"\",\"\",%.4f"
          timestamp algo impl n iterations run_id (Printexc.to_string e) cpu_freq_ghz in
      Printf.fprintf logger "%s\n" line;
      Printf.printf "%s\n" line;
      flush logger;
      "ERRO"

let log_skipped logger algo impl n iter_count run_id =
  let ts = get_timestamp () in
  let line = Printf.sprintf "\"%s\",\"%s\",\"%s\",%d,%d,%d,\"SKIPPED\",\"\",\"\",0.0000"
      ts algo impl n iter_count run_id in
  Printf.fprintf logger "%s\n" line;
  Printf.printf "%s\n" line;
  flush logger

let run_sweep logger algo impl n sweep func =
  let consecutive_fails = ref 0 in
  List.iter (fun iter_count ->
    if !consecutive_fails >= 2 then begin
      for r = 1 to runs_per_point do
        log_skipped logger algo impl n iter_count r
      done
    end else begin
      let fails = ref 0 in
      let stop  = ref false in
      let r = ref 1 in
      while not !stop && !r <= runs_per_point do
        let status = run_single logger algo impl n iter_count !r func in
        if status = "TIMEOUT" || status = "STACK OVERFLOW" then begin
          incr fails;
          if !fails >= 2 && !r < runs_per_point then begin
            for skip = !r + 1 to runs_per_point do
              log_skipped logger algo impl n iter_count skip
            done;
            stop := true
          end
        end;
        incr r
      done;
      let half = (runs_per_point + 1) / 2 in
      if !fails >= half then incr consecutive_fails
      else consecutive_fails := 0
    end
  ) sweep

(* ============================================================
   TESTES
   ============================================================ *)
let () =
  let logger = start_logger () in

  (* ----- Factorial -----
     Nota: OCaml int wraps em n=1000. O benchmark testa CPU/pilha, nao correcao. *)
  run_sweep logger "Factorial" "Normal"     10   sweep_cheap            (fun () -> factorial_normal 10);
  run_sweep logger "Factorial" "Tail (acc)" 10   sweep_cheap            (fun () -> factorial_tail 10);
  run_sweep logger "Factorial" "Normal"     1000 sweep_factorial_bignum (fun () -> factorial_normal 1000);
  run_sweep logger "Factorial" "Tail (acc)" 1000 sweep_factorial_bignum (fun () -> factorial_tail 1000);

  (* ----- Mutually Recursive ----- *)
  run_sweep logger "Mutually Rec (Even)" "Normal" 1000 sweep_cheap (fun () -> even_normal 1000);
  run_sweep logger "Mutually Rec (Even)" "Tail"   1000 sweep_cheap (fun () -> is_even 1000);
  run_sweep logger "Mutually Rec (Odd)"  "Normal" 1000 sweep_cheap (fun () -> odd_normal 1000);
  run_sweep logger "Mutually Rec (Odd)"  "Tail"   1000 sweep_cheap (fun () -> is_odd 1000);

  (* ----- State Machine ----- *)
  run_sweep logger "State Machine" "Normal" 999 sweep_cheap (fun () -> state_a_normal 999);
  run_sweep logger "State Machine" "Tail"   999 sweep_cheap (fun () -> state_a 999);

  close_logger logger
