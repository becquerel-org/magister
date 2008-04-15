;;;

(declare
 (unit shell)
 (usual-integrations)
 (standard-bindings)
 (extended-bindings)
 (bound-to-procedure read-pipe-list read-pipe-list*
                     read-pipe-line read-pipe-line*
                     system-execute-action
                     get-configuration))

(use extras posix utils match)

;;; Reads a list of lines for a pipe.
;;; Returns the output of the pipe, as a list of strings.
;;; Usage is the same as the chicken (process) function.
(define read-pipe-list
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
(define read-pipe-list*
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
  (car (apply read-pipe-list args)))
;;; As above, but returns raw.
(define (read-pipe-line* . args)
  (car (apply read-pipe-list* args)))

;;; A simple wrapper for running shell commands
(define (system-execute-action commandline)
  (= 0 (system commandline)))

;;; Reads the configuration file, returning the value of variable var.
;;; <var> must be a string, the name of the variable you want to retrieve.
;;; Returns the value of the variable, as a string.
(define (get-configuration var)
  (let ([varmatch (regexp (string-append var " = "))])
    (string-substitute varmatch
		       ""
		       (car (grep varmatch
				  (with-input-from-file (session-config-file session) read-lines))))))
