;;; -*- mode: Scheme; mode: folding; -*-

(declare
 (unit paludis)
 (usual-integrations)
 (standard-bindings)
 (extended-bindings)
 (bound-to-precedure multiple-versions?
                     generate-fqpn
                     generate-installation-command
                     generate-extraction-command
                     extract-packages
                     extract-package
                     pretend-install
                     built-with-use?
                     execute-action-list))

(use library extras posix utils regex srfi-1)

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
