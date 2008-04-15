;;; -*- mode: Scheme; -*-

;;; Global declarations.
(cond-expand
 (compiling
  (declare
   (uses library)
   (uses srfi-37 args)
   (usual-integrations)
   (standard-bindings)
   (extended-bindings)
   (always-bound session option-spec)
   (bound-to-procedure compiled?
                       make-session session?
                       session-version session-config-file session-pretend session-resume session-state-file
                       session-version-set! session-config-file-set! session-pretend-set! session-resume-set! session-state-file-set!
                       make-state state?)
   (unused compiled?)))
 (else
  (use extras posix utils regex srfi-1 srfi-13 srfi-69)
  (use args)))

;;; Top-level variables.
(cond-expand (compiling (define (compiled?) #t)) (else (define (compiled?) #f)))
(define-record session
  version config-file pretend resume state-file)
(define-record-printer (session s out)
  (fprintf out "#,(session ~S ~S ~S ~S ~S)"
           (session-version s) (session-config-file s) (session-pretend s) (session-resume s) (session-state-file s)))
(define session
  (make-session "0.2.0" "/etc/magister.conf" #f #f "/var/tmp/magister-resume"))
(define-record state
  verbose toolchain system everything version-lock pre-deps upgrade checks debug)
(define-record-printer (state s out)
  (fprintf out "#,(state verbose: ~S toolchain: ~S system: ~S everything: ~S version-lock: ~S pre-deps: ~S checks: ~S debug: ~S)"
           (state-verbose s)      (state-toolchain s) (state-system s)  (state-everything s)
           (state-version-lock s) (state-pre-deps s)  (state-upgrade s) (state-checks s) (state-debug s)))
(define-reader-ctor 'state make-state)
(define-record package
  category name version slot repository)
(define-record-printer (package a out)
  (fprintf out "#,(package ~S ~S ~S ~S ~S)"
           (package-category a) (package-name a) (package-version a) (package-slot a) (package-repository a)))
(define-reader-ctor 'package make-package)
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
