(* bench.ml
   Para rodar com a máxima performance (compilação nativa), execute no terminal:
   
   ocamlopt -o bench unix.cmxa bench.ml
   ./bench
*)

(* ============================================================
   LOGGER (Formato CSV)
   ============================================================ *)
let filename = "bench_results_ocaml.csv"

let start_logger () =
  let oc = open_out filename in
  let header = "Data,Algoritmo,Implementacao,N,Iteracoes,Ciclos_CPU,Ciclos_por_iter,Memoria_KB" in
  Printf.fprintf oc "%s\n" header;
  Printf.printf "%s\n" header;
  flush oc;
  oc

let close_logger oc =
  close_out oc;
  Printf.printf "\nLog salvo em: %s\n" filename

(* Lê a frequência da CPU em GHz a partir de /proc/cpuinfo *)
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

(* Função auxiliar para gerar o timestamp *)
let get_timestamp () =
  let tm = Unix.localtime (Unix.time ()) in
  Printf.sprintf "%04d-%02d-%02d %02d:%02d:%02d"
    (tm.Unix.tm_year + 1900) (tm.Unix.tm_mon + 1) tm.Unix.tm_mday
    tm.Unix.tm_hour tm.Unix.tm_min tm.Unix.tm_sec

(* ============================================================
   Algorithm 1 — Factorial with accumulator (self-tail)
   ============================================================ *)

(* Sem tail call. Para N muito grande, isso causa Stack Overflow *)
let rec factorial_normal n =
  if n = 0 then 1
  else n * factorial_normal (n - 1)

(* Com tail call usando um acumulador (loop interno) *)
let factorial_tail n =
  let rec loop n acc =
    if n = 0 then acc
    else loop (n - 1) (n * acc)
  in
  loop n 1

(* ============================================================
   Algorithm 2 — Mutually recursive even/odd
   ============================================================ *)

(* No OCaml, a recursão mútua é feita com "let rec ... and ...".
   Como as chamadas estão em posição de cauda, o compilador otimiza
   naturalmente, exatamente como no Elixir e Racket. *)
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
   Algorithm 3 — Three-state machine (A → B → C → A)
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

let run_bench logger algo impl n iterations func =
  (* Força a coleta de lixo antes de medir para limpar a memória *)
  Gc.compact ();
  let mem_before = Gc.allocated_bytes () in
  let t0 = Unix.times () in
  let timestamp = get_timestamp () in

  try
    for _ = 1 to iterations do
      ignore (func ())
    done;

    let t1 = Unix.times () in
    let mem_after = Gc.allocated_bytes () in

    let cpu_seconds = (t1.Unix.tms_utime -. t0.Unix.tms_utime)
                    +. (t1.Unix.tms_stime -. t0.Unix.tms_stime) in
    let cycles          = cpu_seconds *. cpu_freq_ghz *. 1e9 in
    let cycles_per_iter = cycles /. float_of_int iterations in
    let mem_kb = (mem_after -. mem_before) /. 1024.0 in

    let line = Printf.sprintf "\"%s\",\"%s\",\"%s\",%d,%d,%.0f,%.2f,%.1f"
        timestamp algo impl n iterations cycles cycles_per_iter mem_kb in
    Printf.fprintf logger "%s\n" line;
    Printf.printf "%s\n" line;
    flush logger

  with
  | Stack_overflow ->
      (* OCaml lança Stack_overflow nativamente se a pilha estourar *)
      let line = Printf.sprintf "\"%s\",\"%s\",\"%s\",%d,%d,\"STACK OVERFLOW\",\"\""
          timestamp algo impl n iterations in
      Printf.fprintf logger "%s\n" line;
      Printf.printf "%s\n" line;
      flush logger
  | e ->
      let line = Printf.sprintf "\"%s\",\"%s\",\"%s\",%d,%d,\"ERRO: %s\",\"\""
          timestamp algo impl n iterations (Printexc.to_string e) in
      Printf.fprintf logger "%s\n" line;
      Printf.printf "%s\n" line;
      flush logger

(* ============================================================
   TESTES
   ============================================================ *)

let () =
  let logger = start_logger () in

  (* ----------------------------------------------------------
     TESTE 1 — Algorithm 1: Factorial with accumulator
     ---------------------------------------------------------- *)
  (* Nota: no OCaml, usar int nativo para n=1000 fará a matemática 
     "transbordar" (wrap around e virar 0). Isso é esperado e não afeta
     o benchmark, cujo objetivo é apenas testar a pilha de chamadas e a CPU. *)
  
  run_bench logger "Factorial" "Normal" 10 500_000 (fun () -> factorial_normal 10);
  run_bench logger "Factorial" "Tail (acc)" 10 500_000 (fun () -> factorial_tail 10);

  run_bench logger "Factorial" "Normal" 1000 10_000 (fun () -> factorial_normal 1000);
  run_bench logger "Factorial" "Tail (acc)" 1000 10_000 (fun () -> factorial_tail 1000);

  (* ----------------------------------------------------------
     TESTE 2 — Algorithm 2: Mutually recursive even/odd
     ---------------------------------------------------------- *)
  run_bench logger "Mutually Rec (Even)" "Normal" 1000 500_000 (fun () -> even_normal 1000);
  run_bench logger "Mutually Rec (Even)" "Tail" 1000 500_000 (fun () -> is_even 1000);

  run_bench logger "Mutually Rec (Odd)" "Normal" 1000 500_000 (fun () -> odd_normal 1000);
  run_bench logger "Mutually Rec (Odd)" "Tail" 1000 500_000 (fun () -> is_odd 1000);

  (* ----------------------------------------------------------
     TESTE 3 — Algorithm 3: Three-state machine A→B→C→A
     ---------------------------------------------------------- *)
  run_bench logger "State Machine" "Normal" 999 500_000 (fun () -> state_a_normal 999);
  run_bench logger "State Machine" "Tail" 999 500_000 (fun () -> state_a 999);

  close_logger logger