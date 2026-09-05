; paredit:ignore-file leftover-inspect-call -- CL-WEAVE's DESCRIBE is the BDD test DSL, not a debugger inspection call.
(in-package #:redis-kit/test)

(describe "Redis execution journal integration"
  (it "journals Redis command boundaries without payloads"
    (let* ((connection
             (redis-kit:make-connection
              :protocol :resp2
              :handshake nil
              :network-boundary (make-test-boundary)))
           (frames nil)
           (result nil))
      (unwind-protect
           (progn
             (setf frames
                   (cl-weave:with-execution-journal
                     (setf result (redis-kit:ping connection))))
             (expect result :to-equal "PONG")
             (let ((command-frame
                     (find :redis-command frames
                           :key #'cl-weave:journal-frame-kind))
                   (result-frame
                     (find :redis-result frames
                           :key #'cl-weave:journal-frame-kind)))
               (expect (cl-weave:journal-frame-form command-frame)
                       :to-equal
                       "PING")
               (expect (cl-weave:journal-frame-actual command-frame)
                       :to-equal
                       '(:argument-count 0))
               (expect (cl-weave:journal-frame-actual result-frame)
                       :to-equal
                       '(:reply-type :simple-string))))
        (redis-kit:close-connection connection))))

  (it "journals pipeline cardinality"
    (let ((connection
            (redis-kit:make-connection
             :protocol :resp2
             :handshake nil
             :network-boundary (make-test-boundary)))
          (frames nil))
      (unwind-protect
           (progn
             (setf frames
                   (cl-weave:with-execution-journal
                     (redis-kit:pipeline
                      connection
                      (list (list "PING") (list "PING")))))
             (let ((result-frame
                     (find :redis-result frames
                           :key #'cl-weave:journal-frame-kind)))
               (expect (cl-weave:journal-frame-form result-frame)
                       :to-equal
                       "PIPELINE")
               (expect (cl-weave:journal-frame-actual result-frame)
                       :to-equal
                       '(:reply-count 2))))
        (redis-kit:close-connection connection))))

  (it "journals command failures by condition type"
    (let ((connection
            (redis-kit:make-connection
             :protocol :resp2
             :handshake nil
             :network-boundary
             (cl-boundary-kit:make-network-boundary
              :request-fn
              (lambda (request &key timeout)
                (declare (ignore request timeout))
                (error "synthetic journal failure")))))
          (frames nil))
      (unwind-protect
         (progn
           (setf frames
                 (cl-weave:with-execution-journal
                   (handler-case (redis-kit:ping connection)
                     (redis-kit:redis-connection-error () nil))))
           (let ((error-frame
                   (find :redis-error frames
                         :key #'cl-weave:journal-frame-kind)))
             (expect (cl-weave:journal-frame-form error-frame)
                     :to-equal
                     "PING")
             (expect (cl-weave:journal-frame-actual error-frame)
                     :to-be
                     'redis-kit:redis-connection-error)))
        (redis-kit:close-connection connection)))))

  (it "keeps journal recording failures non-fatal"
    (let ((condition
            (make-condition 'simple-error
                            :format-control "synthetic journal condition")))
      (with-mocked-functions
          (((symbol-function 'cl-weave:record-journal-frame)
             (lambda (&rest arguments)
               (declare (ignore arguments))
               (error "synthetic journal recorder failure"))))
        (expect (redis-kit::%journal-command-start "PING" 0)
                :to-be
                nil)
        (expect (redis-kit::%journal-command-result "PING" 42)
                :to-be
                nil)
        (expect (redis-kit::%journal-command-error "PING" condition)
                :to-be
                nil))))

(describe "cl-weave execution journals"
  (it "derives facts from an execution journal with logic-program"
    (let* ((frames
             (cl-weave:with-execution-journal
               (cl-weave:journal-note :phase :ready)
               (expect 1 :to-be 1)
               (cl-weave:journal-note :phase :done)))
           (program
             (append
              (cl-weave:journal-facts frames)
              (cl-weave:logic-program
                (:- (:phase-note ?index)
                    (:kind ?index :note)
                    (:actual ?index :ready))))))
      (expect (cl-weave:journal-where program (:phase-note ?index))
              :to-equal
              '(((?index . 0))))))
  (it "queries journal frames directly with logic-run"
    (let ((frames
            (cl-weave:with-execution-journal
              (cl-weave:journal-note :phase :ready))))
      (expect (cl-weave:journal-where frames
                                      (:kind ?index :note)
                                      (:actual ?index :ready))
              :to-equal
              '(((?index . 0))))
      (expect (cl-weave:logic-run (cl-weave:journal-facts frames)
                                  (:form ?index :phase))
              :to-equal
              '(((?index . 0))))))

  (it "captures a continuation result"
    (cl-weave:with-continuation-result (value done)
      (done (+ 20 22))
      (expect value :to-be 42)))

  (it "captures multiple continuation values"
    (cl-weave:with-continuation-values (values done)
      (done :ready 42)
      (expect values :to-equal '(:ready 42)))))
