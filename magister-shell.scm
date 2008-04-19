;;; -*- mode: Scheme; -*-

(cond-expand
 (compiling
  (declare
   (unit magister-shell)
   (uses library extras posix regex)
   (uses magister-variables)
   (standard-bindings)
   (extended-bindings)
   (bound-to-procedure read-pipe-list read-pipe-line
                       system-execute-action
                       get-configuration)
   (unused read-pipe-line system-execute-action get-configuration)))
 (else
  (use extras posix regex)
  (use magister-variables)))

;;; Reads a list of lines for a pipe.
;;; Returns the output of the pipe, as a list of strings.
(define (read-pipe-list commandline)
  (call-with-input-pipe commandline read-lines))

;;; Read a single line of input from a pipe.
;;; Returns the first line of the output of the pipe,
;;; as a string.
(define (read-pipe-line commandline)
  (car (read-pipe-list commandline)))

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
