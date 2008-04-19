#!/bin/sh
#| -*- mode: scheme; -*-
exec csi -ss $0 "$@"
|#
;;; Copyright (c) 2007-2008 Leonardo Valeri Manera <l DOT valerimanera AT google DOT com>
;;; This program is licensed under the terms of the General Public License version 2.

;;; Global declarations.
(cond-expand
 (compiling
  (declare
   (uses library extras posix utils regex srfi-1 srfi-13 srfi-69))
  (use args miscmacros)
  (declare
   (uses magister-variables magister-paludis magister-shell)
   (standard-bindings)
   (extended-bindings)
   (always-bound option-spec)
   (bound-to-procedure print-header print-usage resume-read resume-write
                       configuration-file-r-ok state-dir-ok? state-file-ok? version-lock-ok?
                       read-configuration-file parse-commandline
                       parse-options check-environment)))
 (else
  (use extras posix utils regex srfi-1 srfi-13 srfi-69)
  (use args miscmacros)
  (use magister-variables magister-paludis magister-shell)))

;;; clear the PALUDIS_OPTIONS env var.
(unsetenv "PALUDIS_OPTIONS")

;;; Display functions
;; (print-header): Prints version and basic copyright information.
(define (print-header)
  (begin (print "Magister v" (session-version session))
	 (print "Copyright (c) 2007-2008 Leonardo Valeri Manera")
	 (print "This program is licensed under the terms of the GPL version 2.")
         (newline)))

;; (print-usage): Prints usage information.
(define (print-usage)
  (with-output-to-port (current-output-port)
    (lambda ()
      (print "Usage: magister [options ...]")
      (print "Rebuild all installed packages, or parts thereof.")
      (newline)
      (print (parameterize ((args:separator ", ")
                            (args:indent 2)
                            (args:width 35))
               (args:usage option-spec)))
      (newline)
      (print "This is not a general-operation wrapper script, it is merely intended to help in
making one's installation consistent after a toolchain version or *FLAG change.
It *does not* automagically detect what updates will be done and do it for you.
It will not work binutils-config or gcc-config for you.
It is most certainly *NOT* intended to be run *before* the new toolchain package
is installed.
*I* use it to make my system consistent *after* that has been done.
If you want a script that does more, WRITE ONE.

Notes.
During package-list generation, \"toolchain\" is subtracted from \"system\",
and \"system\" from \"everything\", in order to remove unnecessary
compilation and minimize execution time.

The toolchain is rebuilt in this order. As far as I know this is the \"correct\"
order, if there is such a thing:

  linux-headers glibc binutils (gmp mpfr) gcc glibc binutils (gmp mpfr) gcc

GMP and MPFR are dependent on the version of gcc detected, and - for versions
earlier than 4.3 - whether the fortran USE-flag is enabled.

After that's done, if its present,

  libstdc++-v3

will be installed.")
      (newline)
      (print "Examples:
  magister -t                        Rebuild the toolchain.
  magister -ts --version-lock=none   Rebuild toolchain and system,
                                     allowing slot upgrades.")
      (newline)
      (print "Report bugs to l DOT valerimanera AT gmail DOT com.")))
  (exit))

;;; args options spec.
(define option-spec (list (args:make-option (p pretend)              #:none
                                            "Pretend only: do not reinstall")
                          (args:make-option (V verbose)              #:none
                                               "Be verbose about what's going on\n")
                          (args:make-option (t toolchain)            #:none
                                               "Reinstall the toolchain")
                          (args:make-option (s system)               #:none
                                               "Reinstall the 'system' set
                                     Toolchain packages are filtered out")
                          (args:make-option (e everything)           #:none
                                               "Reinstall the 'everything' set
                                     Toolchain and 'system' packages are filtered out\n")
                          (args:make-option (u upgrade)              #:none
                                               "Pass --dl-upgrade always to paludis while
                                     generating package lists")
                          (args:make-option (version-lock)          (#:required "level")
                                               "How specific to be about the package's version
                     none            Only use the package category/name
                     slot            Use slot information where appropriate (default)
                     version         Use the version number")
                          (args:make-option (dl-installed-deps-pre) (#:required "option")
                                               "As per the paludis option")
                          (args:make-option (checks)                (#:required "when")
                                               "As per the paludis option, defaults to 'none'")
                          (args:make-option (debug-build)           (#:required "option")
                                               "As per the paludis option, defaults to 'none'\n")
                          (args:make-option (r resume)               #:none
                                               "Resume an interrupted operation\n\n")
                          (args:make-option (v version)              #:none
                                               "Print version and exit"
                                               (print-header)
                                               (exit))
                          (args:make-option (h help)                 #:none
                                               "Display this text"
                                               (print-usage))))

;;; Action-list generation
;; (generate-toolchain-list): Creates a list of toolchain packages to be reinstalled.
;; linux-headers glibc libtool binutils (gmp mpfr) gcc ?libstdc++-v3 ?gcc:3.3
(define (generate-toolchain-list state)
  (let* ([package-table (make-hash-table string-ci=? string-ci-hash)]
	 [toolchain-list (list (extract-package state "linux-headers"))]
	 [libstdc++?
	  (system-execute-action "paludis --match sys-libs/libstdc++-v3 &>/dev/null")]
	 [gcc-3.3?
	  (system-execute-action "paludis --match sys-devel/gcc:3.3 &>/dev/null")]
	 [mpfr? #f])
    (for-each (lambda (package) (hash-table-set! package-table package (extract-package state package)))
	      '("glibc" "libtool" "binutils" "gcc"))
    (set! mpfr? (or (>= 4.3 (string->number (string-drop (package-slot (hash-table-ref package-table "gcc")) 1)))
                    (and (string-match ":4\\..*" (package-slot (hash-table-ref package-table "gcc")))
                         (built-with-use? (hash-table-ref package-table "gcc") "fortran"))))
    (when libstdc++?
      (hash-table-set! package-table "libstdc++" (extract-package state "libstdc++-v3")))
    (when gcc-3.3?
      (hash-table-set! package-table "gcc-3.3" (extract-package state "sys-devel/gcc:3.3")))
    (when mpfr?
      (hash-table-set! package-table "gmp" (extract-package state "gmp"))
      (hash-table-set! package-table "mpfr" (extract-package state "mpfr")))
    (repeat 2
            (for-each (lambda (package-name)
                        (set! toolchain-list (append toolchain-list (list (hash-table-ref package-table package-name)))))
                      '("glibc" "libtool" "binutils"))
            (when mpfr?
              (set! toolchain-list (append toolchain-list (list (hash-table-ref package-table "gmp"))))
              (set! toolchain-list (append toolchain-list (list (hash-table-ref package-table "mpfr")))))
            (set! toolchain-list (append toolchain-list (list (hash-table-ref package-table "gcc")))))
    (when gcc-3.3?
      (set! toolchain-list (append toolchain-list (list (hash-table-ref package-table "gcc-3.3")))))
    (when libstdc++?
      (set! toolchain-list (append toolchain-list (list (hash-table-ref package-table "libstdc++")))))
    toolchain-list))

;; (generate-action-list): Generates a list of actions and passes it to execute-action-list.
(define (generate-action-list state)
  (let ([action-list '()]
        [tc-list '()]
	[system-list '()]
	[everything-list '()])
    (display "\nCollecting Toolchain... ")
    (set! tc-list (generate-toolchain-list state))
    (print "done")
    (when (or (system? state)
              (everything? state))
	(display "\nCollecting System... ")
        (set! system-list
              (lset-difference equal? (extract-packages state "system") tc-list))
        (print "done"))
    (when (everything? state)
	(display "\nCollecting Everything... ")
        (set! everything-list
              (lset-difference equal? (extract-packages state "everything") system-list tc-list))
        (print "done"))
    (when (toolchain? state)
      (set! action-list tc-list))
    (when (system? state)
      (set! action-list (append action-list system-list)))
    (when (everything? state)
      (set! action-list (append action-list everything-list)))
    (if (pretend?)
        (paludis-pretend state action-list)
        (execute-action-list state action-list))))

;;; File validity predicates
;; (configuration-file-r-ok?): Checks configuration file readability.
;; Returns boolean.
(define (configuration-file-r-ok?)
  (file-read-access? (session-config-file session)))

;; (state-dir-ok?): Checks permissions of the state directory.
;; <file> is a string pointing to the dir to be checked.
;; Returns boolean; true if the dir is +rwx to us, otherwise returns false.
(define (state-dir-ok? path)
  (and (file-read-access? path)
       (file-write-access? path)
       (file-execute-access? path)))

;; (state-file-ok?) Checks permissions of the state file (if it exists).
;; <file> is a string or file descriptor object.
;; Returns boolean; true if the file either does not exist, or does and is +rw to us,
;; otherwise returns false.
(define (state-file-ok? file)
  (or (not (file-exists? file))
      (and (file-read-access? file)
           (file-write-access? file))))

;;; Option validity predicates
;; (version-lock-ok?): Checks validity of #:version-lock option.
;; <+version-lock+> must be a keyword
;; Returns boolean.
(define (version-lock-ok? version-lock)
  (or (eq? version-lock 'none)
      (eq? version-lock 'slot)
      (eq? version-lock 'version)))

;;; Configuration file parser.
;; (read-configuration-file): Reads the configuration file, checks option validity, and sets the variables.
;; <state> must be the state record.
;; Returns a state record with the configuration, if anything is wrong it prints an error message and exits :)
;; TD: Checking the options that are to be passed to paludis would be nice...
(define (read-configuration-file state)
  (let* ([state-file   (get-configuration "state-file")]
         [state-dir    (pathname-directory state-file)]
         [version-lock (string->symbol (get-configuration "version-lock"))]
         [pre-deps     (get-configuration "pre-dependencies")]
         [checks       (get-configuration "checks")]
         [debug        (get-configuration "debug")])
    (cond [(and (not (state-dir-ok? state-dir))
		(not (state-file-ok? state-file)))
	   (begin (print "\nIncorrect permissions for path: " state-dir "\n"
                         "                      and file: " state-file)
                  (exit 1))]
	  [(not (state-file-ok? state-file))
	   (begin (print "\nIncorrect permissions for path: " state-dir)
                  (exit 1))]
	  [(not (state-dir-ok? state-dir))
	   (begin (print "\nIncorrect permissions for file: " state-file)
		  (exit 1))]
          [else (session-state-file-set! session state-file)])
    (if (version-lock-ok? version-lock)
        (state-version-lock-set! state version-lock)
        (begin (print "\nIn " (session-config-file session) "\n"
                      "Unrecognised value for option 'version-lock': " version-lock)
               (exit 1)))
    (state-pre-deps-set! state pre-deps)
    (state-checks-set! state checks)
    (state-debug-set! state debug)
    state))

;;; Command-line option parser
;; (parse-commandline): Parses commandline using (args).
(define (parse-commandline state)
  (receive (options operands)
      (args:parse (command-line-arguments) option-spec)
    (session-resume-set!  session (pair? (assq 'resume options)))
    (session-pretend-set! session (pair? (assq 'pretend options)))
    (state-verbose-set!      state (pair? (assq 'verbose options)))
    (state-toolchain-set!    state (pair? (assq 'toolchain options)))
    (state-system-set!       state (pair? (assq 'system options)))
    (state-everything-set!   state (pair? (assq 'everything options)))
    (state-upgrade-set!      state (pair? (assq 'upgrade options)))
    (state-version-lock-set! state (string->symbol (or (alist-ref 'version-lock options) "slot")))
    (state-pre-deps-set!     state (or (alist-ref 'dl-installed-deps-pre options) "discard"))
    (state-checks-set!       state (or (alist-ref 'checks options) "none"))
    (state-debug-set!        state (or (alist-ref 'debug-build options) "none"))
    (print options)
    (print session)
    (print state)
    state))

;;; Argument parser
;; Controls parsing and validation of file and commandline options, sets global
;; options and initial environment, and initiates action-list generation or resuming
; and action-list execution.
(define (parse-options)
  (let ([state (make-state #f #f #f #f 'slot "discard" #f "none" "none")])
    (set! state (read-configuration-file state))
    (set! state (parse-commandline state))
    (if (resume?)
        ;; If we got told to resume, read the state file and pass the
        ;; action-list to (execute-action-list).
        (begin (print "\nResuming ...")
               (execute-action-list state (resume-read)))
        ;; Else, proceed with action-list generation.
        (begin (if (verbose? state) (print "\nInitializing..."))
               (generate-action-list state)))))

;;; The world is burning, run!
;; Validates non-option environment, starts option parsing.
(define (main args)
  ;; check that the state-dir variable points to a valid location.
  (unless (configuration-file-r-ok?)
    (print "\nCannot read the configuration file.")
    (exit 1))
  ;; if called w. no arguments, print help and exit.
  (if (null? args)
      (begin (print-header)
             (print-usage)
             (exit))
      (parse-options)))

(when (compiled?)
  (main (command-line-arguments)))
