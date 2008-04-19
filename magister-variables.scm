;;; -*- mode: Scheme; -*-

;;; Global declarations.
(cond-expand
 (compiling
  (declare
   (unit magister-variables)
   (uses library)
   (standard-bindings)
   (extended-bindings)
   (always-bound session)
   (constant compiled? verbose? toolchain? system? everything? pretend? resume?)
   (bound-to-procedure compiled?
                       make-session session?
                       session-version session-config-file session-pretend session-resume session-state-file
                       session-version-set! session-config-file-set! session-pretend-set! session-resume-set! session-state-file-set!
                       make-state state?
                       state-verbose state-toolchain state-system state-everything state-version-lock state-pre-deps state-upgrade state-checks state-debug
                       state-verbose-set! state-toolchain-set! state-system-set! state-everything-set! state-version-lock-set! state-pre-deps-set! state-upgrade-set! state-checks-set! state-debug-set!
                       make-package package?
                       package-category package-name package-version package-slot package-repository
                       package-category-set! package-name-set! package-version-set! package-slot-set! package-repository-set!
                       verbose? toolchain? system? everything? pretend? resume?)
   (unused compiled?
           session?
           session-version session-config-file session-state-file
           session-version-set! session-config-file-set! session-pretend-set! session-resume-set! session-state-file-set!
           make-state state?
           state-version-lock state-pre-deps state-upgrade state-checks state-debug
           state-verbose-set! state-toolchain-set! state-system-set! state-everything-set! state-version-lock-set! state-pre-deps-set! state-upgrade-set! state-checks-set! state-debug-set!
           make-package package?
           package-category package-name package-version package-slot package-repository
           package-category-set! package-name-set! package-version-set! package-slot-set! package-repository-set!
           verbose? toolchain? system? everything? pretend? resume?)))
 (else))

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

;;; Option functions
;; (<option>?): predicates for binary options.
(define (verbose? state)
  (state-verbose state))
(define (toolchain? state)
  (state-toolchain state))
(define (system? state)
  (state-system state))
(define (everything? state)
  (state-everything state))
(define (pretend?)
  (session-pretend session))
(define (resume?)
  (session-resume session))
