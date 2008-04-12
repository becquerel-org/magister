;;; -*- mode: Scheme; -*-

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
                     resume-read resume-write
                     execute-action-list))

(use extras posix utils regex srfi-1)

;;; General paludis handlers
;; (multiple-versions?): predicate for forcing slot info in fqpn generation.
;; <package-name> is a valid category/name string.
;; returns a boolean if multiple versions exist.
(define (multiple-versions? package-name)
  (< 1 (length (read-pipe-list (string-append "paludis --match " package-name)))))

;; (generate-fqpn): Generates a package-spec from a (package slot version) list.
;; <package> must be a package record
;; Returns a string
(define (generate-fqpn state package)
  (let ([version-lock (state-version-lock state)])
    (cond [(or (eq? version-lock 'slot)
               (multiple-versions? (package-name package)))
           (string-append (package-category package) "/" (package-name package) (package-slot package))]
          [(eq? version-lock 'none)
           (string-append (package-category package) "/" (package-name package))]
          [else (string-append (package-category package) "/" (package-name package) "[=" (package-version package) "]")])))

;; (generate-installation-command): Generates an installation commandline.
;; <package> must be a string.
;; Returns a string.
(define (generate-installation-command state package)
  (let ([checks (state-checks state)]
	[debug (state-debug state)])
    (string-append "paludis -i1 "
		   "--checks " checks " "
		   "--dl-deps-default discard "
		   "--debug-build " debug " "
		   (generate-fqpn state package))))

;; (generate-extraction-command): Generates a package-extraction commandline.
;; <target> must be a valid package/set as a string.
;; Returns a string.
(define (generate-extraction-command state target)
  (let ([upgrade (state-upgrade state)]
	[pre-dependencies (state-pre-deps state)])
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

;; (extract-packages): Given a target, generates a list of the packages to be installed.
;; <target> must be a string. It better be a valid set or pakage.
;; Returns a list, '() in case the target is invalid - or in case of any other failure along the
;; way, tbqh.
(define (extract-packages state target)
  (let* ([command (generate-extraction-command state target)]
	 [package-match (regexp "^\\* ([^[:space:]]+)/([^[:space:]]+) ")]
         [package-splitter (regexp "^([^:/]*)/([^:/]*)($|::.*$)")]
	 [version-match (regexp "([^[:space:]]+)\\]")]
	 [atom-explode
	  (lambda (package-line)
	    (let* ([package-list (string-split package-line)]
                   [package-category (string-substitute package-splitter "\\1" (second package-list))]
		   [package-name (string-substitute package-splitter "\\2" (second package-list))]
		   [package-repository (string-substitute package-splitter "\\3" (second package-list))]
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
	      (make-package package-category package-name package-version package-slot package-repository)))])
    (regexp-optimize package-match)
    (regexp-optimize package-splitter)
    (regexp-optimize version-match)
    (map atom-explode
         (grep package-match
               (read-pipe-list command)))))

;; (extract-package): single-package wrapper for (paludis-extract-packages)
(define (extract-package state target)
  (first (extract-packages state target)))

;; (pretend-install): Does what it says on the box, tbfh.
(define (paludis-pretend state action-list)
  (let* ([pretend-command "paludis -pi --dl-deps-default discard --show-reasons none --show-use-descriptions changed"]
	 [append-package!
	  (lambda (package-list)
	    (set! pretend-command (string-append pretend-command " " (generate-fqpn state package-list))))])
    (for-each append-package! action-list)
    (system-execute-action pretend-command)
    (exit)))

;; (built-with-use?): Checks if a package has been built with a USE flag.
(define (built-with-use? package flag)
  (pair? (grep flag (read-pipe-list (string-append "paludis --environment-variable "
                                                   (package-category package) "/" (package-name package) (package-slot package) "[=" (package-version package) "]"
                                                   " USE")))))

;;; Resume-file reading and writing
;; (resume-read) Reads the action-list from the resume-file, and returns it.
;; Returns the state record and action list.
(define (resume-read)
  (let ((state-list (with-input-from-file (session-state-file session) (lambda () (read)))))
    (values (car state-list) (cdr state-list))))

;; (resume-write) Nothing fancy, just dumps the action-list into a file.
;; <state> must be a a state record.
;; <action-list> better be the list you wanna write to the resume-file.
;; Returns undefined.
(define (resume-write state action-list)
  (with-output-to-file (session-state-file session) (lambda () (write (cons state action-list)))))

;;; Action-list execution
;; (execute-action-list): Iterates over an action list, saving it to disk before running it.
(define (execute-action-list state action-list)
  (do ([action-list action-list (cdr action-list)])
      ((null? action-list) (delete-file (session-state-file session)))
    (resume-write action-list)
    (unless (system-execute-action (generate-installation-command state (car action-list)))
      (print "\nPaludis encountered an error!")
      (exit 1))))
