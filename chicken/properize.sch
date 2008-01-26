#!/usr/bin/env csi
;; -*- mode: Scheme; mode: folding; -*-
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
;; CLI Argument parser
(declare (uses tool))
;; SRFI-1, extended list ops
(declare (uses srfi-1))
;; SRFI-11, let-values
(declare (uses srfi-11))
;; mkdir/rm etc alikes
(declare (uses misc-extn-posix))
;; }}}

;;; Global declarations.
;; {{{ Optimizations.
;; Standard functions are not redefined
(declare (block))
;; Let CSC choose versions of internal library functions for speed
(declare (usual-integrations))
;; }}}

;;; Interpeter settings.
;; {{{ Extensions.
(use posix)
(use tool)
(use srfi-1)
(use srfi-11)
(use misc-extn-posix)
;; }}}

;;; Global variables and constants
(declare (always-bound *version* *system-configuration-file*))
;; The version of the application, duh.
(define *version* "0.1.4")
;; The location of the configuration file.
(define *system-configuration-file* "/etc/properize.conf")
;; Yay global variables, what is this, java???
(define verbose #t)

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
;; {{{ Runs a pipe an input pipe and returns the result - one line only.
;; <command> must be a string and a valid sh pipe.
;; Returns whatever was in the 1st line of pipe's output, raw;
;; typechcking is left to the receiver.
(define (read-pipe-line command)
  (call-with-input-pipe command read))
;; }}}

(define (read-pipe-list command)
  (let ((port (open-input-pipe command))
	(pipe-list '()))
    (for-each-line (lambda (line) (set! pipe-list (cons line pipe-list))) port)
    pipe-list))

;; {{{ Reads a $var from a file, and returns its result.
;; <var> must be a string, the name of the $var you want to retrieve, sans the $
;; <file> must be a valid file identifier, either a file object or a string.
;; Returns whatever was in the $var, as a string.
(define (read-$var-from-file var file)
  (let* ((source-echo-command (string-append "source " file " 2>/dev/null; echo $" var))
	 (value (read-pipe-line source-echo-command)))
    (cond ((symbol? value) (symbol->string value))
	  ((number? value) (number->string value))
	  (else value))))
;; }}}

;;; Resume-file reading and writing
;; {{{ Reads the action-list from the resume-file, and returns it.
;; <resume-file> must be a string pointing to a file, or a readable file port.
;; Returns a list.
(define (resume-read resume-file)
  (let ((action-list (with-input-from-file resume-file (lambda () (read)))))
    action-list))
;; }}}

;; {{{ Nothing fancy, just dumps the action-list into a file.
;; <resume-file> must be a string pointing to a file, or a readable file port.
;; <action-list> better be the list you wanna write to the resume-file
;; Returns undefined.
(define (resume-write resume-file action-list)
  (with-output-to-file resume-file (lambda () (write action-list))))
;; }}}

;;; General command handlers
;; {{{ Encapsulate :eval-exit so we can simply run paludis-execute-action as a condition.
;; <action> must be a string.
;; Returns a boolean (obviously).
(define (system-execute-action action)
  (if (= 0 (status:exit-val (system action)))
      #t
      #f))
;; }}}

;;; Paludis handlers
;; {{{ Generates a command that can be passed as an argument to system-execute-action to build a
;; package.
;; <package> must be a string.
;; Returns a string.
(define (paludis-generate-command package checks)
  (string-append "paludis -i1 "
		 "--checks " checks " "
		 "--dl-deps-default discard "
		 "--debug-build none "
		 package))
;; }}}

;; {{{ Given a target, generates a list of the packages to be installed.
;; <target> must be a string. It better be a valid set or pakage, yo =P
;; Returns a list, '() in case the target is invalid - or in case of any other failure along the
;; way, tbqh.
;; FIXME: Gotta figure out a way to make it more debuggable. How expensive would it be to
;; implement w. inbuilt Regexp & String-ops?
;; Guile bidirectional pipes do not a good text filter make.
(define* (paludis-extract-packages target upgrade pre-dependencies #:optional (toolchain #f))
  (let* ((command (string-append "paludis -pi "
				 (if upgrade
				     "--dl-upgrade always "
				     "--dl-upgrade as-needed ")
				 "--dl-new-slots as-needed "
				 (if toolchain
				     "--dl-deps-default discard "
				     (string-append "--dl-installed-deps-pre "
						    pre-dependencies " "
						    "--dl-reinstall always "))
				 target
				 " | egrep '^\\* .*/.* '"
				 " | awk '{print $2}'"))
	 (port (open-input-pipe command))
	 (package-list '("")))
    (do ((package (read port) (read port)))
	((eof-object? package) (close-pipe port) (cdr package-list))
      (set! package-list (append package-list
				 (list (symbol->string package)))))))
;; }}}

;; {{{ paludis-pretend: Does what it says on the box, tbfh.
(define (paludis-pretend action-list)
  (do ((action-list action-list (cdr action-list))
       (pretend-command "paludis -pi1 --dl-deps-default discard --show-reasons summary --show-use-descriptions changed"))
      ((null? action-list) (system-execute-action pretend-command) (exit))
    (set! pretend-command (string-append pretend-command " " (car action-list)))))
;; }}}

;;; Action-list execution
;; {{{ Iterates over the action list, saving it to disk before running it.
(define (execute-action-list action-list resume-file)
  (do ((action-list action-list (cdr action-list)))
      ((null? action-list) (delete-file resume-file))
    (resume-write resume-file action-list)
    (if (not (system-execute-action (car action-list)))
	(begin (display "\nHmm, paludis did not exit happy. Fixit & try resuming, k?\n")
	       (exit)))))
;; }}}

;;; Action-list generation
;; {{{ Generates a list of actions and passes it to execute-action-list.
(define (generate-action-list toolchain system everything pretend
			      upgrade pre-dependencies checks resume-file)
  (let ((generate-toolchain-list
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
(define (valid-configuration-file? file)
  (if (and (access? file R_OK)
	   (= 0 (status:exit-val (system (string-append "source " file)))))
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
;; {{{ Parses commandline using (ice-9 getopt-long).
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
