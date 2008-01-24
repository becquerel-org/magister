#!/usr/bin/env scheme-script
#!r6rs ; -*- mode: Scheme; mode: folding; -*-
;;; name-to-be-decided
;;;
;;; Copyright (c) 2007 Leonardo Valeri Manera <lvalerimanera>@{NOSPAM}<google.com>
;;; This program is licensed under the terms of the General Public License version 2.
;;; Inspired by the portage script emwrap.sh, (c) 2004-2007 Hiel Van Campen.

;;; R5RS requires
(require 'srfi-0)
(require 'srfi-8)
(require 'srfi-1) ;zomgerror
(require 'string)
(require 'std-ffi)
(require 'unix)   ;zomgerror

;;; Global variables and constants
(define *version* "0.1.5")
(define *system-configuration-file* "/etc/properize.conf")
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

;;; Pipe-reading: needs popen() rnrs lib

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
