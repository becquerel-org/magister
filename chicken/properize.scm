#!/usr/bin/csi -script
;;;; Copyright (c) 2007 Leonardo Valeri Manera <lvalerimanera>@{NOSPAM}<google.com>
;;;; This program is licensed under the terms of the General Public License version 2.
;;;; Based on the portage script emwrap.sh, (c) 2004-2007 Hiel Van Campen.

;; PALUDIS_OPTIONS="" paludis -pi1 --dl-deps-default discard --show-reasons none --show-use-descriptions none --checks none $toolchain
;; PALUDIS_OPTIONS="" paludis -pi1 --dl-deps-default discard --show-reasons none --show-use-descriptions none --checks none --resume-command-template /var/tmp/properize-resume system|everything

;;; We declare all modules used explicitly. This allows us to use -explicit-use
;;; during compilation, resulting in a smaller executable.
(declare (uses library))
;; We need reular expressions.
(declare (uses regex))
;; Getopt-long provides a method to parse standard UNIX-style
;; command-line options.
;(use-modules (ice-9 getopt-long))
;;; This is just the single-line require-etensions used for csi
(use regex)
;;; Set environment options and parameters
;; Global declarations are not redefined
(declare (block))
;; We don't use threading (for now)
(declare (disable-interrupts))
;; Let CSC choose versions of internal library functions for speed
(declare (usual-integrations))

;;; Version and similar constants
(define-constant *properize-version* "0.0.1")

;;; Load the configuration file
(load "/etc/properize.conf")

;;; Display functions
(define (print-header)
  (begin (display "Properize ") (display *properize-version*) (display " (") (display program-name) (display ")\n")
	 (display "Copyright (c) 2007 Leonardo Valeri Manera <lvalerimanera>@{NOSPAM}google.com\n")
	 (display "This program is licensed under the terms of the GPL version 2.\n")
	 (display "Based on the portage script emwrap.sh, (c) 2004-2007 Hiel Van Campen.\n\n")))
(define (print-help)
  (display"\
properize [options]
  -v --version           Display version.
  -h --help              Display this help.

  -p --pretend           Pretend only.

  -t --toolchain[=$TYPE]
                         Rebuild toolchain. Optional argument defines the
                         type of operation. See below.
  -s --system[=all]      Rebuild set:system. Optional argument rebuilds
                         toolchain as well
  -e --everything[=all]  Rebuild set:everything. Optional argument rebuilds
                         set:system as well.

  -V --verbose           Print information about each step - useful for debugging.

  -r --resume            Resume an interrupted operation.

  \"everything\" implies \"system\" implies \"toolchain\";
  This is not a general-operation wrapper script, it is merely
  intended to help in making one's installation consistent after
  a toolchain or flag change.
  During normal operation \"toolchain\" is subtracted from \"system\",
  and \"system\" from \"everything\", in order to remove unnecessary
  compilation and minimize execution time. This behavious can be overridden
  by passing the \"all\" option immediately after the respective
  long (= optional) or short option:

  properize -s all --everything=all

  properize --system all

  Various \"toolchain\" operations are available, specificable immediately
  after the long (= optional) or short option:

  properize -set gcc-single

  properize --system --toolchain=binutils-single

  and so on.

  The toolchain operation types, and the packages that will be rebuilt,
  in order, are:

  Full rebuilds:

  glibc            =\"glibc binutils gcc glibc binutils gcc\" (default)
  binutils|gcc     =\"binutils gcc binutils gcc\"

  Single builds:

  glibc-single          =\"glibc binutils gcc\"
  binutils|gcc-single   =\"binutils gcc\"

  The default value can be overridden in the configuration file.

  Currently, the builds are lifted straight out of emwrap.sh,
  Copyright (c) 2004-2007 Hiel Van Campen.
  If you have a better idea, I'm open to suggestions.\n\n"))
;; we use this a lot if "verbose" is on
(define (print-state)
  (begin (display "State:")
	 (display "\n  Toolchain: ") (display (state-toolchain state))
	 (display "\n  System: ") (display (state-system state))
	 (display "\n  Everything: ") (display (state-everything state))
	 (display "\n  Progress: ") (display (state-progress state)) (newline)))

;;; Convenience functions


;;; Define the "state" vector, and the shortcut functions to read and write to its values
(define-class <properize-state> ()
  ;; Setting the version as a constant at instatiation time will let us warn users about
  ;; resuming from a possibly outdated resume-state file.
  (version #:init-form *properize-version* #:getter state-version?)
  (toolchain #:init-form 0 #:accessor state-toolchain)
  (system #:init-form 0 #:accessor state-system)
  (everything #:init-form 0 #:accessor state-everything)
  (progress #:init-form "Initialization" #:accessor state-progress))
(define state (make-vector 5 '())) ; using the "concrete" version makes reading and writing to file easier
(hashq-create-handle! state 'version *properize-version*) ; we set this right now, as its really a constant

;;; Argument parser
(define (parse-arguments)
  (let* ((set-option? (lambda (arg) (string=? "all" arg)))
	 (toolchain-option? (lambda (arg) (regexp-match? (string-match "^((headers|gcc|binutils|glibc){1}(-single)?)$" arg))))
	 (option-spec `((help (single-char #\h) (value #f))
			(version (single-char #\v) (value #f))
			(pretend (single-char #\p) (value #f))
			(verbose (single-char #\V) (value #f))
			(resume (single-char #\r) (value #f))
			(toolchain (single-char #\t) (value optional) (predicate ,toolchain-option?))
			(system (single-char #\s) (value optional) (predicate ,set-option?))
			(everything (single-char #\e) (value optional) (predicate ,set-option?))))
	 (options (getopt-long (command-line) option-spec))
	 (help-wanted (option-ref options 'help #f))
	 (version-wanted (option-ref options 'version #f))
	 (pretend-wanted (option-ref options 'pretend #t))
	 (verbose-wanted (option-ref options 'verbose #t))
	 (resume-wanted (option-ref options 'resume #f))
	 (toolchain-wanted (option-ref options 'toolchain #f))
	 (system-wanted (option-ref options 'system #f))
	 (everything-wanted (option-ref options 'everything #f)))
    (begin (if help-wanted
	       (begin (print-header) (print-help) (exit)))
	   (if version-wanted
	       (begin (print-header) (exit)))
           ;; The following need to be mebdded in an if w. regards to resume-wanted
           ;; on accounts of if we need to resume we just replace state with the one
           ;; read from resume file, and go.
	   (set! (state-toolchain state) (cond ((eqv? toolchain-wanted #f) 0)
					       ((eqv? toolchain-wanted #t) 1)
					       ((string=? toolchain-wanted "headers") 2)
					       ((string=? toolchain-wanted "headers-single") 3)
					       ((string=? toolchain-wanted "glibc") 4)
					       ((string=? toolchain-wanted "glibc-single") 5)
					       ((or (string=? toolchain-wanted "gcc")
						    (string=? toolchain-wanted "binutils")) 6)
					       ((or (string=? toolchain-wanted "gcc-single")
						    (string=? toolchain-wanted "binutils-single")) 7)))
	   (set! (state-system state) (cond ((eqv? system-wanted #f) 0)
					    ((eqv? system-wanted #t) 1)
					    ((string=? system-wanted "all") 2)))
	   (set! (state-everything state) (cond ((eqv? everything-wanted #f) 0)
						((eqv? everything-wanted #t) 1)
						((string=? everyting-wanted "all") 2)))
	   (set! (state-progress state) "Options Parsed")
	   (if verbose-wanted
	       (begin (display "Options: ") (display options)
		      (newline) (newline) (print-state) (newline)))))
    

;;; The world is burning, run!
(define (main)
  (if (null? (cdr (command-line)))
      (begin (print-header) (print-help) (exit))
      (parse-arguments))
  (execlp "paludis" "paludis" "-p" "-i" "gcc"))

;;; Program starts on last line *g*
(main)
