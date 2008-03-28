;;;

(unit shell)

(use posix utils match miscmacros)

;;; Reads a list of lines for a pipe.
;;; Returns the output of the pipe, as a list of strings.
;;; Usage is the same as the chicken (process) function.
(define read-pipe
  (match-lambda*
   [((? atom? commandline))
    (call-with-input-pipe commandline read-lines)]
   [((? atom? command) ((? atom? args) ...))
    (let-values ([(input output pid) (process command args)])
      (process-wait pid)
      (close-output-port output)
      (with-input-from-port input read-lines))]
   [((? atom? command) ((? atom? args) ...) ((? atom? env) ...))
    (let-values ([(input output pid) (process command args env)])
      (process-wait pid)
      (close-output-port output)
      (with-input-from-port input read-lines))]))
;;; As above, but returns raw.
(define read-pipe*
  (match-lambda*
   [((? atom? commandline))
    (with-input-from-pipe
     commandline
     (lambda ()
       (port-map identity read)))]
   [((? atom? command) ((? atom? args) ...))
    (let-values ([(input output pid) (process command args)])
      (process-wait pid)
      (close-output-port output)
      (with-input-from-port input
        (lambda ()
          (port-map identity read))))]
   [((? atom? command) ((? atom? args) ...) ((? atom? env) ...))
    (let-values ([(input output pid) (process command args env)])
      (process-wait pid)
      (close-output-port output)
      (with-input-from-port input
        (lambda ()
          (port-map identity read))))]))

;;; Read a single line of input from a pipe.
;;; Returns the first line of the output of the pipe,
;;; as a string.
;;; Usage is the same as the (process) chicken function.
(define (read-pipe-line . args)
  (car (apply read-pipe args)))
;;; As above, but returns raw.
(define (read-pipe-line* . args)
  (car (apply read-pipe* args)))

;;; A simple wrapper for running shell commands
(define shell
  (case-lambda
   [(commandline)
    (nth-value 1 (process-wait (process-run (->string commandline))))]
   [(command . args)
    (nth-value 1 (process-wait (process-run (->string command) (map ->string args))))]))

;;; Reads the configuration file, returning the value of variable var.
;;; <var> must be a string, the name of the variable you want to retrieve.
;;; Returns the value of the variable, as a string.
(define (get-configuration var)
  (let ([varmatch (regexp (string-append var " = "))])
    (string-substitute varmatch
		       ""
		       (car (grep varmatch
				  (with-input-from-file *system-configuration-file* read-lines))))))
