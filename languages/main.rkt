#lang racket
(require racket/date)

;; ============================================================
;; REPRODUTIBILIDADE
;; ============================================================
(random-seed 42)

;; ============================================================
;; LOGGER (Formato CSV)
;; ============================================================
(define log-port (open-output-file "bench_results_scheme.csv"
                                   #:mode 'text
                                   #:exists 'replace))

(define (log-write line)
  (displayln line)
  (displayln line log-port)
  (flush-output log-port))

(define (log-start)
  (log-write "Data,Algoritmo,Implementacao,N,Iteracoes,Run,Ciclos_CPU,Ciclos_por_iter,Memoria_KB,Freq_GHz"))

(define (log-close)
  (close-output-port log-port)
  (displayln "\nLog salvo em: bench_results_scheme.csv"))

;; ============================================================
;; Algorithm 1 -- Factorial
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
;; Algorithm 2 -- Mutually recursive even/odd
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
;; Algorithm 3 -- Three-state machine
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
;; CPU FREQUENCY
;; ============================================================
(define (get-cpu-freq-ghz)
  (with-handlers ([exn:fail? (lambda (_) 2.0)])
    (define content (file->string "/proc/cpuinfo"))
    (define m (regexp-match #rx"cpu MHz[ \t]*:[ \t]*([0-9.]+)" content))
    (if m (/ (string->number (cadr m)) 1000.0) 2.0)))

(define cpu-freq-ghz (get-cpu-freq-ghz))

;; ============================================================
;; CONFIGURACAO
;; ============================================================
(define MAX-TIME-SEC 60)

(define QUICK (equal? (getenv "BENCH_QUICK") "1"))
(define RUNS-PER-POINT (if QUICK 2 10))
(define SWEEP-CHEAP
  (if QUICK '(10000 100000) '(10000 30000 100000 300000 1000000)))
(define SWEEP-FACTORIAL-BIGNUM
  (if QUICK '(200 1000) '(200 500 1000 3000 10000)))

(when QUICK
  (displayln "[BENCH_QUICK=1] usando sweep reduzido e 2 runs por ponto"))

;; ============================================================
;; BENCHMARK ENGINE
;; ============================================================
(define (current-timestamp)
  (parameterize ([date-display-format 'iso-8601])
    (date->string (current-date) #t)))

(define (run-single algo impl n iterations run-id thunk)
  (collect-garbage) (collect-garbage)
  (define mem-before (current-memory-use 'cumulative))
  (define t0 (current-process-milliseconds))
  (define wall-start (current-inexact-milliseconds))
  (define ts (current-timestamp))
  (define result
    (with-handlers ([exn:fail? (lambda (e) (cons 'error (exn-message e)))])
      ;; Roda dentro de uma custodian-controlled thread para suportar timeout
      (define ch (make-channel))
      (define cust (make-custodian))
      (parameterize ([current-custodian cust])
        (thread (lambda ()
                  (with-handlers ([exn:fail? (lambda (e) (channel-put ch (cons 'error (exn-message e))))])
                    (for ([_ (in-range iterations)]) (thunk))
                    (channel-put ch 'ok)))))
      (define out (sync/timeout MAX-TIME-SEC ch))
      (custodian-shutdown-all cust)
      (cond
        [(not out) (cons 'timeout "TIMEOUT")]
        [else out])))
  (define t1 (current-process-milliseconds))
  (define mem-after (current-memory-use 'cumulative))
  (cond
    [(eq? result 'ok)
     (define cpu-ms (- t1 t0))
     (define cycles (* (/ cpu-ms 1000.0) cpu-freq-ghz 1e9))
     (define cycles-per-iter (/ cycles iterations))
     (define mem-kb (/ (- mem-after mem-before) 1024.0))
     (log-write (format "\"~a\",\"~a\",\"~a\",~a,~a,~a,~a,~a,~a,~a"
                        ts algo impl n iterations run-id
                        (~r cycles #:precision 0)
                        (~r cycles-per-iter #:precision 2)
                        (~r mem-kb #:precision 1)
                        (~r cpu-freq-ghz #:precision 4)))
     "OK"]
    [(pair? result)
     (define tag (car result))
     (define msg (cond [(eq? tag 'timeout) "TIMEOUT"]
                       [else (format "ERRO: ~a" (cdr result))]))
     (log-write (format "\"~a\",\"~a\",\"~a\",~a,~a,~a,\"~a\",\"\",\"\",~a"
                        ts algo impl n iterations run-id msg
                        (~r cpu-freq-ghz #:precision 4)))
     msg]))

(define (log-skipped algo impl n iter-count run-id)
  (log-write (format "\"~a\",\"~a\",\"~a\",~a,~a,~a,\"SKIPPED\",\"\",\"\",0.0000"
                     (current-timestamp) algo impl n iter-count run-id)))

(define (run-sweep algo impl n sweep thunk)
  (let loop ([remaining sweep] [consecutive-fails 0])
    (cond
      [(null? remaining) (void)]
      [(>= consecutive-fails 2)
       (let ([iter-count (car remaining)])
         (for ([r (in-range 1 (+ RUNS-PER-POINT 1))])
           (log-skipped algo impl n iter-count r))
         (loop (cdr remaining) consecutive-fails))]
      [else
       (let ([iter-count (car remaining)])
         (define fails-and-stop
           (let pt-loop ([r 1] [fails 0])
             (cond
               [(> r RUNS-PER-POINT) (cons fails #f)]
               [else
                (define status (run-single algo impl n iter-count r thunk))
                (define new-fails (if (or (string=? status "TIMEOUT")
                                          (string=? status "STACK OVERFLOW"))
                                      (+ fails 1) fails))
                (cond
                  [(and (>= new-fails 2) (< r RUNS-PER-POINT))
                   (for ([skip (in-range (+ r 1) (+ RUNS-PER-POINT 1))])
                     (log-skipped algo impl n iter-count skip))
                   (cons new-fails #t)]
                  [else (pt-loop (+ r 1) new-fails)])])))
         (define fails (car fails-and-stop))
         (define half (ceiling (/ RUNS-PER-POINT 2)))
         (loop (cdr remaining)
               (if (>= fails half) (+ consecutive-fails 1) 0)))])))

;; ============================================================
;; TESTES
;; ============================================================
(log-start)

;; ----- Factorial -----
(run-sweep "Factorial" "Normal"     10   SWEEP-CHEAP            (lambda () (factorial-normal 10)))
(run-sweep "Factorial" "Tail (acc)" 10   SWEEP-CHEAP            (lambda () (factorial-tail 10)))
(run-sweep "Factorial" "Normal"     1000 SWEEP-FACTORIAL-BIGNUM (lambda () (factorial-normal 1000)))
(run-sweep "Factorial" "Tail (acc)" 1000 SWEEP-FACTORIAL-BIGNUM (lambda () (factorial-tail 1000)))

;; ----- Mutually Recursive -----
(run-sweep "Mutually Rec (Even)" "Normal" 1000 SWEEP-CHEAP (lambda () (even-normal 1000)))
(run-sweep "Mutually Rec (Even)" "Tail"   1000 SWEEP-CHEAP (lambda () (is-even 1000)))
(run-sweep "Mutually Rec (Odd)"  "Normal" 1000 SWEEP-CHEAP (lambda () (odd-normal 1000)))
(run-sweep "Mutually Rec (Odd)"  "Tail"   1000 SWEEP-CHEAP (lambda () (is-odd 1000)))

;; ----- State Machine -----
(run-sweep "State Machine" "Normal" 999 SWEEP-CHEAP (lambda () (state-a-normal 999)))
(run-sweep "State Machine" "Tail"   999 SWEEP-CHEAP (lambda () (state-a 999)))

(log-close)
