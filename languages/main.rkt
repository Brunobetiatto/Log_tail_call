#lang racket
(require racket/date)

;; ============================================================
;; LOGGER (Formato CSV)
;; ============================================================
(define log-port (open-output-file "bench_results_scheme.csv"
                                   #:mode 'text
                                   #:exists 'replace))

(define (log-write line)
  (displayln line)
  (displayln line log-port))

(define (log-start)
  ;; Escreve o cabeçalho das colunas do CSV
  (log-write "Data,Algoritmo,Implementacao,N,Iteracoes,Tempo_ms,Memoria_KB"))

(define (log-close)
  (close-output-port log-port)
  (displayln "\nLog salvo em: bench_results_scheme.csv"))

;; ============================================================
;; Algorithm 1 — Factorial with accumulator (self-tail)
;; ============================================================

(define (factorial-normal n)
  (if (= n 0) 1
      (* n (factorial-normal (- n 1)))))

(define (factorial-tail n)
  (define (loop n acc)
    (if (= n 0) acc
        (loop (- n 1) (* acc n))))
  (loop n 1))

;; ============================================================
;; Algorithm 2 — Mutually recursive even/odd
;; ============================================================

(define (even-normal n)
  (if (= n 0) #t
      (odd-normal (- n 1))))

(define (odd-normal n)
  (if (= n 0) #f
      (even-normal (- n 1))))

(define (is-even n)
  (if (= n 0) #t
      (is-odd (- n 1))))

(define (is-odd n)
  (if (= n 0) #f
      (is-even (- n 1))))

;; ============================================================
;; Algorithm 3 — Three-state machine (A → B → C → A)
;; ============================================================

(define (state-a-normal k)
  (if (= k 0) 'finished
      (state-b-normal (- k 1))))

(define (state-b-normal k)
  (if (= k 0) 'finished
      (state-c-normal (- k 1))))

(define (state-c-normal k)
  (if (= k 0) 'finished
      (state-a-normal (- k 1))))

(define (state-a k)
  (if (= k 0) 'finished
      (state-b (- k 1))))

(define (state-b k)
  (if (= k 0) 'finished
      (state-c (- k 1))))

(define (state-c k)
  (if (= k 0) 'finished
      (state-a (- k 1))))

;; ============================================================
;; BENCHMARK ENGINE
;; ============================================================
(define (run-bench thunk iterations)
  (collect-garbage) (collect-garbage)
  (define mem-before (current-memory-use 'cumulative))
  (define t0 (current-inexact-milliseconds))
  (for ([_ (in-range iterations)]) (thunk))
  (define t1 (current-inexact-milliseconds))
  (define mem-after (current-memory-use 'cumulative))
  (values (- t1 t0) (- mem-after mem-before)))

;; Refatorado para receber todos os metadados e imprimir em colunas separadas por vírgula
(define (benchmark! algo impl n iterations thunk)
  (define-values (ms mem) (run-bench thunk iterations))
  (define current-time (date->string (current-date) #t))
  
  (log-write (format "\"~a\",\"~a\",\"~a\",~a,~a,~a,~a"
                     current-time
                     algo
                     impl
                     n
                     iterations
                     (~r ms #:precision 1)
                     (~r (/ mem 1024.0) #:precision 1))))

;; ============================================================
;; TESTES
;; ============================================================
(log-start)

;; ----------------------------------------------------------
;; TESTE 1 — Algorithm 1: Factorial
;; ----------------------------------------------------------
;; n=10, 500.000 iterações (sem bignum)
(benchmark! "Factorial" "Normal" 10 500000 (lambda () (factorial-normal 10)))
(benchmark! "Factorial" "Tail (acc)" 10 500000 (lambda () (factorial-tail 10)))

;; n=1000, 10.000 iterações (com bignum)
(benchmark! "Factorial" "Normal" 1000 10000 (lambda () (factorial-normal 1000)))
(benchmark! "Factorial" "Tail (acc)" 1000 10000 (lambda () (factorial-tail 1000)))

;; ----------------------------------------------------------
;; TESTE 2 — Algorithm 2: Mutually recursive even/odd
;; ----------------------------------------------------------
;; n=1000, 500.000 iterações
(benchmark! "Mutually Rec (Even)" "Normal" 1000 500000 (lambda () (even-normal 1000)))
(benchmark! "Mutually Rec (Even)" "Tail" 1000 500000 (lambda () (is-even 1000)))

(benchmark! "Mutually Rec (Odd)" "Normal" 1000 500000 (lambda () (odd-normal 1000)))
(benchmark! "Mutually Rec (Odd)" "Tail" 1000 500000 (lambda () (is-odd 1000)))

;; ----------------------------------------------------------
;; TESTE 3 — Algorithm 3: Three-state machine A→B→C→A
;; ----------------------------------------------------------
;; k=999 (múltiplo de 3), 500.000 iterações
(benchmark! "State Machine" "Normal" 999 500000 (lambda () (state-a-normal 999)))
(benchmark! "State Machine" "Tail" 999 500000 (lambda () (state-a 999)))

(log-close)