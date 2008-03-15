#! /bin/sh
#| -*- mode: Scheme; mode: folding; -*-
exec csi -s $0 "$@"
|#
(use args)
(define options
  (list (args:make-option (p pretend)              #:none
			  "Pretend only: do not reinstall")
	(args:make-option (v verbose)              #:none
			  "Be verbose about what's going on\n")
	(args:make-option (t toolchain)            #:none
			  "Reinstall the toolchain")
	(args:make-option (s system)               #:none
			  "Reinstall the 'system' set
                                     Toolchain packages are filtered out")
	(args:make-option (e everything)           #:none
			  "Reinstall the 'everything' set
                                     Toolchain and 'system' packages are filtered out\n")
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
			  "Resume an aborted reinstallation\n\n")
	(args:make-option (V version)              #:none
			  "Print version and exit"
			  (print "args-test v0.0.1")
			  (exit))
	(args:make-option (h help)                 #:none
			  "Display this text"
			  (usage))))

(define (usage)
  (with-output-to-port (current-output-port)
    (lambda ()
      (print "Usage: magister [options...]")
      (print "Rebuild all installed packages, or parts thereof.")
      (newline)
      (print (parameterize ((args:separator ", ")
			    (args:indent 2)
			    (args:width 35))
	       (args:usage options)))
      (newline)
      (print "Examples:
  magister -t                        Rebuild the toolchain.
  magister -ts --version-lock=none   Rebuild toolchain and system,
                                     doing all possible upgrades.")
      (newline)
      (print "Report bugs to lvalerimanera at gmail.")))
  (exit))

(receive (options operands)
    (args:parse (command-line-arguments) options)
  (print "--version-lock -> " (alist-ref 'version-lock options))
  (print options)
  (print operands))
