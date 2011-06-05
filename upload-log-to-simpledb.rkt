#! /bin/sh
#| Hey Emacs, this is -*-scheme-*- code!
exec racket -l errortrace --require "$0" --main -- ${1+"$@"}
|#

#lang racket

(require racket/trace
         rackunit rackunit/text-ui)

;; This is a symlink, created thus:

#|
ln -s /home/erich/doodles/plt-scheme/web/amazon/ ~/.racket/5.1.1/collects/
|#
(require
 (only-in amazon/simpledb simpledb-post )
 (only-in amazon/group group))

;; Eventually I should make my amazon package presentable,
;; and upload it to PLaneT.

(struct sighting (who when description) #:prefab)

;; grovel log, pulling out new-style sexps (and associated timestamps)
;;   actually, only get those whose command is JOIN, PART, QUIT, or
;;   PRIVMSG
;; come up with a struct sighting

(define (trim-action utterance)
  (match utterance
    [(regexp #px"^\1ACTION (.*)\1$" (list _ action))
     ;; actions are generally in the present tense, e.g. "backs away
     ;; slowly".  I wish I could convert to past tense here, but alas.
     (format ": ~a" (bytes->string/utf-8 action))]
    [_ (format "saying ~s" (bytes->string/utf-8 utterance))]))

(define (timestamp+message->description m)
  (match m
    [(list timestamp
           (list 'prefix prefix)
           (list 'command command)
           (list 'params params ...))

     (let* ([command-str (bytes->string/utf-8 command)])
       (case (string->symbol command-str)
         ((JOIN)
          (format "~aing ~a"      (string-downcase command-str) (second (first params))))
         ((PART)
          (format "~aing from ~a" (string-downcase command-str) (second (first params))))
         ((QUIT)
          (let ([parting-words (second (first params))])
            (if (bytes=? #"" parting-words)
                (format "quitting")
                (format "quitting, saying ~s" (bytes->string/utf-8 parting-words)))))
         ((PRIVMSG)
          (format "~a ~a" (trim-action
                           (second (second params)))
                  (second (first params)) ))))]
    [_ 'wtf]))

(define (make-numbered-dict seq)
  (for/list ([(elt i) (in-indexed seq)])
    (list (string->symbol (format "param-~a" i)) elt)))

;; Massage our rfc1459 structure into a flat list suitable for shoving
;; into simpledb
(define (message->flat-alist m)
  (match m
    [(list (list 'prefix prefeces ...)  ; usually there's one prefix,
                                        ; but sometimes there's zero.
           (list 'command command)
           (list 'params params ...))
     `((prefix ,@prefeces)
       (command ,command)
       ,@(make-numbered-dict (map second params)))
     ]))

(define (log-line->alist l)
  (match l
    [(regexp #px"^([[:graph:]]+) <= (\\(.*\\))$" (list _ timestamp stuff))
     (cons timestamp (message->flat-alist (read (open-input-string stuff))))]
    [_ #f])  )


(define-test-suite tests
  (check-equal? (trim-action #"frotz")
                "saying \"frotz\"")
  (check-equal? (trim-action #"\1ACTION you said it\1")
                ": you said it")
  (check-equal? (timestamp+message->description
                 '("123.456"
                   (prefix #"colonel Mustard")
                   (command #"PRIVMSG")
                   (params (param #"in the study")
                           (param #"\1ACTION whuppin' hisself on de haid wit de candlestick\1"))))
                ": whuppin' hisself on de haid wit de candlestick in the study")
  (check-equal? (timestamp+message->description '("123.456"
                                                  (prefix #"colonel Mustard")
                                                  (command #"PRIVMSG")
                                                  (params (param #"in the study")
                                                          (param #"gimme seltzer"))))
                "saying \"gimme seltzer\" in the study")

  (check-equal? (timestamp+message->description '("123.456"
                                                  (prefix #"rudybot!~luser@ec2-204-236-167-175.us-west-1.compute.amazonaws.com")
                                                  (command #"PART")
                                                  (params (param #"#scheme"))))
                "parting from #scheme")

  (check-equal? (timestamp+message->description '("123.456"
                                                  (prefix #"monqy")
                                                  (command #"QUIT")
                                                  (params (param #"Quit: can't see a thing"))))
                "quitting, saying \"Quit: can't see a thing\"")

  (check-equal? (timestamp+message->description
                 '("123.456"
                   (prefix #"monqy")
                   (command #"QUIT")
                   (params (param #""))))
                "quitting")
  (check-equal?
   (message->flat-alist
    '((prefix #"monqy!~chap@pool-71-102-217-117.snloca.dsl-w.verizon.net")
      (command #"QUIT")
      (params
       (param #"Quit: cant see a thing")
       (param #"Oh, by the way"))))
   '((prefix #"monqy!~chap@pool-71-102-217-117.snloca.dsl-w.verizon.net")
     (command #"QUIT")
     (param-0 #"Quit: cant see a thing")
     (param-1 #"Oh, by the way")))
  (check-equal?
   (message->flat-alist
    '((prefix) (command #"PING") (params (param #"niven.freenode.net"))))
   '((prefix)
     (command #"PING")
     (param-0 #"niven.freenode.net")))
  (check-equal?
   (make-numbered-dict '(1 2 3))
   '((param-0 1) (param-1 2) (param-2 3))))

(provide main)
(define (main . args)
  (define input-file-names
    (command-line
     #:program "upload-yadda-yadda"
     #:args input-file-names
     input-file-names))

  (define pe (curry fprintf (current-error-port)))

  (cond
   ((null? input-file-names)
    (displayln "You didn't specify any input files; running unit tests instead of parsing" (current-error-port))
    (exit (if (positive?  (run-tests tests)) 1 0)))
   ((< 1 (length input-file-names))
    (error 'log-parser "I want at most one input file name; instead you gave me ~s" input-file-names))
   (else
    (let ([input-file-name (car input-file-names)])
      (call-with-input-file
          input-file-name
        (lambda (ip)
          (pe "Reading from ~a..." input-file-name)
          (for ([line (in-lines ip)])
            (pe "~s" line)
            (cond
             ((log-line->alist line) => (curry pe " => ~a")))
            (pe "~%"))))
      (pe "done~%")))))