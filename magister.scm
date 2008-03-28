#! /bin/sh
#| -*- mode: Scheme; mode: folding; -*-
exec csi -ss $0 "$@"
|#
;;; Copyright (c) 2007 Leonardo Valeri Manera <lvalerimanera>@{NOSPAM}<google.com>
;;; This program is licensed under the terms of the General Public License version 2.
;;; Based on the portage script emwrap.sh, (c) 2004-2007 Hiel Van Campen.

;;; Global declarations.
;; {{{ Optimizations.
;; Standard functions are not redefined
(declare (block))
;; Let CSC choose versions of internal library functions for speed
(declare (usual-integrations)
         (standard-bindings)
         (extended-bindings))
;; Declare top-level variables and functions, to allow skipping
;; of bound checks
(declare (always-bound *version*
                       *system-configuration-file*
                       option-alist
                       option-spec
                       pretend
                       resume
                       resume-file)
         (bound-to-procedure option-get
                             option-set!
                             verbose?
                             toolchain?
                             system?
                             everything?
                             print-header
                             print-usage
                             read-pipe-line
                             read-pipe-list
                             get-configuration
                             resume-read
                             resume-write
                             system-execute-action
                             multiple-versions?
                             generate-fqpn
                             generate-installation-command
                             generate-extraction-command
                             extract-packages
                             extract-package
                             paludis-pretend
                             built-with-use?
                             execute-action-list
                             configuration-file-r-ok
                             state-dir-ok?
                             state-file-ok?
                             version-lock-ok?
                             read-configuration-file
                             parse-commandlines
                             parse-options
                             check-environment))
;; }}}

;;; Interpreter settings.
;; {{{ Extensions.
(use posix)
(use srfi-1)
(use miscmacros)
(use args)
;; }}}

;;; Top-level variables.
;; {{{ Constants.
;; The version of the application, duh.
(define-constant *version* "0.1.5")
;; The location of the configuration file.
(define-constant *system-configuration-file* "/etc/properize.conf")
;; }}}
;; {{{ Globals.
(define option-alist '((#:verbose . #f)
                       (#:toolchain . #f)
                       (#:system . #f)
                       (#:everything . #f)
                       (#:version-lock . #:slot)
                       (#:pre-deps . "discard")
                       (#:checks . "none")
                       (#:debug . "none")))
(define pretend #f)
(define resume #f)
(define state-file "/var/tmp/magister-resume")
;; }}}
;; {{{ option-spec: the 'args option list
(define option-spec (list (args:make-option (p pretend)                 #:none
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
                                     generating package lists"
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
;; }}}

;;; Option functions
;; {{{ (option-get): Returns the value of the option from the option alist.
;; <key> is the key whose value you want to get.
;; Returns whatever was in the cdr of the key's pair, or #f if it wasn't there.
(define (option-get key)
  (alist-ref key option-alist))
;; }}}

;; {{{ (option-set!): Sets the value of the option in the alist to the specified value.
;; <key> is the key whose value you want to set.
;; <value> is the value you want to set for that key.
;; Returns the created alist, but if the <key> was not present the options will not be updated.
(define (option-set! key value)
  (alist-update! key value option-alist))
;; }}}

;; {{{ (<option>?): predicates for binary options.
(define (verbose?) (eqv? (option-get #:verbose) #:yes))
(define (toolchain?) (eqv? (option-get #:toolchain) #:yes))
(define (system?) (eqv? (option-get #:system) #:yes))
(define (everything?) (eqv? (option-get #:everything) #:yes))
;; }}}

;;; Display functions
;; {{{ (print-header): Prints version and basic copyright information.
(define (print-header)
  (begin (print "Magister v" *version* " (" (car (command-line-arguments)) ")")
	 (print "Copyright (c) 2007 Leonardo Valeri Manera")
	 (print "This program is licensed under the terms of the GPL version 2.")
         (newline)))
;; }}}

;; {{{ (print-usage): Prints usage information.
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
;; }}}

;;; Pipe-reading
;; {{{ (read-pipe-line): Runs an input pipe and returns the first line of the output.
;; <command> must be a string and a valid sh command/pipe.
;; Returns whatever was in the 1st line of pipe's output, as a string.
(define (read-pipe-line command)
  (with-input-from-pipe command read-line))
;; }}}

;; {{{ (read-pipe-list): Runs an input pipe and returns the output.
;; <command> must be a string and a valid sh command/pipe.
;; Returns a list of strings, each string being one line of the output.
(define (read-pipe-list command)
  (with-input-from-pipe command read-lines))
;; }}}

;; {{{ (get-configuration): Reads the configuration file, returning the value of variable var.
;; <var> must be a string, the name of the variable you want to retrieve.
;; Returns the value of the variable, as a string.
(define (get-configuration var)
  (let ([varmatch (regexp (string-append var " = "))])
    (string-substitute varmatch
		       ""
		       (car (grep varmatch
				  (with-input-from-file *system-configuration-file* read-lines))))))
;; }}}

;;; Resume-file reading and writing
;; {{{ (resume-read): Reads the resume-file, sets the options and returns the action list.
;; Returns a list.
(define (resume-read)
  (let ([res-list (with-input-from-file state-file read)])
    (set! options (car res-list))
    (cdr res-list)))
;; }}}

;; {{{ (resume-write): Writes the options and action-list into a file.
;; <action-list> better be the list you wanna write to the resume-file
;; Returns undefined.
(define (resume-write action-list)
  (with-output-to-file state-file (lambda () (write (cons options action-list)))))
;; }}}

;;; General command handlers
;; {{{ (system-execute-action): Encapsulate the exit value of a process so it can be used as a condition.
;; <action> must be a string and a valid sh command/pipe.
;; Returns a boolean.
(define (system-execute-action action)
  (= 0 (nth-value 2 (process-wait (process-run action)))))
;; }}}

;;; General paludis handlers
;; {{{ (multiple-versions?): predicate for forcing slot info in fqpn generation.
;; <package-name> is a valid category/name string.
;; returns a boolean if multiple versions exist.
(define (multiple-versions? package-name)
  (< 1 (length (read-pipe-list (string-append "paludis --match " package-name)))))
;; }}}

;; {{{ (generate-fqpn): Generates a package-spec from a (package slot version) list.
;; <package-list> must be a valid 3-part package-spec list
;; Returns a string
(define (generate-fqpn package-list)
  (let ([version-lock (option-get #:version-lock)])
    (cond [(or (eq? version-lock #:slot)
               (multiple-versions? (first package-list)))
           (string-append (first package-list) (second package-list))]
          [(eq? version-lock #:none)
           (first package-list)]
          [else (string-append (first package-list) (second package-list) "[=" (third package-list) "]")])))
;; }}}

;; {{{ (generate-installation-command): Generates an installation commandline.
;; <package> must be a string.
;; Returns a string.
(define (generate-installation-command package-list)
  (let ([checks (option-get #:checks)]
	[debug (option-get #:debug)])
    (string-append "paludis -i1 "
		   "--checks " checks " "
		   "--dl-deps-default discard "
		   "--debug-build " debug " "
		   (generate-fqpn package-list))))
;; }}}

;; {{{ (generate-extraction-command): Generates a package-extraction commandline.
;; <target> must be a valid package/set as a string.
;; Returns a string.
(define (generate-extraction-command target)
  (let ([upgrade (option-get #:upgrade)]
	[pre-dependencies (option-get #:pre-dependencies)])
    (string-append "paludis -pi "
		   "--show-use-descriptions none "
		   "--compact "
		   (if upgrade
		       "--dl-upgrade always "
		       "--dl-upgrade as-needed ")
		   "--dl-new-slots as-needed "
		   (if (not (or (string=? target "system")
				(string=? target "everything")))
		       "--dl-deps-default discard "
		       (string-append "--dl-installed-deps-pre "
				      pre-dependencies " "
				      "--dl-reinstall always "))
		   target " 2>/dev/null")))
;; }}}

;; {{{ (extract-packages): Given a target, generates a list of the packages to be installed.
;; <target> must be a string. It better be a valid set or pakage.
;; Returns a list, '() in case the target is invalid - or in case of any other failure along the
;; way, tbqh.
(define (extract-packages target)
  (let* ([command (generate-extraction-command target)]
	 [package-match (regexp "^\\* ([^[:space:]]+)/([^[:space:]]+) ")]
	 [package-lines (grep package-match
			     (read-pipe-list command))]
	 [version-match (regexp "([^[:space:]]+)\\]")]
	 [atom-explode
	  (lambda (package-line)
	    (let* ([package-list (string-split package-line)]
		   [package-name (second package-list)]
		   [package-slot (if (eq? #\: (string-ref (third package-list) 0))
				     (third package-list)
				     "")]
		   [package-version (if (< 0 (string-length package-slot))
					(if (string=? "->" (fifth package-list))
					    (string-substitute version-match "\\1" (sixth package-list))
					    (string-substitute version-match "\\1" (fifth package-list)))
					(if (string=? "->" (fourth package-list))
					    (string-substitute version-match "\\1" (fifth package-list))
					    (string-substitute version-match "\\1" (fourth package-list))))])
	      (list package-name package-slot package-version)))])
    (map atom-explode package-lines)))
;; }}}

;; {{{ (extract-package): single-package wrapper for (paludis-extract-packages)
(define (extract-package target)
  (first (extract-packages target)))
;; }}}

;; {{{ (pretend-install): Does what it says on the box, tbfh.
(define (paludis-pretend action-list)
  (let* ([pretend-command "paludis -pi --dl-deps-default discard --show-reasons none --show-use-descriptions changed"]
	 [append-package!
	  (lambda (package-list)
	    (set! pretend-command (string-append pretend-command " " (generate-fqpn package-list))))])
    (for-each append-package! action-list)
    (system-execute-action pretend-command)
    (exit)))
;; }}}

;; {{{ (built-with-use?): Checks if a package has been built with a USE flag.
(define (built-with-use? package-list flag)
  (pair? (grep flag (read-pipe-list (string-append "paludis --environment-variable "
                                                   (first package-list) (second package-list) "[=" (third package-list) "]"
                                                   " USE")))))
;; }}}

;;; Action-list execution
;; {{{ (execute-action-list): Iterates over an action list, saving it to disk before running it.
(define (execute-action-list action-list)
  (do ([action-list action-list (cdr action-list)])
      ((null? action-list) (delete-file resume-file))
    (resume-write action-list)
    (unless (system-execute-action (generate-installation-command (car action-list)))
      (print "\nPaludis encountered an error!")
      (exit 1))))
;; }}}

;;; Action-list generation
;; {{{ (generate-toolchain-list): Creates a list of toolchain packages to be reinstalled.
;; linux-headers glibc libtool binutils (gmp mpfr) gcc ?libstdc++-v3 ?gcc:3.3
(define (generate-toolchain-list)
  (let* ([package-table (make-hash-table)]
	 [toolchain-list (list (extract-package "linux-headers"))]
	 [libstdc++?
	  (system-execute-action "paludis --match sys-libs/libstdc++-v3")]
	 [gcc-3.3?
	  (system-execute-action "paludis --match sys-devel/gcc:3.3")]
	 [mpfr?
	  (and (string-match ":4\\..*" (second (hash-table-ref package-table "gcc")))
	       (built-with-use? (hash-table-ref package-table "gcc") "fortran"))])
    (for-each (lambda (package) (hash-table-set! package (extract-package package)))
	      '("glibc" "libtool" "binutils" "gcc"))
    (when libstdc++?
      (hash-table-set! "libstdc++" (extract-package "libstdc++-v3")))
    (when gcc-3.3?
      (hash-table-set! "gcc-3.3" (extract-package "sys-devel/gcc:3.3")))
    (when mpfr?
      (hash-table-set! "gmp" (extract-package "gmp"))
      (hash-table-set! "mpfr" (extract-package "mpfr")))
    (repeat 2
            (for-each (lambda (package-name)
                        (set! toolchain-list (append toolchain-list (hash-table-ref package-table package-name))))
                      '("glibc" "libtool" "binutils"))
            (when mpfr?
              (set! toolchain-list (append toolchain-list (hash-table-ref package-table "gmp")))
              (set! toolchain-list (append toolchain-list (hash-table-ref package-table "mpfr"))))
            (set! toolchain-list (append toolchain-list (hash-table-ref package-table "gcc"))))
    (when gcc-3.3?
      (set! toolchain-list (append toolchain-list (hash-table-ref package-table "gcc-3.3"))))
    (when libstdc++?
      (set! toolchain-list (append toolchain-list (hash-table-ref package-table "libstdc++"))))
    toolchain-list))
;; }}}

;; {{{ (generate-action-list): Generates a list of actions and passes it to execute-action-list.
(define (generate-action-list)
  (let ([action-list '()]
        [tc-list '()]
	[system-list '()]
	[everything-list '()]
        [list=? (lambda (a b)
                  (list= string=? a b))])
    (display "\nCollecting Toolchain... ")
    (set! tc-list (generate-toolchain-list))
    (print "done")
    (when (or system? everything?)
	(display "\nCollecting System... ")
        (set! system-list
              (lset-difference
               list=?
               (extract-packages "system")
               tc-list))
        (print "done"))
    (when everything?
	(display "\nCollecting Everything... ")
        (set! everything-list
              (lset-difference
               list=?
               (extract-packages "everything")
               system-list
               tc-list))
        (print "done"))
    (when toolchain?
      (set! action-list tc-list))
    (when system?
      (set! action-list (append action-list system-list)))
    (when everything?
      (set! action-list (append action-list everything-list)))
    (when pretend
      (pretend-install action-list))
    (execute-action-list action-list)))
;; }}}

;;; File validity predicates
;; {{{ (configuration-file-r-ok?): Checks configuration file readability.
;; Returns boolean.
(define (configuration-file-r-ok?)
  (file-read-access? *system-configuration-file*))
;; }}}

;; {{{ (state-dir-ok?): Checks permissions of the state directory.
;; <file> is a string pointing to the dir to be checked.
;; Returns boolean; true if the dir is +rwx to us, otherwise returns false.
(define (state-dir-ok? path)
  (and (file-read-access? state-dir)
       (file-write-access? state-dir)
       (file-execute-access? state-dir)))
;; }}}

;; {{{ (state-file-ok?) Checks permissions of the state file (if it exists).
;; <file> is a string or file descriptor object.
;; Returns boolean; true if the file either does not exist, or does and is +rw to us,
;; otherwise returns false.
(define (state-file-ok? file)
  (or (not (file-exists? state-file))
      (and (file-read-access? state-file)
           (file-write-access? state-file))))
;; }}}

;;; Option validity predicates
;; {{{ (version-lock-ok?): Checks validity of #:version-lock option.
;; <+version-lock+> must be a keyword
;; Returns boolean.
(define (version-lock-ok? +version-lock+)
  (or (eq? +version-lock+ #:none)
      (eq? +version-lock+ #:slot)
      (eq? +version-lock+ #:version)))
;; }}}

;;; Configuration file parser.
;; {{{ (read-configuration-file): Reads the configuration file, checks option validity, and sets the variables.
;; Returns undefined, if anything is wrong it prints an error message and exits :)
;; TD: Checking the options that are to be passed to paludis would be nice...
(define (read-configuration-file)
  (let* ([+state-file+ (get-configuration "state-file")]
         [+state-dir+ (pathname-directory +state-file+)]
         [+version-lock+ (string->keyword (get-configuration "version-lock"))]
         [+pre-dependencies+ (get-configuration "pre-dependencies")]
         [+checks+ (get-configuration "checks")]
         [+debug+ (get-configuration "debug")])
    (cond [(and (not state-dir-ok? +state-dir+)
		(not state-file-ok? +state-file+))
	   (begin (print "\nIncorrect permissions for path: " +state-dir+ "\n"
                         "                      and file: " +state-file+)
                  (exit 1))]
	  [(not (state-file-ok? +state-file+))
	   (begin (print "\nIncorrect permissions for path: " +state-dir+)
                  (exit 1))]
	  [(not (state-dir-ok? +state-dir+))
	   (begin (print "\nIncorrect permissions for file: " +state-file+)
		  (exit 1))]
          [else (set! state-file +state-file+)])
    (if (version-lock-ok? +version-lock+)
        (option-set! #:version-lock)
        (begin (print "\nIn " *system-configuration-file* "\n"
                      "Unrecognised value for option 'version-lock': " +version-lock+)
               (exit 1)))
    (option-set! #:pre-dependencies +pre-dependencies+)
    (option-set! #:checks +checks+)
    (option-set! #:debug +debug+)))
;; }}}

;;; Command-line option parser
;; {{{ (parse-commandline): Parses commandline using (args).
(define (parse-commandline)
  (receive (options operands)
      (args:parse (command-line-arguments) option-spec)
    (set! resume (alist-ref 'resume options)
    (set! pretend (alist-ref 'pretend options)
    (option-set! #:verbose (or (alist-ref 'verbose options) #f))
    (option-set! #:toolchain (or (alist-ref 'toolchain options) #f))
    (option-set! #:system (or (alist-ref 'system options) #f))
    (option-set! #:everything (or (alist-ref 'everything options) #f))
    (option-set! #:upgrade (or (alist-ref 'upgrade options) #f))
    (option-set! #:version-lock (or (string->keyword (alist-ref 'version-lock options)) #:slot))
    (option-set! #:pre-deps (or (alist-ref 'dl-installed-deps-pre options) "discard"))
    (option-set! #:checks (or (alist-ref 'checks options) "none"))
    (option-set! #:debug (or (alist-ref 'debug-build options) "none"))))
;; }}}

;;; Argument parser
;; {{{ Controls parsing and validation of file and commandline options, sets global
;; options and initial environment, and initiates action-list generation or resuming
;; and action-list execution.
(define (parse-options)
  (read-configuration-file)
  (parse-commandline)
  ;; clear the PALUDIS_OPTIONS env var.
  (unsetenv "PALUDIS_OPTIONS")
  (if resume
      ;; If we got told to resume, read the state file and pass the
      ;; action-list to (execute-action-list).
      (begin (print "\nResuming ...")
             (execute-action-list (resume-read))
      ;; Else, proceed with action-list generation.
      (begin (if verbose (display "\nInitializing...\n"))
             (generate-action-list))))
;; }}}

;;; The world is burning, run!
;; {{{ Validates non-option environment, starts option parsing.
(define (main)
  ;; check that the state-dir variable points to a valid location.
  (when (not (configuration-file-r-ok?))
    (print "\nCannot read the confugration file.")
    (exit 1)))
  ;; if called w. no arguments, print help and exit.
  (if (null? (command-line-arguments))
      (begin (print-header)
             (print-help)
             (exit))
      (parse-options)))
;; }}}

;;; Program starts on last line *g*
#;(check-environment)
