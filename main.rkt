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
  (log-write "Benchmark Tail Call vs Normal — Racket")
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
;; IMPLEMENTAÇÕES
;; ============================================================
(define (factorial-normal n)
  (if (= n 0) 1 (* n (factorial-normal (- n 1)))))

(define (factorial-tail n)
  (define (loop n acc)
    (if (= n 0) acc (loop (- n 1) (* acc n))))
  (loop n 1))

(define (fib-normal n)
  (if (< n 2) n
      (+ (fib-normal (- n 1)) (fib-normal (- n 2)))))

(define (fib-tail n)
  (define (loop n a b)
    (if (= n 0) a (loop (- n 1) b (+ a b))))
  (loop n 0 1))

(define (sum-normal lst)
  (if (null? lst) 0 (+ (car lst) (sum-normal (cdr lst)))))

(define (sum-tail lst)
  (define (loop lst acc)
    (if (null? lst) acc (loop (cdr lst) (+ acc (car lst)))))
  (loop lst 0))

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
                   (lambda (e)
                     (log-write "STACK OVERFLOW! ✗"))])
    (define result (thunk))
    (log-write (format "OK! (~a)" (result-fn result)))))

;; ============================================================
;; TESTES
;; ============================================================
(log-start)

(section "TESTE 1: Factorial n=10 — 500.000 iterações (sem bignum)")
(benchmark! "Normal   " (lambda () (factorial-normal 10)) 500000)
(benchmark! "Tail Call" (lambda () (factorial-tail   10)) 500000)

(section "TESTE 2: Factorial n=1000 — 10.000 iterações (com bignum)")
(benchmark! "Normal   " (lambda () (factorial-normal 1000)) 10000)
(benchmark! "Tail Call" (lambda () (factorial-tail   1000)) 10000)

(section "TESTE 3: Fibonacci n=30 — 100 iterações (exponencial vs linear)")
(benchmark! "Normal   " (lambda () (fib-normal 30)) 100)
(benchmark! "Tail Call" (lambda () (fib-tail   30)) 100)

(section "TESTE 4: Soma de lista 100.000 elementos — 200 iterações")
(define big-list (build-list 100000 (lambda (i) i)))
(benchmark! "Normal   " (lambda () (sum-normal big-list)) 200)
(benchmark! "Tail Call" (lambda () (sum-tail   big-list)) 200)

(section "TESTE 5: Limite da stack — n=100.000")

(overflow-test "Tail  factorial 100k "
               (lambda () (factorial-tail 100000))
               (lambda (r) (format "~a dígitos" (string-length (number->string r)))))

(overflow-test "Normal factorial 100k"
               (lambda () (factorial-normal 100000))
               (lambda (r) (format "~a dígitos" (string-length (number->string r)))))

(define big-list-2 (build-list 1000000 (lambda (i) i)))

(overflow-test "Tail  soma lista 1M  "
               (lambda () (sum-tail big-list-2))
               (lambda (r) (format "soma = ~a" r)))

(overflow-test "Normal soma lista 1M "
               (lambda () (sum-normal big-list-2))
               (lambda (r) (format "soma = ~a" r)))

(log-close)