#lang racket
(require racket/date)

;; ============================================================
;; LOGGER
;; ============================================================
(define log-port (open-output-file "bench_results_scheme.log"
                                   #:mode 'text
                                   #:exists 'replace))

(define (log-write line)
  (displayln line)
  (displayln line log-port))

(define (log-start)
  (log-write "========================================")
  (log-write "Benchmark — Recursão Tail Call em Racket")
  (log-write (format "~a" (date->string (current-date) #t)))
  (log-write "========================================\n"))

(define (log-close)
  (log-write "\n========================================")
  (log-write "Fim do benchmark")
  (log-write (format "~a" (date->string (current-date) #t)))
  (log-write "========================================")
  (close-output-port log-port)
  (displayln "\nLog salvo em: bench_results_scheme.log"))

;; ============================================================
;; Algorithm 1 — Factorial with accumulator (self-tail)
;; ============================================================

;; Sem tail call
(define (factorial-normal n)
  (if (= n 0) 1
      (* n (factorial-normal (- n 1)))))

;; Algorithm 1: FACTORIAL(n, acc)
;;   if n = 0 then return acc
;;   else return FACTORIAL(n − 1, n × acc)
(define (factorial-tail n)
  (define (loop n acc)
    (if (= n 0) acc
        (loop (- n 1) (* acc n))))
  (loop n 1))

;; ============================================================
;; Algorithm 2 — Mutually recursive even/odd
;; ============================================================

;; Versão normal
(define (even-normal n)
  (if (= n 0) #t
      (odd-normal (- n 1))))

(define (odd-normal n)
  (if (= n 0) #f
      (even-normal (- n 1))))

;; Algorithm 2: ISEVEN e ISODD mutuamente recursivos
;;   ISEVEN(n): if n=0 → true,  else → ISODD(n−1)
;;   ISODD(n):  if n=0 → false, else → ISEVEN(n−1)
;; Racket garante TCO em chamadas de cauda entre funções distintas
(define (is-even n)
  (if (= n 0) #t
      (is-odd (- n 1))))    ; tail position → TCO

(define (is-odd n)
  (if (= n 0) #f
      (is-even (- n 1))))   ; tail position → TCO

;; ============================================================
;; Algorithm 3 — Three-state machine (A → B → C → A)
;; ============================================================

;; Versão normal
(define (state-a-normal k)
  (if (= k 0) 'finished
      (state-b-normal (- k 1))))

(define (state-b-normal k)
  (if (= k 0) 'finished
      (state-c-normal (- k 1))))

(define (state-c-normal k)
  (if (= k 0) 'finished
      (state-a-normal (- k 1))))

;; Algorithm 3: máquina de três estados com TCO
;;   STATEA(k): if k=0 → finished, else → STATEB(k−1)
;;   STATEB(k): if k=0 → finished, else → STATEC(k−1)
;;   STATEC(k): if k=0 → finished, else → STATEA(k−1)
(define (state-a k)
  (if (= k 0) 'finished
      (state-b (- k 1))))   ; tail position → TCO

(define (state-b k)
  (if (= k 0) 'finished
      (state-c (- k 1))))   ; tail position → TCO

(define (state-c k)
  (if (= k 0) 'finished
      (state-a (- k 1))))   ; tail position → TCO

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

(define (benchmark! label thunk iterations)
  (define-values (ms mem) (run-bench thunk iterations))
  (log-write (format "  ~a\n    Tempo: ~a ms  |  Mem alocada: ~a KB"
                     label
                     (~r ms #:precision 1)
                     (~r (/ mem 1024.0) #:precision 1))))

(define (section title)
  (log-write (format "\n~a\n~a" title (make-string (string-length title) #\-))))

(define (overflow-test label thunk result-fn)
  (display (format "  ~a ... " label))
  (display (format "  ~a ... " label) log-port)
  (with-handlers ([exn:fail?
                   (lambda (e) (log-write "STACK OVERFLOW! ✗"))])
    (define result (thunk))
    (log-write (format "OK! (~a)" (result-fn result)))))

;; ============================================================
;; TESTES
;; ============================================================
(log-start)

;; ----------------------------------------------------------
;; TESTE 1 — Algorithm 1: Factorial with accumulator
;; ----------------------------------------------------------
(section "TESTE 1: Algorithm 1 — Factorial (self-tail)")

(log-write "  n=10, 500.000 iterações (sem bignum)")
(benchmark! "Normal      " (lambda () (factorial-normal 10)) 500000)
(benchmark! "Tail (acc)  " (lambda () (factorial-tail   10)) 500000)

(log-write "")
(log-write "  n=1000, 10.000 iterações (com bignum)")
(benchmark! "Normal      " (lambda () (factorial-normal 1000)) 10000)
(benchmark! "Tail (acc)  " (lambda () (factorial-tail   1000)) 10000)

;; ----------------------------------------------------------
;; TESTE 2 — Algorithm 2: Mutually recursive even/odd
;; ----------------------------------------------------------
(section "TESTE 2: Algorithm 2 — Mutually recursive even/odd")

(log-write "  n=1000, 500.000 iterações")
(benchmark! "Normal even " (lambda () (even-normal 1000)) 500000)
(benchmark! "Tail   even " (lambda () (is-even     1000)) 500000)
(benchmark! "Normal odd  " (lambda () (odd-normal  1000)) 500000)
(benchmark! "Tail   odd  " (lambda () (is-odd      1000)) 500000)


;; ----------------------------------------------------------
;; TESTE 3 — Algorithm 3: Three-state machine A→B→C→A
;; ----------------------------------------------------------
(section "TESTE 3: Algorithm 3 — Three-state machine (A→B→C→A)")

(log-write "  k=999 (múltiplo de 3), 500.000 iterações")
(benchmark! "Normal A→B→C" (lambda () (state-a-normal 999)) 500000)
(benchmark! "Tail   A→B→C" (lambda () (state-a        999)) 500000)


(log-close)