#! /bin/sh
#| -*- mode: Scheme; mode: folding; -*-
exec csi -s $0 "$@"
|#
;;; Copyright (c) 2007 Leonardo Valeri Manera <lvalerimanera>@{NOSPAM}<google.com>
;;; This program is licensed under the terms of the General Public License version 2.
;;; Based on the portage script emwrap.sh, (c) 2004-2007 Hiel Van Campen.

;;; Library declarations.
;; {{{ Declare all modules used explicitly.
;; This allows us to use -explicit-use during compilation, resulting in a smaller executable.
;; Core chicken libraries needed.
(declare (uses library))
(declare (uses extras))
(declare (uses regex))
(declare (uses utils))
(declare (uses scheduler))
(declare (uses posix))
;; SRFI-1, extended list ops
(declare (uses srfi-1))
;; Args, the voluble option parser.
(declare (uses args)))
;; }}}

;;; Global declarations.
;; {{{ Optimizations.
;; Standard functions are not redefined
(declare (block))
;; Let CSC choose versions of internal library functions for speed
(declare (usual-integrations))
;; }}}

;;; Interpreter settings.
;; {{{ Extensions.
(use posix)
(use srfi-1)
(use args)
;; }}}

;;; Top-level variables.
;; {{{ Constants.
(declare (always-bound *version* *system-configuration-file*))
;; The version of the application, duh.
(define-constant *version* "0.1.5")
;; The location of the configuration file.
(define-constant *system-configuration-file* "/etc/properize.conf")
;; }}}
;; {{{ Globals.
(declare (always-bound options pretend resume-file))
(define options '((#:verbose . #:no)
		  (#:toolchain . #:no)
		  (#:system . #:no)
		  (#:everything . #:no)
		  (#:version-lock . #:slot)
		  (#:pre-deps . "discard")
		  (#:checks . "none")
		  (#:debug . "none")))
(define pretend #f)
(define resume-file "/var/tmp/magister-resume")
;; }}}

;;; Option functions
;; {{{ (get-option): Returns the value of the option from the option alist.
;; <key> is the key whose value you want to get.
;; Returns whatever was in the cdr of the key's pair, or #f if it wasn't there.
(define (get-option key)
  (alist-ref key options))
;; }}}

;; {{{ (set-option): Sets the value of the option in the alist to the specified value.
;; <key> is the key whose value you want to set.
;; <value> is the value you want to set for that key.
;; Returns the created alist, but if the <key> was not present the options will not be updated.
(define (set-option! key value)
  (alist-update! key value options))
;; }}}

;; {{{ (<option>?): predicates for binary options.
(define (verbose?) (eqv? (get-option #:verbose) #:yes))
(define (toolchain?) (eqv? (get-option #:toolchain) #:yes))
(define (system?) (eqv? (get-option #:system) #:yes))
(define (everything?) (eqv? (get-option #:everything) #:yes))
;; }}}

;;; Display functions
;; {{{ Prints version and basic copyright information.
(define (print-header)
  (begin (display "Properize v")
	 (display *properize-version*)
	 (display " (") (display (car (command-line))) (display ")\n")
	 (display "Copyright (c) 2007 Leonardo Valeri Manera ")
	 (display "<lvalerimanera>@{NOSPAM}google.com\n")
	 (display "This program is licensed under the terms of the GPL version 2.\n\n")))
;; }}}

;; {{{ Prints the good old --help dialogue.
(define (print-help)
  (display"\
Usage:
Make installation consistent with toolchain:
     properize [OPTION] [SETS]

Resume an interrupted operation:
     properize --resume
       

Option arguments must follow the option immediately, both these forms are valid:
  --foo=bar
  --foo bar

-General options
  -v --version           Display version.
  -h --help              Display this help.
  -V --verbose           Print information about each step - useful for debugging.

-Action options
  -r --resume            Resume an interrupted operation.
  -p --pretend           Pretend only.
  -u --upgrade           Passes --dl-upgrade always to paludis during set
                         package-list generation.
     --pre-dependencies=deptype
                         Passes the supplied value as argument to
                         --dl-installed-deps-pre to paludis *AS_IS*
                         during set package-list generation.
                         Defaults to \"discard\".
     --checks=runopt     Passes the supplied value as an argument to
                         --checks to paludis *AS_IS* during build
                         operations.
                         Defaults to \"none\".

-Package-list generation options
  -t --toolchain         Rebuild the toolchain.
  -s --system            Rebuild set:system after the toolchain. Implies toolchain.
  -e --everything        Rebuild set:everything after the system. Implies system.

This is not a general-operation wrapper script, it is merely intended to help in
making one's installation consistent after a toolchain or C/CXX/LDFLAG change.
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

  glibc binutils gcc glibc binutils gcc

After that's done, if they're present,

  libtool
  libstdc++-v3

will be installed. Then system (if you asked for it) will be rebuilt.\n\n"))
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
  (let ([res-list (with-input-from-file resume-file read)])
    (set! options (car res-list))
    (cdr res-list)))
;; }}}

;; {{{ (resume-write): Writes the options and action-list into a file.
;; <action-list> better be the list you wanna write to the resume-file
;; Returns undefined.
(define (resume-write action-list)
  (with-output-to-file resume-file (lambda () (write (cons options action-list)))))
;; }}}

;;; General command handlers
;; {{{ (system-execute-action): Encapsulate the exit value of a process so it can be used as a condition.
;; <action> must be a string and a valid sh command/pipe.
;; Returns a boolean.
(define (system-execute-action action)
  (= 0 (nth-value 2 (process-wait (process-run action)))))
;; }}}

;;; Paludis handlers
;; {{{ (paludis-generate-fqpn): Generates a package-spec from a (package slot version) list.
;; <package-list> must be a valid 3-part package-spec list
;; Returns a string
(define (paludis-generate-fqpn package-list)
  (case (get-option #:version-lock)
    [(#:none) (first package-list)]
    [(#:slot) (string-append (first package-list) (second package-list))]
    [else (string-append (first package-list) (second package-list) "[=" (third package-list) "]")]))
;; }}}

;; {{{ (paludis-generate-installation-command): Generates an installation commandline.
;; <package> must be a string.
;; Returns a string.
(define (paludis-generate-installation-command package-list)
  (let ([checks (get-option #:checks)]
	[debug (get-option #:debug)])
    (string-append "paludis -i1 "
		   "--checks " checks " "
		   "--dl-deps-default discard "
		   "--debug-build " debug " "
		   (paludis-generate-fqpn package-list))))
;; }}}

;; {{{ (paludis-generate-extraction-command): Generates a package-extraction commandline.
;; <target> must be a valid package/set as a string.
;; Returns a string.
(define (paludis-generate-extraction-command target)
  (let ([upgrade (get-option #:upgrade)]
	[pre-dependencies (get-option #:pre-dependencies)])
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

;; {{{ (paludis-extract-packages): Given a target, generates a list of the packages to be installed.
;; <target> must be a string. It better be a valid set or pakage.
;; <upgrade> must be a boolean.
;; <pre-dependendencies> must be a string value for the paludis option.
;; <toolchain> must be a boolean, optional, defaults to #f.
;; Returns a list, '() in case the target is invalid - or in case of any other failure along the
;; way, tbqh.
(define (paludis-extract-packages target)
  (let* ([command (paludis-generate-extraction-command target)]
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

;; {{{ (paludis-pretend): Does what it says on the box, tbfh.
(define (paludis-pretend action-list)
  (let ([pretend-command "paludis -pi --dl-deps-default discard --show-reasons none --show-use-descriptions changed"]
	[append-package!
	 (lambda (package-list)
	   (set! pretend-command (string-append pretend-command " " (paludis-generate-fqpn package-list))))])
    (for-each append-package! action-list)
    (system-execute-action pretend-command)
    (exit)))
;; }}}

;;; Action-list execution
;; {{{ (execute-action-list): Iterates over an action list, saving it to disk before running it.
(define (execute-action-list action-list)
  (do ((action-list action-list (cdr action-list)))
      ((null? action-list) (delete-file resume-file))
    (resume-write action-list)
    (unless (system-execute-action (paludis-generate-installation-command (car action-list)))
      (print "\nPaludis encountered an error.")
      (exit 1))))
;; }}}

;;; Action-list generation
;; {{{ (generate-action-list): Generates a list of actions and passes it to execute-action-list.
(define (generate-action-list)
  (let ([]
	(generate-toolchain-list
	 (lambda (upgrade)
	   (let ((toolchain-list '("linux-headers" "glibc" "libtool" "binutils" "mpfr" "gcc" "glibc" "libtool" "binutils" "mpfr" "gcc"))
		 (libstdc++-needed
		  (if (eof-object? (read-pipe-line "ls /var/db/pkg/sys-libs/ | grep libstdc\\+\\+-v3"))
		      #f #t))
		 (toolchain-packages '("")))
	     (if libstdc++-needed (append! toolchain-list '("libstdc++-v3")))
	     (do ((toolchain-list toolchain-list (cdr toolchain-list)))
		 ((null? toolchain-list) (cdr toolchain-packages))
	       (append! toolchain-packages
			(paludis-extract-packages (car toolchain-list)
						  upgrade "discard" #t))))))
	(tc-list '(""))
	(action-list '(""))
	(system-list '(""))
	(everything-list '("")))
    (display "\nCollecting Toolchain... ")
    (set! tc-list (generate-toolchain-list upgrade))
    (if toolchain (set! action-list (append action-list tc-list)))
    (display "done\n")
    (if (or system everything)
	(begin (display "\nCollecting System... ")
	       (set! system-list
		     (lset-difference
		      string=?
		      (paludis-extract-packages "system" upgrade pre-dependencies)
		      tc-list))
	       (if system (set! action-list (append action-list system-list)))
	       (display "done\n")))
    (if everything
	(begin (display "\nCollecting Everything... ")
	       (set! everything-list
		     (lset-difference
		      string=?
		      (paludis-extract-packages "everything" upgrade pre-dependencies)
		      system-list
		      tc-list))
	       (set! action-list (append action-list everything-list))
	       (display "done\n")))
    (set! action-list (cdr action-list))
    (if pretend
	(paludis-pretend action-list))
    (do ((action-list action-list (cdr action-list))
	 (finalized-action-list '("")))
	((null? action-list) (execute-action-list (cdr finalized-action-list)
						  resume-file))
      (set! finalized-action-list (append finalized-action-list
					  (list (paludis-generate-command
						 (car action-list)
						 checks)))))))
;; }}}

;;; File validity predicates
;; {{{ Checks a configuration file for problems.
;; <file> must be a string.
;; Returns boolean.
;; FIXME: Split one for existence, the other for syntax.
(define (valid-configuration-file?)
  (if (and (access? file R_OK)
	   (= 0 (status:exit-val (system (string-append "source " *system-configuration-file*)))))
      #t
      #f))
;; }}}

;; {{{ Simple check for the state-dir.
;; Returns boolean; true if the dir is +rwx to us, otherwise returns false.
;; FIXME: does not work with SUID/SGID, implement an exception-catching try-fail
;; tester.
(define (valid-resume-directory? dir)
  (if (access? dir (logior R_OK W_OK X_OK))
      #t
      #f))
;; }}}

;; {{{ Simple check for the state-file.
;; Returns boolean; true if the file either does not exist, or does and is +rw to us,
;; otherwise returns false.
;; FIXME: seee (valid-resume-directory?)
(define (valid-resume-file? file)
  (if (or (not (access? file F_OK))
	  (access? file (logior W_OK R_OK)))
      #t
      #f))
;; }}}

;;; Configuration file parser.
;; {{{ Reads a configuration file, checking for the validity of the options therein.
;; <file> must be a string, and better be a valid filename-cum-path too.
;; Returns the resume-file location.
(define (read-configuration-file file)
  (let* ((resume-file (read-$var-from-file "RESUME_FILE" file))
	 (resume-directory
	  (match:substring (string-match "^(/.*)(/)(.*)$" resume-file) 1))
	 (resume-directory-ok (valid-resume-directory? resume-directory))
	 (resume-file-ok (valid-resume-file? resume-file)))
    (cond ((and (not resume-directory-ok)
		(not resume-file-ok))
	   (begin (display "\nThere's a problem with the resume-file you specified:\n")
		  (display "Properize needs +rwx permissions to the containing directory, ")
		  (display "and +rw to the file you named.\n") (exit)))
	  ((not resume-file-ok)
	   (begin (display "\nThere's a problem with the resume-file you specified:\n")
		  (display "Properize needs +rw permissions to the file you named.\n") (exit)))
	  ((not resume-directory-ok)
	   (begin (display "\nThere's a problem with the resume-file you specified:\n")
		  (display "Properize needs +rwx permissions to the containing directory.\n")
		  (exit))))
    resume-file))
;; }}}

;;; Command-line option parser
;; {{{ (parse-commandline): Parses commandline using (tool).
(define (parse-commandline)
  (let* ((option-spec `((help (single-char #\h) (value #f))
			(version (single-char #\v) (value #f))
			(pretend (single-char #\p) (value #f))
			(verbose (single-char #\V) (value #f))
			(upgrade (single-char #\u) (value #f))
			(pre-dependencies (value #t))
			(checks (value #t))
			(resume (single-char #\r) (value #f))
			(toolchain (single-char #\t) (value #f))
			(system (single-char #\s) (value #f))
			(everything (single-char #\e) (value #f))))
	 (options (getopt-long (command-line) option-spec))
	 (help-wanted (option-ref options 'help #f))
	 (version-wanted (option-ref options 'version #f))
	 (pretend-wanted (option-ref options 'pretend #f))
	 (verbose-wanted (option-ref options 'verbose #f))
	 (upgrade-wanted (option-ref options 'upgrade #f))
	 (pre-dependencies-wanted (option-ref options 'pre-dependencies "discard"))
	 (checks-wanted (option-ref options 'checks "none"))
	 (resume-wanted (option-ref options 'resume #f))
	 (toolchain-wanted (option-ref options 'toolchain #t))
	 (system-wanted (option-ref options 'system #f))
	 (everything-wanted (option-ref options 'everything #f)))
    (values help-wanted
	    version-wanted
	    pretend-wanted
	    verbose-wanted
	    upgrade-wanted
	    pre-dependencies-wanted
	    checks-wanted
	    resume-wanted
	    toolchain-wanted
	    system-wanted
	    everything-wanted)))
;; }}}

;;; Argument parser
;; {{{ Controls parsing and validation of file and commandline options, sets global
;; options and initial environment, and initiates action-list generation or resuming
;; and action-list execution.
(define (parse-options configuration-file)
  (let-values (((resume-file) (read-configuration-file configuration-file))
		((help-wanted
		  version-wanted
		  pretend-wanted
		  verbose-wanted
		  upgrade-wanted
		  pre-dependencies-wanted
		  checks-wanted
		  resume-wanted
		  toolchain-wanted
		  system-wanted
		  everything-wanted) (parse-commandline)))
	       ;; Check for these before anything else.
	       (if help-wanted
		   (begin (print-header) (print-help) (exit)))
	       (if version-wanted
		   (begin (print-header) (exit)))
	       (if verbose-wanted (set! verbose #t))
	       ;; Regardless, we clear the PALUDIS_OPTIONS env var.
	       (unsetenv "PALUDIS_OPTIONS")
	       (if resume-wanted
		   ;; If we got told to resume, read the state file and pass the
		   ;; action-list to (execute-action-list).
		   (let ((action-list (resume-read resume-file)))
		     (display "\nResuming...\n")
		     (execute-action-list action-list resume-file))
		   ;; Else, proceed with potion mangling and action-list generation.
		   (begin (if verbose (display "\nInitializing...\n"))
			  (generate-action-list toolchain-wanted
						system-wanted
						everything-wanted
						pretend-wanted
						upgrade-wanted
						pre-dependencies-wanted
						checks-wanted
						resume-file)))))
;; }}}

;;; The world is burning, run!
;; {{{ Validates non-option environment, starts option parsing.
(define (check-environment)
  ;; check that the state-dir variable points to a valid location.
  (if (not (valid-configuration-file? *system-configuration-file*))
      (begin (display "\nThere is a problem with the configuration file;\n")
	     (display "Please check your syntax.\n")
	     (exit)))
  ;; if called w. no arguments, print help and exit.
  (if (null? (cdr (command-line)))
      (begin (print-header) (print-help) (exit))
      (parse-options *system-configuration-file*)))
;; }}}

;;; Program starts on last line *g*
(check-environment)
